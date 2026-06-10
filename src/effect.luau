local graph = require "./graph"
local createNode = graph.createNode
local assertStableScope = graph.assertStableScope
local evaluateNode = graph.evaluateNode

local function effect<T>(callback: (T) -> T, initialValue: T)
    local node = createNode(assertStableScope(), callback, initialValue)

    evaluateNode(node)
end

return effect :: (<T>(callback: (T) -> T, initialValue: T) -> ()) & ((callback: () -> ()) -> ())
