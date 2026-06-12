local flags = require "./flags"

export type SourceNode<T> = {
    cache: T,
    [number]: Node<T>
}

export type Node<T> =  {
    cache: T,
    effect:  ((T) -> T) | (() -> T) | false,
    cleanups: { () -> () } | false,

    context: { [number]: unknown } | false,

    owned: { Node<T> } | false,
    owner: Node<T> | false,

    parents: { SourceNode<T> },
    [number]: Node<T> -- children
}

export type ElementNode = Node<false> & {
    element: true;
}

local scopes = { n = 0 } :: { [number]: Node<any>, n: number } -- scopes stack

-- effect function handler
local function efn(err: string)
    local trace = debug.traceback(err, 2)

    if string.find(err, "^effect error stacktrace") then -- if effect error is nested
        trace = string.gsub("    " .. trace, "\n", function() -- indent entire error
            return "\n    "
        end)
    end

    trace ..= "\nsource update stacktrace:"
    return trace
end

local function ycall<T, U>(fn: (T) -> U, arg: T): (boolean, string | U)
    local thread = coroutine.create(xpcall)
    local resumeOk, runOk, result = coroutine.resume(thread, fn, efn, arg)

    assert(resumeOk)
        
    if coroutine.status(thread) ~= "dead" then
        return false, debug.traceback(thread, "attempt to yield in reactive scope")
    end

    return runOk, result
end

local function getScope(): Node<unknown>?
    return scopes[scopes.n]
end

local function popScope()
    local n = scopes.n
    scopes.n = n - 1
    scopes[n] = nil
end

local function popInvalidElementScope()
    -- because an invalid element will propagate
    -- the error up, popping out only that element is not sufficient
    -- to combat that we clear all active element scopes

    local scope = getScope()
    while scope and (scope :: ElementNode).element do
        popScope()

        scope = getScope()
    end
end

local function assertStableScope(strict: boolean?): Node<unknown>
    local scope = getScope()

    if not scope then
        local callerName = debug.info(2, "n")
        return error(`cannot use {callerName}() outside a stable or reactive scope`, 0)
    elseif scope.effect then
        error("cannot create a new reactive scope inside another reactive scope", 0)
    elseif strict and (scope :: ElementNode).element then
        -- an error here caused by a property constructor
        -- propagates the error through all the components,
        -- leaving all the ancestors of the invalid one in an active scope
        
        popInvalidElementScope()

        local callerName: string = debug.info(2, "n")
        error(`cannot use {if #callerName == 0 then "anonymous" else callerName}() inside of an element scope`, 0)
    end

    return scope
end

local function assertElementScope(): ElementNode
    local scope = getScope() :: ElementNode

    if not scope or not scope.element then
        local callerName = debug.info(2, "n")
        return error(`cannot use {callerName}() outside a stable or element scope`, 0)
    end

    return scope
end

local function pushChild<T>(parent: SourceNode<any>, child: Node<any>)
    table.insert(parent, child)
    table.insert(child.parents, parent)
end

local function pushScope<T>(node: Node<T>)
    local n = scopes.n + 1
    scopes.n = n
    scopes[n] = node
end

local function pushCleanup<T>(node: Node<T>, cleanup: () -> ())
    if node.cleanups then
        table.insert(node.cleanups, cleanup)
    else
        node.cleanups = { cleanup }
    end
end

local function flushCleanups<T>(node: Node<T>)
    if node.cleanups then
        for _, cleanup in node.cleanups do
            local ok, err: string? = xpcall(cleanup, debug.traceback :: any)
            if not ok then error(`cleanup error: {err}`, 0) end
        end

        table.clear(node.cleanups)
    end
end

local function findAndSwapPop<T>(t: { T }, v: T)
    local i = table.find(t, v) :: number
    local n = #t
    t[i] = t[n]
    t[n] = nil
end

-- unparents all dependencies from the node
-- this is due to the node reobtaining them
-- anyways after the update that occurs after this is ran
local function unparent<T>(node: Node<T>)
    local parents = node.parents

    -- parent is source, node is reactive instance
    for i, parent in parents do
        findAndSwapPop(parent, node)
        parents[i] = nil
    end
end

local function destroy<T>(node: Node<T>)
    if flags.strict and table.find(scopes, node) then
        error("attempt to destroy an active scope", 0)
    end

    flushCleanups(node)
    unparent(node)
    
    if node.owner then
        findAndSwapPop(node.owner.owned :: { Node<T> }, node)
        node.owner = false
    end

    if node.owned then
        local owned = node.owned
        while owned[1] do destroy(owned[1]) end
    end
end

local function destroyOwned<T>(node: Node<T>)
    if node.owned then
        local owned = node.owned
        while owned[1] do destroy(owned[1]) end
    end
