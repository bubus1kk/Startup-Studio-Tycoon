--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficeShellBuilder = require(ServerScriptService.Systems.OfficeShellBuilder)
local TestHarness = require(script.Parent.Parent.TestHarness)
local PlotTestUtils = require(script.Parent.Parent.ServerFixtures.PlotTestUtils)

type TestCase = TestHarness.TestCase

local PlotServiceIntegrationSpec = {}

local function collectPartGeometry(model: Model): { [string]: string }
	local geometry: { [string]: string } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			geometry[descendant:GetFullName()] =
				`{tostring(descendant.Size)}|{tostring(descendant.CFrame)}|{descendant.Name}`
		end
	end
	return geometry
end

local function allocationCapacityReleaseAndReuseTest()
	local fixture = PlotTestUtils.createFixture(nil)
	local service = fixture.service

	local studioUserResult = service:AssignPlayer(-1)
	TestHarness.assertTrue(studioUserResult.ok)
	if studioUserResult.ok then
		TestHarness.assertEqual(studioUserResult.value.plotId, "plot_01")
	end
	TestHarness.assertTrue(service:ReleasePlayer(-1).ok)

	local firstResult = service:AssignPlayer(1001)
	TestHarness.assertTrue(firstResult.ok)
	if not firstResult.ok then
		fixture:Destroy()
		return
	end
	TestHarness.assertEqual(firstResult.value.plotId, "plot_01")
	TestHarness.assertEqual(firstResult.value.state, "Active")

	local duplicateResult = service:AssignPlayer(1001)
	TestHarness.assertTrue(duplicateResult.ok)
	if duplicateResult.ok then
		TestHarness.assertEqual(duplicateResult.value.plotId, "plot_01")
	end
	TestHarness.assertEqual(service:GetOwnerUserId("plot_01"), 1001)

	for userId = 1002, 1006 do
		local result = service:AssignPlayer(userId)
		TestHarness.assertTrue(result.ok)
		if result.ok then
			TestHarness.assertEqual(result.value.plotId, `plot_{string.format("%02d", userId - 1000)}`)
		end
	end
	TestHarness.assertTrue(service:ValidateRuntimeState().ok)

	local capacityResult = service:AssignPlayer(1007)
	TestHarness.assertTrue(not capacityResult.ok)
	if not capacityResult.ok then
		TestHarness.assertEqual(capacityResult.error.code, "NoAvailablePlot")
	end
	TestHarness.assertTrue(service:GetPlotIdForUserId(1007) == nil)

	local releaseResult = service:ReleasePlayer(1001)
	TestHarness.assertTrue(releaseResult.ok and releaseResult.value)
	local doubleReleaseResult = service:ReleasePlayer(1001)
	TestHarness.assertTrue(doubleReleaseResult.ok and not doubleReleaseResult.value)
	TestHarness.assertTrue(service:ValidateRuntimeState().ok)

	local reuseResult = service:AssignPlayer(1007)
	TestHarness.assertTrue(reuseResult.ok)
	if reuseResult.ok then
		TestHarness.assertEqual(reuseResult.value.plotId, "plot_01")
	end
	TestHarness.assertTrue(service:ValidateRuntimeState().ok)
	fixture:Destroy()
	TestHarness.assertTrue(service:ValidateRuntimeState().ok)
end

local function ownershipRejectionDoesNotMutateTest()
	local fixture = PlotTestUtils.createFixture(nil)
	local service = fixture.service
	TestHarness.assertTrue(service:AssignPlayer(2001).ok)
	TestHarness.assertTrue(service:AssignPlayer(2002).ok)

	local ownerResult = service:RequireOwnership(2001, "plot_01")
	TestHarness.assertTrue(ownerResult.ok)
	if ownerResult.ok then
		ownerResult.value.model:SetAttribute("TestMutationCount", 1)
	end
	local foreignResult = service:RequireOwnership(2002, "plot_01")
	TestHarness.assertTrue(not foreignResult.ok)
	if not foreignResult.ok then
		TestHarness.assertEqual(foreignResult.error.code, "PlotOwnershipMismatch")
	end
	local model = service:GetRuntimePlotModel("plot_01")
	TestHarness.assertTrue(model ~= nil)
	if model ~= nil then
		TestHarness.assertEqual(model:GetAttribute("TestMutationCount"), 1)
	end
	TestHarness.assertTrue(service:ValidateRuntimeState().ok)
	fixture:Destroy()
end

