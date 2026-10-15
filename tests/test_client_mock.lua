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
local lastMenu = nil
local bulkTransferred = 0
local focusSwitches=0
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
    onPutItems=function(items)
        bulkTransferred=bulkTransferred+1
        assert(#items==4)
    end,
    onGrabItems=function(items) transfers=transfers+1; assert(#items==4) end,
    createMenu=function(_,_,items)
        menus=menus+1
        assert(#items==4)
        for _, index in ipairs({1,2,4,5}) do
            assert(items[index == 1 and 1 or index == 2 and 2 or index == 4 and 3 or 4] == objects[index])
        end
        local menu = {numOptions=2}
        function menu:addOptionOnTop(label, target, callback, playerNum)
            self.numOptions = self.numOptions + 1
            self.bulk={label=label,target=target,callback=callback,playerNum=playerNum}
        end
        lastMenu=menu
        return menu
    end
}
ISInventoryPane = {
    update=function() end, prerender=function() end,
    doContextOnJoypadSelected=function() vanillaA=vanillaA+1 end
}
ISInventoryPage = {
    update=function() end,
    collapseNow=function(self) self.isCollapsed=true end,
    onJoypadDown=function(self,btn)
        if btn==Joypad.AButton then self.inventoryPane:doContextOnJoypadSelected() end
        if btn==Joypad.XButton then vanillaX=vanillaX+1 end
    end,
    onJoypadDirLeft=function() error('unexpected fallback LEFT') end,
    onJoypadDirRight=function() error('unexpected fallback RIGHT') end,
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
local lootContainer={isInCharacterInventory=function() return false end}
local lootPane=setmetatable({
    player=0,inventory=lootContainer,mode='details',items={},joyselection=0,
    doController=false,itemHgt=20,headerHgt=18,height=250,width=250
}, {__index=ISInventoryPane})
local lootPage=setmetatable({
    player=0,inventoryPane=lootPane,onCharacter=false,joyfocus=false,
    isCollapsed=true,collapseCounter=150
}, {__index=ISInventoryPage})
lootPane.inventoryPage=lootPage
for _,pg in ipairs({page,lootPage}) do
    pg.isCollapsed=true
    pg.visible=false
    pg.getIsVisible=function(self) return self.visible end
    pg.setVisible=function(self,value) self.visible=value end
    pg.clearMaxDrawHeight=function(self) self.heightRestored=true end
end
page.onCharacter=true
getPlayerInventory=function(n) if n==0 then return page end end
getPlayerLoot=function(n) if n==0 then return lootPage end end
setJoypadFocus=function(n,target)
    -- Vanilla context menus aren't inventory pages; simulated loss of focus
    -- happens only when switching between the two inventory panes.
    if not target or not target.inventoryPane then return end
    assert(n==0)
    if JoypadState.players[1].focus then
        JoypadState.players[1].focus.joyfocus=false
        JoypadState.players[1].focus.inventoryPane.doController=false
    end
    target.joyfocus=true
    target.inventoryPane.doController=true
    JoypadState.players[1].focus=target
    focusSwitches=focusSwitches+1
end
getFocusForPlayer=function() return JoypadState.players[1] and JoypadState.players[1].focus end
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

-- Context menu and transfer collect exactly the selected items.
page:onJoypadDown(Joypad.AButton)
assert(menus==1 and vanillaA==1)
assert(ZRS.lastMenuCount == 4 and ZRS.lastMenuSide=='PERSONAL')
assert(ZRS.lastMenuStatus=='bulk option added')
assert(lastMenu and lastMenu.bulk and #lastMenu.bulk.target==4)
assert(lastMenu.bulk.label:find('markierte nehmen',1,true))
lastMenu.bulk.callback(lastMenu.bulk.target,lastMenu.bulk.playerNum)
assert(transfers==1)
page:onJoypadDown(Joypad.XButton)
assert(transfers==2 and vanillaX==0)
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

-- B42 left/right should be directional, and keep both inventory pages expanded.
JoypadState.players[1]={id=2,focus=page}
page.joyfocus=true
page.inventoryPane.doController=true
page:onJoypadDirRight()
assert(ZRS.lastNav:find('RIGHT target=LOOT actual=LOOT',1,true))
assert(focusSwitches==1 and lootPage.joyfocus and not page.joyfocus)
assert(not lootPage.isCollapsed and not page.isCollapsed)
assert(page.visible and lootPage.visible)
-- Pressing right again does not toggle back to personal.
lootPage:onJoypadDirRight()
assert(focusSwitches==1)
lootPage:onJoypadDirLeft()
assert(ZRS.lastNav:find('LEFT target=PERSONAL actual=PERSONAL',1,true))
assert(focusSwitches==2 and page.joyfocus and not lootPage.joyfocus)
page:onJoypadDirLeft()
assert(focusSwitches==2)

-- Simulate auto-collapsing an inactive window; update should reopen both
-- only while the controller focus is on an inventory page.
lootPage.isCollapsed=true
lootPage:update()
assert(not lootPage.isCollapsed)
JoypadState.players[1].focus=nil
page.joyfocus=false
page.inventoryPane.doController=false
lootPage.isCollapsed=true
lootPage:update()
assert(lootPage.isCollapsed)
-- Auto-collapse during controller focus must be suppressed, on either side.
JoypadState.players[1].focus=page
page.joyfocus=true
lootPage.isCollapsed=false
lootPage:collapseNow()
assert(not lootPage.isCollapsed)
JoypadState.players[1].focus=nil
page.joyfocus=false
lootPage:collapseNow()
assert(lootPage.isCollapsed)

-- Check the new pane context hook is restored after later UI replacement.
ISInventoryPane.doContextOnJoypadSelected=function() error('late override') end
ZRS.ensureHooks('mock')
assert(ISInventoryPane.doContextOnJoypadSelected==ZRS.paneContextHook)
print('OK: B42 bulk menu action invoked with 4 items, RT, directional navigation, collapse guard, late rehook')
