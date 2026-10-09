--!strict

local Workspace = game:GetService("Workspace")

local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)

type Coordination = AcceptanceTestUtils.Coordination
type Recorder = AcceptanceTestUtils.Recorder

local Stage5NpcAcceptance = {}

function Stage5NpcAcceptance.Run(
	recorder: Recorder,
	coordination: Coordination,
	args: { [string]: unknown }
): { [string]: number | string | boolean }
	local countValue = args.employeeCount
	assert(
		typeof(countValue) == "number" and (countValue == 10 or countValue == 30),
		"NPC suite requires 10 or 30 employees"
	)
	local count = countValue :: number
	local player = AcceptanceTestUtils.GetPlayers(1, 20)[1]
	AcceptanceTestUtils.WaitForReady(player, 20)
	local employeeIdsBeforeRebuild = {} :: { [string]: boolean }
	local animationRevisionsBeforeRebuild = {} :: { [string]: number }
	recorder:Test("Global HQ exposes all 30 stable workstation attachments", function()
		local order = {}
		for _, itemId in AcceptanceTestUtils.FullProgressionOrder() do
			if itemId ~= "furniture_recreation" then
				table.insert(order, itemId)
			end
		end
		local result = AcceptanceTestUtils.RequestClient(coordination, player, "PurchaseOrder", { order = order }, 100)
		assert(result.ok and result.data ~= nil, result.message or "Full office progression failed")
		AcceptanceTestUtils.Delay(1, 3, "Global HQ workstation rebuild")
		local plot = AcceptanceTestUtils.GetRuntimePlot(player)
		local workAttachments = 0
		local approachAttachments = 0
		for _, descendant in plot:GetDescendants() do
			if descendant:IsA("Attachment") and string.find(descendant.Name, "EmployeeWork_", 1, true) == 1 then
				workAttachments += 1
			elseif descendant:IsA("Attachment") and string.find(descendant.Name, "EmployeeApproach_", 1, true) == 1 then
				approachAttachments += 1
			end
		end
		assert(
			workAttachments == 30 and approachAttachments == 30,
			`Expected 30/30 attachments, got {workAttachments}/{approachAttachments}`
		)
	end)
	recorder:Test(`hire {count} employees with unique reservations and bounded NPC structure`, function()
		local result =
			AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeHireCount", { count = count }, 110)
		assert(result.ok and result.data ~= nil, result.message or "Employee hire count failed")
		local overview = result.data :: { [string]: unknown }
		assert(
			overview.rosterTotal == count and overview.occupiedWorkstations == count,
			"Roster/reservation target count failed"
		)
		local folder = Workspace:FindFirstChild(`EmployeeNpcs_{player.UserId}`)
		assert(folder ~= nil and #folder:GetChildren() == count, "NPC model count failed")
		local humanoids = 0
		local animators = 0
		local normalPathMovedNpcs = 0
		local employeeIds = {}
		local workstationIds = {}
		local requiredR15Parts = {
			"HumanoidRootPart",
			"LowerTorso",
			"UpperTorso",
			"Head",
			"LeftUpperArm",
			"LeftLowerArm",
			"LeftHand",
			"RightUpperArm",
			"RightLowerArm",
			"RightHand",
			"LeftUpperLeg",
			"LeftLowerLeg",
			"LeftFoot",
			"RightUpperLeg",
			"RightLowerLeg",
			"RightFoot",
		}
		for _, npc in folder:GetChildren() do
			local employeeId = npc:GetAttribute("EmployeeId")
			assert(typeof(employeeId) == "string" and not employeeIds[employeeId], "Duplicate NPC employee ID")
			employeeIds[employeeId] = true
			employeeIdsBeforeRebuild[employeeId] = true
			local workstationId = npc:GetAttribute("WorkstationId")
			assert(
				typeof(workstationId) == "string" and not workstationIds[workstationId],
				"NPC workstation reservation is missing or duplicated"
			)
			workstationIds[workstationId] = true
			assert(npc:GetAttribute("R15Compatible") == true, "NPC is not marked R15-compatible")
			assert(npc:GetAttribute("CollisionGroup") == "EmployeeNpcs", "NPC collision group is unavailable")
			assert(npc:GetAttribute("LocomotionMechanism") == "KinematicPivotTo", "NPC locomotion contract drifted")
			assert(
				npc:GetAttribute("RootAnchoringContract") == "AnchoredForKinematicPivotTo",
				"NPC root anchoring contract drifted"
			)
			assert(npc:GetAttribute("AnimationsConfigured") == true, "NPC production animations are not configured")
			for _, partName in requiredR15Parts do
				assert(npc:FindFirstChild(partName) ~= nil, `NPC is missing R15 part {partName}`)
			end
			for _, descendant in npc:GetDescendants() do
				if descendant:IsA("Humanoid") then
					humanoids += 1
				end
				if descendant:IsA("Animator") then
					animators += 1
				end
				assert(not descendant:IsA("BaseScript"), "NPC contains a per-employee script")
				if descendant:IsA("BasePart") then
					assert(not descendant.CanCollide, "NPC can crowd-block another NPC or player")
					assert(
						descendant.Anchored == (descendant.Name == "HumanoidRootPart"),
						"NPC animation rig has an invalid anchored body part"
					)
				end
			end
		end
		assert(humanoids == count and animators == count, "Humanoid/Animator structural budget failed")
		assert(folder:GetAttribute("CentralSchedulerCount") == 1, "NPC runtime did not use one central scheduler")
		assert(
			(folder:GetAttribute("PathRequestPeakPerSecond") :: number? or math.huge) <= 8,
			"Per-player path request budget was exceeded"
		)
		local settled, message = AcceptanceTestUtils.WaitFor(function(): boolean
			for _, npc in folder:GetChildren() do
				if npc:GetAttribute("MovementState") ~= "Working" then
					return false
				end
			end
			return true
		end, 35, `all {count} NPC to settle or recover`)
		assert(settled, message)
		local settledPathRequests = folder:GetAttribute("PathRequestCount") :: number? or 0
		AcceptanceTestUtils.Delay(5, 8, "settled path request stability")
		assert(
			folder:GetAttribute("PathRequestCount") == settledPathRequests,
			"Path requests kept growing after all NPC settled"
		)
		for _, npc in folder:GetChildren() do
			local normalPathStepCount = npc:GetAttribute("NormalPathStepCount") :: number? or 0
			local normalPathDistance = npc:GetAttribute("NormalPathDistance") :: number? or 0
			local normalPathStart = npc:GetAttribute("NormalPathStartWorldPosition")
			local normalPathLast = npc:GetAttribute("NormalPathLastWorldPosition")
			if
				normalPathStepCount > 0
				and normalPathDistance > 0
				and typeof(normalPathStart) == "Vector3"
				and typeof(normalPathLast) == "Vector3"
				and ((normalPathLast :: Vector3) - (normalPathStart :: Vector3)).Magnitude > 0
			then
				normalPathMovedNpcs += 1
			end
			local animationMode = npc:GetAttribute("AnimationMode")
			assert(
				animationMode == "Asset" or animationMode == "ProceduralFallback",
				"Working NPC has no safe production animation mode"
			)
			local employeeId = npc:GetAttribute("EmployeeId")
			local animationRevision = npc:GetAttribute("AnimationStateRevision")
			assert(
				typeof(employeeId) == "string" and typeof(animationRevision) == "number",
				"NPC animation revision is missing"
			)
			animationRevisionsBeforeRebuild[employeeId] = animationRevision
			local pathCount = npc:GetAttribute("PathRequestCount") :: number? or 0
			local minimumInterval = npc:GetAttribute("MinimumPathInterval") :: number?
			if pathCount > 1 then
				assert(minimumInterval ~= nil and minimumInterval >= 1.95, "NPC path requests ignored the 2s throttle")
			end
		end
		assert(normalPathMovedNpcs > 0, "No NPC changed world position through the ordinary waypoint path")
	end)
	recorder:Test("post-hire office rebuild preserves reservations without duplicate NPC", function()
		local result = AcceptanceTestUtils.RequestClient(coordination, player, "PurchaseOrder", {
			order = { "furniture_recreation" },
		}, 45)
		assert(result.ok and result.data ~= nil, result.message or "Post-hire rebuild purchase failed")
		local folder = Workspace:FindFirstChild(`EmployeeNpcs_{player.UserId}`)
		assert(folder ~= nil, "NPC folder disappeared during office rebuild")
		local rebound, message = AcceptanceTestUtils.WaitFor(function(): boolean
			if #folder:GetChildren() ~= count then
				return false
			end
			for _, npc in folder:GetChildren() do
				if npc:GetAttribute("MovementState") ~= "Working" then
					return false
				end
			end
			return true
		end, 35, "NPC rebind after office rebuild")
		assert(rebound, message)
		local seen = {}
		for _, npc in folder:GetChildren() do
			local employeeId = npc:GetAttribute("EmployeeId")
			assert(typeof(employeeId) == "string" and employeeIdsBeforeRebuild[employeeId], "Rebuild replaced an NPC")
			assert(not seen[employeeId], "Rebuild duplicated an NPC")
			local animationRevision = npc:GetAttribute("AnimationStateRevision")
			assert(
				typeof(animationRevision) == "number"
					and animationRevision > (animationRevisionsBeforeRebuild[employeeId] or math.huge),
				"NPC animation did not restart during office rebuild/rebind"
			)
			local animationMode = npc:GetAttribute("AnimationMode")
			assert(
				animationMode == "Asset" or animationMode == "ProceduralFallback",
				"Rebound NPC lost its safe production animation mode"
			)
			local root = npc:FindFirstChild("HumanoidRootPart")
			assert(root ~= nil and root:IsA("BasePart") and root.Anchored, "Kinematic root unanchored during rebuild")
			seen[employeeId] = true
		end
	end)
	recorder:Test("repeated dismiss cleanup removes every NPC and reservation", function()
		local result = AcceptanceTestUtils.RequestClient(coordination, player, "EmployeeDismissAll", {}, 110)
		assert(result.ok and result.data ~= nil, result.message or "Employee cleanup failed")
		assert(result.data.rosterTotal == 0 and result.data.occupiedWorkstations == 0, "Roster cleanup failed")
		local folder = Workspace:FindFirstChild(`EmployeeNpcs_{player.UserId}`)
		assert(
			folder ~= nil and #folder:GetChildren() == 0 and folder:GetAttribute("ActiveNpcCount") == 0,
			"NPC cleanup did not return to baseline"
		)
	end)
	return {
		targetEmployees = count,
		npcModels = count,
		humanoids = count,
		workstationCapacity = 30,
		rebuildPreservedNpc = true,
		normalPathMovementObserved = true,
		cleanupNpcModels = 0,
	}
end

return table.freeze(Stage5NpcAcceptance)
