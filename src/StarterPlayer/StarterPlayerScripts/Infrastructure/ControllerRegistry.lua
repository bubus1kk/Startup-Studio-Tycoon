--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)

-- ControllerRegistry delegates to the same lifecycle engine as ServiceRegistry.
return LifecycleRegistry
