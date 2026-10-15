-- World/server context diagnostic. No changes to gameplay.
ZRSServerProbe = ZRSServerProbe or { handlers = {}, fired = {} }
print('[ZRS-PROBE] SERVER FILE LOADED client=' ..
    tostring(type(isClient) == 'function' and isClient() or 'unknown') ..
    ' server=' .. tostring(type(isServer) == 'function' and isServer() or 'unknown'))
for _, name in ipairs({'OnGameStart', 'OnTick', 'OnServerStarted'}) do
    local event = Events and Events[name]
    if event and event.Add then
        local handler = function()
            if ZRSServerProbe.fired[name] then return end
            ZRSServerProbe.fired[name] = true
            print('[ZRS-PROBE] SERVER EVENT FIRED ' .. name)
        end
        ZRSServerProbe.handlers[name] = handler
        event.Add(handler)
        print('[ZRS-PROBE] SERVER EVENT REGISTERED ' .. name)
    end
end
