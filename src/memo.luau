local registry = require "./registry"
local derive = require "./derive"

local function memo<T>(source: () -> T): () -> T
	local fn = derive(source, "memo")

	registry.registerVideInstance(fn, "memo")

	return fn
end

return memo;