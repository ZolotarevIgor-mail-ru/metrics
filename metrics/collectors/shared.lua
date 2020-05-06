local clock = require('clock')
local fiber = require('fiber')
local log = require('log')

local Shared = {}

-- Create collector class with the list of instance methods copied from
-- this class (like an inheritance but with limited list of methods).
function Shared:new_class(kind, method_names)
    method_names = method_names or {}
    -- essential methods
    table.insert(method_names, 'new')
    table.insert(method_names, 'set_registry')
    table.insert(method_names, 'make_key')
    table.insert(method_names, 'append_global_labels')
    table.insert(method_names, 'collect')
    local methods = {}
    for _, name in pairs(method_names) do
        methods[name] = self[name]
    end
    local class = {kind = kind}
    class.__index = class
    return setmetatable(class, {__index = methods})
end

function Shared:new(name, help)
    if not name then
        error("Name should be set for %s")
    end
    return setmetatable({
        name = name,
        help = help or "",
        observations = {},
        label_pairs = {},
    }, self)
end

function Shared:set_registry(registry)
    self.registry = registry
end

function Shared.make_key(label_pairs)
    local parts = {}
    for k, v in pairs(label_pairs) do
        table.insert(parts, k .. '\t' .. v)
    end
    table.sort(parts)
    return table.concat(parts, '\t')
end

function Shared:set(num, label_pairs)
    num = num or 0
    label_pairs = label_pairs or {}
    local key = self.make_key(label_pairs)
    self.observations[key] = num
    self.label_pairs[key] = label_pairs
end

function Shared:inc(num, label_pairs)
    num = num or 1
    label_pairs = label_pairs or {}
    local key = self.make_key(label_pairs)
    local old_value = self.observations[key] or 0
    self.observations[key] = old_value + num
    self.label_pairs[key] = label_pairs
end

function Shared:dec(num, label_pairs)
    num = num or 1
    label_pairs = label_pairs or {}
    local key = self.make_key(label_pairs)
    local old_value = self.observations[key] or 0
    self.observations[key] = old_value - num
    self.label_pairs[key] = label_pairs
end

--- Measure latency and invoke collector with labels from given route
--
-- @param label_pairs either table with labels or function to generate labels.
--      If function is given its called with the results of pcall.
-- ... arguments for pcall to instrument
function Shared:observe_latency(label_pairs, ...)
    local start_time = clock.monotonic()
    local ok, result = pcall(...)
    local latency = clock.monotonic() - start_time

    xpcall(function()
        if type(label_pairs) == 'function' then
            label_pairs = label_pairs(ok, result)
        end
        self:observe(latency, label_pairs)
    end, function(err)
        log.error(debug.traceback('Saving metrics failed: ' .. tostring(err)))
    end)

    if not ok then
        error(result)
    end
    return result
end

function Shared:append_global_labels(label_pairs)
    local global_labels = self.registry and self.registry.label_pairs
    if global_labels == nil or next(global_labels) == nil then
        return label_pairs
    end

    local extended_label_pairs = table.copy(label_pairs)

    for k, v in pairs(global_labels) do
        if extended_label_pairs[k] == nil then
            extended_label_pairs[k] = v
        end
    end

    return extended_label_pairs
end

function Shared:collect()
    if next(self.observations) == nil then
        return {}
    end
    local result = {}
    for key, observation in pairs(self.observations) do
        local obs = {
            metric_name = self.name,
            label_pairs = self:append_global_labels(self.label_pairs[key]),
            value = observation,
            timestamp = fiber.time64(),
        }
        table.insert(result, obs)
    end
    return result
end

return Shared
