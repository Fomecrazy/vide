local graph = require "./graph"
local createNode = graph.createNode
local pushScopeAsChildOf = graph.pushScopeAsChildOf
local assertStableScope = graph.assertStableScope
local evaluateNode = graph.evaluateNode

local function derive<T>(source: () -> T): () -> T
    local node = createNode(assertStableScope(), source, false :: any)

    evaluateNode(node)

    return function()
        pushScopeAsChildOf(node)
        return node.cache
    end
end

return derive
