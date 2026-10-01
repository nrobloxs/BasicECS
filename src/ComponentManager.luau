--!strict

local CollectionService = game:GetService("CollectionService")

local Types = require(script.Parent.Types)
local Utility = require(script.Parent.Utility)

export type Component = Types.Component
export type ComponentClass = Types.ComponentClass
export type ComponentMap = Types.ComponentMap
export type ComponentManager = Types.ComponentManager

local LOG_PREFIX = "[ComponentManager] "

local ComponentManager = {} :: ComponentManager

local function _Traceback(Error: any): string
	return debug.traceback(tostring(Error))
end

ComponentManager._Components = {}
ComponentManager._ByTag = {}
ComponentManager._Classes = {}
ComponentManager._Connections = {}
ComponentManager._Initialized = false

--------------------------------------------------------------------------------
-- Internals
--------------------------------------------------------------------------------

--- Loads (and caches) the class module for a tag. Missing modules are not cached so they
--- can appear later; modules that fail to load are cached as `false` to avoid warn spam.
local function _GetClass(self: ComponentManager, ComponentTag: string): ComponentClass?
	local Cached = self._Classes[ComponentTag]
	if Cached ~= nil then
		return if Cached then Cached else nil
	end

	local Folder = script.Parent:FindFirstChild("Components")
	local Module = if Folder then Folder:FindFirstChild(ComponentTag) else nil
	if not Module or not Module:IsA("ModuleScript") then
		return nil
	end

	local Success, Result = pcall(require, Module)
	if not Success then
		warn(`{LOG_PREFIX}Failed to require "{ComponentTag}": {Result}`)
		self._Classes[ComponentTag] = false
		return nil
	end

	if type(Result) ~= "table" or type((Result :: any).new) ~= "function" then
		warn(`{LOG_PREFIX}"{ComponentTag}" must return a table with a .new(Entity) constructor`)
		self._Classes[ComponentTag] = false
		return nil
	end

	local Class = Result :: ComponentClass
	self._Classes[ComponentTag] = Class
	return Class
end

--- Idempotent: returns the existing component if the entity already has one.
local function _AddComponent(self: ComponentManager, Entity: Instance, ComponentTag: string): Component?
	if not Utility.IsComponentTag(ComponentTag) then
		warn(`{LOG_PREFIX}"{ComponentTag}" is not a component tag (expected prefix "{Utility.COMPONENT_PREFIX}")`)
		return nil
	end

	local EntityComponents = self._Components[Entity]
	if EntityComponents and EntityComponents[ComponentTag] then
		return EntityComponents[ComponentTag]
	end

	local Class = _GetClass(self, ComponentTag)
	if not Class then
		return nil
	end

	local Success, Result = xpcall(Class.new, _Traceback, Entity)
	if not Success then
		warn(`{LOG_PREFIX}"{ComponentTag}".new errored for {Entity:GetFullName()}:\n{Result}`)
		return nil
	end
	local NewComponent = Result :: Component

	-- Only create bookkeeping tables once we know construction succeeded (no empty-table leaks).
	if not EntityComponents then
		EntityComponents = {}
		self._Components[Entity] = EntityComponents
	end
	EntityComponents[ComponentTag] = NewComponent

	local Bucket = self._ByTag[ComponentTag]
	if not Bucket then
		Bucket = {}
		self._ByTag[ComponentTag] = Bucket
	end
	Bucket[Entity] = NewComponent

	-- Keep CollectionService as the source of truth. The tag signal will re-enter
	-- _AddComponent, which is a no-op thanks to the idempotency check above.
	if not CollectionService:HasTag(Entity, ComponentTag) then
		CollectionService:AddTag(Entity, ComponentTag)
	end

	return NewComponent
end

