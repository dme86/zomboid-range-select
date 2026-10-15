-- Zomboid Range Select (PZ Build 42, controller inventory UI only).
-- Independent implementation: hold RT + D-pad to extend a range; leave vanilla A intact.
require 'ISUI/ISInventoryPage'
require 'ISUI/ISInventoryPane'
require 'ISUI/ISInventoryPaneContextMenu'

local Core = require 'ZRS_Core'

local originalDown = ISInventoryPage.onJoypadDown
local originalUp = ISInventoryPage.onJoypadDirUp
local originalDirDown = ISInventoryPage.onJoypadDirDown
local originalPaneUpdate = ISInventoryPane.update
local originalPanePrerender = ISInventoryPane.prerender

local function inventoryRow(row)
    return instanceof(row, 'InventoryItem')
end

local function getState(pane)
    if not pane.zrsState or pane.zrsInventory ~= pane.inventory then
        pane.zrsInventory = pane.inventory
        pane.zrsState = Core.new()
    end
    return pane.zrsState
end

-- Triggers are analog axes in B42: released ~= -1; fully pulled ~= +1.
-- Require a deliberate pull, independent of controller button mappings.
local function getPadId(playerNum, eventData, rememberedId)
    -- The D-pad callback is proof of the actual controller that sent input.
    -- In B42 the JoypadState.players entry may not yet be populated for
    -- keyboard/mouse players that just switched to a controller.
    if eventData and type(eventData.id) == 'number' and eventData.id >= 0 then
        return eventData.id
    end
    if rememberedId ~= nil and rememberedId >= 0 then return rememberedId end
    local jd = JoypadState and JoypadState.players and JoypadState.players[playerNum + 1]
    if jd and jd.id ~= nil and jd.id >= 0 then return jd.id end
    local player = getSpecificPlayer(playerNum)
    if player and player.getJoypadBind then
        local bound = player:getJoypadBind()
        if bound and bound >= 0 then return bound end
    end
    return nil
end

local function rtValue(playerNum, eventData, rememberedId)
    local id = getPadId(playerNum, eventData, rememberedId)
    local axis = JoypadAxis1d and JoypadAxis1d.RightTrigger
    if not id or not axis then return nil, id end
    return axis:getValue(id), id
end

local function isRtHeld(playerNum, eventData, rememberedId)
    local value, id = rtValue(playerNum, eventData, rememberedId)
    -- B42 represents a released trigger as -1 and a fully pulled trigger as +1.
    return value ~= nil and value > 0.25, id, value
end

local function isReady(page)
    local pane = page and page.inventoryPane
    if not pane or pane.mode ~= 'details' then return false end
    -- This function is called from an actual ISInventoryPage joypad callback.
    -- Requiring both joyfocus and doController is too strict during B42
    -- transitions between mouse and controller focus.
    if JoypadState and JoypadState.disableInvInteraction then return false end
    local player = getSpecificPlayer(page.player)
    if not player or player:isAsleep() then return false end
    local speed = UIManager.getSpeedControls()
    if speed and speed:getCurrentGameSpeed() == 0 then return false end
    return true
end

local function cursor(pane)
    local n = #pane.items
    if n < 1 then return nil end
    -- Vanilla normalizes joyselection in renderdetails. Normalize here as well,
    -- because gamepad D-pad callbacks can run before the next render.
    pane.joyselection = (pane.joyselection or 0) % n
    return pane.joyselection + 1
end

local function availableItems(pane, state)
    Core.prune(state, pane.inventory)
    return Core.actionItems(state, pane.items, pane.inventory, inventoryRow)
end

local function showSelectedMenu(page, pane, state)
    local items = availableItems(pane, state)
    if #items == 0 then return false end
    local player = getSpecificPlayer(page.player)
    if not player then return false end
    local isInInventory = pane.inventory:isInCharacterInventory(player)
    local x = pane:getAbsoluteX() + 64
    local y = pane:getAbsoluteY() + 8 + ((cursor(pane) or 1) - 1) * pane.itemHgt + pane:getYScroll()
    local menu = ISInventoryPaneContextMenu.createMenu(page.player, isInInventory, items, x, y)
    if menu then
        menu.origin = page
        menu.mouseOver = 1
        if menu.numOptions > 1 then setJoypadFocus(page.player, menu) end
    end
    return true
end

local function transferSelection(page, pane, state)
    local items = availableItems(pane, state)
    if #items == 0 then return false end
    if pane.inventory:isInCharacterInventory(getSpecificPlayer(page.player)) then
        ISInventoryPaneContextMenu.onPutItems(items, page.player)
    else
        ISInventoryPaneContextMenu.onGrabItems(items, page.player)
    end
    Core.clear(state)
    return true
