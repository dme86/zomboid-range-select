package.path = 'Contents/mods/ZomboidRangeSelect/42/media/lua/shared/?.lua;' .. package.path
local Core = require 'ZRS_Core'
local function item(id)
    local x = {id = id, container = 'bag'}
    function x:getContainer() return self.container end
    return x
end
local function isItem(x) return x and x.id ~= nil end
local a,b,c,d,e,f = item('a'),item('b'),item('c'),item('d'),item('e'),item('f')
local rows = {a,b,c,d,e,f}
local s = Core.new()
local function selected(...)
    local yes = {...}
    assert(Core.count(s) == #yes, 'unexpected count')
    for _,obj in ipairs(yes) do assert(s.selected[obj], 'missing selected item ' .. obj.id) end
end

Core.begin(s, 2)
assert(Core.extend(s, rows, 4, isItem))
selected(b,c,d)
-- shrink live range; row d must fall out
assert(Core.extend(s, rows, 3, isItem))
selected(b,c)
assert(Core.release(s))
-- second separate range appends, doesn't replace the first
Core.begin(s, 6)
assert(Core.extend(s, rows, 5, isItem))
selected(b,c,e,f)
assert(Core.release(s))
-- tapping A without moving has no selection side effects
Core.begin(s, 1)
assert(not Core.release(s))
selected(b,c,e,f)
-- collapsed groups deduplicate the fake header item
local stack = {items = {a,a,d}}
Core.clear(s)
Core.begin(s, 1)
Core.extend(s, {stack,e}, 2, isItem)
selected(a,d,e)
assert(Core.isRowFullySelected(s, stack, isItem))
assert(#Core.actionItems(s,{stack,e},'bag',isItem)==3)
-- no stale references after moving an item out of a container
Core.release(s)
d.container = 'ground'
Core.prune(s, 'bag')
selected(a,e)
print('OK: selection ranges, unions, shrink, tap, stacks, action list, stale item pruning')
