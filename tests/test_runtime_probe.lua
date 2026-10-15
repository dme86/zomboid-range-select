-- Standalone Lua mock for the independent environment diagnostics.
local callbacks = {}
Events = {}
for _, name in ipairs({
    'OnFETick','OnGameStart','OnCreatePlayer','OnTick','OnPlayerUpdate',
    'OnPreUIDraw','OnPostUIDraw','OnServerStarted'
}) do
    callbacks[name] = {}
    Events[name] = { Add=function(fn) table.insert(callbacks[name],fn) end }
end
local phase = 'menu'
getSpecificPlayer = function()
    if phase=='game' then return { name='player' } end
end
MainScreen = {instance={inGame=false}}
isClient = function() return true end
isServer = function() return false end
JoypadState = {players={[1]={id=2}}}
assert(loadfile('Contents/mods/ZomboidRangeSelect/common/media/lua/client/ZRS_CommonProbe.lua'))()
assert(loadfile('Contents/mods/ZomboidRangeSelect/42/media/lua/shared/ZRS_SharedProbe.lua'))()
assert(loadfile('Contents/mods/ZomboidRangeSelect/42/media/lua/client/ZZ_ZRS_RuntimeProbe.lua'))()
assert(#callbacks.OnFETick==1 and #callbacks.OnTick==1 and #callbacks.OnPlayerUpdate==1)
assert(type(ZRSRuntimeProbe.handlers.OnTick)=='function')
callbacks.OnFETick[1]()
phase='game'; MainScreen.instance.inGame=true
callbacks.OnTick[1]()
callbacks.OnPlayerUpdate[1]()
callbacks.OnPostUIDraw[1]()
assert(ZRSRuntimeProbe.fired.OnFETick and ZRSRuntimeProbe.fired.OnTick)
assert(ZRSRuntimeProbe.fired.OnPlayerUpdate and ZRSRuntimeProbe.fired.OnPostUIDraw)
assert(loadfile('Contents/mods/ZomboidRangeSelect/42/media/lua/server/ZRS_ServerProbe.lua'))()
assert(#callbacks.OnServerStarted==1)
callbacks.OnServerStarted[1]()
assert(ZRSServerProbe.fired.OnServerStarted)
print('OK: probe load and independently registered frontend/world handlers')
