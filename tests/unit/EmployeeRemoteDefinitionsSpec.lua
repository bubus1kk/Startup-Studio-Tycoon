--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefinitions = require(ReplicatedStorage.Shared.Remotes.RemoteDefinitions)
local RemoteTypes = require(ReplicatedStorage.Shared.Remotes.RemoteTypes)
local TestHarness = require(script.Parent.Parent.TestHarness)

type RemoteDefinition = RemoteTypes.RemoteDefinition
type TestCase = TestHarness.TestCase

local EmployeeRemoteDefinitionsSpec = {}

local function byName(name: string): RemoteDefinition
	for _, definition in RemoteDefinitions.definitions do
		if definition.name == name then
			return definition
		end
	end
	error(`Missing remote definition {name}`, 2)
end

local function exactRemoteSurfaceTest()
	local names = {}
	for _, definition in RemoteDefinitions.definitions do
		names[definition.name] = true
		TestHarness.assertEqual(definition.kind, "Function")
		TestHarness.assertEqual(definition.direction, "ClientToServer")
	end
	TestHarness.assertEqual(#RemoteDefinitions.definitions, 7)
	for _, name in
		{
			"RequestOfficeCatalog",
			"RequestOfficePurchase",
			"RequestEmployeeOverview",
			"RequestEmployeeHire",
			"RequestEmployeeAssignment",
			"RequestEmployeeDismiss",
			"RequestCandidateRefresh",
		}
	do
		TestHarness.assertTrue(names[name] == true, `Missing remote {name}`)
	end
end

local function employeePayloadBoundaryTest()
	local overview = byName("RequestEmployeeOverview")
	local hire = byName("RequestEmployeeHire")
	local assignment = byName("RequestEmployeeAssignment")
	local dismiss = byName("RequestEmployeeDismiss")
	local refresh = byName("RequestCandidateRefresh")
	TestHarness.assertTrue(overview.requestValidator({ rosterPage = 1 }).ok)
	TestHarness.assertTrue(not overview.requestValidator({ rosterPage = 1, cash = 999999 }).ok)
	TestHarness.assertTrue(hire.requestValidator({ requestId = "hire-1", candidateId = "candidate:1" }).ok)
	TestHarness.assertTrue(
		not hire.requestValidator({ requestId = "hire-1", candidateId = "candidate:1", hiringCost = 1 }).ok
	)
	TestHarness.assertTrue(assignment.requestValidator({
		requestId = "assign-1",
		employeeId = "employee:1",
		workstationId = "workstation:Developer:1",
	}).ok)
	TestHarness.assertTrue(not assignment.requestValidator({
		requestId = "assign-1",
		employeeId = "employee:1",
		workstationId = string.rep("x", 73),
	}).ok)
	TestHarness.assertTrue(dismiss.requestValidator({ requestId = "dismiss-1", employeeId = "employee:1" }).ok)
	TestHarness.assertTrue(refresh.requestValidator({ requestId = "refresh-1" }).ok)
	TestHarness.assertTrue(not refresh.requestValidator({ requestId = "refresh-1", timestamp = 0 }).ok)
end

function EmployeeRemoteDefinitionsSpec.tests(): { TestCase }
	return {
		{ name = "employee remote surface contains exactly five Stage 5 functions", run = exactRemoteSurfaceTest },
		{
			name = "employee remote validators reject authority-bearing and oversized fields",
			run = employeePayloadBoundaryTest,
		},
	}
end

return table.freeze(EmployeeRemoteDefinitionsSpec)