--- Unregisters first, then destroys, so a Destroy that touches tags can't re-enter us.
local function _RemoveComponent(self: ComponentManager, Entity: Instance, ComponentTag: string): boolean
	local EntityComponents = self._Components[Entity]
	if not EntityComponents then
		return false
	end

	local Existing = EntityComponents[ComponentTag]
	if not Existing then
		return false
	end

	EntityComponents[ComponentTag] = nil
	if next(EntityComponents) == nil then
		self._Components[Entity] = nil
	end

	local Bucket = self._ByTag[ComponentTag]
	if Bucket then
		Bucket[Entity] = nil
		if next(Bucket) == nil then
			self._ByTag[ComponentTag] = nil
		end
	end

	local Success, Err = pcall(Existing.Destroy, Existing)
	if not Success then
		warn(`{LOG_PREFIX}"{ComponentTag}":Destroy errored for {Entity:GetFullName()}: {Err}`)
	end

	return true
end

local function _RemoveAllFrom(self: ComponentManager, Entity: Instance)
	local EntityComponents = self._Components[Entity]
	if not EntityComponents then
		return
	end

	-- Snapshot the tags: _RemoveComponent mutates the table we'd be iterating.
	local Tags: { string } = {}
	for Tag in EntityComponents do
		table.insert(Tags, Tag)
	end
	for _, Tag in Tags do
		_RemoveComponent(self, Entity, Tag)
	end
end

--- Starts following a tag: build components for tagged instances (now and in future),
--- destroy them when the tag is removed or the instance leaves the DataModel.
--- Unlike DescendantAdded/Removing, reparenting inside the DataModel does NOT churn components.
local function _Track(self: ComponentManager, ComponentTag: string)
	table.insert(
		self._Connections,
		CollectionService:GetInstanceAddedSignal(ComponentTag):Connect(function(Entity: Instance)
			_AddComponent(self, Entity, ComponentTag)
		end)
	)
	table.insert(
		self._Connections,
		CollectionService:GetInstanceRemovedSignal(ComponentTag):Connect(function(Entity: Instance)
			_RemoveComponent(self, Entity, ComponentTag)
		end)
	)

	for _, Entity in CollectionService:GetTagged(ComponentTag) do
		_AddComponent(self, Entity, ComponentTag)
	end
end

--- Shared argument dispatch for the polymorphic API. The result shape mirrors the arguments:
---   Instance,   string   -> Callback result
---   Instance,   {string} -> { [tag]: result }
---   {Instance}, string   -> { [entity]: result }
---   {Instance}, {string} -> { [entity]: { [tag]: result } }
--- nil results are omitted from the maps.
local function _Dispatch(FunctionName: string, Entity: any, ComponentTag: any, Callback: (Instance, string) -> any): any
	local TagIsString = type(ComponentTag) == "string"
	if not TagIsString and type(ComponentTag) ~= "table" then
		warn(`{LOG_PREFIX}{FunctionName}: ComponentTag must be a string or an array of strings`)
		return nil
	end

	if typeof(Entity) == "Instance" then
		if TagIsString then
			return Callback(Entity, ComponentTag)
		end

		local Results: { [any]: any } = {}
		for _, Tag in ComponentTag do
			if type(Tag) == "string" then
				local Result = Callback(Entity, Tag)
				if Result ~= nil then
					Results[Tag] = Result
				end
			end
		end
		return Results
	elseif type(Entity) == "table" then
		local Results: { [any]: any } = {}
		for _, SingleEntity in Entity do
			if typeof(SingleEntity) == "Instance" then
				local Result = _Dispatch(FunctionName, SingleEntity, ComponentTag, Callback)
				if Result ~= nil then
					Results[SingleEntity] = Result
				end
			end
		end
		return Results
	end

	warn(`{LOG_PREFIX}{FunctionName}: Entity must be an Instance or an array of Instances`)
	return nil
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function ComponentManager.AddComponent(self: ComponentManager, Entity: any, ComponentTag: any): any
	if Entity == nil or ComponentTag == nil then
		return nil
	end

	return _Dispatch("AddComponent", Entity, ComponentTag, function(SingleEntity: Instance, Tag: string)
		return _AddComponent(self, SingleEntity, Tag)
	end)
end

