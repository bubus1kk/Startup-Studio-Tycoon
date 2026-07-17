--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local OfficePlacement = require(ServerScriptService.Domain.OfficePlacement)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)
local OfficeLayoutBuilder = require(ServerScriptService.Systems.OfficeLayoutBuilder)
local PlotRuntimeBuilder = require(ServerScriptService.Systems.PlotRuntimeBuilder)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)
local PlotTestUtils = require(script.Parent.Parent.ServerFixtures.PlotTestUtils)

type Fixture = OfficeTestUtils.Fixture
type PlotDefinition = PlotTypes.PlotDefinition
type TestCase = TestHarness.TestCase

local OfficeEntranceApproachSpec = {}

local EPSILON = 1e-3
local MINIMUM_WALKABLE_WIDTH = 6
local MAXIMUM_SURFACE_STEP = 0.05
local INSTANCE_BUDGET = 450
local BASE_PART_BUDGET = 300

local function projectedHalfExtent(part: BasePart, worldAxis: Vector3): number
	return math.abs(part.CFrame.RightVector:Dot(worldAxis)) * part.Size.X * 0.5
		+ math.abs(part.CFrame.UpVector:Dot(worldAxis)) * part.Size.Y * 0.5
		+ math.abs(part.CFrame.LookVector:Dot(worldAxis)) * part.Size.Z * 0.5
end

local function localAxisRange(part: BasePart, origin: CFrame, localAxis: Vector3): (number, number)
	local worldAxis = origin:VectorToWorldSpace(localAxis)
	local localCenter = origin:PointToObjectSpace(part.Position)
	local center = localCenter:Dot(localAxis)
	local halfExtent = projectedHalfExtent(part, worldAxis)
	return center - halfExtent, center + halfExtent
end

local function topSurface(part: BasePart): number
	return part.Position.Y + projectedHalfExtent(part, Vector3.yAxis)
end

local function countInstances(root: Instance): (number, number)
	local instances = 1
	local baseParts = if root:IsA("BasePart") then 1 else 0
	for _, descendant in root:GetDescendants() do
		instances += 1
		if descendant:IsA("BasePart") then
			baseParts += 1
		end
	end
	return instances, baseParts
end

local function findSingleApproach(root: Instance): BasePart
	local approach: BasePart? = nil
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant.Name == "EntranceApproach" and descendant:IsA("BasePart") then
			count += 1
			approach = descendant
		end
	end
	TestHarness.assertEqual(count, 1, `Expected one EntranceApproach under {root:GetFullName()}`)
	if approach == nil then
		error("EntranceApproach is missing", 2)
	end
	return approach
end

