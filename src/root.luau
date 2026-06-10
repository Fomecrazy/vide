local graph = require "./graph"
type Node<T> = graph.Node<T>
local createNode = graph.createNode
local pushScope = graph.pushScope
local popScope = graph.popScope
local destroy = graph.destroy

local refs = {}

local function root<T...>(fn: (destroy: () -> ()) -> T...): (() -> (), T...)
    local node = createNode(false, false, false)

    refs[node] = true -- prevent gc of root node

    local destroy = function()
        if not refs[node] then error "root already destroyed" end
        refs[node] = nil
        destroy(node)
    end

    pushScope(node)

    local result = { xpcall(fn, debug.traceback :: any, destroy) }

    popScope()

    if not result[1] then
        destroy()
        error(`error while running root():\n\n{result[2]}`, 0)
    end

    return destroy, unpack(result :: any, 2)
end

return root :: <T...>(fn: (destroy: () -> ()) -> T...) -> (() -> (), T...)
