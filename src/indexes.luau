local branch = require "./branch"
local source = require "./source"
local effect = require "./effect"
local timeout = require "./timeout" ()

type Array<T> = { T }
type Map<K, V> = { [K]: V }
type Source<T> = () -> T

local function indexes<K, V, Obj>(
    input: Source<Map<K, V>>,
    component: (Source<V>, K, Source<boolean>) -> (Obj, ...number)
): Source<Array<Obj>>
    local updateCount = 0
    local scopes = {} :: Map<K, {
        destroy: () -> (),
        object: Obj,
        value: V?,
        valueSource: (V?) -> V,
        count: number,
        delay: number,
        present: (() -> boolean) & (boolean) -> boolean,
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

        -- create or update scopes
        for i, v in data do
            local scope = scopes[i]

            if scope == nil then -- create new scope and create component
                local valueSource = source(v)
                local present = source(false)

                local delay = nil :: number?
                local destroy, object = branch(function()
                    local object, t = component(valueSource, i, present)
                    delay = t
                    return object
                end)

                present(true)
                
                doChildrenNeedUpdate = true

                scopes[i] = {
                    destroy = destroy,
                    object = object,
                    value = v,
                    valueSource = valueSource :: V,
                    count = count,
                    delay = delay or 0,
                    present = present,
                    timeout = nil,
                }
            else -- update scope
                scope.count = count

                if scope.value ~= v then
                    if scope.timeout then -- index is in input table again; cancel destruction
                        scope.timeout.cancel = true
                        scope.timeout = nil
                        scope.present(true)
                    end
                    
                    scope.value = v
                    scope.valueSource(v)
                end
            end
        end

        -- destroy scopes
        for i, scope in scopes do
            if scope.count < count then -- if count is not latest then index is no longer in the input table
                scope.present(false)

                if scope.delay == 0 then
                    scope.destroy()
                    scopes[i] = nil
                    doChildrenNeedUpdate = true
                else
                    scope.value = nil -- set to nil for the `scope.value ~= v` check
                    if scope.timeout == nil then
                        scope.timeout = timeout(scope.delay, function() -- todo: possible redundant updates
                            scope.destroy()
                            scopes[i] = nil
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

return indexes