local function assertApproachGeometry(tierId: string, definition: PlotDefinition, root: Model, spawn: SpawnLocation)
	local tierShell = root:FindFirstChild("TierShell")
	TestHarness.assertTrue(tierShell ~= nil and tierShell:IsA("Model"), `{tierId}: TierShell missing`)
	if tierShell == nil or not tierShell:IsA("Model") then
		return
	end
	local approach = findSingleApproach(root)
	local floorBack = tierShell:FindFirstChild("FloorBack")
	local frontLeftWall = tierShell:FindFirstChild("FrontLeftWall")
	local frontRightWall = tierShell:FindFirstChild("FrontRightWall")
	TestHarness.assertTrue(floorBack ~= nil and floorBack:IsA("BasePart"), `{tierId}: FloorBack missing`)
	TestHarness.assertTrue(frontLeftWall ~= nil and frontLeftWall:IsA("BasePart"), `{tierId}: FrontLeftWall missing`)
	TestHarness.assertTrue(frontRightWall ~= nil and frontRightWall:IsA("BasePart"), `{tierId}: FrontRightWall missing`)
	if
		floorBack == nil
		or not floorBack:IsA("BasePart")
		or frontLeftWall == nil
		or not frontLeftWall:IsA("BasePart")
		or frontRightWall == nil
		or not frontRightWall:IsA("BasePart")
	then
		return
	end

	TestHarness.assertEqual(approach.Parent, tierShell, `{tierId}: approach must belong to TierShell`)
	TestHarness.assertTrue(approach.Anchored, `{tierId}: approach must be anchored`)
	TestHarness.assertTrue(approach.CanCollide, `{tierId}: approach must be collidable`)
	TestHarness.assertTrue(approach.Size.X >= MINIMUM_WALKABLE_WIDTH, `{tierId}: approach is too narrow`)
	TestHarness.assertTrue(
		PlotBounds.containsBox(definition, approach.CFrame, approach.Size),
		`{tierId}: approach escaped plot bounds`
	)
	TestHarness.assertTrue(
		approach.CFrame.RightVector:Dot(definition.origin.RightVector) > 0.999,
		`{tierId}: approach lost plot rotation`
	)

	local floorMinimumZ, floorMaximumZ = localAxisRange(floorBack, definition.origin, Vector3.zAxis)
	local approachMinimumZ, approachMaximumZ = localAxisRange(approach, definition.origin, Vector3.zAxis)
	local spawnMinimumZ, spawnMaximumZ = localAxisRange(spawn, definition.origin, Vector3.zAxis)
	TestHarness.assertTrue(floorMinimumZ < floorMaximumZ and spawnMinimumZ < spawnMaximumZ)
	TestHarness.assertTrue(
		math.abs(approachMinimumZ - floorMaximumZ) <= EPSILON,
		`{tierId}: floor-to-approach gap={approachMinimumZ - floorMaximumZ}`
	)
	TestHarness.assertTrue(
		math.abs(spawnMinimumZ - approachMaximumZ) <= EPSILON,
		`{tierId}: approach-to-spawn gap={spawnMinimumZ - approachMaximumZ}`
	)
	TestHarness.assertTrue(
		approachMaximumZ <= spawnMinimumZ + EPSILON,
		`{tierId}: approach overlaps and blocks SpawnLocation`
	)

	local approachMinimumX, approachMaximumX = localAxisRange(approach, definition.origin, Vector3.xAxis)
	local spawnMinimumX, spawnMaximumX = localAxisRange(spawn, definition.origin, Vector3.xAxis)
	local _, leftWallMaximumX = localAxisRange(frontLeftWall, definition.origin, Vector3.xAxis)
	local rightWallMinimumX = localAxisRange(frontRightWall, definition.origin, Vector3.xAxis)
	local horizontalOverlap = math.min(approachMaximumX, spawnMaximumX) - math.max(approachMinimumX, spawnMinimumX)
	TestHarness.assertTrue(
		horizontalOverlap >= MINIMUM_WALKABLE_WIDTH - EPSILON,
		`{tierId}: spawn approach is misaligned`
	)
	TestHarness.assertTrue(
		approachMinimumX >= leftWallMaximumX - EPSILON and approachMaximumX <= rightWallMinimumX + EPSILON,
		`{tierId}: approach overlaps the entrance opening walls`
	)

	TestHarness.assertTrue(
		math.abs(topSurface(approach) - topSurface(spawn)) <= MAXIMUM_SURFACE_STEP,
		`{tierId}: spawn surface step={math.abs(topSurface(approach) - topSurface(spawn))}`
	)
	TestHarness.assertTrue(
		math.abs(topSurface(approach) - topSurface(floorBack)) <= MAXIMUM_SURFACE_STEP,
		`{tierId}: office floor surface step={math.abs(topSurface(approach) - topSurface(floorBack))}`
	)
end

local function allTierLocalSpaceGeometryTest()
	local sourceDefinition = PlotTestUtils.validatedConfig().definitions[1]
	local definition = table.clone(sourceDefinition)
	definition.origin = CFrame.new(37, 0, -19) * CFrame.Angles(0, math.rad(31), 0)
	local plotResult = PlotRuntimeBuilder.new(nil):Build(definition)
	if not plotResult.ok then
		error(`Rotated plot build failed: {plotResult.error.code}`)
	end
	local plotModel = plotResult.value
	local spawn = plotModel:FindFirstChild("SpawnLocation")
	local anchor = plotModel:FindFirstChild("PlotAnchor")
	TestHarness.assertTrue(spawn ~= nil and spawn:IsA("SpawnLocation"))
	TestHarness.assertTrue(anchor ~= nil and anchor:IsA("BasePart"))
	if spawn == nil or not spawn:IsA("SpawnLocation") or anchor == nil or not anchor:IsA("BasePart") then
		plotModel:Destroy()
		return
	end
	local config = OfficeTestUtils.validatedConfig()
	local progression = OfficeProgression.new(config)
	local templates = ServerStorage:FindFirstChild("OfficeTemplates")
	TestHarness.assertTrue(templates ~= nil, "OfficeTemplates missing")
	if templates == nil then
		plotModel:Destroy()
		return
	end
	local builder = OfficeLayoutBuilder.new(templates, config, progression, OfficePlacement.new(progression), nil)
	for _, tier in config.tiers do
		local layout = progression:CreateInitialLayout()
		layout.officeTierId = tier.id
		local rootResult = builder:BuildReplacementRoot({
			definition = definition,
			model = plotModel,
			generationToken = 1,
		}, layout)
		if not rootResult.ok then
			error(
				`{tier.id} approach build failed: error.code={rootResult.error.code}; error.message={rootResult.error.message}`
			)
		end
		assertApproachGeometry(tier.id, definition, rootResult.value, spawn)
		TestHarness.assertEqual(spawn.Parent, plotModel, `{tier.id}: SpawnLocation ownership changed`)
		TestHarness.assertTrue(
			not spawn:IsDescendantOf(rootResult.value),
			`{tier.id}: SpawnLocation entered office root`
		)
		TestHarness.assertEqual(plotModel.PrimaryPart, anchor, `{tier.id}: PlotAnchor PrimaryPart changed`)
		rootResult.value:Destroy()
	end
	TestHarness.assertEqual(plotModel:FindFirstChild("SpawnLocation"), spawn)
	TestHarness.assertEqual(plotModel.PrimaryPart, anchor)
	plotModel:Destroy()
