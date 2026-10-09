--!strict

local RunService = game:GetService("RunService")

local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)

type TestCase = TestHarness.TestCase
local EmployeeHireIntegrationSpec = {}

local function successfulHireIdempotencyDismissTest()
	local fixture = EmployeeTestUtils.createFixture(8101, false, 250000)
	local before = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(before.ok and overview.ok and #overview.candidates == 3)
	local candidate = overview.candidates[1]
	local request = { requestId = "hire-idempotent", candidateId = candidate.candidateId }
	local response = fixture.employees:Hire(fixture.userId, request)
	TestHarness.assertTrue(response.ok)
	local duplicate = fixture.employees:Hire(fixture.userId, request)
	TestHarness.assertTrue(duplicate.ok)
	local conflict = fixture.employees:Hire(fixture.userId, {
		requestId = request.requestId,
		candidateId = overview.candidates[2].candidateId,
	})
	TestHarness.assertTrue(not conflict.ok and conflict.error ~= nil and conflict.error.code == "RequestIdConflict")
	local consumed = fixture.employees:Hire(fixture.userId, {
		requestId = "hire-consumed-candidate",
		candidateId = candidate.candidateId,
	})
	TestHarness.assertTrue(
		not consumed.ok and consumed.error ~= nil and consumed.error.code == "CandidateAlreadyConsumed"
	)
	local after = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(after.ok and before.ok and before.value - after.value == candidate.hiringCost)
	local assignments = fixture.workstations:ExportAssignments(fixture.userId)
	local employeeId: string? = nil
	for id in assignments do
		employeeId = id
	end
	TestHarness.assertTrue(employeeId ~= nil)
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 1)
	TestHarness.assertEqual(fixture.movement:GetNpcCount(fixture.userId), 1)
	if employeeId ~= nil then
		fixture.requestSequence += 1
		local dismiss = fixture.employees:Dismiss(fixture.userId, {
			requestId = `dismiss-{fixture.requestSequence}`,
			employeeId = employeeId,
		})
		TestHarness.assertTrue(dismiss.ok)
		fixture.requestSequence += 1
		local dismissedAgain = fixture.employees:Dismiss(fixture.userId, {
			requestId = `dismiss-{fixture.requestSequence}`,
			employeeId = employeeId,
		})
		TestHarness.assertTrue(
			not dismissedAgain.ok and dismissedAgain.error ~= nil and dismissedAgain.error.code == "EmployeeDismissed"
		)
	end
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 0)
	TestHarness.assertEqual(fixture.movement:GetNpcCount(fixture.userId), 0)
	fixture:Destroy()
end

local function insufficientFundsRollbackTest()
	local fixture = EmployeeTestUtils.createFixture(8102, false, 1400)
	local before = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	local result = fixture:HireAny()
	local after = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(not result.ok and result.error ~= nil and result.error.code == "InsufficientFunds")
	TestHarness.assertTrue(before.ok and after.ok and before.value == after.value)
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 0)
	TestHarness.assertEqual(fixture.movement:GetNpcCount(fixture.userId), 0)
	fixture:Destroy()
end

