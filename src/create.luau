local typeof = game and typeof or require "../test/mock".typeof :: never
local Instance = game and Instance or require "../test/mock".Instance :: never

local graph = require "./graph"
local defaults = require "./defaults"
local apply = require "./apply"
local flags = require "./flags"

local createElementNode = graph.createElementNode
local pushScope = graph.pushScope
local popScope = graph.popScope
local popInvalidElementScope = graph.popInvalidElementScope;
local getScope = graph.getScope;
local scopes = graph.scopes;

type Constructor = ({ [unknown]: unknown }) -> Instance

local function createConstructorForClass(class: string): Constructor
    local function constructor(properties: { [unknown]: unknown }): Instance
        local ok, instance: Instance = pcall(Instance.new, class :: any)
        if not ok then error(`invalid class name {class}`, 0) end

        if flags.defaults then
            local default: { [string]: unknown }? = defaults[class]
            if default then
                for i, v in default do
                    (instance :: any)[i] = v
                end
            end
        end

        return apply(instance, properties)
    end

    return constructor
end

local constructorCache = {} :: { [string]: Constructor }

local function __create(classOrInstance: string|Instance, properties: { [unknown]: unknown }?): unknown
    local constructor: Constructor
    if type(classOrInstance) == "string" then
        constructor = constructorCache[classOrInstance]
        if not constructor then
            constructor = createConstructorForClass(classOrInstance)
            constructorCache[classOrInstance] = constructor
        end
    else
        constructor = function(props)
            local clone = assert(classOrInstance:Clone(), "attempt to clone a non-archivable instance")
            return apply(clone, props)
        end
    end

    return if properties
        then constructor(properties)
        else constructor
end

-- TODO: remove support for different overloads
local function create(classOrInstance: string|Instance, properties: { [unknown]: unknown }?): unknown
    if type(classOrInstance) ~= "string" and typeof(classOrInstance) ~= "Instance" then
        error("bad argument #1, expected string or instance, got " .. typeof(classOrInstance), 0)
    end
    
    local scope = getScope()

    -- if outside of scope return clean element
    if not scope then
        return __create(classOrInstance, properties)
    end

    local node = createElementNode(scope)

    -- push the scope here to allow running
    -- property functions within the element scope
    pushScope(node)
    
    -- ^ this gets popped either inside the mountComponent
    -- if an effect error occurs
    -- OR in assertElementScope and assertStableScope in strict mode
    -- when any property constructor errors when called
    -- we do that because we cannot wrap the property constructors
    -- in a pcall, leaving us with popping the scope in the function
    -- calling the error
    
    local function mountComponent(constructorGetter: typeof(__create) | Constructor, ...: unknown): Instance
        local args = table.pack(...)
        
        if flags.strict then
            local ok, component = xpcall(constructorGetter :: (a: any, b: any) -> Instance, debug.traceback :: any, args[1], args[2])
            
            if not ok then
                popInvalidElementScope()
                error(`component effect error stacktrace\n{component :: any}`, 0)
            elseif scopes.n > 1 then
                popScope()
            end
            
            return component
        else
            local ok, component = pcall(constructorGetter :: (a: any, b: any) -> Instance, args[1], args[2])
            
            if not ok then
                popInvalidElementScope()
                error(`component effect error:\n{component :: any}`, 0)
            elseif scopes.n > 1 then
                popScope()
            end

            return component
        end
    end

    if properties ~= nil then
        return mountComponent(__create, classOrInstance, properties)
    else
        return function(props: { [unknown]: unknown })
            return mountComponent(__create(classOrInstance) :: Constructor, props)
        end
    end
end

type Instances = {
    Folder: Folder,
    BillboardGui: BillboardGui,
    CanvasGroup: CanvasGroup,
    Frame: Frame,
    ImageButton: ImageButton,
    ImageLabel: ImageLabel,
    ScreenGui: ScreenGui,
    ScrollingFrame: ScrollingFrame,
    SurfaceGui: SurfaceGui,
    TextBox: TextBox,
    TextButton: TextButton,
    TextLabel: TextLabel,
    UIAspectRatioConstraint: UIAspectRatioConstraint,
    UICorner: UICorner,
    UIGradient: UIGradient,
    UIGridLayout: UIGridLayout,
    UIListLayout: UIListLayout,
    Camera: Camera,
    WorldModel: WorldModel,
}

type function Properties(instance: type?)
    local properties = types.newtable()

    while instance do
        for i, v in instance:properties() do
            local connector = v.read and v.read.tag == "table" and v.read:readproperty(types.singleton("Connect"))
            if connector then
                local params = connector:parameters().head
                if not params then continue end
                local listener = params[2]
                if not listener then continue end
                properties:setproperty(i, types.optional(listener))
            elseif v.write then
                properties:setproperty(i, types.optional(types.unionof(
                    v.write,
                    types.newfunction({}, { head = { v.write } })
                )))
            end
        end

        instance = instance:readparent()
    end

    properties:setindexer(types.number, types.any)

    return properties
end

type Create = <Name>(Name|keyof<Instances>|"") -> (Properties<index<Instances, Name>>) -> index<Instances, Name>

return create :: Create
