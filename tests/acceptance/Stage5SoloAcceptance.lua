--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)

type Coordination = AcceptanceTestUtils.Coordination
type Recorder = AcceptanceTestUtils.Recorder

local Stage5SoloAcceptance = {}

local function data(result: AcceptanceTestUtils.ClientResult, command: string): { [string]: unknown }
	assert(result.ok and result.data ~= nil, `{command} failed: {result.message or "missing data"}`)
	return result.data :: { [string]: unknown }
end

function Stage5SoloAcceptance.Run(
	recorder: Recorder,
	coordination: Coordination,
	_args: { [string]: unknown }
): { [string]: number | string | boolean }
	local player = AcceptanceTestUtils.GetPlayers(1, 20)[1]
	local expectedHireCost = 0
	local cashBeforeHire = 0
	local hiredEmployeeId = ""
	recorder:Test("employee session and production remote registry are ready", function()
		AcceptanceTestUtils.WaitForReady(player, 20)
		assert(player:GetAttribute("EmployeeSessionReady") == true, "EmployeeSessionReady is not true")
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		assert(remotes ~= nil and #remotes:GetChildren() == 7, "Production remote registry must contain 7 functions")
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
			local remote = remotes:FindFirstChild(name)
			assert(remote ~= nil and remote:IsA("RemoteFunction"), `Production remote {name} is missing`)
		end
	end)
	recorder:Test("candidate board is server generated with exactly three bounded cards", function()
		local overview = data(
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeOverview", {}, 20),
			"EmployeeOverview"
		)
		assert(
			overview.ok == true and typeof(overview.candidates) == "table" and #overview.candidates == 3,
			"Candidate board contract failed"
		)
		assert(overview.rosterTotal == 0, "Fresh employee roster is not empty")
	end)
	recorder:Test("Developer hire performs exact server debit assignment and NPC spawn", function()
		data(
			AcceptanceTestUtils.RequestClient(coordination, player, "PurchaseOrder", {
				order = { "room_development", "equipment_dev_workstation" },
			}, 45),
			"PurchaseOrder"
		)
		AcceptanceTestUtils.Delay(1, 3, "workstation rebuild")
		local beforeHire = data(
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeOverview", {}, 20),
			"EmployeeOverview before hire"
		)
		cashBeforeHire = assert(beforeHire.cash :: number, "Pre-hire Cash is missing")
		for _, candidateValue in beforeHire.candidates :: { { [string]: unknown } } do
			if candidateValue.roleId == "Developer" then
				expectedHireCost = assert(candidateValue.hiringCost :: number, "Developer hiring cost is missing")
				break
			end
		end
		assert(expectedHireCost > 0, "No hireable Developer candidate was guaranteed")
		local hired = data(
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeHireCount", { count = 1 }, 45),
			"EmployeeHireCount"
		)
		assert(hired.rosterTotal == 1 and hired.occupiedWorkstations == 1, "Hire did not create one roster/reservation")
		assert(hired.cash == cashBeforeHire - expectedHireCost, "Hire did not perform the exact authoritative debit")
		local roster = hired.roster
		assert(typeof(roster) == "table" and #roster == 1, "Hired roster page is invalid")
		hiredEmployeeId = assert((roster[1] :: { [string]: unknown }).employeeId :: string, "Employee ID is missing")
		local folder = Workspace:FindFirstChild(`EmployeeNpcs_{player.UserId}`)
		assert(folder ~= nil and #folder:GetChildren() == 1, "Exactly one employee NPC was not spawned")
		local npc = folder:GetChildren()[1]
		assert(#npc:GetDescendants() > 0, "Employee NPC is empty")
		local humanoids = 0
		local animators = 0
		for _, descendant in npc:GetDescendants() do
			if descendant:IsA("Humanoid") then
				humanoids += 1
			end
			if descendant:IsA("Animator") then
				animators += 1
			end
			assert(not descendant:IsA("BaseScript"), "Employee NPC contains a script")
		end
		assert(humanoids == 1 and animators == 1, "Employee NPC humanoid/animator budget failed")
	end)
	recorder:Test("assigned employee produces role work XP and reaches the workstation", function()
		AcceptanceTestUtils.Delay(3, 6, "employee productivity and path settle")
		local overview = data(
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeOverview", {}, 20),
			"EmployeeOverview after work"
		)
		local roster = overview.roster
		assert(typeof(roster) == "table" and #roster == 1, "Working roster is invalid")
		assert(((roster[1] :: { [string]: unknown }).xp :: number) > 0, "Assigned employee XP did not grow")
		local developerPoints = 0
		for _, summary in overview.roleWorkSummary :: { { [string]: unknown } } do
			if summary.roleId == "Developer" then
				developerPoints = summary.workPoints :: number
			end
		end
		assert(developerPoints > 0, "Developer work ledger did not grow")
		local folder = Workspace:FindFirstChild(`EmployeeNpcs_{player.UserId}`)
		local plot = AcceptanceTestUtils.GetRuntimePlot(player)
		local approach = plot:FindFirstChild("EmployeeApproach_1", true)
		assert(folder ~= nil and #folder:GetChildren() == 1, "Working NPC is missing")
		assert(approach ~= nil and approach:IsA("Attachment"), "Developer approach point is missing")
		assert(
			(folder:GetChildren()[1]:GetPivot().Position - approach.WorldPosition).Magnitude < 8,
			"Employee did not settle near the assigned workstation"
		)
	end)
	recorder:Test("manual candidate refresh enforces its server cooldown", function()
		local first = data(
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeRefresh", {}, 20),
			"EmployeeRefresh first"
		)
		assert(first.ok == true, "First candidate refresh was not accepted")
		local second = data(
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeRefresh", {}, 20),
			"EmployeeRefresh second"
		)
		local errorValue = second.error
		assert(
			second.ok == false and typeof(errorValue) == "table" and errorValue.code == "CandidateRefreshCooldown",
			"Candidate refresh cooldown was not enforced"
		)
	end)
	recorder:Test("production Employees UI exists once and survives respawn", function()
		data(AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeUiSmoke", {}, 20), "EmployeeUiSmoke")
		player:LoadCharacterAsync()
		AcceptanceTestUtils.WaitForReady(player, 20)
		assert(player:GetAttribute("EmployeeSessionReady") == true, "Employee readiness was lost after respawn")
		local result = data(
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeUiSmoke", {}, 20),
			"EmployeeUiSmoke after respawn"
		)
		assert(result.guiCount == 1, "Employees GUI duplicated after respawn")
		local clientSpecs = data(
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeRunClientSpecs", {}, 25),
			"EmployeeRunClientSpecs"
		)
		assert(clientSpecs.employeeClientSpecs == true, "Employee client specs did not complete")
	end)
	recorder:Test("dismiss releases the workstation and removes the NPC", function()
		local dismissed = data(
			AcceptanceTestUtils.RequestClient(
				coordination,
				player,
				"EmployeeDismissOwn",
				{ employeeId = hiredEmployeeId },
				20
			),
			"EmployeeDismissOwn"
		)
		assert(dismissed.ok == true, "Dismiss request failed")
		local overview = dismissed.overview
		assert(
			typeof(overview) == "table" and overview.rosterTotal == 0 and overview.occupiedWorkstations == 0,
			"Dismiss did not release roster and workstation"
		)
		local folder = Workspace:FindFirstChild(`EmployeeNpcs_{player.UserId}`)
		assert(folder ~= nil and #folder:GetChildren() == 0, "Dismiss did not remove employee NPC")
	end)
	return { candidates = 3, employeesHired = 1, employeesDismissed = 1, exactDebit = true, productionRemotes = 7 }
end

return table.freeze(Stage5SoloAcceptance)
