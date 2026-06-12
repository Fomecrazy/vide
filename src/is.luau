local registry = require("./registry")
local flags = require("./flags")

local function is<T>(instanceType: registry.VideInstance)
	return function<T>(instance: ((() -> T) & ((value: T) -> T)) | () -> T)
		local registeredType = registry.registry[tostring(instance):gsub("function: ", "")]
		
		if not registeredType then
			if flags.strict then
				error(debug.traceback(`called is("{instanceType}") for an unregistered instance.`, 2))
			else
				warn(`called is("{instanceType}") for an unregistered instance`)
			end
		end

		return registeredType == instanceType
	end
end

return is;
