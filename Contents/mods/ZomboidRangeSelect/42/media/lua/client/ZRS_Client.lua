-- Zomboid Range Select v0.1.5 for Project Zomboid Build 42.
-- Poll the game's own inventory cursor and RT axis; do not intercept D-pad events.
-- This is intentionally independent of the B42 joypad focus callback pipeline.
require 'ISUI/ISInventoryPage'
require 'ISUI/ISInventoryPane'
require 'ISUI/ISInventoryPaneContextMenu'
local Core = require 'ZRS_Core'

local oldDown = ISInventoryPage.onJoypadDown
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

if Events and Events.OnTick then
    Events.OnTick.Add(pollActivePages)
    print('[ZomboidRangeSelect] registered game-tick fallback')
else
    print('[ZomboidRangeSelect] OnTick unavailable; UI update polling only')
end

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
    local menu = ISInventoryPaneContextMenu.createMenu(
        page.player, inInv, items, pane:getAbsoluteX() + 64, y)
    if not menu then return false end
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

-- Leave A/X/B vanilla unless the player actually has marked items.
function ISInventoryPage:onJoypadDown(button)
    reportOnce('page-button', 'ISInventoryPage:onJoypadDown reached: ' ..
        tostring(button) .. ' ' .. focusDetails(self))
    if not isReady(self) then return oldDown(self, button) end
    pollPane(self)
    local state = stateFor(self.inventoryPane)
    if state.anchor then return oldDown(self, button) end
    if Core.count(state) == 0 then return oldDown(self, button) end
    if button == Joypad.AButton and menuForSelection(self, self.inventoryPane, state) then
        return
    elseif button == Joypad.XButton and transferSelection(self, self.inventoryPane, state) then
        return
    elseif button == Joypad.BButton then
        Core.clear(state)
        return
    end
    return oldDown(self, button)
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
    self:setStencilRect(0, self.headerHgt, self.width - 1, height)
    local scroll = self:getYScroll()
    local first = math.max(1, math.floor(-scroll / self.itemHgt) - 1)
    local last = math.min(#self.items, math.ceil((self.height - scroll) / self.itemHgt) + 1)
    for i = first, last do
        if Core.isRowFullySelected(state, self.items[i], isItem) then
            local y = self.headerHgt + (i - 1) * self.itemHgt
            self:drawRect(1, y, self.width - 2, self.itemHgt, 0.3, 0.28, 0.65, 1)
        end
    end
    self:setStencilRect(0, 0, self.width - 1, self.height - 1)
end

print('[ZomboidRangeSelect] v0.1.5 diagnostic polling hooks installed')