local function upgradeRetentionAndDeletedDeskTest()
	local fixture = EmployeeTestUtils.createFixture(8103, false, 250000)
	local hire = fixture:HireAny()
	TestHarness.assertTrue(hire.ok)
	local assignments = fixture.workstations:ExportAssignments(fixture.userId)
	local employeeId: string? = nil
	local workstationId: string? = nil
	for id, assigned in assignments do
		employeeId = id
		workstationId = assigned
	end
	local upgrade = fixture.officeFixture:Purchase("upgrade_dev_workstation")
	TestHarness.assertTrue(upgrade.ok)
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	if employeeId ~= nil and workstationId ~= nil then
		local retained = fixture.workstations:ExportAssignments(fixture.userId)
		TestHarness.assertEqual(retained[employeeId], workstationId)
		local slot = fixture.workstations:GetSlot(fixture.userId, workstationId)
		TestHarness.assertTrue(slot ~= nil and slot.equipmentLevel == 2)
	end
	local rebuild = fixture.officeFixture:Purchase("furniture_development")
	TestHarness.assertTrue(rebuild.ok)
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	if employeeId ~= nil and workstationId ~= nil then
		local rebuilt = fixture.workstations:ExportAssignments(fixture.userId)
		TestHarness.assertEqual(rebuilt[employeeId], workstationId)
		TestHarness.assertEqual(fixture.movement:GetNpcCount(fixture.userId), 1)
	end
	local context = fixture.officeFixture.office:GetRuntimeContext(fixture.userId)
	TestHarness.assertTrue(context ~= nil)
	if context ~= nil then
		local equipment = context.root:FindFirstChild("equipment_dev_workstation", true)
		TestHarness.assertTrue(equipment ~= nil)
		if equipment ~= nil then
			equipment:Destroy()
		end
	end
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(overview.ok and #overview.roster == 1)
	if overview.ok and #overview.roster == 1 then
		TestHarness.assertTrue(overview.roster[1].assignedWorkstationId == nil)
	end
	local ledgerBefore = fixture.employees:GetRoleWorkLedger(fixture.userId)
	RunService.Heartbeat:Wait()
	task.wait(1.1)
	RunService.Heartbeat:Wait()
	local ledgerAfter = fixture.employees:GetRoleWorkLedger(fixture.userId)
	TestHarness.assertTrue(ledgerBefore ~= nil and ledgerAfter ~= nil)
	if ledgerBefore ~= nil and ledgerAfter ~= nil then
		TestHarness.assertEqual(ledgerAfter.Developer, ledgerBefore.Developer)
	end
	fixture:Destroy()
end

local function expiredCandidateTransactionTest()
	local now = 100
	local fixture = EmployeeTestUtils.createFixture(8106, false, 250000, nil, function(): number
		return now
	end)
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(overview.ok and #overview.candidates == 3)
	local candidateId = overview.candidates[1].candidateId
	local balanceBefore = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	now += fixture.config.candidate.ttlSeconds + 1
	local result = fixture.employees:Hire(fixture.userId, {
		requestId = "expired-candidate-transaction",
		candidateId = candidateId,
	})
	local balanceAfter = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(not result.ok and result.error ~= nil and result.error.code == "CandidateExpired")
	TestHarness.assertTrue(balanceBefore.ok and balanceAfter.ok and balanceBefore.value == balanceAfter.value)
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 0)
	TestHarness.assertEqual(fixture.movement:GetNpcCount(fixture.userId), 0)
	fixture:Destroy()
end

local function payrollSchedulerTransitionTest()
	local now = 100
	local fixture = EmployeeTestUtils.createFixture(8107, false, 250000, nil, function(): number
		return now
	end)
	TestHarness.assertTrue(fixture:HireAny().ok)
	local balance = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(balance.ok and balance.value > 0)
	if not balance.ok then
		fixture:Destroy()
		return
	end
	local drain = fixture.officeFixture.currency:ReserveDebit(
		fixture.userId,
		"Cash",
		balance.value,
		"EmployeePayrollIntegrationDrain",
		"employee-payroll-integration-drain"
	)
	TestHarness.assertTrue(drain.ok)
	if not drain.ok then
		fixture:Destroy()
		return
	end
	TestHarness.assertTrue(fixture.officeFixture.currency:CommitDebit(drain.value.reservationId).ok)
	now += fixture.config.payroll.intervalSeconds + 1
	RunService.Heartbeat:Wait()
	local unpaid = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(unpaid.ok and unpaid.roster[1].status == "Unpaid")
	now += fixture.config.payroll.intervalSeconds
	RunService.Heartbeat:Wait()
	local inactive = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(inactive.ok and inactive.roster[1].status == "Inactive")
	TestHarness.assertTrue(fixture.officeFixture.currency:RollbackCommittedDebit(drain.value.reservationId).ok)
	now += fixture.config.payroll.intervalSeconds
	RunService.Heartbeat:Wait()
	local recovered = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	local recoveredBalance = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(recovered.ok and recovered.roster[1].status == "Active")
	TestHarness.assertTrue(recoveredBalance.ok and recoveredBalance.value >= 0)
	fixture:Destroy()
end

local function tierCapAndReservationCollisionTest()
	local fixture = EmployeeTestUtils.createFixture(8104, false, 250000)
	TestHarness.assertTrue(fixture.officeFixture:Purchase("upgrade_dev_workstation").ok)
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	TestHarness.assertTrue(fixture:HireAny().ok)
	TestHarness.assertTrue(fixture:HireAny().ok)
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(overview.ok and #overview.roster == 2)
	if not overview.ok or #overview.roster ~= 2 then
		fixture:Destroy()
		return
	end
	local firstId = overview.roster[1].employeeId
	local secondId = overview.roster[2].employeeId
	local moveFirst = fixture.employees:Assign(fixture.userId, {
		requestId = "assign-first-slot-three",
		employeeId = firstId,
		workstationId = "workstation:Developer:3",
	})
	TestHarness.assertTrue(moveFirst.ok)
	local occupied = fixture.employees:Assign(fixture.userId, {
		requestId = "assign-second-occupied",
		employeeId = secondId,
		workstationId = "workstation:Developer:3",
	})
	TestHarness.assertTrue(not occupied.ok and occupied.error ~= nil and occupied.error.code == "WorkstationOccupied")
	local already = fixture.employees:Assign(fixture.userId, {
		requestId = "assign-first-same",
		employeeId = firstId,
		workstationId = "workstation:Developer:3",
	})
	TestHarness.assertTrue(not already.ok and already.error ~= nil and already.error.code == "EmployeeAlreadyAssigned")
	local third = fixture:HireAny()
	TestHarness.assertTrue(
		not third.ok and third.error ~= nil and third.error.code == "EmployeeCapacityReached",
		"Garage tier cap must win even when an L2 workstation has three slots"
	)
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 2)
	fixture:Destroy()
end

local function noCompatibleWorkstationRollbackTest()
	local fixture = EmployeeTestUtils.createFixture(8105, false, 250000)
	TestHarness.assertTrue(fixture.officeFixture:Purchase("room_design").ok)
	TestHarness.assertTrue(fixture.officeFixture:Purchase("equipment_design_workstation").ok)
	RunService.Heartbeat:Wait()
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(overview.ok)
	local candidateId = ""
	if overview.ok then
		for _, candidate in overview.candidates do
			if candidate.roleId == "Developer" then
				candidateId = candidate.candidateId
				break
			end
		end
	end
	TestHarness.assertTrue(candidateId ~= "")
	local balanceBefore = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	local context = fixture.officeFixture.office:GetRuntimeContext(fixture.userId)
	if context ~= nil then
		local equipment = context.root:FindFirstChild("equipment_dev_workstation", true)
		if equipment ~= nil then
			equipment:Destroy()
		end
	end
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	local response = fixture.employees:Hire(fixture.userId, {
		requestId = "hire-with-stale-role-candidate",
		candidateId = candidateId,
	})
	local balanceAfter = fixture.officeFixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(
		not response.ok and response.error ~= nil and response.error.code == "NoCompatibleWorkstation"
	)
	TestHarness.assertTrue(
		balanceBefore.ok and balanceAfter.ok and balanceBefore.value == balanceAfter.value,
		"Missing compatible workstation must not debit Cash"
	)
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 0)
	fixture:Destroy()
