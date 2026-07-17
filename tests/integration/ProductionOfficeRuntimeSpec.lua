--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local TestHarness = require(script.Parent.Parent.TestHarness)

type TestCase = TestHarness.TestCase
local ProductionOfficeRuntimeSpec = {}

local function waitUntil(predicate: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	repeat
		if predicate() then
			return true
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return predicate()
end

local function productionOfficeStructureTest()
	local bootstrap = ServerScriptService.Bootstrap:FindFirstChild("Bootstrap")
	TestHarness.assertTrue(bootstrap ~= nil)
	if bootstrap ~= nil then
		TestHarness.assertTrue(waitUntil(function(): boolean
			return bootstrap:GetAttribute("ServerBootstrapState") == "Ready"
		end, 15))
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	TestHarness.assertTrue(remotes ~= nil)
	if remotes ~= nil then
		TestHarness.assertTrue(remotes:FindFirstChild("RequestOfficeCatalog") ~= nil)
		TestHarness.assertTrue(remotes:FindFirstChild("RequestOfficePurchase") ~= nil)
	end
	local player = Players:GetPlayers()[1]
	TestHarness.assertTrue(player ~= nil)
	if player == nil then
		return
	end
	TestHarness.assertTrue(waitUntil(function(): boolean
		return player:GetAttribute("OfficeSessionReady") == true
	end, 15))
	local plotId = player:GetAttribute("AssignedPlotId")
	local map = Workspace:FindFirstChild("Map")
	local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
	local plot = if plots ~= nil and typeof(plotId) == "string" then plots:FindFirstChild(plotId) else nil
	TestHarness.assertTrue(plot ~= nil and plot:IsA("Model"))
	if plot ~= nil and plot:IsA("Model") then
		TestHarness.assertEqual(plot.PrimaryPart, plot:FindFirstChild("PlotAnchor"))
		local spawn = plot:FindFirstChild("SpawnLocation")
		local officeRoot = plot:FindFirstChild("OfficeBuildRoot")
		TestHarness.assertTrue(spawn ~= nil and spawn:IsA("SpawnLocation"))
		TestHarness.assertTrue(officeRoot ~= nil and officeRoot:IsA("Model"))
		if spawn ~= nil and spawn:IsA("SpawnLocation") and officeRoot ~= nil and officeRoot:IsA("Model") then
			local approachCount = 0
			for _, descendant in officeRoot:GetDescendants() do
				if descendant.Name == "EntranceApproach" and descendant:IsA("BasePart") then
					approachCount += 1
				end
			end
			TestHarness.assertEqual(approachCount, 1)
			TestHarness.assertTrue(not spawn:IsDescendantOf(officeRoot))
			TestHarness.assertEqual(player.RespawnLocation, spawn)
		end
		TestHarness.assertEqual(#plot:GetChildren(), 5)
	end
end

function ProductionOfficeRuntimeSpec.tests(): { TestCase }
	return {
		{ name = "production bootstrap exposes one stable plot and office root", run = productionOfficeStructureTest },
	}
end
return table.freeze(ProductionOfficeRuntimeSpec)
