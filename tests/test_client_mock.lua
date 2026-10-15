-- Standalone Lua mock: verifies range selection without D-pad callback hooks.
package.path = 'Contents/mods/ZomboidRangeSelect/42/media/lua/shared/?.lua;' .. package.path
for _, name in ipairs({'ISUI/ISInventoryPage','ISUI/ISInventoryPane','ISUI/ISInventoryPaneContextMenu'}) do
    package.preload[name] = function() return true end
end
local handlers = {}
local function makeEvent(name)
    return {Add = function(fn) handlers[name] = fn end}
end
Events = {
    OnTick = makeEvent('OnTick'),
    OnGameStart = makeEvent('OnGameStart'),
    OnCreatePlayer = makeEvent('OnCreatePlayer'),
    OnPlayerUpdate = makeEvent('OnPlayerUpdate'),
}
local rtValue = -1
local vanillaA, vanillaX, vanillaLeft, vanillaRight, menus, transfers = 0, 0, 0, 0, 0, 0
local lastMenu = nil
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
    onGrabItems=function(items) transfers=transfers+1; assert(#items==4) end,
    createMenu=function(_,_,items)
        menus=menus+1
        assert(#items==4)
        for _, index in ipairs({1,2,4,5}) do
            assert(items[index == 1 and 1 or index == 2 and 2 or index == 4 and 3 or 4] == objects[index])
        end
        local menu = {numOptions=2}
        function menu:addOptionOnTop() error('unexpected custom bulk option') end
        function menu:addOption() error('unexpected custom bulk option') end
        lastMenu=menu
        return menu
    end
}
ISInventoryPane = {
    update=function() end, prerender=function() end,
    doContextOnJoypadSelected=function() vanillaA=vanillaA+1 end
}
ISInventoryPage = {
    onJoypadDown=function(self,btn)
        if btn==Joypad.AButton then self.inventoryPane:doContextOnJoypadSelected() end
        if btn==Joypad.XButton then vanillaX=vanillaX+1 end
    end,
    onJoypadDirLeft=function() vanillaLeft=vanillaLeft+1 end,
    onJoypadDirRight=function() vanillaRight=vanillaRight+1 end,
}
local pane = setmetatable({
    player=0,inventory=inv,mode='details',items=objects,joyselection=0,
    doController=true,itemHgt=20,headerHgt=18,height=250,width=250
}, {__index=ISInventoryPane})
function pane:getAbsoluteX() return 0 end
function pane:getAbsoluteY() return 0 end
function pane:getYScroll() return 0 end
local page = setmetatable({player=0,joyfocus=true,inventoryPane=pane},{__index=ISInventoryPage})
pane.inventoryPage=page
page.onCharacter=true
getPlayerInventory=function(n) if n==0 then return page end end
getPlayerLoot=function() return nil end
getFocusForPlayer=function() return JoypadState.players[1] and JoypadState.players[1].focus end
setJoypadFocus=function(n,target) assert(n==0 and target==lastMenu) end
JoypadState.players[1].focus=page
assert(loadfile('Contents/mods/ZomboidRangeSelect/42/media/lua/client/ZRS_Client.lua'))()
assert(type(handlers.OnTick)=='function')
assert(type(handlers.OnGameStart)=='function')
assert(type(handlers.OnCreatePlayer)=='function')
assert(type(handlers.OnPlayerUpdate)=='function')
assert(type(ZRS.ensureHooks)=='function')
local tick = handlers.OnTick
handlers.OnGameStart()
handlers.OnPlayerUpdate(player)
local lateCalls = 0
ISInventoryPane.update = function() lateCalls = lateCalls + 1 end
assert(ISInventoryPane.update ~= ZRS.paneUpdateHook)
tick()
assert(ISInventoryPane.update == ZRS.paneUpdateHook)
pane:update()
assert(lateCalls == 1)

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

-- Horizontal navigation must not abandon a pane with pending marks.
page:onJoypadDirLeft()
assert(vanillaLeft==0 and ZRS.lastNav=='LEFT ignored while selection is pending')
page:onJoypadDirRight()
assert(vanillaRight==0 and ZRS.lastNav=='RIGHT ignored while selection is pending')

-- Context menu and transfer collect exactly the selected items.
page:onJoypadDown(Joypad.AButton)
assert(menus==1 and vanillaA==1)
assert(ZRS.lastMenuCount == 4 and ZRS.lastMenuSide=='PERSONAL')
assert(ZRS.lastMenuStatus=='vanilla multi-item menu')
assert(lastMenu and lastMenu.numOptions==2 and lastMenu.bulk==nil)
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

-- Once marks are cleared, horizontal navigation belongs to vanilla again.
JoypadState.players[1]={id=2,focus=page}
page.joyfocus=true
page.inventoryPane.doController=true
page:onJoypadDown(Joypad.BButton)
assert(require('ZRS_Core').count(state)==0)
page:onJoypadDirRight()
page:onJoypadDirLeft()
assert(vanillaRight==1 and ZRS.lastNav=='LEFT handled by vanilla')
assert(vanillaLeft==1)

-- Highlighting clips numerically and never mutates PZ's shared stencil.
local draws = {}
function pane:drawRect(x,y,w,h) draws[#draws+1]={x=x,y=y,w=w,h=h} end
function pane:setStencilRect() error('selection overlay touched shared stencil') end
function pane:clearStencilRect() error('selection overlay touched shared stencil') end
state.selected[objects[2]]=true
pane:prerender()
assert(#draws==1 and draws[1].y==38 and draws[1].h==20)
require('ZRS_Core').clear(state)

-- Check the new pane context hook is restored after later UI replacement.
ISInventoryPane.doContextOnJoypadSelected=function() error('late override') end
ZRS.ensureHooks('mock')
assert(ISInventoryPane.doContextOnJoypadSelected==ZRS.paneContextHook)
print('OK: B42 vanilla multi-item menu, bulk transfer, selection lock, stencil-safe highlight, late rehook')