end

local updateQueue = { n = 0 } :: { n: number, [number]: Node<any> }

local function evaluateNode<T>(node: Node<T>)
    if flags.strict then
        if table.find(scopes, node) then
            error("a scope, that should rerun due to the update of a source, is already active", 0)
        end

        local initialValue = node.cache

        -- the for loop is something related to error reporting
        -- however im still not sure whats the reason behind it
        for i = 1, 2 do
            local currentValue = node.cache

            flushCleanups(node)
            destroyOwned(node)
    
            pushScope(node)
            local ok, newValue = ycall(node.effect :: (T) -> T, currentValue)
            popScope()
            
            if not ok then
                table.clear(updateQueue)
                updateQueue.n = 0
                error(`effect error stacktrace\n{newValue :: string}`, 0)
            end

            node.cache = newValue :: T
        end

        return initialValue ~= node.cache
    else
        local currentValue = node.cache

        flushCleanups(node)
        destroyOwned(node)

        pushScope(node)
        local ok, newValue = pcall(node.effect :: (T) -> T, node.cache)
        popScope()

        if not ok then
            table.clear(updateQueue)
            updateQueue.n = 0
            error(`effect error:\n{newValue}\n`, 0)
        end
    
        node.cache = newValue
        return currentValue ~= newValue
    end
end

local function queueChildrenForUpdate<T>(node: SourceNode<T>)
    local i = updateQueue.n
    while node[1] do
        local effect = node[1]

        i += 1
        updateQueue[i] = effect

        -- unparent effect from the source
        unparent(effect)
    end
    updateQueue.n = i
end

local function getUpdateQueueLength()
    return updateQueue.n
end

local function flushUpdateQueue(from: number)
    local i = from + 1
    while i <= updateQueue.n do
        local node = updateQueue[i]
        --assert(node.effect)

        if node.owner and evaluateNode(node) then
            queueChildrenForUpdate(node)
        end

        updateQueue[i] = false :: any
        i += 1
    end
    
    updateQueue.n = from
end

local function updateDescendants<T>(root: SourceNode<T>)
    -- queue length pre-effect update
    local n0 = updateQueue.n

    -- adds all children(effects) to the queue
    queueChildrenForUpdate(root)

    if flags.batch then return end

    local i = n0 + 1
    while i <= updateQueue.n do
        local node = updateQueue[i]
        --assert(node.effect)

        -- check if node is still owned in case destroyed after queued
        if node.owner and evaluateNode(node) then
            queueChildrenForUpdate(node)
        end

        updateQueue[i] = false :: any -- false instead of nil to avoid sparse
        i += 1
    end

    updateQueue.n = n0
end

local function pushScopeAsChildOf<T>(node: SourceNode<T>)
    local scope = getScope()
    if scope and scope.effect then -- do not track nodes with no effect
        pushChild(node, scope)
    end
end

local function createNode<T>(owner: false | Node<any>, effect: false | ((T) -> T) | (() -> T), value: T): Node<T>
    local node: Node<T> = {
        cache = value,
        effect = effect,
        cleanups = false,

        context = false,

        owner = owner,
        owned = false,

        parents = {},
    }

    if owner then
        if owner.owned then
            table.insert(owner.owned, node)
        else
            owner.owned = { node }
        end
    end

    return node
end

local function createElementNode(owner: false | Node<any>): ElementNode
    local node = createNode(owner, false, false) :: ElementNode
    node.element = true

    return node
end

local function createSourceNode<T>(value: T): SourceNode<T>
    return { cache = value }
end

local function getChildren<T>(node: Node<T>): { Node<unknown> }
    return { unpack(node) } :: { Node<any> }
end

local function setContext<T>(node: Node<T>, key: number, value: unknown)
    if node.context then
        node.context[key] = value
    else
        node.context = { [key] = value }
    end
end

return table.freeze {
    pushScope = pushScope,
    popScope = popScope,
    popInvalidElementScope = popInvalidElementScope,
    evaluateNode = evaluateNode,
    getScope = getScope,
    assertStableScope = assertStableScope,
    assertElementScope = assertElementScope,
    pushCleanup = pushCleanup,
    destroy = destroy,
    flushCleanups = flushCleanups,
    pushScopeAsChildOf = pushScopeAsChildOf,
    updateDescendants = updateDescendants,
    pushChild = pushChild,
    createNode = createNode,
    createElementNode = createElementNode,
    createSourceNode = createSourceNode,
    getChildren = getChildren,
    flushUpdateQueue = flushUpdateQueue,
    getUpdateQueueLength = getUpdateQueueLength,
    setContext = setContext,
    scopes = scopes,

    q = updateQueue
}
