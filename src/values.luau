local flags = require "./flags"
local branch = require "./branch"
local source = require "./source"
local effect = require "./effect"
local timeout = require "./timeout" ()

type Array<T> = { T }
type Map<K, V> = { [K]: V }
type Source<T> = () -> T

local function values<K, V, Obj>(
    input: Source<Map<K, V>>,
    component: (V, Source<K>, Source<boolean>) -> (Obj, ...number)
): Source<Array<Obj>>
    local updateCount = 0
    local scopes = {} :: Map<V, {
        destroy: () -> (),
        object: Obj,
        index: K?,
        indexSource: (K?) -> K,
        count: number,
        delay: number,
        present: (() -> boolean) & ((boolean) -> boolean),
        timeout: { cancel: boolean }?,
    }>

    local output = source({} :: Array<Obj>)
    local function updateOutput()
        local objects = table.create(4)

        for _, scope in scopes do
            table.insert(objects, scope.object)
        end

        output(objects)
    end

    effect(function()
        local data = input()

        local count = updateCount
        updateCount += 1

        local doChildrenNeedUpdate = false -- set to true if a scope is created or destroyed

        if flags.strict then -- check for duplicate values
            local map = {}
            for _, v in data do
                if map[v] then
                    error("table source passed to `values()` contains duplicate values", 0)
                end
                map[v] = true
            end
        end

        -- create or update scopes
        for i, v in data do
            local scope = scopes[v]

            if scope == nil then -- create new scope and create component
                local indexSource = source(i)
                local present = source(false)

                local delay = nil :: number?
                local destroy, object = branch(function()
                    local object, t = component(v, indexSource, present)
                    delay = t
                    return object
                end)

                present(true)
                
                doChildrenNeedUpdate = true

                scopes[v] = {
                    destroy = destroy,
                    object = object,
                    index = i,
                    indexSource = indexSource :: (K?) -> K,
                    count = count,
                    delay = delay or 0,
                    present = present,
                    timeout = nil,
                }
            else -- update scope
                scope.count = count

                if scope.index ~= i then
                    if scope.timeout then -- value is in input table again; cancel destruction
                        scope.timeout.cancel = true
                        scope.timeout = nil
                        scope.present(true)
                    end
                    
                    scope.index = i
                    scope.indexSource(i)
                end
            end
        end

        -- destroy scopes
        for v, scope in scopes do
            if scope.count < count then -- if count is not latest then value is no longer in the input table
                scope.present(false)

                if scope.delay == 0 then
                    scope.destroy()
                    scopes[v] = nil
                    doChildrenNeedUpdate = true
                else
                    scope.index = nil -- set to nil for the `scope.index ~= i` check
                    if scope.timeout == nil then
                        scope.timeout = timeout(scope.delay, function() -- todo: possible redundant updates
                            scope.destroy()
                            scopes[v] = nil
                            updateOutput()
                        end)
                    end
                end
            end
        end

        if doChildrenNeedUpdate then
            updateOutput()
        end
    end)

    return output
end

return values
