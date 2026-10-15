-- Zomboid Range Select v0.1.17 for Project Zomboid Build 42.
-- Poll the game's own inventory cursor and RT axis. Vertical D-pad navigation
-- stays native; horizontal pane switching is suppressed while marks are pending.
-- This is intentionally independent of the B42 joypad focus callback pipeline.
require 'ISUI/ISInventoryPage'
require 'ISUI/ISInventoryPane'
require 'ISUI/ISInventoryPaneContextMenu'
local Core = require 'ZRS_Core'

-- Persistent callbacks survive beyond this Lua file's scope.
ZRS = ZRS or {}
ZRS.version = '0.1.17'

local oldDown = ISInventoryPage.onJoypadDown
local oldDirLeft = ISInventoryPage.onJoypadDirLeft
local oldDirRight = ISInventoryPage.onJoypadDirRight
local oldPaneContext = ISInventoryPane.doContextOnJoypadSelected
local oldPaneUpdate = ISInventoryPane.update
local oldPrerender = ISInventoryPane.prerender

-- Low-volume diagnostic breadcrumbs. Report each state once, not on every frame.
local diagnosticsSeen = {}
local function reportOnce(key, message)
    if diagnosticsSeen[key] then return end
    diagnosticsSeen[key] = true
    print('[ZomboidRangeSelect] DIAG ' .. message)
end

