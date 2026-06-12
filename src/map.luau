-- local registry = require "./registry"
local derive = require "./derive"

local function map<T>(source: () -> T): () -> T
	local fn = derive(source, "map")

	-- dont register as getting map functions
	-- is impossible i think
	-- registry.registerVideInstance(fn, "map")

	return fn
end

return map
