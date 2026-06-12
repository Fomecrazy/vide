local graph = require "./graph"

type Node<T> = graph.Node<T>
type ElementNode = graph.ElementNode;

local createNode = graph.createNode
local assertStableScope = graph.assertStableScope
local getScope = graph.getScope
local evaluateNode = graph.evaluateNode
local pushCleanup = graph.pushCleanup

local function updatePropertyEffect(p: {
    instance: Instance,
    property: string,
    source: () -> unknown  
})
    (p.instance :: any)[p.property] = p.source()
    return p
end

local function updateParentEffect(p: {
    instance: Instance,
    source: () -> Instance
})
    p.instance.Parent = p.source()
    return p
end

-- todo: investigate if "count" method used in indexes() and values() can improve performance here
local function updateChildrenEffect(p: {
    instance: Instance,
    currentChildrenSet: { [Instance]: true },
    newChildrenSet: { [Instance]: true },
    source: () -> Instance | { Instance }
})
    local currentChildrenSet: { [Instance]: true } = p.currentChildrenSet -- cache of all children parented before update
    local newChildrenSet: { [Instance]: true } = p.newChildrenSet -- cache of all children parented after update

    local newChildren = p.source() -- all (and only) children that should be parented after this update
    
    local function processChild(child: Instance | { Instance })
        if type(child) == "userdata" then
            if newChildrenSet[child :: Instance] then return end -- stops redundant reparenting

            newChildrenSet[child :: Instance] = true -- record child set from this update
            
            if not currentChildrenSet[child :: Instance] then
                (child :: Instance).Parent = p.instance -- if child wasn't already parented then parent it
            else 
                currentChildrenSet[child :: Instance] = nil -- remove child from cache if it was already in cache
            end  
        elseif type(child) == "table" then
            for _, child in child do
                processChild(child)
            end
        elseif type(child) == "function" then
            local node = createNode(assert(getScope()), updateChildrenEffect, {
                instance = p.instance,
                currentChildrenSet = {},
                newChildrenSet = {},
                source = child   
            });

            -- -- make element node
            (node :: ElementNode).element = true
    
            evaluateNode(node)

            pushCleanup(assert(getScope()), function()
                for child in node.cache.currentChildrenSet do
                    child.Parent = nil
                end
            end)
        end
    end

    processChild(newChildren)

    for child in currentChildrenSet do
        child.Parent = nil -- unparent all children that weren't in the new children set
    end

    table.clear(currentChildrenSet) -- clear cache, preserve capacity
    p.currentChildrenSet, p.newChildrenSet = newChildrenSet, currentChildrenSet

    return p
end


return {
    property = function(instance, property, source)
        local node = createNode(assertStableScope(), updatePropertyEffect, {
            instance = instance,
            property = property,
            source = source,
        });

        -- make element node
        (node :: ElementNode).element = true
        
        evaluateNode(node)
        
        return node
    end,
    
    parent = function(instance, parent)
        local node = createNode(assertStableScope(), updateParentEffect, {
            instance = instance,
            source = parent,
        });

        -- make element node
        (node :: ElementNode).element = true

        evaluateNode(node)
        
        return node
    end,

    children = function(instance, children)
    local node = createNode(assertStableScope(), updateChildrenEffect :: any, {
            instance = instance,
            currentChildrenSet = {},
            newChildrenSet = {},
            source = children
        });

        -- make element node
        (node :: ElementNode).element = true

        evaluateNode(node)

        pushCleanup(assertStableScope(), function()
            for child in node.cache.currentChildrenSet do
                child.Parent = nil
            end
        end)

        return node
    end
}
