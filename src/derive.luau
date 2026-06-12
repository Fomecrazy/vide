local graph = require "./graph"
local createNode = graph.createNode
local pushScopeAsChildOf = graph.pushScopeAsChildOf
local assertStableScope = graph.assertStableScope
local assertElementScope = graph.assertElementScope;
local evaluateNode = graph.evaluateNode

local function derive<T>(source: () -> T, hookType: "memo" | "map" | nil): () -> T
    local asserter = assertStableScope(hookType == "memo")
    if hookType == "map" then
        asserter = assertElementScope()
    end

    local node = createNode(asserter, source, false :: any)

    evaluateNode(node)

    return function()
        pushScopeAsChildOf(node)
        return node.cache
    end
end

return derive
