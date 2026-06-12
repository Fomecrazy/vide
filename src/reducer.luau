local source = require "./source"

export type Reducer<T, A> = (state: T, action: A) -> T;
type Dispatch<T, A> = (action: A) -> ();

local function reducer<T, A>(reducerFn: Reducer<T, A>, initialValue: T): (source.Source<T>, Dispatch<T, A>)
	local value = source(initialValue)

	local dispatch = function(action: A)
		local result = reducerFn(value(), action)
		value(result)
	end

	return value, dispatch
end

return reducer