end

local function incompatibleAssignmentRollbackTest()
	local fixture = EmployeeTestUtils.createFixture(8108, false, 250000)
	TestHarness.assertTrue(fixture.officeFixture:Purchase("room_design").ok)
	TestHarness.assertTrue(fixture.officeFixture:Purchase("equipment_design_workstation").ok)
	RunService.Heartbeat:Wait()
	TestHarness.assertTrue(fixture:HireAny().ok)
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(overview.ok and #overview.roster == 1)
	if not overview.ok or #overview.roster ~= 1 then
		fixture:Destroy()
		return
	end
	local employee = overview.roster[1]
	local originalWorkstationId = employee.assignedWorkstationId
	local result = fixture.employees:Assign(fixture.userId, {
		requestId = "incompatible-role-assignment",
		employeeId = employee.employeeId,
		workstationId = "workstation:Designer:1",
	})
	TestHarness.assertTrue(not result.ok and result.error ~= nil and result.error.code == "WorkstationIncompatible")
	local assignments = fixture.workstations:ExportAssignments(fixture.userId)
	TestHarness.assertEqual(assignments[employee.employeeId], originalWorkstationId)
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 1)
	fixture:Destroy()
end

function EmployeeHireIntegrationSpec.tests(): { TestCase }
	return {
		{
			name = "employee hire debits once reserves one desk spawns one NPC and dismiss cleans up",
			run = successfulHireIdempotencyDismissTest,
		},
		{
			name = "employee hire insufficient funds rolls back Cash roster reservation and NPC",
			run = insufficientFundsRollbackTest,
		},
		{
			name = "equipment upgrade preserves employee assignment and deleted desk releases it",
			run = upgradeRetentionAndDeletedDeskTest,
		},
		{
			name = "tier cap and bidirectional workstation reservations reject collisions",
			run = tierCapAndReservationCollisionTest,
		},
		{
			name = "stale-role candidate without a compatible workstation rolls back without debit",
			run = noCompatibleWorkstationRollbackTest,
		},
		{
			name = "expired candidate transaction preserves Cash roster reservation and NPC state",
			run = expiredCandidateTransactionTest,
		},
		{
			name = "employee scheduler applies unpaid inactive and payroll recovery transitions",
			run = payrollSchedulerTransitionTest,
		},
		{
			name = "role-incompatible assignment preserves the original reservation",
			run = incompatibleAssignmentRollbackTest,
		},
	}
end

return table.freeze(EmployeeHireIntegrationSpec)
