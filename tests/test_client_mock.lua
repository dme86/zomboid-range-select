-- Standalone Lua mock: verifies range selection without D-pad callback hooks.
package.path = 'Contents/mods/ZomboidRangeSelect/42/media/lua/shared/?.lua;' .. package.path
for _, name in ipairs({'ISUI/ISInventoryPage','ISUI/ISInventoryPane','ISUI/ISInventoryPaneContextMenu'}) do
    package.preload[name] = function() return true end
end
local tick
Events = { OnTick = { Add = function(fn) tick = fn end } }
local rtValue = -1
local vanillaA, vanillaX, menus, transfers = 0, 0, 0, 0
Joypad = {AButton=1,BButton=2,XButton=3,YButton=4}
JoypadState = {players={[1]={id=2}}, controllers={[2]={connected=true}}}
JoypadAxis1d = {RightTrigger={getValue=function(_,id) assert(id==2); return rtValue end}}
UIManager = {getSpeedControls=function() return nil end}
local player = {isAsleep=function() return false end, getJoypadBind=function() return 2 end}
getSpecificPlayer = function(n) if n == 0 then return player end end
instanceof = function(obj,kind) return kind=='InventoryItem' and obj.id ~= nil end
local inv = {isInCharacterInventory=function() return false end}
local objects = {}
for i=1,6 do
    local o={id=i}
    function o:getContainer() return inv end
    objects[i]=o
end
ISInventoryPaneContextMenu = {
    onPutItems=function() error('unexpected put') end,
    onGrabItems=function(items) transfers=transfers+1; assert(#items==4) end,
    createMenu=function(_,_,items) menus=menus+1; assert(#items==4); return {numOptions=2} end
}
setJoypadFocus = function() end
ISInventoryPane = {update=function() end, prerender=function() end}
ISInventoryPage = {onJoypadDown=function(_,btn)
    if btn==Joypad.AButton then vanillaA=vanillaA+1 end
    if btn==Joypad.XButton then vanillaX=vanillaX+1 end
end}
local pane = setmetatable({
    player=0,inventory=inv,mode='details',items=objects,joyselection=0,
    doController=true,itemHgt=20,headerHgt=18,height=250,width=250
}, {__index=ISInventoryPane})
function pane:getAbsoluteX() return 0 end
function pane:getAbsoluteY() return 0 end
function pane:getYScroll() return 0 end
local page = setmetatable({player=0,joyfocus=true,inventoryPane=pane},{__index=ISInventoryPage})
pane.inventoryPage=page
getPlayerInventory=function(n) if n==0 then return page end end
getPlayerLoot=function() return nil end
assert(loadfile('Contents/mods/ZomboidRangeSelect/42/media/lua/client/ZRS_Client.lua'))()
assert(type(tick)=='function')

-- Normal A remains immediately responsive.
tick();page:onJoypadDown(Joypad.AButton)
assert(vanillaA==1)

-- RT + navigation works without invoking onJoypadDirUp/Down.
rtValue=1;tick()
pane.joyselection=1;tick()
pane.joyselection=2;tick()
pane.joyselection=1;tick()
rtValue=-1;tick()
local state=pane.zrsState
assert(state.selected[objects[1]] and state.selected[objects[2]])
assert(not state.selected[objects[3]])
assert(state.anchor==nil)

-- Second disjoint range is additive. Released RT alone does nothing.
pane.joyselection=4;tick()
rtValue=1;tick()
pane.joyselection=3;tick()
rtValue=-1;tick()
assert(state.selected[objects[1]] and state.selected[objects[2]])
assert(state.selected[objects[4]] and state.selected[objects[5]])
assert(not state.selected[objects[3]])
assert(require('ZRS_Core').count(state)==4)

-- Context menu and transfer collect exactly the selected items.
page:onJoypadDown(Joypad.AButton)
assert(menus==1 and vanillaA==1)
page:onJoypadDown(Joypad.XButton)
assert(transfers==1 and vanillaX==0)
assert(require('ZRS_Core').count(state)==0)
page:onJoypadDown(Joypad.AButton)
assert(vanillaA==2)

-- Analog 0 = released is supported for Steam Input style trigger ranges.
rtValue=0;tick()
assert(state.anchor==nil)
pane.joyselection=2;tick()
rtValue=.8;tick()
pane.joyselection=3;tick()
assert(state.selected[objects[3]] and state.selected[objects[4]])
rtValue=0;tick()
assert(state.anchor==nil)

-- Controller reassignment fallback when JoypadState.players is absent.
JoypadState.players={}
rtValue=1;tick()
pane.joyselection=4;tick()
assert(state.selected[objects[5]])
rtValue=-1;tick()

print('OK: RT polled without D-pad callbacks, additive and shrinking ranges, A/X, axis 0..1, joypad mapping fallback')