end

local function transitionsRebuildAndBudgetTest()
	local fixture = OfficeTestUtils.createFixture(6101, nil)
	local initialContext = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
	if not initialContext.ok then
		error(`Initial plot context failed: {initialContext.error.code}`)
	end
	local spawn = initialContext.value.model:FindFirstChild("SpawnLocation")
	local anchor = initialContext.value.model:FindFirstChild("PlotAnchor")
	if spawn == nil or not spawn:IsA("SpawnLocation") or anchor == nil or not anchor:IsA("BasePart") then
		error("Stable plot spawn or anchor is missing")
	end

	local function assertRuntimeOwnership(): (Model, BasePart)
		local context = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
		if not context.ok then
			error(`Runtime plot context failed: {context.error.code}`)
		end
		local root = context.value.model:FindFirstChild("OfficeBuildRoot")
		if root == nil or not root:IsA("Model") then
			error("Canonical OfficeBuildRoot is missing")
		end
		local approach = findSingleApproach(root)
		TestHarness.assertEqual(context.value.model:FindFirstChild("SpawnLocation"), spawn)
		TestHarness.assertEqual(spawn.Parent, context.value.model)
		TestHarness.assertTrue(not spawn:IsDescendantOf(root))
		TestHarness.assertEqual(context.value.model.PrimaryPart, anchor)
		return root, approach
	end

	assertRuntimeOwnership()
	local observedTiers = 1
	for _, itemId in OfficeTestUtils.fullProgressionOrder(fixture.config) do
		local isTierTransition = fixture.progression:GetTier(itemId) ~= nil
		local previousApproach: BasePart? = nil
		if isTierTransition then
			local _, approach = assertRuntimeOwnership()
			previousApproach = approach
		end
		local response = fixture:Purchase(itemId)
		TestHarness.assertTrue(response.ok, OfficeTestUtils.purchaseDiagnostic(itemId, response))
		if isTierTransition then
			observedTiers += 1
			local _, approach = assertRuntimeOwnership()
			TestHarness.assertTrue(previousApproach ~= nil and previousApproach.Parent == nil)
			TestHarness.assertTrue(approach ~= previousApproach)
		end
	end
	TestHarness.assertEqual(observedTiers, 5, "Not every tier transition was observed")

	local maximumRoot, oldApproach = assertRuntimeOwnership()
	local instances, baseParts = countInstances(maximumRoot)
	TestHarness.assertTrue(instances <= INSTANCE_BUDGET, `Entrance approach layout instances={instances}`)
	TestHarness.assertTrue(baseParts <= BASE_PART_BUDGET, `Entrance approach layout baseParts={baseParts}`)
	print(
		`[Stage4Test] METRIC entranceApproach instances={instances} baseParts={baseParts} instanceBudget={INSTANCE_BUDGET} basePartBudget={BASE_PART_BUDGET}`
	)

	local exported = fixture.office:ExportLayout(fixture.userId)
	if not exported.ok then
		error(`Entrance approach serialize failed: {exported.error.code}`)
	end
	local closed = fixture.office:CloseSession(fixture.userId)
	TestHarness.assertTrue(closed.ok and closed.value, "Entrance approach session close failed")
	TestHarness.assertTrue(oldApproach.Parent == nil, "Old EntranceApproach survived session close")
	TestHarness.assertEqual(initialContext.value.model:FindFirstChild("SpawnLocation"), spawn)
	local rebuilt = fixture.office:PrepareSession(fixture.userId, exported.value)
	if not rebuilt.ok then
		error(`Entrance approach rebuild failed: {rebuilt.error.code}`)
	end
	local rebuiltRoot, rebuiltApproach = assertRuntimeOwnership()
	TestHarness.assertTrue(rebuiltApproach ~= oldApproach)
	local rebuiltInstances, rebuiltBaseParts = countInstances(rebuiltRoot)
	TestHarness.assertEqual(rebuiltInstances, instances, "Rebuild changed maximum-content Instance count")
	TestHarness.assertEqual(rebuiltBaseParts, baseParts, "Rebuild changed maximum-content BasePart count")
	fixture:Destroy()
end

function OfficeEntranceApproachSpec.tests(): { TestCase }
	return {
		{
			name = "all five tiers provide a rotated gap-free walkable entrance approach",
			run = allTierLocalSpaceGeometryTest,
		},
		{
			name = "tier transitions and rebuild retain one entrance approach within budgets",
			run = transitionsRebuildAndBudgetTest,
		},
	}
end

return table.freeze(OfficeEntranceApproachSpec)
