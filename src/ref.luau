local untrack = require "./untrack"
local source = require "./source"

export type MutableRef<T> = {
	current: T;
}

local function ref<T>(initialValue: T): MutableRef<T>
	local value = source(initialValue)

	local refObject = setmetatable({}, {
		__index = function(_, index): T?
			if index ~= "current" then return nil end
			
			return untrack(value)
		end,
		__newindex = function(_, index, newValue)
			if index ~= "current" then return end
			
			value(newValue)
		end
	})

	return refObject :: MutableRef<T>;
end

return ref
