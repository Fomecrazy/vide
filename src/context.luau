local graph = require "./graph"
type Node<T> = graph.Node<T>
local createNode = graph.createNode
local getScope = graph.getScope
local pushScope = graph.pushScope
local popScope = graph.popScope
local setContext = graph.setContext

export type Context<T> = (() -> T) & (<U>(T, () -> U) -> U)

local nilSymbol = newproxy()
local count = 0

local function context<T>(...: T): Context<T>
    count += 1
    local id = count

    local hasDefault = select("#", ...) > 0
    local defaultValue = ...

    return function<T>(...): any -- todo: fix type error
        local scope: Node<unknown>? | false = getScope()

        if select("#", ...) == 0 then -- get
            while scope do
                local ctx = scope.context
    
                if not ctx then
                    scope = scope.owner
                    continue
                end

                local value = (ctx :: { unknown })[id]

                if value == nil then
                    scope = scope.owner
                    continue
                end
                
                return (if value ~= nilSymbol then value else nil) :: T
            end

            if hasDefault ~= nil then
                return defaultValue
            else
                error("attempt to get context when no context is set and no default context is set", 0)
            end
        else -- set
            if not scope then return error("attempt to set context outside of a vide scope", 0) end

            local value, component = ...
            
            local newScope = createNode(scope, false, false)
            setContext(newScope, id, if value == nil then nilSymbol else value)

            pushScope(newScope)

            local function efn(err: string) return debug.traceback(err, 3) end
            local ok, result = xpcall(component, efn)

            popScope()

            if not ok then
                error(`error while running context:\n\n{result}`, 0)
            end

            return result
        end

        -- return nil :: any
    end
end

return context
