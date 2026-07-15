--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)

-- ServiceRegistry is a server-facing name for the single shared lifecycle engine.
-- No dependency-resolution or lifecycle algorithm is implemented in this module.
return LifecycleRegistry
