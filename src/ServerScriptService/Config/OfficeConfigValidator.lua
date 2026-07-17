--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)

type OfficeConfig = OfficeTypes.OfficeConfig
type Result<T> = AppTypes.Result<T>

local OfficeConfigValidator = {}

local EXPECTED_TIERS = 5
local EXPECTED_ROOMS = 9
local EXPECTED_ITEMS = 18
local EXPECTED_UPGRADES = 9
local EXPECTED_TOTAL_PRICE = 205150

local function isPositiveInteger(value: unknown): boolean
	return typeof(value) == "number" and value > 0 and value % 1 == 0
end

local function isFiniteVector3(value: Vector3): boolean
	return value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

local function fail(code: string, path: string): AppTypes.Failure
	return AppTypes.failure(code, "Office configuration is invalid", { path = path })
end

function OfficeConfigValidator.validate(value: unknown): Result<OfficeConfig>
	if typeof(value) ~= "table" then
		return fail("OfficeConfigTypeMismatch", "OfficeDefinitions")
	end
	local config = value :: OfficeConfig
	if config.schemaVersion ~= 1 or config.configVersion ~= 1 then
		return fail("OfficeConfigVersionInvalid", "OfficeDefinitions.version")
	end
	if config.pageSize ~= 5 then
		return fail("OfficePageSizeInvalid", "OfficeDefinitions.pageSize")
	end
	if #config.tiers ~= EXPECTED_TIERS or #config.rooms ~= EXPECTED_ROOMS then
		return fail("OfficeContentCountInvalid", "OfficeDefinitions.tiersOrRooms")
	end
	if #config.items ~= EXPECTED_ITEMS or #config.upgrades ~= EXPECTED_UPGRADES then
		return fail("OfficeContentCountInvalid", "OfficeDefinitions.itemsOrUpgrades")
	end

	local ids: { [string]: boolean } = {}
	local tierById: { [string]: OfficeTypes.TierDefinition } = {}
	local totalPrice = 0
	for index, tier in config.tiers do
		if ids[tier.id] or tier.id == "" then
			return fail("DuplicateOfficeId", `tiers[{index}].id`)
		end
		ids[tier.id] = true
		tierById[tier.id] = tier
		if index == 1 then
			if tier.id ~= "tier_garage" or tier.price ~= 0 then
				return fail("InitialTierInvalid", `tiers[{index}]`)
			end
		elseif not isPositiveInteger(tier.price) then
			return fail("OfficePriceInvalid", `tiers[{index}].price`)
		end
		totalPrice += tier.price
		if
			not isFiniteVector3(tier.shellSize)
			or tier.shellSize.X <= 0
			or tier.shellSize.Y <= 0
			or tier.shellSize.Z <= 0
		then
			return fail("OfficeEnvelopeInvalid", `tiers[{index}].shellSize`)
		end
	end

	local roomById: { [string]: OfficeTypes.RoomDefinition } = {}
	for index, room in config.rooms do
		if ids[room.id] then
			return fail("DuplicateOfficeId", `rooms[{index}].id`)
		end
		ids[room.id] = true
		roomById[room.id] = room
		if not isPositiveInteger(room.price) or tierById[room.requiredTierId] == nil then
			return fail("OfficeRoomInvalid", `rooms[{index}]`)
		end
		if
			not isFiniteVector3(room.envelope.size)
			or room.envelope.size.X <= 0
			or room.envelope.size.Y <= 0
			or room.envelope.size.Z <= 0
		then
			return fail("OfficeEnvelopeInvalid", `rooms[{index}].envelope`)
		end
		if room.equipmentSlot.id == room.furnitureSlot.id then
			return fail("DuplicateOfficeSlot", `rooms[{index}].slots`)
		end
		totalPrice += room.price
	end

	local itemById: { [string]: OfficeTypes.ItemDefinition } = {}
	for index, item in config.items do
		if ids[item.id] then
			return fail("DuplicateOfficeId", `items[{index}].id`)
		end
		ids[item.id] = true
		itemById[item.id] = item
		if not isPositiveInteger(item.price) or roomById[item.requiredRoomId] == nil then
			return fail("OfficeItemInvalid", `items[{index}]`)
		end
		local room = roomById[item.requiredRoomId]
		local expectedSlot = if item.kind == "Equipment" then room.equipmentSlot.id else room.furnitureSlot.id
		if item.slotId ~= expectedSlot then
			return fail("OfficeItemSlotInvalid", `items[{index}].slotId`)
		end
		totalPrice += item.price
	end

	for index, upgrade in config.upgrades do
		if ids[upgrade.id] then
			return fail("DuplicateOfficeId", `upgrades[{index}].id`)
		end
		ids[upgrade.id] = true
		if itemById[upgrade.targetItemId] == nil or upgrade.maxLevel ~= 3 then
			return fail("OfficeUpgradeInvalid", `upgrades[{index}]`)
		end
		for level = 2, upgrade.maxLevel do
			local price = upgrade.pricesByLevel[level]
			if not isPositiveInteger(price) or upgrade.templateIdsByLevel[level] == nil then
				return fail("OfficeUpgradeLevelInvalid", `upgrades[{index}].level{level}`)
			end
			totalPrice += price
		end
	end

	for _, tier in config.tiers do
		for _, roomId in tier.allowedRooms do
			if roomById[roomId] == nil or tier.roomAnchors[roomId] == nil then
				return fail("OfficeTierRoomInvalid", `{tier.id}.{roomId}`)
			end
		end
	end

	for id in roomById do
		local room = roomById[id]
		for _, prerequisiteId in room.prerequisites do
			if roomById[prerequisiteId] == nil or prerequisiteId == id then
				return fail("OfficePrerequisiteInvalid", `{id}.{prerequisiteId}`)
			end
		end
	end

	local visiting: { [string]: boolean } = {}
	local visited: { [string]: boolean } = {}
	local function visit(roomId: string): boolean
		if visiting[roomId] then
			return false
		end
		if visited[roomId] then
			return true
		end
		visiting[roomId] = true
		for _, prerequisiteId in roomById[roomId].prerequisites do
			if not visit(prerequisiteId) then
				return false
			end
		end
		visiting[roomId] = nil
		visited[roomId] = true
		return true
	end
	for roomId in roomById do
		if not visit(roomId) then
			return fail("OfficePrerequisiteCycle", roomId)
		end
	end

	if totalPrice ~= EXPECTED_TOTAL_PRICE then
		return AppTypes.failure("OfficeCatalogTotalInvalid", "Office catalog total changed", {
			expected = tostring(EXPECTED_TOTAL_PRICE),
			actual = tostring(totalPrice),
		})
	end
	return AppTypes.success(config)
end

return table.freeze(OfficeConfigValidator)
