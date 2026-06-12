export type VideInstance = "source" | "memo" | "map"

local registry: { [string]: VideInstance } = {}

local function registerVideInstance<T>(instance: (() -> T & (value: T) -> T), instanceType: VideInstance)
	local instanceId = tostring(instance):gsub("function: ", "")
	
	if registry[instanceId] then return end

	registry[instanceId] = instanceType
end

return { registerVideInstance = registerVideInstance, registry = registry };