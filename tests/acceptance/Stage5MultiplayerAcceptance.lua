--!strict

local Workspace = game:GetService("Workspace")

local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)

type Coordination = AcceptanceTestUtils.Coordination
type Recorder = AcceptanceTestUtils.Recorder

local Stage5MultiplayerAcceptance = {}

function Stage5MultiplayerAcceptance.Run(
	recorder: Recorder,
	coordination: Coordination,
	_args: { [string]: unknown }
): { [string]: number | string | boolean }
	local players = AcceptanceTestUtils.GetPlayers(3, 25)
	local candidateIdsByUser: { [number]: string } = {}
	recorder:Test("three employee sessions have isolated readiness plots and candidate pools", function()
		for _, player in players do
			AcceptanceTestUtils.WaitForReady(player, 20)
			assert(
				player:GetAttribute("EmployeeSessionReady") == true,
				`Employee session not ready for {player.UserId}`
			)
		end
		local results = AcceptanceTestUtils.RequestClients(
			coordination,
			players,
			"EmployeeOverview",
			function(): { [string]: unknown }
				return {}
			end,
			25
		)
		local candidateIds = {}
		for _, player in players do
			local result = results[player.UserId]
			assert(result ~= nil and result.ok and result.data ~= nil, "Employee overview missing")
			local candidates = (result.data :: { [string]: unknown }).candidates
			assert(typeof(candidates) == "table" and #candidates == 3, "Candidate pool size is not 3")
			local first = candidates[1] :: { [string]: unknown }
			assert(
				typeof(first.candidateId) == "string" and not candidateIds[first.candidateId],
				"Candidate ID leaked across owners"
			)
			candidateIds[first.candidateId] = true
			candidateIdsByUser[player.UserId] = first.candidateId :: string
		end
	end)
	recorder:Test("foreign candidate hire is rejected without changing either roster", function()
		local attacker = players[2]
		local victim = players[1]
		local result = AcceptanceTestUtils.RequestClient(
			coordination,
			attacker,
			"EmployeeHireCandidate",
			{ candidateId = candidateIdsByUser[victim.UserId] },
			20
		)
		assert(result.ok and result.data ~= nil and result.data.ok == false, "Foreign candidate hire was accepted")
	end)
	local employeeIdsByUser: { [number]: string } = {}
	recorder:Test("three players hire isolated employees and NPC folders", function()
		AcceptanceTestUtils.RequestClients(coordination, players, "PurchaseOrder", function(): { [string]: unknown }
			return { order = { "room_development", "equipment_dev_workstation" } }
		end, 60)
		AcceptanceTestUtils.Delay(1, 3, "multiplayer workstation rebuild")
		local results = AcceptanceTestUtils.RequestClients(
			coordination,
			players,
			"EmployeeHireCount",
			function(): { [string]: unknown }
				return { count = 1 }
			end,
			60
		)
		for _, player in players do
			local result = results[player.UserId]
			assert(result ~= nil and result.ok and result.data ~= nil, "Employee hire result missing")
			local data = result.data :: { [string]: unknown }
			local roster = data.roster
			assert(data.rosterTotal == 1 and typeof(roster) == "table" and #roster == 1, "Isolated roster count failed")
			local employeeId = (roster[1] :: { [string]: unknown }).employeeId
			assert(typeof(employeeId) == "string", "Employee ID is invalid")
			employeeIdsByUser[player.UserId] = employeeId
			local folder = Workspace:FindFirstChild(`EmployeeNpcs_{player.UserId}`)
			assert(folder ~= nil and #folder:GetChildren() == 1, "Per-owner NPC folder is invalid")
		end
	end)
	recorder:Test("foreign employee dismiss is rejected without changing either roster", function()
		local attacker = players[2]
		local victim = players[1]
		local foreignId = employeeIdsByUser[victim.UserId]
		assert(foreignId ~= nil, "Victim employee is missing")
		local result = AcceptanceTestUtils.RequestClient(
			coordination,
			attacker,
			"EmployeeForeignDismiss",
			{ employeeId = foreignId },
			20
		)
		assert(
			result.ok and result.data ~= nil and result.data.code == "ForeignEmployee",
			"Foreign dismiss was not rejected"
		)
		local overviews = AcceptanceTestUtils.RequestClients(
			coordination,
			players,
			"EmployeeOverview",
			function(): { [string]: unknown }
				return {}
			end,
			25
		)
		for _, player in players do
			assert(
				(overviews[player.UserId].data :: { [string]: unknown }).rosterTotal == 1,
				"Foreign request changed a roster"
			)
		end
	end)
	recorder:Test("foreign employee and foreign-only workstation assignment are rejected", function()
		local attacker = players[2]
		local victim = players[1]
		local foreignEmployee = AcceptanceTestUtils.RequestClient(coordination, attacker, "EmployeeAssign", {
			employeeId = employeeIdsByUser[victim.UserId],
			workstationId = "workstation:Developer:1",
		}, 20)
		assert(foreignEmployee.ok and foreignEmployee.data ~= nil, "Foreign employee assignment returned no data")
		local employeeError = (foreignEmployee.data :: { [string]: unknown }).error
		assert(
			(foreignEmployee.data :: { [string]: unknown }).ok == false
				and typeof(employeeError) == "table"
				and employeeError.code == "ForeignEmployee",
			"Foreign employee assignment was not rejected"
		)
		local setup = AcceptanceTestUtils.RequestClient(coordination, victim, "PurchaseOrder", {
			order = { "room_design", "equipment_design_workstation" },
		}, 45)
		assert(setup.ok, setup.message or "Victim-only design workstation setup failed")
		AcceptanceTestUtils.Delay(1, 3, "victim design workstation rebuild")
		local foreignWorkstation = AcceptanceTestUtils.RequestClient(coordination, attacker, "EmployeeAssign", {
			employeeId = employeeIdsByUser[attacker.UserId],
			workstationId = "workstation:Designer:1",
		}, 20)
		assert(
			foreignWorkstation.ok and foreignWorkstation.data ~= nil,
			"Foreign workstation assignment returned no data"
		)
		local workstationError = (foreignWorkstation.data :: { [string]: unknown }).error
		assert(
			(foreignWorkstation.data :: { [string]: unknown }).ok == false
				and typeof(workstationError) == "table"
				and workstationError.code == "ForeignWorkstation",
			"Foreign workstation assignment was not rejected"
		)
	end)
	recorder:Test("payroll debits and role work ledgers remain isolated for all three players", function()
		local beforeByUser = {} :: { [number]: { cash: number, salary: number, workPoints: number } }
		local maximumPayrollRemaining = 0
		for _, player in players do
			local result = AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeOverview", {}, 20)
			assert(result.ok and result.data ~= nil, "Pre-payroll employee overview failed")
			local overview = result.data :: { [string]: unknown }
			local roster = overview.roster
			assert(typeof(roster) == "table" and #roster == 1, "Pre-payroll roster is invalid")
			local employee = roster[1] :: { [string]: unknown }
			local workPoints = 0
			for _, summary in overview.roleWorkSummary :: { { [string]: unknown } } do
				if summary.roleId == "Developer" then
					workPoints = summary.workPoints :: number
				end
			end
			beforeByUser[player.UserId] = {
				cash = overview.cash :: number,
				salary = employee.salaryPerCycle :: number,
				workPoints = workPoints,
			}
			maximumPayrollRemaining = math.max(maximumPayrollRemaining, overview.payrollRemainingSeconds :: number)
		end
		AcceptanceTestUtils.Delay(maximumPayrollRemaining + 1, maximumPayrollRemaining + 5, "isolated payroll cycle")
		for _, player in players do
			local result = AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeOverview", {}, 20)
			assert(result.ok and result.data ~= nil, "Post-payroll employee overview failed")
			local overview = result.data :: { [string]: unknown }
			local expected = beforeByUser[player.UserId]
			assert(expected ~= nil, "Pre-payroll snapshot is missing")
			assert(overview.cash == expected.cash - expected.salary, "Payroll crossed player ownership boundaries")
			local developerPoints = 0
			for _, summary in overview.roleWorkSummary :: { { [string]: unknown } } do
				if summary.roleId == "Developer" then
					developerPoints = summary.workPoints :: number
				end
			end
			assert(developerPoints > expected.workPoints, "Player work ledger did not advance independently")
		end
	end)
	recorder:Test("one player leaving removes only its employee runtime", function()
		local departing = players[3]
		local survivors = { players[1], players[2] }
		local leaveResult = AcceptanceTestUtils.RequestClient(coordination, departing, "Leave", {}, 15)
		assert(leaveResult.ok and leaveResult.data ~= nil, leaveResult.message or "Employee client leave failed")
		local left, message = AcceptanceTestUtils.WaitFor(function(): boolean
			return departing.Parent == nil
				and #game:GetService("Players"):GetPlayers() == 2
				and Workspace:FindFirstChild(`EmployeeNpcs_{departing.UserId}`) == nil
		end, 25, "departing employee runtime cleanup")
		assert(left, message)
		for _, survivor in survivors do
			local result = AcceptanceTestUtils.RequestClient(coordination, survivor, "EmployeeOverview", {}, 20)
			assert(result.ok and result.data ~= nil and result.data.rosterTotal == 1, "Survivor roster changed")
			local folder = Workspace:FindFirstChild(`EmployeeNpcs_{survivor.UserId}`)
			assert(folder ~= nil and #folder:GetChildren() == 1, "Survivor NPC runtime changed")
		end
	end)
	return { players = 3, candidatePools = 3, employees = 3, npcFolders = 3, payrollCycles = 3, departed = 1 }
end

return table.freeze(Stage5MultiplayerAcceptance)
