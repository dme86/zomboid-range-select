-- Zomboid Range Select: game-independent selection state.
-- A selection stores item references, never list indices: inventory rows can be reordered.
local Core = {}

local function clone(map)
    local result = {}
    for k, value in pairs(map or {}) do
        if value then result[k] = true end
    end
    return result
end

local function visitRow(row, isItem, fn)
    if not row then return end
    if isItem(row) then
        fn(row)
    elseif type(row) == 'table' and type(row.items) == 'table' then
        -- Stack headers include a duplicated first item in vanilla PZ; sets deduplicate it.
        for _, item in ipairs(row.items) do
            if isItem(item) then fn(item) end
        end
    end
end

function Core.new()
    return {selected = {}, anchor = nil, base = nil, dragging = false}
end

function Core.clear(state)
    state.selected = {}
    state.anchor = nil
    state.base = nil
    state.dragging = false
end

function Core.begin(state, anchor)
    state.anchor = anchor
    state.base = clone(state.selected)
    state.dragging = false
end

function Core.extend(state, rows, cursor, isItem)
    if not state.anchor then return false end
    if cursor == state.anchor and not state.dragging then return false end
    local nextSelection = clone(state.base)
    local first = math.min(state.anchor, cursor)
    local last = math.max(state.anchor, cursor)
    for i = first, last do
        visitRow(rows[i], isItem, function(item) nextSelection[item] = true end)
    end
    state.selected = nextSelection
    state.dragging = true
    return true
end

function Core.release(state)
    local wasDragging = state.dragging
    state.anchor = nil
    state.base = nil
    state.dragging = false
    return wasDragging
end

function Core.count(state)
    local count = 0
    for _, marked in pairs(state.selected) do
        if marked then count = count + 1 end
    end
    return count
end

function Core.prune(state, inventory)
    for item in pairs(state.selected) do
        if item:getContainer() ~= inventory then state.selected[item] = nil end
    end
end

function Core.isRowFullySelected(state, row, isItem)
    local sawItem, all = false, true
    visitRow(row, isItem, function(item)
        sawItem = true
        if not state.selected[item] then all = false end
    end)
    return sawItem and all
end

function Core.actionItems(state, rows, inventory, isItem)
    local items, seen = {}, {}
    for _, row in ipairs(rows) do
        visitRow(row, isItem, function(item)
            if state.selected[item] and not seen[item] and item:getContainer() == inventory then
                seen[item] = true
                items[#items + 1] = item
            end
        end)
    end
    return items
end

return Core
