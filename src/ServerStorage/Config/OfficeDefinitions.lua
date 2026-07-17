--!strict

local function envelope(x: number, y: number, z: number, offset: CFrame?)
	return {
		size = Vector3.new(x, y, z),
		localOffset = offset or CFrame.identity,
	}
end

local function anchor(x: number, z: number): CFrame
	return CFrame.new(x, 1, z)
end

local roomIds = {
	"room_development",
	"room_design",
	"room_qa",
	"room_marketing",
	"room_meeting",
	"room_server",
	"room_recreation",
	"room_executive",
	"room_research",
}

local garageAnchors = {
	room_development = anchor(-10, -8),
	room_design = anchor(10, -8),
}

local loftAnchors = {
	room_development = anchor(-20, -14),
	room_design = anchor(0, -14),
	room_qa = anchor(20, -14),
	room_marketing = anchor(-12, 8),
	room_meeting = anchor(12, 8),
}

local downtownAnchors = {
	room_development = anchor(-26, -18),
	room_design = anchor(0, -18),
	room_qa = anchor(26, -18),
	room_marketing = anchor(-26, 0),
	room_meeting = anchor(0, 0),
	room_server = anchor(26, 0),
	room_recreation = anchor(-20, 16),
}

local campusAnchors = {
	room_development = anchor(-28, -24),
	room_design = anchor(0, -24),
	room_qa = anchor(28, -24),
	room_marketing = anchor(-28, -4),
	room_meeting = anchor(0, -4),
	room_server = anchor(28, -4),
	room_recreation = anchor(-28, 16),
	room_executive = anchor(-12, 16),
	room_research = anchor(28, 16),
}

local tiers = {
	{
		id = "tier_garage",
		displayName = "Garage",
		description = "A focused two-room founder garage.",
		sortOrder = 1,
		price = 0,
		prerequisites = {},
		templateId = "Garage",
		shellSize = Vector3.new(48, 14, 36),
		shellOffset = CFrame.new(0, 7, -8),
		roomAnchors = garageAnchors,
		allowedRooms = { "room_development", "room_design" },
	},
	{
		id = "tier_small_loft",
		displayName = "Small Loft",
		description = "An open loft for the first cross-functional team.",
		sortOrder = 2,
		price = 2500,
		prerequisites = { "room_development", "room_design" },
		templateId = "SmallLoft",
		shellSize = Vector3.new(64, 16, 48),
		shellOffset = CFrame.new(0, 8, -4),
		roomAnchors = loftAnchors,
		allowedRooms = { "room_development", "room_design", "room_qa", "room_marketing", "room_meeting" },
	},
	{
		id = "tier_downtown",
		displayName = "Downtown Office",
		description = "A polished office with operations capacity.",
		sortOrder = 3,
		price = 8000,
		prerequisites = { "room_qa", "room_marketing", "room_meeting" },
		templateId = "DowntownOffice",
		shellSize = Vector3.new(80, 20, 60),
		shellOffset = CFrame.new(0, 10, -4),
		roomAnchors = downtownAnchors,
		allowedRooms = {
			"room_development",
			"room_design",
			"room_qa",
			"room_marketing",
			"room_meeting",
			"room_server",
			"room_recreation",
		},
	},
	{
		id = "tier_tech_campus",
		displayName = "Tech Campus",
		description = "A large campus for executive and research work.",
		sortOrder = 4,
		price = 18000,
		prerequisites = { "room_server", "room_recreation" },
		templateId = "TechCampus",
		shellSize = Vector3.new(88, 24, 76),
		shellOffset = CFrame.new(0, 12, -6),
		roomAnchors = campusAnchors,
		allowedRooms = roomIds,
	},
	{
		id = "tier_global_hq",
		displayName = "Global HQ",
		description = "The complete headquarters of a global studio.",
		sortOrder = 5,
		price = 35000,
		prerequisites = { "room_executive", "room_research" },
		templateId = "GlobalHQ",
		shellSize = Vector3.new(88, 30, 88),
		shellOffset = CFrame.new(0, 15, -4),
		roomAnchors = campusAnchors,
		allowedRooms = roomIds,
	},
}

