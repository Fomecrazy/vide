local graph = require "./graph"
type Node<T> = graph.Node<T>
local createSourceNode = graph.createSourceNode
local pushScopeAsChildOf = graph.pushScopeAsChildOf
local updateDescendants = graph.updateDescendants

export type Source<T> = (() -> T) & ((value: T) -> T)

local function source<T>(initialValue: T): Source<T>
    local node = createSourceNode(initialValue)

    local function updateSource(...): T
        if select("#", ...) == 0 then -- no args were given
            pushScopeAsChildOf(node)
            return node.cache
        end

        local v = ... :: T
        if node.cache == v and (type(v) ~= "table" or table.isfrozen(v)) then 
            return v
        end

        node.cache = v
        updateDescendants(node)
        return v
    end

    return updateSource
end

return source :: (<T>(initialValue: T) -> Source<T>) & (<T>() -> Source<T>)