end

-- RT starts a range only when moving the D-pad. A retains vanilla behavior
-- unless a completed selection exists, in which case A opens a menu for it.
function ISInventoryPage:onJoypadDown(button)
    if not isReady(self) then return originalDown(self, button) end
    local pane = self.inventoryPane
    local state = getState(pane)
    if button == Joypad.AButton and state.anchor == nil and Core.count(state) > 0 then
        if showSelectedMenu(self, pane, state) then return end
    end
    if button == Joypad.XButton and state.anchor == nil and Core.count(state) > 0 then
        if transferSelection(self, pane, state) then return end
    end
    if button == Joypad.BButton and (state.anchor ~= nil or Core.count(state) > 0) then
        Core.clear(state)
        return
    end
    return originalDown(self, button)
end

-- Print one observation per controller state; this helps distinguish "no pad"
-- from a wrong analog mapping without flooding console.txt on every key repeat.
local loggedInput = {}
local function logDpadOnce(page, controllerId, value, held)
    local category = held and 'rt-held' or (value == nil and 'no-axis' or 'rt-up')
    local key = tostring(page.player) .. ':' .. category
    if loggedInput[key] then return end
    loggedInput[key] = true
    print('[ZomboidRangeSelect] D-pad: player=' .. tostring(page.player) ..
        ' controller=' .. tostring(controllerId) .. ' RT=' .. tostring(value) ..
        ' held=' .. tostring(held) .. ' focus=' .. tostring(page.joyfocus) ..
        ' controllerUI=' .. tostring(page.inventoryPane.doController))
end

local function beforeNavigation(page, pane, oldIndex, joypadData)
    if not oldIndex or not isReady(page) then return nil end
    local existing = pane.zrsState
    local remembered = existing and existing.zrsPadId
    local held, controllerId, value = isRtHeld(page.player, joypadData, remembered)
    logDpadOnce(page, controllerId, value, held)
    if not held then
        -- Release may occur between two D-pad events; don't grow the old range.
        if existing and existing.anchor ~= nil then Core.release(existing) end
        return nil
    end
    local state = getState(pane)
    if state.anchor == nil then
        Core.begin(state, oldIndex)
        print('[ZomboidRangeSelect] RT selection started at row ' .. oldIndex)
    end
    state.zrsPadId = controllerId
    return state
end

local function afterNavigation(page, pane, oldIndex, state)
    if not state or pane ~= page.inventoryPane or pane.inventory ~= pane.zrsInventory then return end
    local newIndex = cursor(pane)
    if newIndex and newIndex ~= oldIndex then
        Core.extend(state, pane.items, newIndex, inventoryRow)
    end
end

function ISInventoryPage:onJoypadDirUp(joypadData)
    local pane = self.inventoryPane
    local oldIndex = pane and cursor(pane)
    local state = beforeNavigation(self, pane, oldIndex, joypadData)
    local result = originalUp(self, joypadData)
    afterNavigation(self, pane, oldIndex, state)
    return result
end

function ISInventoryPage:onJoypadDirDown(joypadData)
    local pane = self.inventoryPane
    local oldIndex = pane and cursor(pane)
    local state = beforeNavigation(self, pane, oldIndex, joypadData)
    local result = originalDirDown(self, joypadData)
    afterNavigation(self, pane, oldIndex, state)
    return result
end

-- Vanilla UI supplies no RT-up callback. Finish pending range once RT is released.
function ISInventoryPane:update()
    originalPaneUpdate(self)
    local state = self.zrsState
    if not state then return end
    if self.zrsInventory ~= self.inventory then
        Core.clear(state)
        self.zrsState = nil
        return
    end
    if state.anchor ~= nil and not isRtHeld(self.player, nil, state.zrsPadId) then
        Core.release(state)
        print('[ZomboidRangeSelect] RT released; selected items=' .. Core.count(state))
    end
    if self.inventory then Core.prune(state, self.inventory) end
end

