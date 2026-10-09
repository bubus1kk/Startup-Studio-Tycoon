--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)

type EmployeeConfig = EmployeeTypes.EmployeeConfig
type OfficeConfig = OfficeTypes.OfficeConfig
type Result<T> = AppTypes.Result<T>

type ExpectedTrait = {
	speedMultiplier: number,
	qualityMultiplier: number,
	reliabilityMultiplier: number,
	outputMultiplier: number,
	xpMultiplier: number,
	salaryMultiplier: number,
	positiveMoraleMultiplier: number,
	focusedMoraleMinimum: number | false,
	teamOutputBonus: number,
	mentorXpBonus: number,
	hiringCostMultiplier: number,
	ignoresTeamBonuses: boolean,
}

local EmployeeConfigValidator = {}

local function failure(code: string, path: string): AppTypes.Failure
	return AppTypes.failure(code, "Employee configuration is invalid", { path = path })
end

local function finite(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function positive(value: unknown): boolean
	return finite(value) and (value :: number) > 0
end

local function positiveInteger(value: unknown): boolean
	return positive(value) and (value :: number) % 1 == 0
end

local function finiteCFrame(value: unknown): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { (value :: CFrame):GetComponents() } do
		if not finite(component) then
			return false
		end
	end
	return true
end

local function safeDataTree(value: unknown, seen: { [{ [unknown]: unknown }]: boolean }?, depth: number?): boolean
	local valueType = typeof(value)
	if valueType == "number" then
		return finite(value)
	elseif valueType == "string" or valueType == "boolean" then
		return true
	elseif valueType == "CFrame" then
		return finiteCFrame(value)
	elseif valueType ~= "table" then
		return false
	end
	local current = value :: { [unknown]: unknown }
	if getmetatable(current) ~= nil or (depth or 0) >= 12 then
		return false
	end
	local visited = seen or {}
	if visited[current] then
		return false
	end
	visited[current] = true
	for key, nested in current do
		if
			(typeof(key) ~= "string" and typeof(key) ~= "number") or not safeDataTree(nested, visited, (depth or 0) + 1)
		then
			return false
		end
	end
	visited[current] = nil
	return true
end

function EmployeeConfigValidator.validate(value: unknown, officeConfig: OfficeConfig): Result<EmployeeConfig>
	if typeof(value) ~= "table" then
		return failure("EmployeeConfigTypeMismatch", "EmployeeDefinitions")
	end
	if not safeDataTree(value) then
		return failure("EmployeeConfigUnsafeValue", "EmployeeDefinitions")
	end
	local config = value :: EmployeeConfig
	if config.schemaVersion ~= 1 or config.configVersion ~= 1 then
		return failure("EmployeeConfigVersionInvalid", "EmployeeDefinitions.version")
	end
	if #config.roles ~= 9 or #config.grades ~= 4 or #config.traits ~= 12 then
		return failure("EmployeeContentCountInvalid", "EmployeeDefinitions.counts")
	end
	if
		config.candidate.poolSize ~= 3
		or config.candidate.ttlSeconds ~= 300
		or config.candidate.refreshCooldownSeconds ~= 120
	then
		return failure("EmployeeCandidateConfigInvalid", "EmployeeDefinitions.candidate")
	end
	if config.payroll.intervalSeconds ~= 60 or config.ui.rosterPageSize ~= 5 then
		return failure("EmployeeIntervalInvalid", "EmployeeDefinitions.payrollOrUi")
	end
	if
		not positiveInteger(config.statClamp.minimum)
		or not positiveInteger(config.statClamp.maximum)
		or config.statClamp.minimum >= config.statClamp.maximum
	then
		return failure("EmployeeStatClampInvalid", "EmployeeDefinitions.statClamp")
	end

	local roomIds: { [string]: boolean } = {}
	local itemIds: { [string]: boolean } = {}
	local upgradeIds: { [string]: boolean } = {}
	local tierIds: { [string]: boolean } = {}
	for _, tier in officeConfig.tiers do
		tierIds[tier.id] = true
	end
	for _, room in officeConfig.rooms do
		roomIds[room.id] = true
	end
	for _, item in officeConfig.items do
		itemIds[item.id] = true
	end
	for _, upgrade in officeConfig.upgrades do
		upgradeIds[upgrade.id] = true
	end

	local roleIds: { [string]: boolean } = {}
	local expectedRoleLinks = {
		Developer = { "Developer", "room_development", "equipment_dev_workstation", "upgrade_dev_workstation", 2, 0, 0 },
		Designer = { "Designer", "room_design", "equipment_design_workstation", "upgrade_design_workstation", 0, 2, 0 },
		QAEngineer = { "QA Engineer", "room_qa", "equipment_qa_test_rig", "upgrade_qa_test_rig", 0, 1, 2 },
		Marketer = { "Marketer", "room_marketing", "equipment_marketing_console", "upgrade_marketing_console", 1, 1, 0 },
		ProductManager = {
			"Product Manager",
			"room_meeting",
			"equipment_meeting_system",
			"upgrade_meeting_system",
			0,
			0,
			2,
		},
		SystemAdministrator = {
			"System Administrator",
			"room_server",
			"equipment_server_rack",
			"upgrade_server_rack",
			0,
			0,
			2,
		},
		HRSpecialist = {
			"HR Specialist",
			"room_recreation",
			"equipment_recreation_gaming_pod",
			"upgrade_recreation_gaming_pod",
			0,
			1,
			1,
		},
		Executive = { "Executive", "room_executive", "equipment_executive_desk", "upgrade_executive_desk", 1, 1, 1 },
		Researcher = {
			"Researcher",
			"room_research",
			"equipment_research_compute_bench",
			"upgrade_research_compute_bench",
			0,
			2,
			0,
		},
	}
	for index, role in config.roles do
		local expected = expectedRoleLinks[role.id]
		if
			expected == nil
			or roleIds[role.id]
			or not roomIds[role.roomId]
			or not itemIds[role.equipmentId]
			or not upgradeIds[role.upgradeId]
			or role.displayName ~= expected[1]
			or role.roomId ~= expected[2]
			or role.equipmentId ~= expected[3]
			or role.upgradeId ~= expected[4]
			or role.statBias.speed ~= expected[5]
			or role.statBias.quality ~= expected[6]
			or role.statBias.reliability ~= expected[7]
		then
			return failure("EmployeeRoleInvalid", `roles[{index}]`)
		end
		roleIds[role.id] = true
		for statName, bias in role.statBias do
			if not finite(bias) or bias < 0 or bias % 1 ~= 0 then
				return failure("EmployeeStatBiasInvalid", `roles[{index}].statBias.{statName}`)
			end
		end
	end

	local gradeIds: { [string]: boolean } = {}
	local expectedGrades = {
		Trainee = { 1, 5, 3, 6, 250, 10 },
		Junior = { 2, 10, 6, 10, 750, 30 },
		Specialist = { 3, 15, 10, 15, 2000, 80 },
		Expert = { 4, 20, 15, 22, 5000, 180 },
	}
	for index, grade in config.grades do
		local expected = expectedGrades[grade.id]
		if
			expected == nil
			or gradeIds[grade.id]
			or grade.order ~= index
			or grade.statMin > grade.statMax
			or grade.order ~= expected[1]
			or grade.maxLevel ~= expected[2]
			or grade.statMin ~= expected[3]
			or grade.statMax ~= expected[4]
			or grade.baseHiringCost ~= expected[5]
			or grade.baseSalary ~= expected[6]
		then
			return failure("EmployeeGradeOrderInvalid", `grades[{index}]`)
		end
		if
			not positiveInteger(grade.maxLevel)
			or not positiveInteger(grade.baseHiringCost)
			or not positiveInteger(grade.baseSalary)
		then
			return failure("EmployeeCurrencyInvalid", `grades[{index}]`)
		end
		if grade.statMin < 0 or grade.statMin % 1 ~= 0 or grade.statMax % 1 ~= 0 then
			return failure("EmployeeStatRangeInvalid", `grades[{index}]`)
		end
		gradeIds[grade.id] = true
	end

	local traitIds: { [string]: boolean } = {}
	local expectedTraits: { [string]: ExpectedTrait } = {
		FastLearner = {
			speedMultiplier = 1,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1,
			outputMultiplier = 1,
			xpMultiplier = 1.2,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Focused = {
			speedMultiplier = 1,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1,
			outputMultiplier = 1.1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = 70,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		TeamPlayer = {
			speedMultiplier = 1,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1,
			outputMultiplier = 1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0.05,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Efficient = {
			speedMultiplier = 1,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1,
			outputMultiplier = 1,
			xpMultiplier = 1,
			salaryMultiplier = 0.9,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Perfectionist = {
			speedMultiplier = 0.95,
			qualityMultiplier = 1.15,
			reliabilityMultiplier = 1,
			outputMultiplier = 1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Reliable = {
			speedMultiplier = 1,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1.2,
			outputMultiplier = 1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Workaholic = {
			speedMultiplier = 1.15,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1,
			outputMultiplier = 1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 0.75,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Creative = {
			speedMultiplier = 1,
			qualityMultiplier = 1.2,
			reliabilityMultiplier = 0.95,
			outputMultiplier = 1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Independent = {
			speedMultiplier = 1,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1,
			outputMultiplier = 1.1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = true,
		},
		Mentor = {
			speedMultiplier = 1,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1,
			outputMultiplier = 1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0.1,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Eager = {
			speedMultiplier = 1,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1,
			outputMultiplier = 1,
			xpMultiplier = 1.1,
			salaryMultiplier = 1.05,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
		Methodical = {
			speedMultiplier = 0.95,
			qualityMultiplier = 1,
			reliabilityMultiplier = 1.1,
			outputMultiplier = 1,
			xpMultiplier = 1,
			salaryMultiplier = 1,
			positiveMoraleMultiplier = 1,
			focusedMoraleMinimum = false,
			teamOutputBonus = 0,
			mentorXpBonus = 0,
			hiringCostMultiplier = 1,
			ignoresTeamBonuses = false,
		},
	}
	for index, traitDefinition in config.traits do
		local expected = expectedTraits[traitDefinition.id]
		if expected == nil or traitIds[traitDefinition.id] then
			return failure("DuplicateEmployeeTrait", `traits[{index}].id`)
		end
		traitIds[traitDefinition.id] = true
		for _, multiplier in
			{
				traitDefinition.speedMultiplier,
				traitDefinition.qualityMultiplier,
				traitDefinition.reliabilityMultiplier,
				traitDefinition.outputMultiplier,
				traitDefinition.xpMultiplier,
				traitDefinition.salaryMultiplier,
				traitDefinition.positiveMoraleMultiplier,
				traitDefinition.hiringCostMultiplier,
			}
		do
			if not positive(multiplier) or multiplier < 0.5 or multiplier > 2 then
				return failure("EmployeeTraitMultiplierInvalid", `traits[{index}]`)
			end
		end
		if traitDefinition.teamOutputBonus < 0 or traitDefinition.mentorXpBonus < 0 then
			return failure("EmployeeTraitBonusInvalid", `traits[{index}]`)
		end
		if
			traitDefinition.speedMultiplier ~= expected.speedMultiplier
			or traitDefinition.qualityMultiplier ~= expected.qualityMultiplier
			or traitDefinition.reliabilityMultiplier ~= expected.reliabilityMultiplier
			or traitDefinition.outputMultiplier ~= expected.outputMultiplier
			or traitDefinition.xpMultiplier ~= expected.xpMultiplier
			or traitDefinition.salaryMultiplier ~= expected.salaryMultiplier
			or traitDefinition.positiveMoraleMultiplier ~= expected.positiveMoraleMultiplier
			or (traitDefinition.focusedMoraleMinimum or false) ~= expected.focusedMoraleMinimum
			or traitDefinition.teamOutputBonus ~= expected.teamOutputBonus
			or traitDefinition.mentorXpBonus ~= expected.mentorXpBonus
			or traitDefinition.hiringCostMultiplier ~= expected.hiringCostMultiplier
			or traitDefinition.ignoresTeamBonuses ~= expected.ignoresTeamBonuses
		then
			return failure("EmployeeTraitEffectInvalid", `traits[{index}]`)
		end
	end

	local expectedTierWeights = {
		tier_garage = { Trainee = 70, Junior = 30 },
		tier_small_loft = { Trainee = 45, Junior = 45, Specialist = 10 },
		tier_downtown = { Trainee = 20, Junior = 50, Specialist = 27, Expert = 3 },
		tier_tech_campus = { Junior = 35, Specialist = 50, Expert = 15 },
		tier_global_hq = { Junior = 20, Specialist = 50, Expert = 30 },
	}
	for tierId in tierIds do
		local weights = config.gradeWeightsByTier[tierId]
		local expectedWeights = expectedTierWeights[tierId]
		local cap = config.tierEmployeeCaps[tierId]
		if weights == nil or expectedWeights == nil or not positiveInteger(cap) or cap > 30 then
			return failure("EmployeeTierConfigInvalid", tierId)
		end
		local weightTotal = 0
		local weightCount = 0
		for gradeId, weight in weights do
			weightCount += 1
			if not gradeIds[gradeId] or not positiveInteger(weight) or expectedWeights[gradeId] ~= weight then
				return failure("EmployeeTierWeightInvalid", `{tierId}.{gradeId}`)
			end
			weightTotal += weight
		end
		local expectedWeightCount = 0
		for gradeId, expectedWeight in expectedWeights do
			expectedWeightCount += 1
			if weights[gradeId] ~= expectedWeight then
				return failure("EmployeeTierWeightInvalid", `{tierId}.{gradeId}`)
			end
		end
		if weightTotal ~= 100 or weightCount ~= expectedWeightCount then
			return failure("EmployeeTierWeightInvalid", tierId)
		end
	end
	local expectedTierCaps = {
		tier_garage = 2,
		tier_small_loft = 5,
		tier_downtown = 10,
		tier_tech_campus = 20,
		tier_global_hq = 30,
	}
	for tierId, cap in config.tierEmployeeCaps do
		if expectedTierCaps[tierId] ~= cap then
			return failure("EmployeeTierConfigInvalid", tierId)
		end
	end
	if
		config.gradeWeightsByTier.tier_garage.Expert ~= nil
		or config.gradeWeightsByTier.tier_small_loft.Expert ~= nil
	then
		return failure("EmployeeExpertTierInvalid", "gradeWeightsByTier")
	end

	local workstationRoles: { [string]: boolean } = {}
	local expectedCapacities = {
		Developer = { 1, 3, 5 },
		Designer = { 1, 2, 4 },
		QAEngineer = { 1, 2, 4 },
		Marketer = { 1, 2, 4 },
		ProductManager = { 1, 2, 3 },
		SystemAdministrator = { 1, 2, 3 },
		HRSpecialist = { 1, 1, 2 },
		Executive = { 1, 1, 1 },
		Researcher = { 1, 2, 4 },
	}
	local l3Total = 0
	for index, definition in config.workstations do
		if
			workstationRoles[definition.roleId]
			or not roleIds[definition.roleId]
			or not itemIds[definition.logicalEquipmentId]
		then
			return failure("EmployeeWorkstationInvalid", `workstations[{index}]`)
		end
		workstationRoles[definition.roleId] = true
		local expected = expectedCapacities[definition.roleId]
		if
			expected == nil
			or definition.capacities[1] ~= expected[1]
			or definition.capacities[2] ~= expected[2]
			or definition.capacities[3] ~= expected[3]
		then
			return failure("EmployeeWorkstationCapacityInvalid", `workstations[{index}].capacities`)
		end
		local previous = 0
		for level = 1, 3 do
			local capacity = definition.capacities[level]
			if not positiveInteger(capacity) or capacity < previous then
				return failure("EmployeeWorkstationPrefixInvalid", `workstations[{index}].capacities[{level}]`)
			end
			previous = capacity
		end
		if #definition.slots ~= definition.capacities[3] then
			return failure("EmployeeWorkstationPrefixInvalid", `workstations[{index}].slots`)
		end
		l3Total += definition.capacities[3]
		for slotIndex, slot in definition.slots do
			if slot.slotIndex ~= slotIndex or slot.minimumEquipmentLevel < 1 or slot.minimumEquipmentLevel > 3 then
				return failure("EmployeeWorkstationSlotInvalid", `workstations[{index}].slots[{slotIndex}]`)
			end
			if not finiteCFrame(slot.workOffset) or not finiteCFrame(slot.approachOffset) then
				return failure("EmployeeWorkstationOffsetInvalid", `workstations[{index}].slots[{slotIndex}]`)
			end
			for _, offset in { slot.workOffset.Position, slot.approachOffset.Position } do
				if math.abs(offset.X) > 3 or offset.Y < 0 or offset.Y > 5 or math.abs(offset.Z) > 2 then
					return failure("EmployeeWorkstationEnvelopeInvalid", `workstations[{index}].slots[{slotIndex}]`)
				end
			end
			for previousIndex = 1, slotIndex - 1 do
				local previousSlot = definition.slots[previousIndex]
				if
					(slot.workOffset.Position - previousSlot.workOffset.Position).Magnitude < 1.5
					or (slot.approachOffset.Position - previousSlot.approachOffset.Position).Magnitude < 1.5
				then
					return failure("EmployeeWorkstationSpacingInvalid", `workstations[{index}].slots[{slotIndex}]`)
				end
			end
			if
				slotIndex <= definition.capacities[1] and slot.minimumEquipmentLevel ~= 1
				or slotIndex > definition.capacities[1] and slotIndex <= definition.capacities[2] and slot.minimumEquipmentLevel ~= 2
				or slotIndex > definition.capacities[2] and slot.minimumEquipmentLevel ~= 3
			then
				return failure("EmployeeWorkstationPrefixInvalid", `workstations[{index}].slots[{slotIndex}]`)
			end
		end
	end
	if l3Total ~= 30 or #config.workstations ~= 9 then
		return failure("EmployeeWorkstationCapacityInvalid", "workstations.L3")
	end

	for path, valueToCheck in
		{
			["candidate.costPowerCoefficient"] = config.candidate.costPowerCoefficient,
			["candidate.minimumMultiplier"] = config.candidate.minimumMultiplier,
			["candidate.maximumMultiplier"] = config.candidate.maximumMultiplier,
			["scheduler.productivitySeconds"] = config.scheduler.productivitySeconds,
			["scheduler.stuckSeconds"] = config.scheduler.stuckSeconds,
			["scheduler.candidateSeconds"] = config.scheduler.candidateSeconds,
			["movement.stuckAfterSeconds"] = config.movement.stuckAfterSeconds,
			["movement.minimumPathRequestSeconds"] = config.movement.minimumPathRequestSeconds,
			["movement.maxPathRequestsPerPlayerPerSecond"] = config.movement.maxPathRequestsPerPlayerPerSecond,
			["movement.walkSpeed"] = config.movement.walkSpeed,
			["movement.agentRadius"] = config.movement.agentRadius,
			["movement.agentHeight"] = config.movement.agentHeight,
			["productivity.maximumDeltaSeconds"] = config.productivity.maximumDeltaSeconds,
			["morale.recreationRecoveryPerMinute"] = config.morale.recreationRecoveryPerMinute,
		}
	do
		if not positive(valueToCheck) then
			return failure("EmployeeSchedulerInvalid", path)
		end
	end
	if config.candidate.minimumMultiplier > config.candidate.maximumMultiplier then
		return failure("EmployeeCandidateConfigInvalid", "candidate.multiplierClamp")
	end
	local animationCount = 0
	for animationName, animationId in config.movement.animationIds do
		animationCount += 1
		if
			typeof(animationId) ~= "string"
			or #animationId > 64
			or string.match(animationId, "^rbxassetid://%d+$") == nil
		then
			return failure("EmployeeAnimationIdInvalid", `movement.animationIds.{animationName}`)
		end
	end
	if
		animationCount ~= 3
		or string.match(config.movement.animationIds.idle, "^rbxassetid://%d+$") == nil
		or string.match(config.movement.animationIds.walk, "^rbxassetid://%d+$") == nil
		or string.match(config.movement.animationIds.work, "^rbxassetid://%d+$") == nil
	then
		return failure("EmployeeAnimationIdInvalid", "movement.animationIds")
	end
	if
		config.performance.maxEmployeesPerPlayer ~= 30
		or config.performance.maxNpcModelsPerPlayer ~= 30
		or config.performance.maxPlayers ~= 6
	then
		return failure("EmployeePerformanceBudgetInvalid", "performance")
	end
	return AppTypes.success(config)
end

return table.freeze(EmployeeConfigValidator)
