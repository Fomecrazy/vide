local graph = require "./graph"
type Node<T> = graph.Node<T>
local createNode = graph.createNode
local pushScope = graph.pushScope
local popScope = graph.popScope
local destroy = graph.destroy
local getScope = graph.getScope

local function branch<T>(fn: () -> T): (() -> (), T)
    local current = getScope()
    if not current then
        error(`cannot use branch() outside a stable or reactive scope`, 0)
    end

    local parent = current.owner
    if not parent then
        error(`current scope is not owned by a scope`, 0)
    end

    local node = createNode(parent, false, false)

    local destroy = function()
        destroy(node)
    end

    pushScope(node)

    local ok, result = xpcall(fn, debug.traceback :: any)

    popScope()

    if not ok then
        destroy()
        error(`error while running branch():\n\n{result}`, 0)
    end

    return destroy, result
end

return branch
