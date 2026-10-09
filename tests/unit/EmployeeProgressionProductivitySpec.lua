--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local EmployeeProductivity = require(ServerScriptService.Domain.EmployeeProductivity)
local EmployeeProgression = require(ServerScriptService.Domain.EmployeeProgression)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)

type Employee = EmployeeTypes.Employee
type TestCase = TestHarness.TestCase
local EmployeeProgressionProductivitySpec = {}

local function employee(): Employee
	return {
		employeeId = "employee-1-1",
		ownerUserId = 1,
		displayName = "Alex",
		roleId = "Developer",
		grade = "Trainee",
		level = 1,
		xp = 0,
		speed = 5,
		quality = 5,
		reliability = 5,
		traitId = "FastLearner",
		hiringCost = 250,
		salaryPerCycle = 10,
		morale = 80,
		status = "Active",
		missedPayrollCount = 0,
		assignedWorkstationId = "workstation:Developer:1",
		runtimeGeneration = 1,
		createdSequence = 1,
	}
end

local function allTraitsFiniteTest()
	local config = EmployeeTestUtils.validatedConfig()
	for _, traitDefinition in config.traits do
		local value = employee()
		value.traitId = traitDefinition.id
		local result = EmployeeProductivity.Calculate(config, value, traitDefinition, {
			equipmentLevel = 3,
			teamOutputBonus = 100,
			teamXpBonus = 100,
			deltaSeconds = 1,
		})
		TestHarness.assertTrue(result.points >= 0 and result.points < math.huge)
		TestHarness.assertTrue(result.xp >= 0 and result.xp < math.huge)
	end
	local inactive = employee()
	inactive.status = "Inactive"
	local result = EmployeeProductivity.Calculate(config, inactive, config.traits[1], {
		equipmentLevel = 1,
		teamOutputBonus = 0,
		teamXpBonus = 0,
		deltaSeconds = 1,
	})
	TestHarness.assertEqual(result.points, 0)
end

local function progressionCapAndDeterministicStatsTest()
	local config = EmployeeTestUtils.validatedConfig()
	local value = employee()
	local levels = EmployeeProgression.ApplyXp(config, value, 100000)
	TestHarness.assertEqual(levels, 4)
	TestHarness.assertEqual(value.level, 5)
	TestHarness.assertEqual(value.speed, 9)
	TestHarness.assertEqual(value.quality, 7)
	TestHarness.assertEqual(value.reliability, 6)
	TestHarness.assertEqual(value.xp, 0)
end

local function moraleBandsAndTeamCapsTest()
	local config = EmployeeTestUtils.validatedConfig()
	local efficient = config.traits[4]
	local expectedMorale = {
		{ morale = 80, multiplier = 1.1 },
		{ morale = 50, multiplier = 1 },
		{ morale = 25, multiplier = 0.85 },
		{ morale = 0, multiplier = 0.65 },
	}
	for _, expectation in expectedMorale do
		local value = employee()
		value.traitId = efficient.id
		value.morale = expectation.morale
		local result = EmployeeProductivity.Calculate(config, value, efficient, {
			equipmentLevel = 1,
			teamOutputBonus = 0,
			teamXpBonus = 0,
			deltaSeconds = 1,
		})
		TestHarness.assertTrue(
			math.abs(result.pointsPerMinute - 5 * expectation.multiplier) < 1e-6,
			`Morale band {expectation.morale} used the wrong multiplier`
		)
	end
	local value = employee()
	value.traitId = efficient.id
	local capped = EmployeeProductivity.Calculate(config, value, efficient, {
		equipmentLevel = 1,
		teamOutputBonus = 100,
		teamXpBonus = 100,
		deltaSeconds = 1,
	})
	local expectedPoints = 5 * 1.1 * 1.15 / 60
	TestHarness.assertTrue(math.abs(capped.points - expectedPoints) < 1e-6, "TeamPlayer stack cap was not 15%")
	TestHarness.assertTrue(math.abs(capped.xp - expectedPoints * 2 * 1.2) < 1e-6, "Mentor stack cap was not 20%")
	local independent = config.traits[9]
	value.traitId = independent.id
	local ignored = EmployeeProductivity.Calculate(config, value, independent, {
		equipmentLevel = 1,
		teamOutputBonus = 100,
		teamXpBonus = 100,
		deltaSeconds = 1,
	})
	TestHarness.assertTrue(math.abs(ignored.points - 5 * 1.1 * 1.1 / 60) < 1e-6)
	TestHarness.assertTrue(math.abs(ignored.xp - ignored.points * 2) < 1e-6)
end

function EmployeeProgressionProductivitySpec.tests(): { TestCase }
	return {
		{
			name = "all 12 traits produce finite capped productivity and inactive output is zero",
			run = allTraitsFiniteTest,
		},
		{
			name = "employee XP reaches grade cap with deterministic stat growth",
			run = progressionCapAndDeterministicStatsTest,
		},
		{
			name = "morale bands and TeamPlayer Mentor stack caps match the contract",
			run = moraleBandsAndTeamCapsTest,
		},
	}
end

return table.freeze(EmployeeProgressionProductivitySpec)
