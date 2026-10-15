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
-- Test actual focus changes, but don't replace focus with a context menu mock.
local focusChanges = 0
setJoypadFocus = function(_, target)
    if not target or not target.inventoryPane then return end
    local oldFocus = JoypadState.players[1] and JoypadState.players[1].focus
    if oldFocus and oldFocus.inventoryPane then
        oldFocus.joyfocus = false
        oldFocus.inventoryPane.doController = false
    end
    if not JoypadState.players[1] then JoypadState.players[1]={id=2} end
    JoypadState.players[1].focus = target
    target.joyfocus = true
    target.inventoryPane.doController = true
    focusChanges = focusChanges + 1
end
getFocusForPlayer = function() return JoypadState.players[1] and JoypadState.players[1].focus end
ISInventoryPane = {update=function() end, prerender=function() end}
local originalLeft, originalRight, originalCollapses = 0, 0, 0
ISInventoryPage = {
    onJoypadDown=function(_,btn)
        if btn==Joypad.AButton then vanillaA=vanillaA+1 end
        if btn==Joypad.XButton then vanillaX=vanillaX+1 end
    end,
    onJoypadDirLeft=function() originalLeft=originalLeft+1 end,
    onJoypadDirRight=function() originalRight=originalRight+1 end,
    collapseNow=function(self)
        originalCollapses=originalCollapses+1
        self.isCollapsed=true
    end
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
local lootInv = {isInCharacterInventory=function() return false end}
local lootPane = setmetatable({
    player=0, inventory=lootInv,mode='details',items={},joyselection=0,
    doController=false,itemHgt=20,headerHgt=18,height=250,width=250
}, {__index=ISInventoryPane})
local lootPage = setmetatable({
    player=0,joyfocus=false,inventoryPane=lootPane,isCollapsed=true,
    collapseCounter=200
}, {__index=ISInventoryPage})
lootPane.inventoryPage=lootPage
for _, p in ipairs({page,lootPage}) do
    p.setVisible=function(self,yes) self.visible=yes end
    p.clearMaxDrawHeight=function(self) self.maxDrawHeightCleared=true end
    p.ensureVisible=function(self,index) self.lastVisibleIndex=index end
end
getPlayerInventory=function(n) if n==0 then return page end end
getPlayerLoot=function(n) if n==0 then return lootPage end end
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

-- Directional D-pad switches focus, not window open/close.
page.isCollapsed=true
page:onJoypadDirRight()
assert(focusChanges==1 and lootPage.joyfocus and not page.joyfocus)
assert(not page.isCollapsed and not lootPage.isCollapsed)
assert(page.visible and lootPage.visible)
assert(page.maxDrawHeightCleared and lootPage.maxDrawHeightCleared)
assert(page.collapseCounter==0 and lootPage.collapseCounter==0)
assert(originalLeft==0 and originalRight==0)
lootPage:onJoypadDirRight() -- already on right; must not toggle
assert(focusChanges==1)
lootPage:onJoypadDirLeft()
assert(focusChanges==2 and page.joyfocus and not lootPage.joyfocus)
page:onJoypadDirLeft() -- already on left; must not toggle
assert(focusChanges==2)
-- Prevent mouse-away auto-collapse while controller focus is on inventory.
page:collapseNow()
lootPage:collapseNow()
assert(not page.isCollapsed and not lootPage.isCollapsed)
assert(originalCollapses==0)
-- Outside inventory focus, vanilla collapse behavior remains.
page.joyfocus=false
lootPage.joyfocus=false
page.inventoryPane.doController=false
lootPage.inventoryPane.doController=false
JoypadState.players[1].focus=nil
lootPage:collapseNow()
assert(lootPage.isCollapsed and originalCollapses==1)
-- Later UI reinitialization must restore the directional hook.
ISInventoryPage.onJoypadDirLeft=function() originalLeft=originalLeft+1 end
ZRS.ensureHooks('unit-test')
assert(ISInventoryPage.onJoypadDirLeft==ZRS.pageLeftHook)
print('OK: persistent lifecycle handlers, RT selection, directional pane navigation, collapse guard, fallback')
