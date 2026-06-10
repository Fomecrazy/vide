type Destroyable = {
    destroy: (any) -> ();
    disconnect: (any) -> ();
    Destroy: (any) -> ();
    Disconnect: (any) -> ();
}

local typeof = game and typeof or require "../test/mock".typeof :: never

local graph = require "./graph"
local getScope = graph.getScope
local pushCleanup = graph.pushCleanup

local function helper(obj: Destroyable)
    return
        if typeof(obj) == "RBXScriptConnection" then function() obj:Disconnect() end
        elseif type(obj) == "thread" then function() task.cancel(obj) end
        elseif typeof(obj) == "Instance" then function() obj:Destroy() end
        elseif obj.destroy then function() obj:destroy() end
        elseif obj.disconnect then function() obj:disconnect() end
        elseif obj.Destroy then function() obj:Destroy() end
        elseif obj.Disconnect then function() obj:Disconnect() end
        else error "cannot cleanup given object"
end

local function cleanup(value: unknown)
    local scope = getScope()

    if not scope then
        error "cannot cleanup outside a stable or reactive scope"
    end; assert(scope)

    if type(value) == "function" then
        pushCleanup(scope, value :: () -> ())
    else
        pushCleanup(scope, helper(value :: Destroyable))
    end
end

type Disconnectable = { disconnect: (any) -> () } | { Disconnect: (any) -> () }

return cleanup ::
    ( (callback: () -> ()) -> () ) &
    ( (thread: thread) -> () ) &
    ( (instance: Destroyable) -> () ) &
    ( (connection: Disconnectable) -> () ) &
    ( (instance: Instance) -> () ) &
    ( (connection: RBXScriptConnection) -> () )

