--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local PlotConfigValidator = require(ServerScriptService.Config.PlotConfigValidator)
local PlotDefinitions = require(ServerStorage.Config.PlotDefinitions)
local TestHarness = require(script.Parent.Parent.TestHarness)

type TestCase = TestHarness.TestCase

local PlotConfigSpec = {}

local function cloneConfig(): { [string]: unknown }
	local definitions = table.clone(PlotDefinitions.definitions)
	return {
		maxPlayers = PlotDefinitions.maxPlayers,
		centerSpacing = PlotDefinitions.centerSpacing,
		plotGap = PlotDefinitions.plotGap,
		definitions = definitions,
	}
end

local function approvedProductionConfigTest()
	local result = PlotConfigValidator.validate(PlotDefinitions)
	TestHarness.assertTrue(result.ok, if result.ok then nil else result.error.code)
	if not result.ok then
		return
	end
	TestHarness.assertEqual(result.value.maxPlayers, 6)
	TestHarness.assertEqual(result.value.centerSpacing, 128)
	TestHarness.assertEqual(result.value.plotGap, 32)
	TestHarness.assertEqual(#result.value.definitions, 6)
	for index, definition in result.value.definitions do
		TestHarness.assertEqual(definition.id, `plot_{string.format("%02d", index)}`)
		TestHarness.assertEqual(definition.footprintSize, Vector2.new(96, 96))
		TestHarness.assertEqual(definition.maxHeight, 64)
	end
end

local function duplicateAndOverlapRejectionTest()
	local duplicateConfig = cloneConfig()
	local duplicateDefinitions = duplicateConfig.definitions :: { { [string]: unknown } }
	duplicateDefinitions[2] = table.clone(duplicateDefinitions[2])
	duplicateDefinitions[2].id = "plot_01"
	local duplicateResult = PlotConfigValidator.validate(duplicateConfig)
	TestHarness.assertTrue(not duplicateResult.ok)
	if not duplicateResult.ok then
		TestHarness.assertEqual(duplicateResult.error.code, "DuplicatePlotId")
	end

	local overlapConfig = cloneConfig()
	local overlapDefinitions = overlapConfig.definitions :: { { [string]: unknown } }
	overlapDefinitions[2] = table.clone(overlapDefinitions[2])
	overlapDefinitions[2].origin = overlapDefinitions[1].origin
	local overlapResult = PlotConfigValidator.validate(overlapConfig)
	TestHarness.assertTrue(not overlapResult.ok)
	if not overlapResult.ok then
		TestHarness.assertEqual(overlapResult.error.code, "OverlappingPlotDefinitions")
	end
end

local function outOfBoundsConfigRejectionTest()
	local config = cloneConfig()
	local definitions = config.definitions :: { { [string]: unknown } }
	definitions[1] = table.clone(definitions[1])
	definitions[1].spawnOffset = CFrame.new(100, 0, 0)
	local spawnResult = PlotConfigValidator.validate(config)
	TestHarness.assertTrue(not spawnResult.ok)
	if not spawnResult.ok then
		TestHarness.assertEqual(spawnResult.error.code, "PlotSpawnOutOfBounds")
	end

	local shellConfig = cloneConfig()
	local shellDefinitions = shellConfig.definitions :: { { [string]: unknown } }
	shellDefinitions[1] = table.clone(shellDefinitions[1])
	local shell = table.clone(shellDefinitions[1].officeShell :: { [string]: unknown })
	shell.localOffset = CFrame.new(60, 0, 0)
	shellDefinitions[1].officeShell = shell
	local shellResult = PlotConfigValidator.validate(shellConfig)
	TestHarness.assertTrue(not shellResult.ok)
	if not shellResult.ok then
		TestHarness.assertEqual(shellResult.error.code, "PlotOfficeOutOfBounds")
	end
end

function PlotConfigSpec.tests(): { TestCase }
	return {
		{ name = "production plot config matches approved capacity and geometry", run = approvedProductionConfigTest },
		{ name = "plot config rejects duplicate and overlapping definitions", run = duplicateAndOverlapRejectionTest },
		{ name = "plot config rejects spawn and office outside boundaries", run = outOfBoundsConfigRejectionTest },
	}
end

return table.freeze(PlotConfigSpec)
