--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)
local TestHarness = require(script.Parent.Parent.TestHarness)
local PlotTestUtils = require(script.Parent.Parent.ServerFixtures.PlotTestUtils)

type PlotDefinition = PlotTypes.PlotDefinition
type TestCase = TestHarness.TestCase

local PlotBoundsSpec = {}

local function groundLevelVerticalBoundsTest()
	local definition = PlotTestUtils.validatedConfig().definitions[1]
	TestHarness.assertTrue(PlotBounds.containsPoint(definition, definition.origin.Position))
	TestHarness.assertTrue(
		PlotBounds.containsPoint(definition, definition.origin:PointToWorldSpace(Vector3.new(0, 64, 0)))
	)
	TestHarness.assertTrue(
		not PlotBounds.containsPoint(definition, definition.origin:PointToWorldSpace(Vector3.new(0, -0.1, 0)))
	)
	TestHarness.assertTrue(
		not PlotBounds.containsPoint(definition, definition.origin:PointToWorldSpace(Vector3.new(0, 64.1, 0)))
	)
end

local function rotatedLocalSpaceTest()
	local source = PlotTestUtils.validatedConfig().definitions[1]
	local rotated: PlotDefinition = {
		id = "plot_90",
		origin = CFrame.new(300, 0, 150) * CFrame.Angles(0, math.rad(45), 0),
		footprintSize = source.footprintSize,
		maxHeight = source.maxHeight,
		spawnOffset = source.spawnOffset,
		officeShell = source.officeShell,
	}
	local insidePoint = rotated.origin:PointToWorldSpace(Vector3.new(40, 10, 40))
	local outsidePoint = rotated.origin:PointToWorldSpace(Vector3.new(49, 10, 0))
	TestHarness.assertTrue(PlotBounds.containsPoint(rotated, insidePoint))
	TestHarness.assertTrue(not PlotBounds.containsPoint(rotated, outsidePoint))
	TestHarness.assertTrue(
		PlotBounds.containsBox(rotated, rotated.origin * CFrame.new(0, 5, 0), Vector3.new(20, 10, 20))
	)
end

local function exactGapAndOverlapTest()
	local definitions = PlotTestUtils.validatedConfig().definitions
	TestHarness.assertTrue(not PlotBounds.footprintsOverlap(definitions[1], definitions[2], 32))

	local second = definitions[2]
	local tooClose: PlotDefinition = {
		id = "plot_91",
		origin = second.origin * CFrame.new(-1, 0, 0),
		footprintSize = second.footprintSize,
		maxHeight = second.maxHeight,
		spawnOffset = second.spawnOffset,
		officeShell = second.officeShell,
	}
	TestHarness.assertTrue(PlotBounds.footprintsOverlap(definitions[1], tooClose, 32))
end

function PlotBoundsSpec.tests(): { TestCase }
	return {
		{ name = "plot bounds use ground-level vertical range", run = groundLevelVerticalBoundsTest },
		{ name = "plot bounds support rotated local-space geometry", run = rotatedLocalSpaceTest },
		{ name = "plot bounds enforce the configured gap", run = exactGapAndOverlapTest },
	}
end

return table.freeze(PlotBoundsSpec)
