local source = require "./source"
local derive = require "./derive"
local effect = require "./effect"
local switch = require "./switch"

type Array<T> = { T }
type Source<T> = () -> T

type function Not(ty)
    return types.negationof(ty)
end

local function show<T, Obj>(
    input: Source<T?>,
    component: (Source<T>, Source<boolean>) -> (Obj, ...number),
    fallback: ((Source<boolean>) -> (Obj, ...number))?
): Source<nil | Obj | Array<Obj>>
    local filteredInput = source()

    effect(function()
        local v = input() 
        if v then
            filteredInput(v)
        end
    end)

    local inputIsTruthy = derive(function()
        return not not input()
    end)

    return switch(inputIsTruthy) {
        [true] = function(present)
            return component(filteredInput, present)
        end,
        [false] = fallback :: typeof(fallback) & Not<nil>
    }
end

return show