-- A subtle highlight is rendered independently of pane.selected, which the base
-- controller UI clears each update. This also avoids interfering with mouse selection.
function ISInventoryPane:prerender()
    originalPanePrerender(self)
    local state = self.zrsState
    if not state or self.zrsInventory ~= self.inventory or self.mode ~= 'details' then return end
    if Core.count(state) == 0 then return end
    local height = self.height - self.headerHgt - 1
    if height <= 0 then return end
    self:setStencilRect(0, self.headerHgt, self.width - 1, height)
    local minIndex = math.max(1, math.floor(-self:getYScroll() / self.itemHgt) - 1)
    local maxIndex = math.min(#self.items, math.ceil((self.height - self:getYScroll()) / self.itemHgt) + 1)
    for i = minIndex, maxIndex do
        if Core.isRowFullySelected(state, self.items[i], inventoryRow) then
            local y = self.headerHgt + (i - 1) * self.itemHgt
            self:drawRect(1, y, self.width - 2, self.itemHgt, 0.28, 0.30, 0.56, 0.95)
        end
    end
    -- Restore the full pane clipping region for the vanilla render phase.
    self:setStencilRect(0, 0, self.width - 1, self.height - 1)
end

-- Controller input monitor for Mac/Steam Input troubleshooting.
-- Runs outside inventory focus so we can tell a Steam Input keyboard/mouse
-- mapping from native joypad signals. Emit only on input/assignment changes.
local monitorTicks = 0
local lastStatus = nil
local lastButtons = {}
local lastAxes = {}

local function safeAxisValue(axis, id)
    if not axis then return nil end
    local ok, value = pcall(function() return axis:getValue(id) end)
    return ok and value or nil
end

local function safeButtonDown(button, id)
    if not button then return false end
    local ok, down = pcall(function() return button:isDown(id) end)
    return ok and down == true
end

local function playerAssignment()
    local player = getSpecificPlayer(0)
    if not player or not player.getJoypadBind then return 'not spawned' end
    return tostring(player:getJoypadBind())
end

local function monitorJoypads()
    monitorTicks = monitorTicks + 1
    if monitorTicks % 5 ~= 0 then return end

    local assigned = playerAssignment()
    local jd = JoypadState and JoypadState.players and JoypadState.players[1]
    local mapped = jd and jd.id or nil
    local connectedIds = {}
    local controllers = JoypadState and JoypadState.controllers or {}
    for id = 0, 15 do
        local ctl = controllers[id]
        if ctl and ctl.connected then
            connectedIds[#connectedIds + 1] = id
        end
    end
    local status = 'player0=' .. assigned .. ' JoypadState=' .. tostring(mapped) ..
        ' connected=[' .. table.concat(connectedIds, ',') .. ']'
    if lastStatus ~= status then
        lastStatus = status
        print('[ZomboidRangeSelect] INPUT STATUS ' .. status)
        if #connectedIds == 0 then
            print('[ZomboidRangeSelect] No native gamepad detected by PZ. '
                .. 'Check Steam Input layout (Gamepad, not keyboard/mouse), connection and PZ controller options.')
        end
    end

    for _, id in ipairs(connectedIds) do
        local rt = safeAxisValue(JoypadAxis1d and JoypadAxis1d.RightTrigger, id)
        local held = rt ~= nil and rt > 0.25
        local prevHeld = lastAxes[id]
        if prevHeld == nil or prevHeld ~= held then
            lastAxes[id] = held
            print('[ZomboidRangeSelect] INPUT RT controller=' .. id ..
                ' value=' .. tostring(rt) .. ' held=' .. tostring(held))
        end
        local up = safeButtonDown(JoypadButton and JoypadButton.DPadUp, id)
        local down = safeButtonDown(JoypadButton and JoypadButton.DPadDown, id)
        local state = (up and 'UP' or '') .. (down and 'DOWN' or '')
        if lastButtons[id] ~= state then
            lastButtons[id] = state
            if state ~= '' then
                print('[ZomboidRangeSelect] INPUT D-PAD controller=' .. id ..
                    ' direction=' .. state .. ' RT=' .. tostring(rt))
            end
        end
    end
end

if Events and Events.OnTick then
    Events.OnTick.Add(monitorJoypads)
else
    print('[ZomboidRangeSelect] INPUT MONITOR unavailable: Events.OnTick missing')
end

-- Player 0 may initially be mouse-controlled even if a controller is available.
-- Report the actual assignment after the save loads; never force a takeover.
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        local player = getSpecificPlayer(0)
        if player and player.getJoypadBind then
            local id = player:getJoypadBind()
            if not id or id < 0 then
                print('[ZomboidRangeSelect] Player 0 has no controller assigned at game start. '
                    .. 'Bind/take over the player with your gamepad before testing RT+D-pad.')
            else
                print('[ZomboidRangeSelect] Player 0 controller id=' .. tostring(id))
            end
        end
    end)
end

print('[ZomboidRangeSelect] Build 42 RT controller hooks installed (v0.1.3)')
