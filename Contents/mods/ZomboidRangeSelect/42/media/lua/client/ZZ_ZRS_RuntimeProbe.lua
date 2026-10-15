-- Independent B42 diagnostics. No input changes; each event prints once.
ZRSRuntimeProbe = ZRSRuntimeProbe or {}
local probe = ZRSRuntimeProbe
probe.session = probe.session or tostring({})
probe.handlers = probe.handlers or {}
probe.fired = probe.fired or {}

local function context()
    local player = nil
    if type(getSpecificPlayer) == 'function' then
        local ok, result = pcall(getSpecificPlayer, 0)
        if ok then player = result end
    end
    local inGame = 'unknown'
    if MainScreen and MainScreen.instance then
        inGame = tostring(MainScreen.instance.inGame)
    end
    local padId = 'nil'
    if JoypadState and JoypadState.players and JoypadState.players[1] then
        padId = tostring(JoypadState.players[1].id)
    end
    return 'session=' .. probe.session .. ' player=' ..
        (player and 'present' or 'nil') .. ' inGame=' .. inGame ..
        ' pad=' .. padId
end

print('[ZRS-PROBE] CLIENT FILE LOADED ' .. context() ..
    ' selectionModule=' .. tostring(ZRS and ZRS.version or 'missing'))

local function hook(eventName)
    local ev = Events and Events[eventName]
    if not ev or not ev.Add then
        print('[ZRS-PROBE] CLIENT EVENT MISSING ' .. eventName)
        return
    end
    -- Global table retains handler references through file scope.
    local fn = function()
        if probe.fired[eventName] then return end
        probe.fired[eventName] = true
        print('[ZRS-PROBE] CLIENT EVENT FIRED ' ..
            eventName .. ' ' .. context())
    end
    probe.handlers[eventName] = fn
    ev.Add(fn)
    print('[ZRS-PROBE] CLIENT EVENT REGISTERED ' .. eventName)
end

-- FE, world, player and UI render entry points can be distinguished.
for _, name in ipairs({
    'OnFETick', 'OnGameStart', 'OnCreatePlayer', 'OnTick',
    'OnPlayerUpdate', 'OnPreUIDraw', 'OnPostUIDraw'
}) do
    hook(name)
end
