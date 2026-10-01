--!strict

local CollectionService = game:GetService("CollectionService")

local Utility = {}

--- Tags (and component module names) must start with this to be treated as components.
Utility.COMPONENT_PREFIX = "__Component"

function Utility.IsComponentTag(Tag: string): boolean
	return string.sub(Tag, 1, #Utility.COMPONENT_PREFIX) == Utility.COMPONENT_PREFIX
end

--- Returns every component tag currently on the entity.
function Utility.ResolveComponents(Entity: Instance): { string }
	local ResolvedTags: { string } = {}

	for _, Tag in CollectionService:GetTags(Entity) do
		if Utility.IsComponentTag(Tag) then
			table.insert(ResolvedTags, Tag)
		end
	end

	return ResolvedTags
end

function Utility.ShallowCopy<K, V>(Source: { [K]: V }): { [K]: V }
	local Copy: { [K]: V } = table.clone(Source)
	return Copy
end

return Utility
