--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local PlotDefinitions = require(game:GetService("ServerStorage").Config.PlotDefinitions)
local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)

type Coordination = AcceptanceTestUtils.Coordination
type Recorder = AcceptanceTestUtils.Recorder

local Stage5BlockedPathAcceptance = {}

function Stage5BlockedPathAcceptance.Run(
	recorder: Recorder,
	coordination: Coordination,
	_args: { [string]: unknown }
): { [string]: number | string | boolean }
	local player = AcceptanceTestUtils.GetPlayers(1, 20)[1]
	AcceptanceTestUtils.WaitForReady(player, 20)
	local obstacles = {} :: { Part }
	recorder:Test("deliberate obstacle blocks the direct entrance-to-workstation route", function()
		local result = AcceptanceTestUtils.RequestClient(coordination, player, "PurchaseOrder", {
			order = { "room_development", "equipment_dev_workstation" },
		}, 45)
		assert(result.ok, result.message or "Office setup failed")
		AcceptanceTestUtils.Delay(1, 3, "blocked-path workstation rebuild")
		local plot = AcceptanceTestUtils.GetRuntimePlot(player)
		local entrance = plot:FindFirstChild("EntranceApproach", true)
		local approach = plot:FindFirstChild("EmployeeApproach_1", true)
		assert(entrance ~= nil and entrance:IsA("BasePart"), "Entrance approach is missing")
		assert(approach ~= nil and approach:IsA("Attachment"), "Employee approach attachment is missing")
		local target = approach.WorldCFrame
		for index, definition in
			{
				{ size = Vector3.new(10, 10, 1), offset = CFrame.new(0, 4, -4) },
				{ size = Vector3.new(10, 10, 1), offset = CFrame.new(0, 4, 4) },
				{ size = Vector3.new(1, 10, 10), offset = CFrame.new(-4, 4, 0) },
				{ size = Vector3.new(1, 10, 10), offset = CFrame.new(4, 4, 0) },
			}
		do
			local wall = Instance.new("Part")
			wall.Name = `Stage5BlockedPathObstacle_{index}`
			wall.Anchored = true
			wall.Size = definition.size
			wall.CFrame = target * definition.offset
			wall.Parent = plot
			table.insert(obstacles, wall)
		end
	end)
	recorder:Test("bounded recovery keeps employee assigned and inside the owned plot", function()
		local result = AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeHireCount", { count = 1 }, 50)
		assert(result.ok and result.data ~= nil, result.message or "Blocked-path hire failed")
		local folder = Workspace:FindFirstChild(`EmployeeNpcs_{player.UserId}`)
		assert(folder ~= nil and #folder:GetChildren() == 1, "Blocked-path NPC was not created")
		local recovered, recoveryMessage = AcceptanceTestUtils.WaitFor(function(): boolean
			local npc = folder:GetChildren()[1]
			return npc ~= nil
				and npc:GetAttribute("MovementState") == "Working"
				and (npc:GetAttribute("RecoveryCount") :: number? or 0) >= 3
		end, 22, "blocked path recompute and final safe reposition")
		assert(recovered, recoveryMessage)
		local overviewResult = AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeOverview", {}, 20)
		assert(overviewResult.ok and overviewResult.data ~= nil, "Blocked-path overview failed")
		local overview = overviewResult.data :: { [string]: unknown }
		local roster = overview.roster
		assert(typeof(roster) == "table" and #roster == 1, "Blocked-path roster is invalid")
		assert(
			(roster[1] :: { [string]: unknown }).assignedWorkstationId ~= nil,
			"Blocked path released valid assignment"
		)
		assert(folder ~= nil and #folder:GetChildren() == 1, "Blocked-path NPC was lost")
		local npc = folder:GetChildren()[1]
		local pathRequests = npc:GetAttribute("PathRequestCount") :: number? or 0
		local recoveries = npc:GetAttribute("RecoveryCount") :: number? or 0
		local minimumInterval = npc:GetAttribute("MinimumPathInterval") :: number?
		assert(pathRequests >= 3 and recoveries >= 3, "Path failure did not trigger bounded recompute/recovery")
		assert(minimumInterval ~= nil and minimumInterval >= 1.95, "Blocked path retries ignored the 2s throttle")
		assert(
			(folder:GetAttribute("PathRequestPeakPerSecond") :: number? or math.huge) <= 8,
			"Blocked path exceeded the per-player path budget"
		)
		AcceptanceTestUtils.Delay(5, 8, "post-reposition path stability")
		assert(npc:GetAttribute("PathRequestCount") == pathRequests, "Blocked path caused infinite path spam")
		local plotId = player:GetAttribute("AssignedPlotId")
		local definition = nil
		for _, candidate in PlotDefinitions.definitions do
			if candidate.id == plotId then
				definition = candidate
				break
			end
		end
		assert(definition ~= nil, "Plot definition is missing")
		assert(PlotBounds.containsPoint(definition, npc:GetPivot().Position), "NPC recovery left the owned plot")
	end)
	for _, obstacle in obstacles do
		obstacle:Destroy()
	end
	return { obstaclesCreated = #obstacles, recoveryAttempts = 3, employeesRemainingAssigned = 1 }
end

return table.freeze(Stage5BlockedPathAcceptance)