local roomContent = {
	{
		"development",
		"Development Room",
		600,
		"tier_garage",
		{},
		"DevelopmentRoom",
		"Development Workstation",
		"Development Whiteboard",
	},
	{
		"design",
		"Design Studio",
		900,
		"tier_garage",
		{ "room_development" },
		"DesignStudio",
		"Design Workstation",
		"Design Moodboard",
	},
	{ "qa", "QA Lab", 1500, "tier_small_loft", { "room_development" }, "QALab", "QA Test Rig", "QA Bug Board" },
	{
		"marketing",
		"Marketing Room",
		2200,
		"tier_small_loft",
		{ "room_design" },
		"MarketingRoom",
		"Marketing Console",
		"Marketing Campaign Display",
	},
	{
		"meeting",
		"Meeting Room",
		3000,
		"tier_small_loft",
		{ "room_qa", "room_marketing" },
		"MeetingRoom",
		"Meeting System",
		"Meeting Credenza",
	},
	{
		"server",
		"Server Room",
		5000,
		"tier_downtown",
		{ "room_meeting" },
		"ServerRoom",
		"Server Rack",
		"Server Cooling Unit",
	},
	{
		"recreation",
		"Recreation Area",
		6500,
		"tier_downtown",
		{ "room_marketing" },
		"RecreationArea",
		"Recreation Gaming Pod",
		"Recreation Lounge Set",
	},
	{
		"executive",
		"Executive Office",
		9500,
		"tier_tech_campus",
		{ "room_server" },
		"ExecutiveOffice",
		"Executive Desk",
		"Executive Award Cabinet",
	},
	{
		"research",
		"Research Lab",
		12000,
		"tier_tech_campus",
		{ "room_qa", "room_server" },
		"ResearchLab",
		"Research Compute Bench",
		"Research Prototype Cabinet",
	},
}

local furnitureSlots = {
	development = CFrame.new(0, 2, -5),
	design = CFrame.new(0, 2, -5),
	qa = CFrame.new(0, 2, -5),
	marketing = CFrame.new(5.5, 1, 4.5),
	meeting = CFrame.new(5.5, 1, 4.5),
	server = CFrame.new(5.5, 1, 4.5),
	recreation = CFrame.new(5.5, 1, 4.5),
	executive = CFrame.new(0, 2, -5),
	research = CFrame.new(5.5, 1, 4.5),
}

local rooms = {}
for index, content in roomContent do
	local key = content[1] :: string
	table.insert(rooms, {
		id = `room_{key}`,
		displayName = content[2],
		description = `{content[2]} expands the studio's production floor.`,
		sortOrder = index,
		price = content[3],
		requiredTierId = content[4],
		prerequisites = content[5],
		templateId = content[6],
		placementKey = `room.{key}`,
		envelope = envelope(16, 12, 16, CFrame.new(0, 5, 0)),
		doorwayClearance = envelope(4, 8, 4, CFrame.new(0, 4, 10)),
		equipmentSlot = {
			id = `{key}.main.01`,
			placementKey = `{key}.main.01`,
			localOffset = CFrame.new(0, 1, 0),
			envelope = envelope(6, 5, 4),
		},
		furnitureSlot = {
			id = `{key}.furniture.01`,
			placementKey = `{key}.furniture.01`,
			localOffset = furnitureSlots[key],
			envelope = envelope(4, 5, 3),
		},
	})
end

