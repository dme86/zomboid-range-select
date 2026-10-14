-- Mock-only integration test of controller callbacks; this does not prove in-game behavior.
package.path = 'Contents/mods/ZomboidRangeSelect/42/media/lua/shared/?.lua;' .. package.path
for _, name in ipairs({'ISUI/ISInventoryPage','ISUI/ISInventoryPane','ISUI/ISInventoryPaneContextMenu'}) do
    package.preload[name] = function() return true end
end
local aDown, menuCount, transfers, vanillaX = 0, 0, 0, 0
local rtValue = -1
Joypad = {AButton=1,BButton=2,XButton=3,YButton=4}
JoypadAxis1d = {RightTrigger={getValue=function() return rtValue end}}
JoypadState = {players={[1]={id=0}},disableInvInteraction=false}
UIManager = {getSpeedControls=function() return nil end}
local player = {isAsleep=function() return false end}
getSpecificPlayer = function() return player end
instanceof = function(obj, kind) return kind=='InventoryItem' and obj.isItem == true end
ISInventoryPaneContextMenu = {
    onGrabItems = function(items) transfers=transfers+1; assert(#items==4) end,
    onPutItems = function(items) transfers=transfers+1 end,
    createMenu = function(_,_,items)
       menuCount=menuCount+1
       assert(#items==4)
       return {numOptions=2}
    end,
}
setJoypadFocus = function() end
ISInventoryPane = {
    update = function() end,
    prerender = function() end,
}
ISInventoryPage = {
    onJoypadDown = function(_, button)
       if button==Joypad.AButton then aDown = aDown+1 end
       if button==Joypad.XButton then vanillaX=vanillaX+1 end
    end,
    onJoypadDirDown = function(page) page.inventoryPane.joyselection=page.inventoryPane.joyselection+1 end,
    onJoypadDirUp = function(page) page.inventoryPane.joyselection=page.inventoryPane.joyselection-1 end,
}
local inv = {isInCharacterInventory=function() return false end}
local objects = {}
for i=1,6 do
    local x={isItem=true,id=i}
    function x:getContainer() return inv end
    objects[i]=x
end
local pane={inventory=inv, items=objects, doController=true,mode='details',joyselection=0, player=0, itemHgt=20}
function pane:getAbsoluteX() return 0 end
function pane:getAbsoluteY() return 0 end
function pane:getYScroll() return 0 end
local page=setmetatable({joyfocus=true, inventoryPane=pane,player=0}, {__index=ISInventoryPage})
setmetatable(pane, {__index=ISInventoryPane})
pane.inventoryPage=page
assert(loadfile('Contents/mods/ZomboidRangeSelect/42/media/lua/client/ZRS_Client.lua'))()
-- A must keep vanilla behavior when no selection exists.
page:onJoypadDown(Joypad.AButton)
assert(aDown==1)

-- RT without D-pad must not start a selection.
rtValue=1; pane:update()
assert(pane.zrsState.anchor==nil)
rtValue=-1; pane:update()

-- First range: RT + down to row 3, then reverse to row 2 (shrink).
rtValue=1
page:onJoypadDirDown({id=0})
page:onJoypadDirDown({id=0})
page:onJoypadDirUp({id=0})
rtValue=-1; pane:update()
assert(pane.zrsState.selected[objects[1]])
assert(pane.zrsState.selected[objects[2]])
assert(not pane.zrsState.selected[objects[3]])

-- Move freely from row 2 to 5, then RT + up selects disjoint [4,5].
page:onJoypadDirDown({id=0})
page:onJoypadDirDown({id=0})
page:onJoypadDirDown({id=0})
rtValue=1
page:onJoypadDirUp({id=0})
rtValue=-1; pane:update()
assert(pane.zrsState.selected[objects[1]])
assert(pane.zrsState.selected[objects[2]])
assert(pane.zrsState.selected[objects[4]])
assert(pane.zrsState.selected[objects[5]])
assert(not pane.zrsState.selected[objects[3]])

-- A opens context menu for all selected items, not only focused row.
page:onJoypadDown(Joypad.AButton)
assert(aDown==1 and menuCount==1)

-- X transfers all four using vanilla transfer helpers and clears selection.
page:onJoypadDown(Joypad.XButton)
assert(transfers==1)
assert(vanillaX==0)
assert(next(pane.zrsState.selected)==nil)

-- RT below activation threshold should simply navigate.
rtValue=0
page:onJoypadDirDown({id=0})
assert(pane.zrsState.anchor == nil)
rtValue=-1
-- Vanilla A stays available afterwards.
page:onJoypadDown(Joypad.AButton)
assert(aDown==2)
print('OK: A vanilla, RT axis threshold, ranges, shrink, disjoint unions, A menu, X transfer')
