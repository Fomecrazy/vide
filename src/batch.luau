local flags = require "./flags"
local graph = require "./graph"

local function batch(setter: () -> ())
    local alreadyBatching = flags.batch
    local from: number

    if not alreadyBatching then
        flags.batch = true
        from = graph.getUpdateQueueLength()
    end

    local ok, err: string? = xpcall(setter, debug.traceback :: any)

    if not alreadyBatching then
        flags.batch = false
        graph.flushUpdateQueue(from)
    end

    if not ok then error(`error occured while batching updates: {err}`, 0) end
end

return batch