local function focusDetails(page)
    local pane = page and page.inventoryPane
    if not pane then return 'no pane' end
    local jd = JoypadState and JoypadState.players and
        JoypadState.players[(page.player or 0) + 1]
    return 'pane=' .. tostring(pane.mode) ..
        ' rows=' .. tostring(pane.items and #pane.items) ..
        ' cursor=' .. tostring(pane.joyselection) ..
        ' pageFocus=' .. tostring(page.joyfocus ~= nil and page.joyfocus ~= false) ..
        ' paneController=' .. tostring(pane.doController) ..
        ' pad=' .. tostring(jd and jd.id) ..
        ' routedFocus=' .. tostring(jd and jd.focus) ..
        ' self=' .. tostring(page)
end

local function isItem(row)
    return instanceof(row, 'InventoryItem')
end

local function stateFor(pane)
    if pane.zrsInventory ~= pane.inventory or not pane.zrsState then
        pane.zrsInventory = pane.inventory
        pane.zrsState = Core.new()
    end
    return pane.zrsState
end

local function rowIndex(pane)
    if not pane.items or #pane.items == 0 then return nil end
    if pane.joyselection == nil then return nil end
    return (pane.joyselection % #pane.items) + 1
end

local function controllerId(playerNum)
    local jd = JoypadState and JoypadState.players and JoypadState.players[playerNum + 1]
    if jd and type(jd.id) == 'number' and jd.id >= 0 then return jd.id end
    local player = getSpecificPlayer(playerNum)
    if player and player.getJoypadBind then
        local id = player:getJoypadBind()
        if type(id) == 'number' and id >= 0 then return id end
    end
    -- Some controller setups have a connected device but no player mapping
    -- during initial inventory focus. Prefer real mappings over this fallback.
    local controllers = JoypadState and JoypadState.controllers
    if controllers then
        for id = 0, 15 do
            if controllers[id] and controllers[id].connected then return id end
        end
    end
    return nil
end

local function triggerValue(id)
    local rt = JoypadAxis1d and JoypadAxis1d.RightTrigger
    if id == nil or not rt then return nil end
    local ok, value = pcall(function() return rt:getValue(id) end)
    if ok and type(value) == 'number' then return value end
    return nil
end

local function readyStatus(page)
    local pane = page and page.inventoryPane
    if not pane then return false, 'missing-pane' end
    if not pane.inventory then return false, 'missing-container' end
    if pane.mode ~= 'details' then return false, 'wrong-mode' end
    if JoypadState and JoypadState.disableInvInteraction then
        return false, 'interaction-disabled'
    end
    local player = getSpecificPlayer(page.player)
    if not player then return false, 'missing-player' end
    if player:isAsleep() then return false, 'asleep' end
    if not (page.joyfocus or pane.doController) then
        return false, 'no-controller-focus'
    end
    local jd = JoypadState and JoypadState.players and JoypadState.players[page.player + 1]
    if jd and jd.focus and jd.focus ~= page then
        return false, 'focus-routed-elsewhere'
    end
    return true, 'ready'
end

local function isReady(page)
    local ready = readyStatus(page)
    return ready
end

local lastRuntimeStatus = {}
local function runtimeNote(page, id, value)
    local key = tostring(page.player) .. ':' .. tostring(id)
    if lastRuntimeStatus[key] then return end
    lastRuntimeStatus[key] = true
    print('[ZomboidRangeSelect] inventory polling active: player=' ..
        tostring(page.player) .. ' pad=' .. tostring(id) .. ' RT=' .. tostring(value))
end

local function hasPendingSelection(page)
    local pane = page and page.inventoryPane
    local state = pane and pane.zrsState
    if not state then return false, 0 end
    if pane.inventory then Core.prune(state, pane.inventory) end
    local count = Core.count(state)
    return state.anchor ~= nil or state.zrsHeld == true or count > 0, count
end

local function pollPane(page)
    local ready, reason = readyStatus(page)
    -- Trace the branch that stops the entire selection before returning.
    if page then
        reportOnce('status:' .. tostring(page.onCharacter) .. ':' .. reason,
            'inventory gate: ' .. reason .. ' ' .. focusDetails(page))
    end
    if not ready then
        local pane = page and page.inventoryPane
        local state = pane and pane.zrsState
        if state then
            if state.anchor then Core.release(state) end
            state.zrsHeld = false
            state.zrsLastCursor = nil
        end
        return
    end
    local pane = page.inventoryPane
    local cursor = rowIndex(pane)
    if not cursor then return end
    local state = stateFor(pane)
    local id = controllerId(page.player)
    local value = triggerValue(id)
    runtimeNote(page, id, value)
    local axisState = value == nil and 'unavailable' or
        (value > 0.25 and 'held' or 'released')
    reportOnce('axis:' .. axisState, 'RT axis ' .. axisState ..
        ' id=' .. tostring(id) .. ' value=' .. tostring(value))
    if value == nil then
        if not state.zrsNoAxisNoted then
            print('[ZomboidRangeSelect] RT axis unavailable. ' ..
                'Check gamepad binding in PZ (controller id=' .. tostring(id) .. ').')
            state.zrsNoAxisNoted = true
        end
        if state.anchor then Core.release(state) end
        state.zrsHeld = false
        state.zrsLastCursor = cursor
        return
    end

    -- Hysteresis avoids accidental release at the analog trigger threshold.
    local held = value > (state.zrsHeld and 0.10 or 0.25)
    if held and not state.zrsHeld then
        -- Use the previous observed cursor, even if RT and D-pad changed between
        -- two UI updates. No D-pad callback or button mapping is required.
        Core.begin(state, state.zrsLastCursor or cursor)
        print('[ZomboidRangeSelect] RT down; anchor=' .. tostring(state.anchor) ..
            ' value=' .. tostring(value))
    elseif not held and state.zrsHeld then
        if state.anchor then Core.release(state) end
        print('[ZomboidRangeSelect] RT up; selected=' .. Core.count(state))
    end

    if held and state.anchor and (state.zrsLastCursor ~= cursor or not state.dragging) then
        local didExtend = Core.extend(state, pane.items, cursor, isItem)
        if didExtend then
            print('[ZomboidRangeSelect] selected=' .. Core.count(state) ..
                ' cursor=' .. cursor)
        end
    end

    state.zrsHeld = held
    state.zrsLastCursor = cursor
    Core.prune(state, pane.inventory)
end

-- Called from both the pane's UI update and PZ's game tick. Either entry
-- point is sufficient; the state machine is idempotent when both run.
function ISInventoryPane:update()
    reportOnce('pane-update', 'ISInventoryPane:update reached')
    oldPaneUpdate(self)
    if self.inventoryPage then
        pollPane(self.inventoryPage)
    else
        reportOnce('no-pane-parent', 'ISInventoryPane:update without inventoryPage')
    end
end

local function pollActivePages()
    reportOnce('tick', 'Events.OnTick executing')
    for playerNum = 0, 3 do
        if getSpecificPlayer(playerNum) then
            reportOnce('player:' .. playerNum, 'game world player ' .. playerNum .. ' found')
            local inv = getPlayerInventory(playerNum)
            local loot = getPlayerLoot(playerNum)
            if inv and inv.inventoryPane then
                pollPane(inv)
            elseif playerNum == 0 then
                reportOnce('no-inventory-page', 'getPlayerInventory(0) has no inventoryPane')
            end
            if loot and loot ~= inv and loot.inventoryPane then pollPane(loot) end
        end
    end
end

-- Event handlers are installed at the bottom of this file.

local function actionItems(pane, state)
    Core.prune(state, pane.inventory)
    return Core.actionItems(state, pane.items, pane.inventory, isItem)
end

local function menuForSelection(page, pane, state)
    local items = actionItems(pane, state)
    if #items == 0 then return false end
    local player = getSpecificPlayer(page.player)
    if not player then return false end
    local inInv = pane.inventory:isInCharacterInventory(player)
    local y = pane:getAbsoluteY() + 8 + ((rowIndex(pane) or 1) - 1) *
        pane.itemHgt + pane:getYScroll()
    -- Pass all selected items, not just the focused row, into the vanilla menu.
    -- Keep a HUD-visible record so selection vs menu-routing bugs are distinct.
    ZRS.lastMenuCount = #items
    ZRS.lastMenuSide = page.onCharacter and 'PERSONAL' or 'LOOT'
    local menu = ISInventoryPaneContextMenu.createMenu(
        page.player, inInv, items, pane:getAbsoluteX() + 64, y)
    if not menu then
        ZRS.lastMenuStatus = 'vanilla menu returned nil'
        return false
    end
    -- Vanilla Build 42 accepts the complete item list here. Its normal
    -- "Nehmen" and "Verschieben nach" handlers operate on every marked item;
    -- adding a separate ZRS action would only duplicate those menu entries.
    ZRS.lastMenuStatus = 'vanilla multi-item menu'
    print('[ZomboidRangeSelect] multi-menu side=' .. ZRS.lastMenuSide ..
        ' items=' .. #items .. ' status=' .. ZRS.lastMenuStatus)
    menu.origin = page
    menu.mouseOver = 1
    if menu.numOptions > 1 then setJoypadFocus(page.player, menu) end
    return true
end

local function transferSelection(page, pane, state)
    local items = actionItems(pane, state)
    if #items == 0 then return false end
    local player = getSpecificPlayer(page.player)
    if not player then return false end
    if pane.inventory:isInCharacterInventory(player) then
        ISInventoryPaneContextMenu.onPutItems(items, page.player)
    else
        ISInventoryPaneContextMenu.onGrabItems(items, page.player)
    end
    Core.clear(state)
    return true
end

-- Native PZ 42 routes A through ISInventoryPane:doContextOnJoypadSelected.
-- Intercept there rather than competing with the page's onJoypadDown wrapper.
function ISInventoryPane:doContextOnJoypadSelected(...)
    local page = self.inventoryPage
    if page and isReady(page) then
        pollPane(page)
        local state = stateFor(self)
        if state.anchor then Core.release(state) end
        if Core.count(state) > 0 and menuForSelection(page, self, state) then
            return
        end
    end
    return oldPaneContext(self, ...)
end

-- Leave A to the original page handler, which invokes the pane method above.
-- X/B work with selections only in the currently focused pane.
function ISInventoryPage:onJoypadDown(button)
    reportOnce('page-button', 'ISInventoryPage:onJoypadDown reached: ' ..
        tostring(button) .. ' ' .. focusDetails(self))
    if not isReady(self) then return oldDown(self, button) end
    pollPane(self)
    local state = stateFor(self.inventoryPane)
    if Core.count(state) == 0 then return oldDown(self, button) end

    -- Pressing an action while RT is still down commits the marked range.
    -- Previously X fell through to vanilla here and transferred only the
    -- focused row, even though multiple rows were visibly highlighted.
    if button == Joypad.AButton or button == Joypad.XButton or
            button == Joypad.BButton then
        if state.anchor then Core.release(state) end
    end
    if button == Joypad.XButton and transferSelection(self, self.inventoryPane, state) then
        return
    elseif button == Joypad.BButton then
        Core.clear(state)
        return
    elseif button == Joypad.YButton then
        -- Do not retain a pending range after intentionally closing inventory.
        Core.clear(state)
    end
    return oldDown(self, button)
end

-- Do not let horizontal D-pad input leave the pane while a range is being
-- marked or while committed marks are waiting for A/X/B. PZ auto-collapses
-- an unpinned inventory after the focus changes; allowing LEFT/RIGHT after RT
-- was released therefore hid the source pane and stranded its selection.
-- Outside a selection, preserve PZ's native pane-switching behavior.
local function isSelectionLocked(page)
    -- Direction callbacks may be the first UI callback in the frame where RT
    -- was pressed, so sample the trigger before deciding whether to switch.
    if page and isReady(page) then pollPane(page) end
    return hasPendingSelection(page)
end

function ISInventoryPage:onJoypadDirLeft(...)
    local locked, count = isSelectionLocked(self)
    if locked then
        ZRS.lastNav = 'LEFT ignored while selection is pending'
        print('[ZomboidRangeSelect] LEFT ignored; pending selection=' .. count)
        return
    end
    ZRS.lastNav = 'LEFT handled by vanilla'
    if oldDirLeft then return oldDirLeft(self, ...) end
end

function ISInventoryPage:onJoypadDirRight(...)
    local locked, count = isSelectionLocked(self)
    if locked then
        ZRS.lastNav = 'RIGHT ignored while selection is pending'
        print('[ZomboidRangeSelect] RIGHT ignored; pending selection=' .. count)
        return
    end
    ZRS.lastNav = 'RIGHT handled by vanilla'
    if oldDirRight then return oldDirRight(self, ...) end
end

-- The vanilla controller clears pane.selected every frame. Our selected items
-- live in separate state, highlighted without modifying native inventory rows.
function ISInventoryPane:prerender()
    reportOnce('pane-prerender', 'ISInventoryPane:prerender reached')
    oldPrerender(self)
    if not self.inventoryPage or not isReady(self.inventoryPage) then return end
    local state = self.zrsState
    if not state or self.zrsInventory ~= self.inventory or Core.count(state) == 0 then return end
    if not self.itemHgt or self.itemHgt <= 0 or not self.headerHgt then return end
    local height = self.height - self.headerHgt - 1
    if height <= 0 then return end
    local scroll = self:getYScroll()
    local first = math.max(1, math.floor(-scroll / self.itemHgt) - 1)
    local last = math.min(#self.items, math.ceil((self.height - scroll) / self.itemHgt) + 1)
    for i = first, last do
        if Core.isRowFullySelected(state, self.items[i], isItem) then
            local y = self.headerHgt + (i - 1) * self.itemHgt
            -- Clip numerically instead of touching PZ's shared stencil buffer.
            -- drawRect() applies yScroll, so convert to screen-local Y only for
            -- calculating the visible portion, then draw in content coordinates.
            local screenY = y + scroll
            local visibleTop = math.max(self.headerHgt, screenY)
            local visibleBottom = math.min(self.height - 1, screenY + self.itemHgt)
            if visibleTop < visibleBottom then
                local clippedY = y + (visibleTop - screenY)
                self:drawRect(1, clippedY, self.width - 2,
                    visibleBottom - visibleTop, 0.3, 0.28, 0.65, 1)
            end
        end
    end
end

-- Keep references to our own wrappers, independently of later UI loading.
ZRS.paneUpdateHook = ISInventoryPane.update
ZRS.paneRenderHook = ISInventoryPane.prerender
ZRS.paneContextHook = ISInventoryPane.doContextOnJoypadSelected
ZRS.pageButtonHook = ISInventoryPage.onJoypadDown
ZRS.pageLeftHook = ISInventoryPage.onJoypadDirLeft
ZRS.pageRightHook = ISInventoryPage.onJoypadDirRight

function ZRS.ensureHooks(source)
    if not ISInventoryPane or not ISInventoryPage then return end
    if ISInventoryPane.update ~= ZRS.paneUpdateHook then
        oldPaneUpdate = ISInventoryPane.update
        ISInventoryPane.update = ZRS.paneUpdateHook
        print('[ZomboidRangeSelect] reattached pane update after ' .. source)
    end
    if ISInventoryPane.prerender ~= ZRS.paneRenderHook then
        oldPrerender = ISInventoryPane.prerender
        ISInventoryPane.prerender = ZRS.paneRenderHook
        print('[ZomboidRangeSelect] reattached pane render after ' .. source)
    end
    if ISInventoryPage.onJoypadDown ~= ZRS.pageButtonHook then
        oldDown = ISInventoryPage.onJoypadDown
        ISInventoryPage.onJoypadDown = ZRS.pageButtonHook
        print('[ZomboidRangeSelect] reattached page controller after ' .. source)
    end
    if ISInventoryPane.doContextOnJoypadSelected ~= ZRS.paneContextHook then
        oldPaneContext = ISInventoryPane.doContextOnJoypadSelected
        ISInventoryPane.doContextOnJoypadSelected = ZRS.paneContextHook
        print('[ZomboidRangeSelect] reattached multi-item context hook after ' .. source)
    end
    if ISInventoryPage.onJoypadDirLeft ~= ZRS.pageLeftHook then
        oldDirLeft = ISInventoryPage.onJoypadDirLeft
        ISInventoryPage.onJoypadDirLeft = ZRS.pageLeftHook
    end
    if ISInventoryPage.onJoypadDirRight ~= ZRS.pageRightHook then
        oldDirRight = ISInventoryPage.onJoypadDirRight
        ISInventoryPage.onJoypadDirRight = ZRS.pageRightHook
    end
end

ZRS.onTick = function()
    reportOnce('real-tick', 'OnTick event fired')
    ZRS.ensureHooks('OnTick')
    pollActivePages()
end

ZRS.onPlayerUpdate = function(player)
    reportOnce('real-player-update', 'OnPlayerUpdate event fired')
    ZRS._playerUpdates = (ZRS._playerUpdates or 0) + 1
    if ZRS._playerUpdates % 10 == 1 then
        ZRS.ensureHooks('OnPlayerUpdate')
        pollActivePages()
    end
end

ZRS.onGameStart = function()
    print('[ZomboidRangeSelect] OnGameStart world entered')
    ZRS.ensureHooks('OnGameStart')
    pollActivePages()
end

ZRS.onCreatePlayer = function(index, player)
    print('[ZomboidRangeSelect] OnCreatePlayer index=' .. tostring(index))
    ZRS.ensureHooks('OnCreatePlayer')
end

local function registerEvent(name, fn)
    local ev = Events and Events[name]
    if ev and ev.Add then
        ev.Add(fn)
        print('[ZomboidRangeSelect] registered ' .. name)
    else
        print('[ZomboidRangeSelect] unavailable event: ' .. name)
    end
end
registerEvent('OnGameStart', ZRS.onGameStart)
registerEvent('OnCreatePlayer', ZRS.onCreatePlayer)
registerEvent('OnPlayerUpdate', ZRS.onPlayerUpdate)
registerEvent('OnTick', ZRS.onTick)
print('[ZomboidRangeSelect] v0.1.17 vanilla multi-item menu and range selection installed')
