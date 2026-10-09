--!strict

local function trait(
	id: string,
	values: {
		speed: number?,
		quality: number?,
		reliability: number?,
		output: number?,
		xp: number?,
		salary: number?,
		morale: number?,
		focused: number?,
		team: number?,
		mentor: number?,
		independent: boolean?,
	}
)
	return {
		id = id,
		speedMultiplier = values.speed or 1,
		qualityMultiplier = values.quality or 1,
		reliabilityMultiplier = values.reliability or 1,
		outputMultiplier = values.output or 1,
		xpMultiplier = values.xp or 1,
		salaryMultiplier = values.salary or 1,
		positiveMoraleMultiplier = values.morale or 1,
		focusedMoraleMinimum = values.focused,
		teamOutputBonus = values.team or 0,
		mentorXpBonus = values.mentor or 0,
		hiringCostMultiplier = 1,
		ignoresTeamBonuses = values.independent == true,
	}
end

local roleRows = {
	{ "Developer", "Developer", "room_development", "equipment_dev_workstation", "upgrade_dev_workstation", 2, 0, 0 },
	{ "Designer", "Designer", "room_design", "equipment_design_workstation", "upgrade_design_workstation", 0, 2, 0 },
	{ "QAEngineer", "QA Engineer", "room_qa", "equipment_qa_test_rig", "upgrade_qa_test_rig", 0, 1, 2 },
	{ "Marketer", "Marketer", "room_marketing", "equipment_marketing_console", "upgrade_marketing_console", 1, 1, 0 },
	{
		"ProductManager",
		"Product Manager",
		"room_meeting",
		"equipment_meeting_system",
		"upgrade_meeting_system",
		0,
		0,
		2,
	},
	{
		"SystemAdministrator",
		"System Administrator",
		"room_server",
		"equipment_server_rack",
		"upgrade_server_rack",
		0,
		0,
		2,
	},
	{
		"HRSpecialist",
		"HR Specialist",
		"room_recreation",
		"equipment_recreation_gaming_pod",
		"upgrade_recreation_gaming_pod",
		0,
		1,
		1,
	},
	{ "Executive", "Executive", "room_executive", "equipment_executive_desk", "upgrade_executive_desk", 1, 1, 1 },
	{
		"Researcher",
		"Researcher",
		"room_research",
		"equipment_research_compute_bench",
		"upgrade_research_compute_bench",
		0,
		2,
		0,
	},
}

local roles = {}
for _, row in roleRows do
	table.insert(roles, {
		id = row[1],
		displayName = row[2],
		roomId = row[3],
		equipmentId = row[4],
		upgradeId = row[5],
		statBias = { speed = row[6], quality = row[7], reliability = row[8] },
	})
end

local grades = {
	{ id = "Trainee", order = 1, maxLevel = 5, statMin = 3, statMax = 6, baseHiringCost = 250, baseSalary = 10 },
	{ id = "Junior", order = 2, maxLevel = 10, statMin = 6, statMax = 10, baseHiringCost = 750, baseSalary = 30 },
	{ id = "Specialist", order = 3, maxLevel = 15, statMin = 10, statMax = 15, baseHiringCost = 2000, baseSalary = 80 },
	{ id = "Expert", order = 4, maxLevel = 20, statMin = 15, statMax = 22, baseHiringCost = 5000, baseSalary = 180 },
}

local traits = {
	trait("FastLearner", { xp = 1.2 }),
	trait("Focused", { output = 1.1, focused = 70 }),
	trait("TeamPlayer", { team = 0.05 }),
	trait("Efficient", { salary = 0.9 }),
	trait("Perfectionist", { speed = 0.95, quality = 1.15 }),
	trait("Reliable", { reliability = 1.2 }),
	trait("Workaholic", { speed = 1.15, morale = 0.75 }),
	trait("Creative", { quality = 1.2, reliability = 0.95 }),
	trait("Independent", { output = 1.1, independent = true }),
	trait("Mentor", { mentor = 0.1 }),
	trait("Eager", { xp = 1.1, salary = 1.05 }),
	trait("Methodical", { speed = 0.95, reliability = 1.1 }),
}

