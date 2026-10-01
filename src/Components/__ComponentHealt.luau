--!strict

--[[
	Example component. The module name IS the CollectionService tag ("__ComponentHealth").
	Tag any Instance with it and the ComponentManager builds one of these for it.
]]

local Health = {}
Health.__index = Health

export type Health = typeof(setmetatable(
	{} :: {
		Entity: Instance,
		Current: number,
		Max: number,
	},
	Health
))

function Health.new(Entity: Instance): Health
	local MaxAttribute = Entity:GetAttribute("MaxHealth")
	local Max: number = if typeof(MaxAttribute) == "number" then MaxAttribute else 100

	return setmetatable({
		Entity = Entity,
		Current = Max,
		Max = Max,
	}, Health)
end

function Health.TakeDamage(self: Health, Amount: number)
	self.Current = math.max(0, self.Current - Amount)
end

function Health.Destroy(self: Health)
	-- Disconnect events / cancel threads here. The manager calls this exactly once.
end

return Health
