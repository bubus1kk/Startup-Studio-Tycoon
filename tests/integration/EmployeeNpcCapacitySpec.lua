--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)

type TestCase = TestHarness.TestCase
local EmployeeNpcCapacitySpec = {}

local function thirtyNpcBudgetTest()
	local fixture = EmployeeTestUtils.createFixture(8301, true, 250000, "furniture_recreation")
	TestHarness.assertEqual(fixture.workstations:GetCapacity(fixture.userId), 30)
	for index = 1, 30 do
		local result = fixture:HireAny()
		TestHarness.assertTrue(
			result.ok,
			`Hire {index} failed: {if result.error ~= nil then result.error.code else "unknown"}`
		)
	end
	local overview = fixture.employees:HandleOverview(fixture.userId, { rosterPage = 1 })
	TestHarness.assertTrue(overview.ok and overview.rosterTotal == 30)
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 30)
	TestHarness.assertEqual(fixture.movement:GetNpcCount(fixture.userId), 30)
	local assignments = fixture.workstations:ExportAssignments(fixture.userId)
	local workstationIds = {}
	local assignmentCount = 0
	for _, workstationId in assignments do
		assignmentCount += 1
		TestHarness.assertTrue(not workstationIds[workstationId], `Duplicate reservation {workstationId}`)
		workstationIds[workstationId] = true
	end
	TestHarness.assertEqual(assignmentCount, 30)
	local metrics = fixture.movement:GetMetrics(fixture.userId)
	TestHarness.assertEqual(metrics.npcModels, 30)
	TestHarness.assertEqual(metrics.centralSchedulers, 1)
	TestHarness.assertTrue(metrics.peakPathRequestsPerSecond <= 8, "Path request burst exceeded the per-player budget")
	local folder = Workspace:FindFirstChild(`EmployeeNpcs_{fixture.userId}`)
	TestHarness.assertTrue(folder ~= nil and folder:GetAttribute("CentralSchedulerCount") == 1)
	if folder ~= nil then
		for _, npc in folder:GetChildren() do
			TestHarness.assertEqual(npc:GetAttribute("CollisionGroup"), "EmployeeNpcs")
			for _, descendant in npc:GetDescendants() do
				if descendant:IsA("BasePart") then
					TestHarness.assertTrue(not descendant.CanCollide, "Employee NPC can crowd-block a player")
				end
			end
		end
	end
	local rebuild = fixture.officeFixture:Purchase("furniture_recreation")
	TestHarness.assertTrue(rebuild.ok)
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	TestHarness.assertEqual(fixture.workstations:GetOccupiedCount(fixture.userId), 30)
	TestHarness.assertEqual(fixture.movement:GetNpcCount(fixture.userId), 30)
	local rebuiltAssignments = fixture.workstations:ExportAssignments(fixture.userId)
	for employeeId, workstationId in assignments do
		TestHarness.assertEqual(rebuiltAssignments[employeeId], workstationId)
	end
	local extra = fixture:HireAny()
	TestHarness.assertTrue(not extra.ok and extra.error ~= nil and extra.error.code == "EmployeeCapacityReached")
	fixture:Destroy()
	TestHarness.assertTrue(
		Workspace:FindFirstChild(`EmployeeNpcs_{fixture.userId}`) == nil,
		"NPC folder survived teardown"
	)
	local cleanedMetrics = fixture.movement:GetMetrics(fixture.userId)
	TestHarness.assertEqual(cleanedMetrics.npcModels, 0)
	TestHarness.assertEqual(cleanedMetrics.centralSchedulers, 0)
end

function EmployeeNpcCapacitySpec.tests(): { TestCase }
	return {
		{
			name = "Global HQ keeps 30 unique NPC reservations bounded across rebuild and cleanup",
			run = thirtyNpcBudgetTest,
		},
	}
end

return table.freeze(EmployeeNpcCapacitySpec)
