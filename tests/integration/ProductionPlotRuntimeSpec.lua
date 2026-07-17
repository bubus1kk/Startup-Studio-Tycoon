--!strict

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local TestHarness = require(script.Parent.Parent.TestHarness)

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

local function countNamedDescendants(root: Instance, name: string): number
	local count = if root.Name == name then 1 else 0
	for _, descendant in root:GetDescendants() do
		if descendant.Name == name then
			count += 1
		end
	end
	return count
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
	local plotAnchor = plotModel:FindFirstChild("PlotAnchor")
	TestHarness.assertTrue(plotAnchor ~= nil and plotAnchor:IsA("BasePart"))
	TestHarness.assertEqual(plotModel.PrimaryPart, plotAnchor)
	local officeRoot = plotModel:FindFirstChild("OfficeBuildRoot")
	TestHarness.assertTrue(officeRoot ~= nil and officeRoot:IsA("Model"))

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

	local previousCharacter = player.Character
	TestHarness.assertTrue(previousCharacter ~= nil)
	if previousCharacter == nil then
		return
	end
	local plotModelCountBeforeRespawn = #plots:GetChildren()

<<<<<<< HEAD
	for resetIndex = 1, 5 do
		player:LoadCharacter()
		TestHarness.assertTrue(
			waitUntil(function()
				local character = player.Character
				if character == nil or character == previousCharacter then
					return false
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				if root == nil or not root:IsA("BasePart") then
					return false
				end
				return (root.Position - expectedSpawnCFrame.Position).Magnitude <= 1
			end, RUNTIME_TIMEOUT_SECONDS),
			`Reset Character {resetIndex}/5 did not use the assigned plot spawn`
		)
		previousCharacter = player.Character
		TestHarness.assertEqual(player:GetAttribute("AssignedPlotId"), plotId)
		TestHarness.assertEqual(player.RespawnLocation, spawnLocation)
		TestHarness.assertEqual(
			#plots:GetChildren(),
			plotModelCountBeforeRespawn,
			`Reset Character {resetIndex}/5 created a duplicate plot model`
		)
		for name, expectedCount in
			{
				SpawnLocation = 1,
				PlotAnchor = 1,
				OfficeBuildRoot = 1,
				EntranceApproach = 1,
			}
		do
			TestHarness.assertEqual(
				countNamedDescendants(plotModel, name),
				expectedCount,
				`Reset Character {resetIndex}/5 changed {name} count`
			)
		end
	end
=======
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
>>>>>>> 94818332a6f52a94409e8f7b68c861c2ad26d4b6

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
