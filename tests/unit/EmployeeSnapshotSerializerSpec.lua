--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local EmployeeSnapshotSerializer = require(ServerScriptService.Domain.EmployeeSnapshotSerializer)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)

type EmployeeSessionSnapshot = EmployeeTypes.EmployeeSessionSnapshot
type TestCase = TestHarness.TestCase
local EmployeeSnapshotSerializerSpec = {}

local function snapshot(): EmployeeSessionSnapshot
	local config = EmployeeTestUtils.validatedConfig()
	local candidate = {
		candidateId = "candidate-1-1-1",
		ownerUserId = 1,
		slotIndex = 1,
		generation = 1,
		displayName = "Alex",
		roleId = "Developer" :: EmployeeTypes.EmployeeRoleId,
		grade = "Trainee" :: EmployeeTypes.EmployeeGrade,
		speed = 5,
		quality = 5,
		reliability = 5,
		traitId = "FastLearner" :: EmployeeTypes.EmployeeTraitId,
		hiringCost = 250,
		salaryPerCycle = 10,
		createdAt = 0,
		expiresAt = 300,
	}
	local candidates = {}
	for index = 1, config.candidate.poolSize do
		local copy = table.clone(candidate)
		copy.candidateId = `candidate-1-{index}-{index}`
		copy.slotIndex = index
		table.insert(candidates, { candidate = copy, remainingTtl = 200 })
	end
	local ledger = {} :: EmployeeTypes.RoleWorkLedger
	for _, role in config.roles do
		ledger[role.id] = 0
	end
	return {
		schemaVersion = 1,
		employees = {
			{
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
			},
		},
		assignments = { ["employee-1-1"] = "workstation:Developer:1" },
		roleWorkLedger = ledger,
		candidates = candidates,
		refreshRemainingSeconds = 20,
		payrollRemainingSeconds = 30,
		nextEmployeeSequence = 1,
	}
end

local function roundTripAndMalformedTest()
	local config = EmployeeTestUtils.validatedConfig()
	local source = snapshot()
	local result = EmployeeSnapshotSerializer.Validate(config, source)
	TestHarness.assertTrue(result.ok)
	if result.ok then
		result.value.employees[1].morale = 1
		TestHarness.assertEqual(source.employees[1].morale, 80)
	end
	local malformed = snapshot()
	malformed.assignments["employee-1-2"] = "workstation:Developer:1"
	local invalid = EmployeeSnapshotSerializer.Validate(config, malformed)
	TestHarness.assertTrue(not invalid.ok and invalid.error.code == "EmployeeSnapshotInvalid")
	local missingValue = snapshot()
	local missingRecord = (missingValue.employees[1] :: unknown) :: { [string]: unknown }
	missingRecord.level = nil
	local callOk, missingResult = pcall(function()
		return EmployeeSnapshotSerializer.Validate(config, missingValue)
	end)
	TestHarness.assertTrue(callOk, "Malformed snapshot validation must not raise")
	TestHarness.assertTrue(
		callOk and not missingResult.ok and missingResult.error.code == "EmployeeSnapshotInvalid",
		"Malformed snapshot must return EmployeeSnapshotInvalid"
	)
	local unsafeValue = snapshot()
	local unsafeRecord = (unsafeValue.employees[1] :: unknown) :: { [string]: unknown }
	local unsafeInstance = Instance.new("Folder")
	unsafeRecord.runtimeInstance = unsafeInstance
	local unsafeResult = EmployeeSnapshotSerializer.Validate(config, unsafeValue)
	TestHarness.assertTrue(not unsafeResult.ok and unsafeResult.error.code == "EmployeeSnapshotInvalid")
	unsafeInstance:Destroy()
end

function EmployeeSnapshotSerializerSpec.tests(): { TestCase }
	return {
		{
			name = "employee snapshot round-trip is data-only and malformed assignments are rejected",
			run = roundTripAndMalformedTest,
		},
	}
end

return table.freeze(EmployeeSnapshotSerializerSpec)
