local function inlineTest(): string
    return debug.info(1, "n")
end

local isO2 = inlineTest() ~= "inlineTest"

return {
    strict = not isO2,
    defaults = true,
    deferNestedProperties = true,
    batch = false,
}
