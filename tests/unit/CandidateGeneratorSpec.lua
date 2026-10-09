--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local CandidateGenerator = require(ServerScriptService.Domain.CandidateGenerator)
local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)

type TestCase = TestHarness.TestCase
local CandidateGeneratorSpec = {}

local function deterministicGenerationTest()
	local config = EmployeeTestUtils.validatedConfig()
	local function minimum(minimumValue: number, _maximum: number): number
		return minimumValue
	end
	local first = CandidateGenerator.new(config, minimum, nil):Generate({
		ownerUserId = 50,
		slotIndex = 1,
		generation = 4,
		officeTierId = "tier_garage",
		availableRoles = { "Developer" },
		now = 100,
	})
	local second = CandidateGenerator.new(config, minimum, nil):Generate({
		ownerUserId = 50,
		slotIndex = 1,
		generation = 4,
		officeTierId = "tier_garage",
		availableRoles = { "Developer" },
		now = 100,
	})
	TestHarness.assertEqual(first.candidateId, second.candidateId)
	TestHarness.assertEqual(first.roleId, "Developer")
	TestHarness.assertEqual(first.grade, "Trainee")
	TestHarness.assertEqual(first.expiresAt, 400)
	TestHarness.assertEqual(first.hiringCost, second.hiringCost)
end

local function gradeAvailabilityAndClampTest()
	local config = EmployeeTestUtils.validatedConfig()
	local function maximum(_minimum: number, maximumValue: number): number
		return maximumValue
	end
	local candidate = CandidateGenerator.new(config, maximum, nil):Generate({
		ownerUserId = 51,
		slotIndex = 3,
		generation = 1,
		officeTierId = "tier_downtown",
		availableRoles = { "Executive" },
		now = 0,
		forcedGrade = "Expert",
	})
	TestHarness.assertEqual(candidate.grade, "Expert")
	TestHarness.assertTrue(candidate.speed <= config.statClamp.maximum)
	TestHarness.assertTrue(candidate.hiringCost > 0 and candidate.hiringCost % 10 == 0)
	TestHarness.assertTrue(candidate.salaryPerCycle > 0 and candidate.salaryPerCycle % 1 == 0)
end

function CandidateGeneratorSpec.tests(): { TestCase }
	return {
		{
			name = "candidate generation is deterministic with injected sources and server TTL",
			run = deterministicGenerationTest,
		},
		{
			name = "candidate generation applies grade availability stat clamps and integer costs",
			run = gradeAvailabilityAndClampTest,
		},
	}
end

return table.freeze(CandidateGeneratorSpec)