function ComponentManager.AddTemporaryComponent(
	self: ComponentManager,
	Entity: Instance,
	ComponentTag: string,
	Duration: number
): Component?
	if typeof(Entity) ~= "Instance" or type(ComponentTag) ~= "string" then
		warn(`{LOG_PREFIX}AddTemporaryComponent: invalid entity or component tag`)
		return nil
	end
	if type(Duration) ~= "number" or Duration < 0 or Duration ~= Duration then
		warn(`{LOG_PREFIX}AddTemporaryComponent: Duration must be a non-negative number`)
		return nil
	end

	local Existing = self._Components[Entity]
	if Existing and Existing[ComponentTag] then
		return Existing[ComponentTag]
	end

	local Added = _AddComponent(self, Entity, ComponentTag)
	if not Added then
		return nil
	end

	task.delay(Duration, function()
		local Current = self._Components[Entity]
		if Current and Current[ComponentTag] == Added then
			_RemoveComponent(self, Entity, ComponentTag)
			if CollectionService:HasTag(Entity, ComponentTag) then
				CollectionService:RemoveTag(Entity, ComponentTag)
			end
		end
	end)

	return Added
end

function ComponentManager.RemoveComponentFrom(self: ComponentManager, Entity: any, ComponentTag: any): any
	if Entity == nil or ComponentTag == nil then
		return nil
	end

	return _Dispatch("RemoveComponentFrom", Entity, ComponentTag, function(SingleEntity: Instance, Tag: string)
		local Removed = _RemoveComponent(self, SingleEntity, Tag)

		-- Keep tags in sync so the entity isn't re-componentised later.
		if Utility.IsComponentTag(Tag) then
			CollectionService:RemoveTag(SingleEntity, Tag)
		end

		return Removed
	end)
end

function ComponentManager.HasComponent(self: ComponentManager, Entity: Instance, ComponentTag: string): boolean
	local EntityComponents = self._Components[Entity]
	return EntityComponents ~= nil and EntityComponents[ComponentTag] ~= nil
end

--- Returns a shallow copy, so callers can't corrupt internal state.
function ComponentManager.GetAllComponentsFrom(self: ComponentManager, Entity: Instance): ComponentMap
	local EntityComponents = self._Components[Entity]
	if not EntityComponents then
		return {}
	end
	return Utility.ShallowCopy(EntityComponents)
end

function ComponentManager.GetComponentFrom(self: ComponentManager, Entity: Instance, ComponentTag: string): Component?
	local EntityComponents = self._Components[Entity]
	if not EntityComponents then
		return nil
	end
	return EntityComponents[ComponentTag]
end

--- Only tags the entity actually has appear in the result.
function ComponentManager.GetComponentsFrom(
	self: ComponentManager,
	Entity: Instance,
	ComponentTags: { string }
): ComponentMap
	local Found: ComponentMap = {}

	local EntityComponents = self._Components[Entity]
	if not EntityComponents then
		return Found
	end

	for _, Tag in ComponentTags do
		local Existing = EntityComponents[Tag]
		if Existing then
			Found[Tag] = Existing
		end
	end

	return Found
end

function ComponentManager.ReturnEntitiesOfComponent(self: ComponentManager, ComponentTag: string): { Instance }
	local Entities: { Instance } = {}

	local Bucket = self._ByTag[ComponentTag]
	if Bucket then
		for Entity in Bucket do
			table.insert(Entities, Entity)
		end
	end

	return Entities
end

function ComponentManager.Init(self: ComponentManager)
	if self._Initialized then
		warn(`{LOG_PREFIX}Init called more than once`)
		return
	end
	self._Initialized = true

	local Folder = script.Parent:FindFirstChild("Components")
	if not Folder then
		warn(`{LOG_PREFIX}No "Components" folder found next to the manager`)
		return
	end

	for _, Module in Folder:GetChildren() do
		if Module:IsA("ModuleScript") and Utility.IsComponentTag(Module.Name) then
			_Track(self, Module.Name)
		end
	end
end

--- Disconnects everything and destroys all live components. Tags are left untouched.
function ComponentManager.Destroy(self: ComponentManager)
	for _, Connection in self._Connections do
		Connection:Disconnect()
	end
	table.clear(self._Connections)

	local Entities: { Instance } = {}
	for Entity in self._Components do
		table.insert(Entities, Entity)
	end
	for _, Entity in Entities do
		_RemoveAllFrom(self, Entity)
	end

	table.clear(self._Classes)
	self._Initialized = false
end

return ComponentManager :: ComponentManager
