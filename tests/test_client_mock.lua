-- Mock-only integration test of controller callbacks; this does not prove in-game behavior.
package.path = 'Contents/mods/ZomboidRangeSelect/42/media/lua/shared/?.lua;' .. package.path
for _, name in ipairs({'ISUI/ISInventoryPage','ISUI/ISInventoryPane','ISUI/ISInventoryPaneContextMenu'}) do
    package.preload[name] = function() return true end
end
local aDown, menuCount, transfers, vanillaX = 0, 0, 0, 0
local pressed = false
Joypad = {AButton=1,BButton=2,XButton=3,YButton=4}
JoypadButton = {A={isDown=function() return pressed end}}
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
-- Quick tap retains original behavior, but only on release.
pressed=true; page:onJoypadDown(Joypad.AButton)
assert(aDown==0)
pressed=false; pane:update()
assert(aDown==1)
-- Hold A and down twice, commit the first range [1,2,3].
pressed=true; page:onJoypadDown(Joypad.AButton)
page:onJoypadDirDown({id=0}); page:onJoypadDirDown({id=0})
pressed=false; pane:update()
assert(pane.zrsState.selected[objects[1]])
assert(pane.zrsState.selected[objects[2]])
assert(pane.zrsState.selected[objects[3]])
assert(not pane.zrsState.selected[objects[4]])
-- Move without A to 5, then A + up to 4: adds disjoint [4,5].
page:onJoypadDirDown({id=0}); page:onJoypadDirDown({id=0})
pressed=true; page:onJoypadDown(Joypad.AButton)
page:onJoypadDirUp({id=0})
pressed=false; pane:update()
-- This picks five items (1-5); reduce back to a total of four for mock action check.
assert(pane.zrsState.selected[objects[5]])
assert(pane.zrsState.selected[objects[4]])
-- Drop selection by removing one item, to test explicit action list.
pane.zrsState.selected[objects[3]]=nil
page:onJoypadDown(Joypad.XButton)
assert(transfers==1)
assert(vanillaX==0)
assert(next(pane.zrsState.selected)==nil)
print('OK: A tap defers, held navigation selects, repeated holds union, X transfers')
