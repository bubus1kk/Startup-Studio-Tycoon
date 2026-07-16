--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local PlayerSessionService = require(ServerScriptService.Services.PlayerSessionService)
local TestHarness = require(script.Parent.Parent.TestHarness)
local PlotTestUtils = require(script.Parent.Parent.ServerFixtures.PlotTestUtils)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type TestCase = TestHarness.TestCase

local ProductionPlotRuntimeSpec = {}
local RUNTIME_TIMEOUT_SECONDS = 15

local function waitUntil(predicate: () -> boolean, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	repeat
		if predicate() then
			return true
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return predicate()
end

local function productionBootstrapAndRespawnTest()
	local bootstrapFolder = ServerScriptService:FindFirstChild("Bootstrap")
	local bootstrapScript = if bootstrapFolder ~= nil then bootstrapFolder:FindFirstChild("Bootstrap") else nil
	TestHarness.assertTrue(bootstrapScript ~= nil and bootstrapScript:IsA("Script"))
	if bootstrapScript == nil or not bootstrapScript:IsA("Script") then
		return
	end
	TestHarness.assertTrue(
		waitUntil(function()
			return bootstrapScript:GetAttribute("ServerBootstrapState") == "Ready"
		end, RUNTIME_TIMEOUT_SECONDS),
		"Production server bootstrap did not become ready"
	)

	TestHarness.assertTrue(
		waitUntil(function()
			return #Players:GetPlayers() > 0
		end, RUNTIME_TIMEOUT_SECONDS),
		"No Studio test player joined"
	)
	local player = Players:GetPlayers()[1]
	if player == nil then
		return
	end
	TestHarness.assertTrue(
		waitUntil(function()
			return typeof(player:GetAttribute("AssignedPlotId")) == "string"
		end, RUNTIME_TIMEOUT_SECONDS),
		"Player did not receive an AssignedPlotId"
	)

	local plotId = player:GetAttribute("AssignedPlotId")
	TestHarness.assertTrue(typeof(plotId) == "string")
	if typeof(plotId) ~= "string" then
		return
	end
	local map = Workspace:FindFirstChild("Map")
	local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
	TestHarness.assertTrue(plots ~= nil and plots:IsA("Folder"))
	if plots == nil or not plots:IsA("Folder") then
		return
	end
	local plotModel = if plots ~= nil then plots:FindFirstChild(plotId) else nil
	TestHarness.assertTrue(plotModel ~= nil and plotModel:IsA("Model"))
	if plotModel == nil or not plotModel:IsA("Model") then
		return
	end
	TestHarness.assertEqual(plotModel:GetAttribute("PlotId"), plotId)
	TestHarness.assertEqual(plotModel:GetAttribute("OwnerUserId"), player.UserId)
	TestHarness.assertTrue(plotModel:GetAttribute("AllocationState") == nil)

	local spawnMarker = plotModel:FindFirstChild("SpawnMarker")
	TestHarness.assertTrue(spawnMarker ~= nil and spawnMarker:IsA("BasePart"))
	if spawnMarker == nil or not spawnMarker:IsA("BasePart") then
		return
	end
	local spawnLocation = plotModel:FindFirstChild("SpawnLocation")
	TestHarness.assertTrue(spawnLocation ~= nil and spawnLocation:IsA("SpawnLocation"))
	if spawnLocation == nil or not spawnLocation:IsA("SpawnLocation") then
		return
	end
	TestHarness.assertEqual(player.RespawnLocation, spawnLocation)

	local expectedSpawnCFrame = spawnMarker.CFrame * CFrame.new(0, 2.9, 0)
	TestHarness.assertTrue(
		waitUntil(function()
			local character = player.Character
			if character == nil then
				return false
			end
			local root = character:FindFirstChild("HumanoidRootPart")
			return root ~= nil
				and root:IsA("BasePart")
				and (root.Position - expectedSpawnCFrame.Position).Magnitude <= 1
		end, RUNTIME_TIMEOUT_SECONDS),
		"Initial character did not use the assigned plot spawn"
	)

	local initialCharacter = player.Character
	TestHarness.assertTrue(initialCharacter ~= nil)
	if initialCharacter == nil then
		return
	end
	local plotModelCountBeforeRespawn = #plots:GetChildren()

	player:LoadCharacter()
	TestHarness.assertTrue(
		waitUntil(function()
			local character = player.Character
			if character == nil or character == initialCharacter then
				return false
			end
			local root = character:FindFirstChild("HumanoidRootPart")
			if root == nil or not root:IsA("BasePart") then
				return false
			end
			return (root.Position - expectedSpawnCFrame.Position).Magnitude <= 1
		end, RUNTIME_TIMEOUT_SECONDS),
		"Respawn did not use the assigned plot spawn"
	)
	TestHarness.assertEqual(player:GetAttribute("AssignedPlotId"), plotId)
	TestHarness.assertEqual(player.RespawnLocation, spawnLocation)
	TestHarness.assertEqual(#plots:GetChildren(), plotModelCountBeforeRespawn, "Respawn created a duplicate plot model")

	local productionRespawnLocation = player.RespawnLocation
	local fixture = PlotTestUtils.createFixture(nil)
	fixture.root.Name = "Stage3SessionSpawnRegression"
	fixture.root.Parent = Workspace
	local logger = Logger.new("Test", "studio-runtime", "PlayerSessionSpawnRegression", true)
	local sessionService = PlayerSessionService.new(Players, logger, true)
	local function getDependency(name: string): unknown
		return if name == "PlotService" then fixture.service else nil
	end
	local resolver: DependencyResolver = {
		Get = function(_self: DependencyResolver, name: string): unknown
			return getDependency(name)
		end,
		Require = function(_self: DependencyResolver, name: string): unknown
			local dependency = getDependency(name)
			if dependency == nil then
				error(`Missing test dependency {name}`)
			end
			return dependency
		end,
	}
	sessionService:Init(resolver)

	local regressionOk, regressionCause = xpcall(function()
		local beginResult = sessionService:BeginSession(player)
		TestHarness.assertTrue(beginResult.ok)
		local firstFixtureSpawn = player.RespawnLocation
		TestHarness.assertTrue(firstFixtureSpawn ~= nil and firstFixtureSpawn:IsA("SpawnLocation"))

		local currentCharacter = player.Character
		TestHarness.assertTrue(currentCharacter ~= nil)
		if currentCharacter == nil then
			return
		end
		local currentRoot = currentCharacter:FindFirstChild("HumanoidRootPart")
		TestHarness.assertTrue(currentRoot ~= nil and currentRoot:IsA("BasePart"))
		if currentRoot == nil or not currentRoot:IsA("BasePart") then
			return
		end
		local currentRootCFrame = currentRoot.CFrame
		TestHarness.assertTrue(
			not sessionService:_positionCharacter(player, initialCharacter, "StaleCharacterAddedRegression")
		)
		TestHarness.assertEqual(currentRoot.CFrame, currentRootCFrame, "Stale callback moved the current character")

		local firstEndResult = sessionService:EndSession(player)
		TestHarness.assertTrue(firstEndResult.ok)
		TestHarness.assertTrue(player.RespawnLocation == nil, "Release did not clear RespawnLocation")
		if firstFixtureSpawn ~= nil then
			TestHarness.assertTrue(firstFixtureSpawn.Parent == nil)
		end

		local reuseResult = sessionService:BeginSession(player)
		TestHarness.assertTrue(reuseResult.ok)
		local reusedFixtureSpawn = player.RespawnLocation
		TestHarness.assertTrue(reusedFixtureSpawn ~= nil and reusedFixtureSpawn:IsA("SpawnLocation"))
		TestHarness.assertTrue(reusedFixtureSpawn ~= firstFixtureSpawn)
	end, function(errorValue: unknown): string
		return debug.traceback(tostring(errorValue), 2)
	end)

	sessionService:EndSession(player)
	sessionService:Destroy()
	fixture:Destroy()
	player.RespawnLocation = productionRespawnLocation
	player:SetAttribute("AssignedPlotId", plotId)
	local currentCharacter = player.Character
	if currentCharacter ~= nil then
		currentCharacter:PivotTo(expectedSpawnCFrame)
	end

	if not regressionOk then
		error(regressionCause, 0)
	end
	TestHarness.assertEqual(player.RespawnLocation, spawnLocation)
	TestHarness.assertEqual(
		#plots:GetChildren(),
		plotModelCountBeforeRespawn,
		"Spawn regression created a duplicate plot"
	)
end

function ProductionPlotRuntimeSpec.tests(): { TestCase }
	return {
		{
			name = "production initial spawn respawn stale callbacks and reuse preserve the assigned plot",
			run = productionBootstrapAndRespawnTest,
		},
	}
end

return table.freeze(ProductionPlotRuntimeSpec)