local capacitiesByRole = {
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

local workstationOffsets = {
	CFrame.new(0, 2.5, -1.15),
	CFrame.new(-2.1, 2.5, -0.25),
	CFrame.new(2.1, 2.5, -0.25),
	CFrame.new(-1.05, 2.5, 1.15),
	CFrame.new(1.05, 2.5, 1.15),
}

local workstations = {}
for _, role in roles do
	local capacities = capacitiesByRole[role.id]
	local slots = {}
	for slotIndex = 1, capacities[3] do
		local minimumLevel = if slotIndex <= capacities[1] then 1 elseif slotIndex <= capacities[2] then 2 else 3
		local workOffset = workstationOffsets[slotIndex]
		table.insert(slots, {
			slotIndex = slotIndex,
			minimumEquipmentLevel = minimumLevel,
			workOffset = workOffset,
			approachOffset = workOffset * CFrame.new(0, 0, 0.65),
		})
	end
	table.insert(workstations, {
		roleId = role.id,
		logicalEquipmentId = role.equipmentId,
		capacities = { [1] = capacities[1], [2] = capacities[2], [3] = capacities[3] },
		slots = slots,
	})
end

return {
	schemaVersion = 1,
	configVersion = 1,
	roles = roles,
	grades = grades,
	traits = traits,
	gradeWeightsByTier = {
		tier_garage = { Trainee = 70, Junior = 30 },
		tier_small_loft = { Trainee = 45, Junior = 45, Specialist = 10 },
		tier_downtown = { Trainee = 20, Junior = 50, Specialist = 27, Expert = 3 },
		tier_tech_campus = { Junior = 35, Specialist = 50, Expert = 15 },
		tier_global_hq = { Junior = 20, Specialist = 50, Expert = 30 },
	},
	tierEmployeeCaps = {
		tier_garage = 2,
		tier_small_loft = 5,
		tier_downtown = 10,
		tier_tech_campus = 20,
		tier_global_hq = 30,
	},
	workstations = workstations,
	statClamp = { minimum = 1, maximum = 25 },
	candidate = {
		poolSize = 3,
		ttlSeconds = 300,
		refreshCooldownSeconds = 120,
		costPowerCoefficient = 0.025,
		minimumMultiplier = 0.8,
		maximumMultiplier = 1.75,
		names = {
			"Alex",
			"Avery",
			"Casey",
			"Dana",
			"Emery",
			"Jordan",
			"Morgan",
			"Quinn",
			"Riley",
			"Taylor",
			"Robin",
			"Sam",
		},
	},
	payroll = { intervalSeconds = 60, firstMissMorale = -15, laterMissMorale = -10, recoveryMorale = 10 },
	morale = {
		initial = 80,
		minimum = 0,
		maximum = 100,
		bands = {
			{ minimum = 80, multiplier = 1.1 },
			{ minimum = 50, multiplier = 1 },
			{ minimum = 25, multiplier = 0.85 },
			{ minimum = 0, multiplier = 0.65 },
		},
		hrRecoveryPerMinute = 0.5,
		recreationRecoveryPerMinute = 0.25,
		teamRecoveryCapPerMinute = 2,
	},
	productivity = {
		speedWeight = 0.5,
		qualityWeight = 0.3,
		reliabilityWeight = 0.2,
		levelBonusPerLevel = 0.025,
		equipmentMultipliers = { [1] = 1, [2] = 1.15, [3] = 1.3 },
		employmentMultipliers = { Active = 1, Unpaid = 0.5, Inactive = 0, Dismissed = 0 },
		teamPlayerStackCap = 0.15,
		mentorStackCap = 0.2,
		maximumDeltaSeconds = 5,
	},
	progression = {
		xpPerWorkPoint = 2,
		baseRequiredXp = 60,
		requiredXpPerLevel = 30,
		levelUpMorale = 5,
		retainXpAtMaxLevel = false,
	},
	scheduler = { productivitySeconds = 1, stuckSeconds = 0.5, candidateSeconds = 1 },
	movement = {
		stuckAfterSeconds = 4,
		minimumProgressStuds = 1,
		minimumPathRequestSeconds = 2,
		maxPathRequestsPerPlayerPerSecond = 8,
		walkSpeed = 10,
		agentRadius = 2,
		agentHeight = 5,
		animationIds = {
			idle = "rbxassetid://507766666",
			walk = "rbxassetid://507777826",
			work = "rbxassetid://507768375",
		},
	},
	performance = { maxEmployeesPerPlayer = 30, maxPlayers = 6, maxNpcModelsPerPlayer = 30 },
	ui = { rosterPageSize = 5 },
}
