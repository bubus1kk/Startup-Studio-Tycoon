--!strict

local RunService = game:GetService("RunService")

local EmployeeTypes = require(game:GetService("ServerScriptService").Domain.EmployeeTypes)

local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)

type TestCase = TestHarness.TestCase
local EmployeeSnapshotRejoinSpec = {}

local function sameServerRoundTripTest()
	local fixture = EmployeeTestUtils.createFixture(8201, false, 250000)
	local hire = fixture:HireAny()
	TestHarness.assertTrue(hire.ok)
	task.wait(1.1)
	RunService.Heartbeat:Wait()
	local ledgerBefore = fixture.employees:GetRoleWorkLedger(fixture.userId)
	TestHarness.assertTrue(fixture.employees:StopMutations(fixture.userId).ok)
	local exported = fixture.employees:ExportSession(fixture.userId)
	TestHarness.assertTrue(exported.ok)
	fixture.employees:CloseSession(fixture.userId)
	if exported.ok then
		local prepare = fixture.employees:PrepareSession(fixture.userId, exported.value)
		TestHarness.assertTrue(prepare.ok)
	end
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(overview.ok and overview.rosterTotal == 1 and #overview.candidates == 3)
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 1)
	TestHarness.assertEqual(fixture.movement:GetNpcCount(fixture.userId), 1)
	local ledgerAfter = fixture.employees:GetRoleWorkLedger(fixture.userId)
	TestHarness.assertTrue(ledgerBefore ~= nil and ledgerAfter ~= nil)
	if ledgerBefore ~= nil and ledgerAfter ~= nil then
		TestHarness.assertEqual(ledgerAfter.Developer, ledgerBefore.Developer)
	end
	fixture:Destroy()
end

local function invalidAssignmentAndMalformedSnapshotFallbackTest()
	local fixture = EmployeeTestUtils.createFixture(8202, false, 250000)
	TestHarness.assertTrue(fixture:HireAny().ok)
	TestHarness.assertTrue(fixture.employees:StopMutations(fixture.userId).ok)
	local exported = fixture.employees:ExportSession(fixture.userId)
	TestHarness.assertTrue(exported.ok)
	fixture.employees:CloseSession(fixture.userId)
	if not exported.ok then
		fixture:Destroy()
		return
	end
	local employeeId = exported.value.employees[1].employeeId
	exported.value.assignments[employeeId] = "workstation:Developer:999"
	local restored = fixture.employees:PrepareSession(fixture.userId, exported.value)
	TestHarness.assertTrue(restored.ok)
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(
		overview.ok and overview.rosterTotal == 1 and overview.roster[1].assignedWorkstationId == nil,
		"Invalid assignment snapshot must restore the employee as unassigned"
	)
	fixture.employees:CloseSession(fixture.userId)
	local malformed = {
		schemaVersion = fixture.config.schemaVersion,
		employees = { { employeeId = "broken" } },
		assignments = {},
		roleWorkLedger = {},
		candidates = {},
		refreshRemainingSeconds = 0,
		payrollRemainingSeconds = 0,
		nextEmployeeSequence = 0,
	}
	local fallback = fixture.employees:PrepareSession(
		fixture.userId,
		(malformed :: unknown) :: EmployeeTypes.EmployeeSessionSnapshot
	)
	TestHarness.assertTrue(fallback.ok)
	local fallbackOverview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(
		fallbackOverview.ok and fallbackOverview.rosterTotal == 0 and #fallbackOverview.candidates == 3,
		"Malformed employee snapshot fallback must preserve a valid empty employee session"
	)
	fixture:Destroy()
end

local function restoredEmployeeLevelUpTest()
	local now = 100
	local fixture = EmployeeTestUtils.createFixture(8203, false, 250000, nil, function(): number
		return now
	end)
	TestHarness.assertTrue(fixture:HireAny().ok)
	TestHarness.assertTrue(fixture.employees:StopMutations(fixture.userId).ok)
	local exported = fixture.employees:ExportSession(fixture.userId)
	TestHarness.assertTrue(exported.ok)
	fixture.employees:CloseSession(fixture.userId)
	if not exported.ok then
		fixture:Destroy()
		return
	end
	local source = exported.value.employees[1]
	local speedBefore = source.speed
	local qualityBefore = source.quality
	local reliabilityBefore = source.reliability
	source.xp = 59.99
	TestHarness.assertTrue(fixture.employees:PrepareSession(fixture.userId, exported.value).ok)
	now += fixture.config.scheduler.productivitySeconds
	RunService.Heartbeat:Wait()
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(overview.ok and #overview.roster == 1)
	if overview.ok and #overview.roster == 1 then
		local employee = overview.roster[1]
		TestHarness.assertEqual(employee.level, 2)
		TestHarness.assertEqual(employee.speed, math.min(fixture.config.statClamp.maximum, speedBefore + 1))
		TestHarness.assertEqual(employee.quality, math.min(fixture.config.statClamp.maximum, qualityBefore + 1))
		TestHarness.assertEqual(employee.reliability, reliabilityBefore)
	end
	fixture:Destroy()
end

function EmployeeSnapshotRejoinSpec.tests(): { TestCase }
	return {
		{
			name = "same-server employee snapshot restores roster candidates assignment and NPC",
			run = sameServerRoundTripTest,
		},
		{
			name = "invalid snapshot assignment becomes unassigned and malformed data falls back safely",
			run = invalidAssignmentAndMalformedSnapshotFallbackTest,
		},
		{
			name = "restored assigned employee levels deterministically from produced work",
			run = restoredEmployeeLevelUpTest,
		},
	}
end

return table.freeze(EmployeeSnapshotRejoinSpec)
