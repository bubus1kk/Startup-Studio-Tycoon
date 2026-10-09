--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local WorkstationDefinitions = require(ServerScriptService.Domain.WorkstationDefinitions)
local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local WorkstationDefinitionsSpec = {}

local function stableCapacityPrefixTest()
	local config = EmployeeTestUtils.validatedConfig()
	local layout = OfficeProgression.new(OfficeTestUtils.validatedConfig()):CreateInitialLayout()
	local total = 0
	for _, definition in config.workstations do
		TestHarness.assertTrue(definition.capacities[1] <= definition.capacities[2])
		TestHarness.assertTrue(definition.capacities[2] <= definition.capacities[3])
		for index, slot in definition.slots do
			TestHarness.assertEqual(slot.slotIndex, index)
		end
		total += definition.capacities[3]
	end
	TestHarness.assertEqual(total, 30)
	TestHarness.assertEqual(WorkstationDefinitions.Id("Developer", 1), "workstation:Developer:1")
	TestHarness.assertEqual(#WorkstationDefinitions.Build(config, layout), 0)
end

function WorkstationDefinitionsSpec.tests(): { TestCase }
	return { { name = "workstation L1 L2 L3 slots are stable prefixes totaling 30", run = stableCapacityPrefixTest } }
end

return table.freeze(WorkstationDefinitionsSpec)
