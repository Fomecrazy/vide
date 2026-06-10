local typeof = game and typeof or require "../test/mock".typeof :: never

local flags = require "./flags"
local implicitEffect = require "./implicitEffect"
local _, isAction = require "./action"()
local graph = require "./graph"
type Node<T> = graph.Node<T>

type Array<V> = { V }
type ArrayOrV<V> = { V } | V
type Map<K, V> = { [K]: V }

type Cache = {
    -- event listeners to connect after properties are set
    events: Array<
        | string -- 1. event name
        | () -> () -- 2. listener
    >,

    -- actions to run after events are connected
    actions: setmetatable<Map<
        number, -- priority
        Array<(Instance) -> ()> -- action callbacks
    >, { __index: (any, i: number) -> Array<(Instance) -> ()> }>,

    -- what to parent the instance to after running actions
    parent: unknown,

    -- cache to detect duplicate property setting at same nesting depth
    nestedDebug: setmetatable<Map<
        number, -- depth
        Map<string, true> -- set of property names
    >, {
        __index: (any, i: number) -> Map<string, true>
    }>,

    -- each nested layer occupies two indexes: 1. table ref 2. nested depth
    -- e.g. { t1 = { t3 = {} }, t2 = {} } -> { t1, 1, t2, 1, t3, 2 }
    nestedStack: { {} | number }
}

local freeCache: Cache?

local function borrowCache(): Cache
    if freeCache then
        local cache = freeCache
        freeCache = nil
        return cache
    else
        return {
            events = {},
            actions = setmetatable({} :: any, { -- lazy init
                __index = function(self, i) self[i] = {}; return self[i] end
            }),
            parent = nil,
            nestedDebug = setmetatable({} :: any, {
                __index = function(self, i: number) self[i] = {}; return self[i] end
            }),
            nestedStack = {}
        }
    end
end

local function returnCache(cache: Cache )
    freeCache = cache
end

local function processProperties(properties: Map<unknown, unknown>, instance: Instance, cache: Cache, depth: number)
    for property, value in properties do
        if type(property) == "string" then
            if flags.strict then -- check for duplicate property assignment at nesting depth
                if cache.nestedDebug[depth][property] then
                    error(`duplicate property {property} at depth {depth}`, 0)
                end
                cache.nestedDebug[depth][property] = true
            end

            if property == "Parent" then
                cache.parent = value
                continue
            end

            if type(value) == "function" then 
                if typeof((instance :: any)[property]) == "RBXScriptSignal" then
                    table.insert(cache.events, property) -- add event name to buffer
                    table.insert(cache.events, value :: () -> ()) -- add event listener to buffer
                else
                    implicitEffect.property(instance, property, value :: () -> unknown) -- create implicit effect for property
                end
            else
                (instance :: any)[property] = value -- set property
            end    
        elseif type(property) == "number" then
            if type(value) == "function" then
                implicitEffect.children(instance, value :: () -> ArrayOrV<Instance>) -- bind children
            elseif type(value) == "table" then
                if isAction(value) then
                    table.insert(cache.actions[(value :: any).priority], (value :: any).callback :: (Instance) -> ()) -- add action to buffer
                elseif flags.deferNestedProperties then
                    table.insert(cache.nestedStack, value :: {})
                    table.insert(cache.nestedStack, depth + 1) -- push table to stack for later processing
                else
                    processProperties(value :: Map<unknown, unknown>, instance, cache, depth + 1)
                end
            elseif type(value) == "userdata" then
                (value :: Instance).Parent = instance -- parent child
            end
        end
    end
end

-- applies table of nested properties to an instance using full vide semantics
local function apply<T>(instance: T & Instance, properties: { [unknown]: unknown }): T
    if not properties then
        error "attempt to call a constructor returned by create() with no properties"
    end

    local caches = borrowCache()
    local events = caches.events
    local actions = caches.actions
    local nestedDebug = caches.nestedDebug
    local nestedStack = caches.nestedStack

    -- process all properties
    local depth = 1
    repeat
        processProperties(properties, instance, caches, depth)
        depth = table.remove(nestedStack) :: number
        properties = table.remove(nestedStack) :: { [unknown]: unknown }
    until not properties

    for i = 1, #events, 2 do
        local eventName = events[i]
        local eventListener = events[i + 1]
        ;(instance :: any)[eventName]:Connect(eventListener)
    end

    for _, queued in actions do
        for _, callback in queued do
            callback(instance)
        end
    end

    local parent = caches.parent
    if parent then
        if type(parent) == "function" then
            implicitEffect.parent(instance, parent :: () -> Instance)
        else
            instance.Parent = parent :: Instance
        end
    end

    table.clear(events)
    for _, queued in actions do table.clear(queued) end
    caches.parent = nil
    if flags.strict then table.clear(nestedDebug) end
    table.clear(nestedStack)

    returnCache(caches)

    return instance
end

return apply
