--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientDependencyResolver = require(ReplicatedStorage.Shared.Infrastructure.ClientDependencyResolver)
local TestHarness = require(script.Parent.Parent.TestHarness)

type TestCase = TestHarness.TestCase

local ClientDependencyResolverSpec = {}

local function waitsForRuntimeCopiedDependenciesTest()
	local playerScripts = Instance.new("Folder")
	playerScripts.Name = "PlayerScriptsFixture"

	task.defer(function()
		local infrastructure = Instance.new("Folder")
		infrastructure.Name = "Infrastructure"
		infrastructure.Parent = playerScripts

		task.defer(function()
			local controllerRegistry = Instance.new("ModuleScript")
			controllerRegistry.Name = "ControllerRegistry"
			controllerRegistry.Parent = infrastructure

			local remoteClient = Instance.new("ModuleScript")
			remoteClient.Name = "RemoteClient"
			remoteClient.Parent = infrastructure
		end)
	end)

	local result = ClientDependencyResolver.resolvePlayerScripts(playerScripts, 1)
	TestHarness.assertTrue(result.ok, if result.ok then nil else result.error.code)
	if result.ok then
		TestHarness.assertEqual(result.value.infrastructure.Name, "Infrastructure")
		TestHarness.assertEqual(result.value.controllerRegistry.Name, "ControllerRegistry")
		TestHarness.assertEqual(result.value.remoteClient.Name, "RemoteClient")
	end

	local missingPlayerScripts = Instance.new("Folder")
	local timeoutResult = ClientDependencyResolver.resolvePlayerScripts(missingPlayerScripts, 0.01)
	TestHarness.assertTrue(not timeoutResult.ok)
	if not timeoutResult.ok then
		TestHarness.assertEqual(timeoutResult.error.code, "StartupDependencyTimeout")
	end

	missingPlayerScripts:Destroy()
	playerScripts:Destroy()
end

function ClientDependencyResolverSpec.tests(): { TestCase }
	return {
		{
			name = "ClientApplication dependency resolver waits for runtime-copied siblings",
			run = waitsForRuntimeCopiedDependenciesTest,
		},
	}
end

return table.freeze(ClientDependencyResolverSpec)
