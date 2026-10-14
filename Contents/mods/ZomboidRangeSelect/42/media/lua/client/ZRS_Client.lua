-- Zomboid Range Select (PZ Build 42, controller inventory UI only).
-- Original independent implementation: defer A until released, select when A + D-pad.
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

local function isHeld(playerNum)
    local jd = JoypadState and JoypadState.players and JoypadState.players[playerNum + 1]
    return jd and jd.id ~= nil and jd.id >= 0 and
        JoypadButton and JoypadButton.A and JoypadButton.A:isDown(jd.id) or false
end

local function isReady(page)
    local pane = page and page.inventoryPane
    if not pane or not page.joyfocus or not pane.doController or pane.mode ~= 'details' then
        return false
    end
    if JoypadState.disableInvInteraction then return false end
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

-- A is deferred until release, so A+D-pad does not pop up the vanilla context menu.
-- X acts on all selected items; B clears the selection before vanilla expand/collapse.
function ISInventoryPage:onJoypadDown(button)
    if not isReady(self) then return originalDown(self, button) end
    local pane = self.inventoryPane
    local state = getState(pane)
    if button == Joypad.AButton then
        if state.anchor == nil then
            local index = cursor(pane)
            if not index then return originalDown(self, button) end
            Core.begin(state, index)
        end
        return
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

local function afterNavigation(page, oldPane, oldIndex)
    if not oldPane or not page.inventoryPane or page.inventoryPane ~= oldPane then return end
    local state = getState(oldPane)
    if state.anchor == nil or not isHeld(page.player) then return end
    local newIndex = cursor(oldPane)
    if newIndex and newIndex ~= oldIndex then
        Core.extend(state, oldPane.items, newIndex, inventoryRow)
    end
end

function ISInventoryPage:onJoypadDirUp(joypadData)
    local pane = self.inventoryPane
    local oldIndex = pane and cursor(pane)
    local result = originalUp(self, joypadData)
    afterNavigation(self, pane, oldIndex)
    return result
end

function ISInventoryPage:onJoypadDirDown(joypadData)
    local pane = self.inventoryPane
    local oldIndex = pane and cursor(pane)
    local result = originalDirDown(self, joypadData)
    afterNavigation(self, pane, oldIndex)
    return result
end

-- Poll the A release once per UI frame. Vanilla UI doesn't supply an A-up callback.
-- A short tap retains its usual action, or opens the menu for an existing multi-selection.
function ISInventoryPane:update()
    originalPaneUpdate(self)
    local state = self.zrsState
    if not state then return end
    if self.zrsInventory ~= self.inventory then
        Core.clear(state)
        self.zrsState = nil
        return
    end
    if state.anchor ~= nil and not isHeld(self.player) then
        local didSelect = Core.release(state)
        if not didSelect then
            local page = self.inventoryPage
            if page and isReady(page) then
                if Core.count(state) == 0 or not showSelectedMenu(page, self, state) then
                    originalDown(page, Joypad.AButton)
                end
            end
        end
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

print('[ZomboidRangeSelect] Build 42 controller selection hooks installed')
