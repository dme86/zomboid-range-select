-- Pure shared/ load marker; no gameplay changes.
print('[ZRS-PROBE] SHARED FILE LOADED client=' ..
    tostring(type(isClient) == 'function' and isClient() or 'unknown') ..
    ' server=' .. tostring(type(isServer) == 'function' and isServer() or 'unknown'))