local itemContent = {
	{
		"dev_workstation",
		"development",
		"Development Workstation",
		700,
		"DevelopmentWorkstation",
		"DevelopmentWhiteboard",
		250,
	},
	{ "design_workstation", "design", "Design Workstation", 1000, "DesignWorkstation", "DesignMoodboard", 300 },
	{ "qa_test_rig", "qa", "QA Test Rig", 1400, "QATestRig", "QABugBoard", 400 },
	{
		"marketing_console",
		"marketing",
		"Marketing Console",
		1800,
		"MarketingConsole",
		"MarketingCampaignDisplay",
		600,
	},
	{ "meeting_system", "meeting", "Meeting System", 2200, "MeetingSystem", "MeetingCredenza", 700 },
	{ "server_rack", "server", "Server Rack", 3200, "ServerRack", "ServerCoolingUnit", 1200 },
	{
		"recreation_gaming_pod",
		"recreation",
		"Recreation Gaming Pod",
		2500,
		"RecreationGamingPod",
		"RecreationLoungeSet",
		900,
	},
	{ "executive_desk", "executive", "Executive Desk", 4000, "ExecutiveDesk", "ExecutiveAwardCabinet", 1200 },
	{
		"research_compute_bench",
		"research",
		"Research Compute Bench",
		4800,
		"ResearchComputeBench",
		"ResearchPrototypeCabinet",
		1500,
	},
}

local tierByRoom = {}
for _, room in rooms do
	tierByRoom[room.id] = room.requiredTierId
end

local items = {}
for index, content in itemContent do
	local itemKey = content[1] :: string
	local roomKey = content[2] :: string
	local roomId = `room_{roomKey}`
	table.insert(items, {
		id = `equipment_{itemKey}`,
		displayName = content[3],
		description = `Core equipment for the {roomKey} team.`,
		sortOrder = index,
		kind = "Equipment",
		price = content[4],
		requiredTierId = tierByRoom[roomId],
		requiredRoomId = roomId,
		prerequisites = { roomId },
		templateId = `{content[5]}L1`,
		slotId = `{roomKey}.main.01`,
		placementKey = `{roomKey}.main.01`,
		envelope = envelope(6, 5, 4, CFrame.new(0, 2.5, 0)),
	})
	table.insert(items, {
		id = `furniture_{roomKey}`,
		displayName = string.gsub(content[6] :: string, "([A-Z])", " %1"):sub(2),
		description = `Finishing furniture for the {roomKey} room.`,
		sortOrder = index,
		kind = "Furniture",
		price = content[7],
		requiredTierId = tierByRoom[roomId],
		requiredRoomId = roomId,
		prerequisites = { roomId },
		templateId = content[6],
		slotId = `{roomKey}.furniture.01`,
		placementKey = `{roomKey}.furniture.01`,
		envelope = envelope(4, 5, 3, CFrame.new(0, 2.5, 0)),
	})
end

local upgradePrices = {
	{ 900, 1600 },
	{ 1300, 2200 },
	{ 1800, 3000 },
	{ 2300, 3800 },
	{ 2800, 4500 },
	{ 4200, 6500 },
	{ 3200, 4800 },
	{ 5200, 8000 },
	{ 6200, 9500 },
}

local upgrades = {}
for index, content in itemContent do
	local itemKey = content[1] :: string
	local roomKey = content[2] :: string
	local prices = upgradePrices[index]
	table.insert(upgrades, {
		id = `upgrade_{itemKey}`,
		displayName = `{content[3]} Upgrade`,
		description = `Improve {content[3]} through three visual levels.`,
		sortOrder = index,
		targetItemId = `equipment_{itemKey}`,
		requiredTierId = tierByRoom[`room_{roomKey}`],
		prerequisites = { `equipment_{itemKey}` },
		maxLevel = 3,
		pricesByLevel = { [2] = prices[1], [3] = prices[2] },
		templateIdsByLevel = {
			[1] = `{content[5]}L1`,
			[2] = `{content[5]}L2`,
			[3] = `{content[5]}L3`,
		},
	})
end

return {
	schemaVersion = 1,
	configVersion = 1,
	pageSize = 5,
	tiers = tiers,
	rooms = rooms,
	items = items,
	upgrades = upgrades,
}
