-- Pure B42 common/ load marker; does not change game behavior.
local player = nil
if type(getSpecificPlayer) == 'function' then
    local ok, result = pcall(getSpecificPlayer, 0)
    if ok then player = result end
end
print('[ZRS-PROBE] COMMON CLIENT FILE LOADED player=' ..
    tostring(player))