local function spawnContextsAreDistinctAndReboundOnReuseTest()
	local fixture = PlotTestUtils.createFixture(nil)
	local service = fixture.service
	for userId = 4001, 4003 do
		TestHarness.assertTrue(service:AssignPlayer(userId).ok)
	end

	local firstContext = service:GetSpawnContextForUserId(4001)
	local secondContext = service:GetSpawnContextForUserId(4002)
	local thirdContext = service:GetSpawnContextForUserId(4003)
	TestHarness.assertTrue(firstContext ~= nil and secondContext ~= nil and thirdContext ~= nil)
	if firstContext == nil or secondContext == nil or thirdContext == nil then
		fixture:Destroy()
		return
	end
	TestHarness.assertTrue(firstContext.spawnLocation:IsA("SpawnLocation"))
	TestHarness.assertTrue(secondContext.spawnLocation:IsA("SpawnLocation"))
	TestHarness.assertTrue(thirdContext.spawnLocation:IsA("SpawnLocation"))
	TestHarness.assertTrue(firstContext.spawnCFrame.Position ~= secondContext.spawnCFrame.Position)
	TestHarness.assertTrue(firstContext.spawnCFrame.Position ~= thirdContext.spawnCFrame.Position)
	TestHarness.assertTrue(secondContext.spawnCFrame.Position ~= thirdContext.spawnCFrame.Position)

	local releasedSpawnLocation = firstContext.spawnLocation
	local releasedSpawnCFrame = firstContext.spawnCFrame
	TestHarness.assertTrue(service:ReleasePlayer(4001).ok)
	TestHarness.assertTrue(releasedSpawnLocation.Parent == nil)

	local reuseResult = service:AssignPlayer(4004)
	TestHarness.assertTrue(reuseResult.ok)
	if reuseResult.ok then
		TestHarness.assertEqual(reuseResult.value.plotId, "plot_01")
	end
	local reusedContext = service:GetSpawnContextForUserId(4004)
	TestHarness.assertTrue(reusedContext ~= nil)
	if reusedContext ~= nil then
		TestHarness.assertTrue(reusedContext.spawnLocation ~= releasedSpawnLocation)
		TestHarness.assertEqual(reusedContext.spawnCFrame, releasedSpawnCFrame)
		TestHarness.assertEqual(reusedContext.userId, 4004)
	end
	TestHarness.assertTrue(service:ValidateRuntimeState().ok)
	fixture:Destroy()
end

local function deterministicOfficeGeometryTest()
	local definition = PlotTestUtils.validatedConfig().definitions[1]
	local builder = OfficeShellBuilder.new(nil)
	local firstResult = builder:Build(definition)
	local secondResult = builder:Build(definition)
	TestHarness.assertTrue(firstResult.ok and secondResult.ok)
	if not firstResult.ok or not secondResult.ok then
		return
	end

	local firstGeometry = collectPartGeometry(firstResult.value)
	local secondGeometry = collectPartGeometry(secondResult.value)
	local partCount = 0
	for path, geometry in firstGeometry do
		partCount += 1
		TestHarness.assertEqual(secondGeometry[path], geometry)
	end
	TestHarness.assertEqual(partCount, 12)
	for path in secondGeometry do
		TestHarness.assertTrue(firstGeometry[path] ~= nil)
	end
	local firstSpawn = firstResult.value:FindFirstChild("SpawnLocation")
	local secondSpawn = secondResult.value:FindFirstChild("SpawnLocation")
	TestHarness.assertTrue(firstSpawn ~= nil and firstSpawn:IsA("SpawnLocation"))
	TestHarness.assertTrue(secondSpawn ~= nil and secondSpawn:IsA("SpawnLocation"))
	firstResult.value:Destroy()
	secondResult.value:Destroy()
end

local function builderFailureRollsBackWithoutOrphanTest()
	local fixture = PlotTestUtils.createFixture(function(_partName: string, partIndex: number)
		if partIndex == 3 then
			error("injected builder failure")
		end
	end)
	local service = fixture.service
	local assignmentResult = service:AssignPlayer(3001)
	TestHarness.assertTrue(not assignmentResult.ok)
	if not assignmentResult.ok then
		TestHarness.assertEqual(assignmentResult.error.code, "PlotGenerationFailed")
	end
	TestHarness.assertTrue(service:GetPlotIdForUserId(3001) == nil)
	TestHarness.assertTrue(service:GetOwnerUserId("plot_01") == nil)
	TestHarness.assertTrue(service:ValidateRuntimeState().ok)

	local map = fixture.root:FindFirstChild("Map")
	local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
	TestHarness.assertTrue(plots ~= nil and #plots:GetChildren() == 0)
	fixture:Destroy()
	TestHarness.assertTrue(service:ValidateRuntimeState().ok)
end

function PlotServiceIntegrationSpec.tests(): { TestCase }
	return {
		{
			name = "plot allocation is unique idempotent capacity-bound and reusable",
			run = allocationCapacityReleaseAndReuseTest,
		},
		{ name = "foreign plot ownership is rejected without mutation", run = ownershipRejectionDoesNotMutateTest },
		{
			name = "three allocations have distinct spawn transforms and reuse creates a new binding",
			run = spawnContextsAreDistinctAndReboundOnReuseTest,
		},
		{ name = "starter office geometry is deterministic", run = deterministicOfficeGeometryTest },
		{ name = "builder failure rolls back without orphaned models", run = builderFailureRollsBackWithoutOrphanTest },
	}
end

return table.freeze(PlotServiceIntegrationSpec)
