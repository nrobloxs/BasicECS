--- Minimum shape every component must satisfy. `Destroy` uses `self: any` so subclasses
--- can declare `Destroy(self: MyComponent)` without breaking parameter contravariance.
export type Component = {
	Entity: Instance,
	Destroy: (self: any) -> (),
}

--- What a module in the Components folder must return.
export type ComponentClass = {
	new: (Entity: Instance) -> Component,
}

--- tag -> component, for one entity
export type ComponentMap = { [string]: Component }

--- Precise type for the common call, loose fallback for the batch forms.
export type AddComponentFn =
	((self: ComponentManager, Entity: Instance, Tag: string) -> Component?)
	& ((self: ComponentManager, Entity: any, Tag: any) -> any)

export type RemoveComponentFn =
	((self: ComponentManager, Entity: Instance, Tag: string) -> boolean)
	& ((self: ComponentManager, Entity: any, Tag: any) -> any)

export type ComponentManager = {
	-- Internal (underscore = private)
	_Components: { [Instance]: ComponentMap },
	_ByTag: { [string]: { [Instance]: Component } },
	_Classes: { [string]: ComponentClass | false }, -- false = failed to load, don't retry
	_Connections: { RBXScriptConnection },
	_Initialized: boolean,
	_RootFolder: Folder?,

	-- Lifecycle
	Init: (self: ComponentManager, ComponentsFolder: Folder) -> (),
	Destroy: (self: ComponentManager) -> (),

	-- Mutation
	AddComponent: AddComponentFn,
	AddTemporaryComponent: (self: ComponentManager, Entity: Instance, Tag: string, Duration: number) -> Component?,
	RemoveComponentFrom: RemoveComponentFn,

	-- Queries
	HasComponent: (self: ComponentManager, Entity: Instance, Tag: string) -> boolean,
	GetAllComponentsFrom: (self: ComponentManager, Entity: Instance) -> ComponentMap,
	GetComponentFrom: (self: ComponentManager, Entity: Instance, Tag: string) -> Component?,
	GetComponentsFrom: (self: ComponentManager, Entity: Instance, Tags: { string }) -> ComponentMap,
	ReturnEntitiesOfComponent: (self: ComponentManager, Tag: string) -> { Instance },
}

return {}
