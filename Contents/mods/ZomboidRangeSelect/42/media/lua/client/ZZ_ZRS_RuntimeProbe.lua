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


-- On-screen diagnostics deliberately bypass the console/debug log.
-- TextManager:DrawString is used directly from PZ's post-UI render event.
-- This probe never changes controller input or the inventory selection.
probe.overlayVersion = '0.1.8'
probe.renderedFrames = 0

local function safeCall(fn, fallback)
    local ok, result = pcall(fn)
    if ok then return result end
    return fallback
end

local function playerZero()
    if type(getSpecificPlayer) ~= 'function' then return nil end
    return safeCall(function() return getSpecificPlayer(0) end)
end

local function padFor(player)
    local jd = JoypadState and JoypadState.players and JoypadState.players[1]
    if jd and type(jd.id) == 'number' and jd.id >= 0 then
        return jd.id, jd
    end
    local bind = player and safeCall(function() return player:getJoypadBind() end)
    if type(bind) == 'number' and bind >= 0 then return bind, jd end
    return nil, jd
end

local function currentPane(player)
    if not player or type(getPlayerInventory) ~= 'function' then return nil, nil end
    local inv = safeCall(function() return getPlayerInventory(0) end)
    local loot = type(getPlayerLoot) == 'function' and
        safeCall(function() return getPlayerLoot(0) end) or nil
    if inv and inv.joyfocus then return inv.inventoryPane, inv end
    if loot and loot.joyfocus then return loot.inventoryPane, loot end
    if inv and inv.inventoryPane and inv.inventoryPane.doController then
        return inv.inventoryPane, inv
    end
    if loot and loot.inventoryPane and loot.inventoryPane.doController then
        return loot.inventoryPane, loot
    end
    return inv and inv.inventoryPane or loot and loot.inventoryPane,
        inv or loot
end

local function describePane(pane, page, jd)
    if not pane then return 'Inventory: unavailable (not loaded)' end
    local cursor = pane.joyselection
    local rows = pane.items and #pane.items or 0
    local selected = 0
    if pane.zrsState and pane.zrsState.selected then
        for _, marked in pairs(pane.zrsState.selected) do
            if marked then selected = selected + 1 end
        end
    end
    local gate = 'ready'
    if pane.mode ~= 'details' then gate = 'mode=' .. tostring(pane.mode)
    elseif rows == 0 then gate = 'empty rows'
    elseif not (page and page.joyfocus or pane.doController) then gate = 'no controller focus'
    elseif jd and jd.focus and jd.focus ~= page then gate = 'focus on other UI'
    end
    return 'Inventory: rows=' .. rows .. ' cursor=' .. tostring(cursor) ..
        ' focus=' .. tostring(page and page.joyfocus) ..
        ' ctrl=' .. tostring(pane.doController) ..
        ' selected=' .. selected .. ' gate=' .. gate
end

local function eventStatus()
    local function yes(name)
        return probe.fired[name] and 'Y' or '-'
    end
    return 'Events: FE=' .. yes('OnFETick') .. ' Tick=' .. yes('OnTick') ..
        ' Player=' .. yes('OnPlayerUpdate') ..
        ' World=' .. yes('OnGameStart')
end

probe.drawHUD = function()
    local player = playerZero()
    local id, jd = padFor(player)
    local rt = nil
    if id ~= nil and JoypadAxis1d and JoypadAxis1d.RightTrigger then
        rt = safeCall(function() return JoypadAxis1d.RightTrigger:getValue(id) end)
    end
    local pane, page = currentPane(player)
    local lines = {
        'ZRS DEBUG v' .. probe.overlayVersion .. ' | HUD alive',
        'Player=' .. (player and 'YES' or 'NO') ..
            '  Controller=' .. tostring(id) .. '  RT=' .. tostring(rt),
        describePane(pane, page, jd),
        eventStatus()
    }
    -- Always draw in menu too. If it vanishes in-game, the UI listener is no
    -- longer receiving callbacks after world transition.
    if type(getTextManager) ~= 'function' or not UIFont then return end
    local manager = getTextManager()
    if not manager or not manager.DrawString then return end
    for i, line in ipairs(lines) do
        manager:DrawString(UIFont.Small, 18, 54 + (i - 1) * 18,
            line, 1, 0.9, 0.25, 1)
    end
    probe.renderedFrames = probe.renderedFrames + 1
end

if Events and Events.OnPostUIDraw then
    probe.handlers.DebugHUD = probe.drawHUD
    Events.OnPostUIDraw.Add(probe.handlers.DebugHUD)
    print('[ZRS-PROBE] DEBUG HUD registered v0.1.8')
end
