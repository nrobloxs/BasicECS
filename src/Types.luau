--!strict

--[[
	Shared types for the component package. This module only exports types.
]]

--- The minimum shape every component object must satisfy.
--- Concrete components add their own fields/methods on top of this.
---
--- NOTE: `Destroy` takes `self: any` on purpose. If it were `self: Component`, a subclass
--- declaring `Destroy(self: MyComponent)` would fail function-parameter contravariance.
export type Component = {
	Entity: Instance,
	Destroy: (self: any) -> (),
}

--- What a module in the `Components` folder must return.
export type ComponentClass = {
	new: (Entity: Instance) -> Component,
}

--- tag -> component, for a single entity
export type ComponentMap = { [string]: Component }

--- entity -> (tag -> component)
export type EntityComponentMap = { [Instance]: ComponentMap }

--- Overloads for AddComponent. Return shape follows the argument shape.
export type AddComponentFn =
	((self: ComponentManager, Entity: Instance, ComponentTag: string) -> Component?)
	& ((self: ComponentManager, Entity: Instance, ComponentTags: { string }) -> ComponentMap)
	& ((self: ComponentManager, Entities: { Instance }, ComponentTag: string) -> { [Instance]: Component })
	& ((self: ComponentManager, Entities: { Instance }, ComponentTags: { string }) -> EntityComponentMap)

--- Overloads for RemoveComponentFrom. Values are `true` if a component was actually removed.
export type RemoveComponentFn =
	((self: ComponentManager, Entity: Instance, ComponentTag: string) -> boolean)
	& ((self: ComponentManager, Entity: Instance, ComponentTags: { string }) -> { [string]: boolean })
	& ((self: ComponentManager, Entities: { Instance }, ComponentTag: string) -> { [Instance]: boolean })
	& ((
		self: ComponentManager,
		Entities: { Instance },
		ComponentTags: { string }
	) -> { [Instance]: { [string]: boolean } })

export type ComponentManager = {
	-- Internal state (underscore = private by convention)
	_Components: { [Instance]: ComponentMap },
	_ByTag: { [string]: { [Instance]: Component } }, -- reverse index for ReturnEntitiesOfComponent
	_Classes: { [string]: ComponentClass | false }, -- false = failed to load, don't retry
	_Connections: { RBXScriptConnection },
	_Initialized: boolean,

	-- Lifecycle
	Init: (self: ComponentManager) -> (),
	Destroy: (self: ComponentManager) -> (),

	-- Mutation
	AddComponent: AddComponentFn,
	AddTemporaryComponent: (
		self: ComponentManager,
		Entity: Instance,
		ComponentTag: string,
		Duration: number
	) -> Component?,
	RemoveComponentFrom: RemoveComponentFn,

	-- Queries
	HasComponent: (self: ComponentManager, Entity: Instance, ComponentTag: string) -> boolean,
	GetAllComponentsFrom: (self: ComponentManager, Entity: Instance) -> ComponentMap,
	GetComponentFrom: (self: ComponentManager, Entity: Instance, ComponentTag: string) -> Component?,
	GetComponentsFrom: (self: ComponentManager, Entity: Instance, ComponentTags: { string }) -> ComponentMap,
	ReturnEntitiesOfComponent: (self: ComponentManager, ComponentTag: string) -> { Instance },
}

return {}
