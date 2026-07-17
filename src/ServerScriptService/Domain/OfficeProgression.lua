--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)

type OfficeConfig = OfficeTypes.OfficeConfig
type OfficeItemState = OfficeTypes.OfficeItemState
type OfficeLayoutState = OfficeTypes.OfficeLayoutState
type Result<T> = AppTypes.Result<T>

export type Evaluation = {
	state: OfficeItemState,
	price: number,
	code: string?,
	currentLevel: number?,
	maxLevel: number?,
}

type ProgressionData = {
	_config: OfficeConfig,
	_tierById: { [string]: OfficeTypes.TierDefinition },
	_roomById: { [string]: OfficeTypes.RoomDefinition },
	_itemById: { [string]: OfficeTypes.ItemDefinition },
	_upgradeById: { [string]: OfficeTypes.UpgradeDefinition },
	_tierOrder: { [string]: number },
}

local OfficeProgression = {}
OfficeProgression.__index = OfficeProgression
export type Progression = typeof(setmetatable({} :: ProgressionData, OfficeProgression))

function OfficeProgression.new(config: OfficeConfig): Progression
	local tierById: { [string]: OfficeTypes.TierDefinition } = {}
	local roomById: { [string]: OfficeTypes.RoomDefinition } = {}
	local itemById: { [string]: OfficeTypes.ItemDefinition } = {}
	local upgradeById: { [string]: OfficeTypes.UpgradeDefinition } = {}
	local tierOrder: { [string]: number } = {}
	for index, tier in config.tiers do
		tierById[tier.id] = tier
		tierOrder[tier.id] = index
	end
	for _, room in config.rooms do
		roomById[room.id] = room
	end
	for _, item in config.items do
		itemById[item.id] = item
	end
	for _, upgrade in config.upgrades do
		upgradeById[upgrade.id] = upgrade
	end
	return setmetatable({
		_config = config,
		_tierById = tierById,
		_roomById = roomById,
		_itemById = itemById,
		_upgradeById = upgradeById,
		_tierOrder = tierOrder,
	}, OfficeProgression)
end

function OfficeProgression.CreateInitialLayout(self: Progression): OfficeLayoutState
	return {
		schemaVersion = self._config.schemaVersion,
		configVersion = self._config.configVersion,
		officeTierId = "tier_garage",
		purchasedRooms = {},
		purchasedEquipment = {},
		purchasedFurniture = {},
		upgradeLevels = {},
		occupiedSlots = {},
		placementKeys = {},
		revision = 0,
	}
end

local function allPurchased(layout: OfficeLayoutState, ids: { string }): boolean
	for _, id in ids do
		if
			not layout.purchasedRooms[id]
			and not layout.purchasedEquipment[id]
			and not layout.purchasedFurniture[id]
		then
			return false
		end
	end
	return true
end

function OfficeProgression.Evaluate(
	self: Progression,
	layout: OfficeLayoutState,
	itemId: string,
	isPending: boolean
): Result<Evaluation>
	if isPending then
		return AppTypes.success({ state = "Pending", price = 0 })
	end
	local tier = self._tierById[itemId]
	if tier ~= nil then
		if itemId == "tier_garage" or self._tierOrder[layout.officeTierId] >= self._tierOrder[itemId] then
			return AppTypes.success({ state = "Purchased", price = tier.price })
		end
		if
			self._tierOrder[itemId] ~= self._tierOrder[layout.officeTierId] + 1
			or not allPurchased(layout, tier.prerequisites)
		then
			return AppTypes.success({ state = "Locked", price = tier.price, code = "PrerequisiteMissing" })
		end
		return AppTypes.success({ state = "Available", price = tier.price })
	end

	local room = self._roomById[itemId]
	if room ~= nil then
		if layout.purchasedRooms[itemId] then
			return AppTypes.success({ state = "Purchased", price = room.price })
		end
		if self._tierOrder[layout.officeTierId] < self._tierOrder[room.requiredTierId] then
			return AppTypes.success({ state = "Locked", price = room.price, code = "OfficeTierLocked" })
		end
		if not allPurchased(layout, room.prerequisites) then
			return AppTypes.success({ state = "Locked", price = room.price, code = "PrerequisiteMissing" })
		end
		return AppTypes.success({ state = "Available", price = room.price })
	end

	local item = self._itemById[itemId]
	if item ~= nil then
		local purchased = if item.kind == "Equipment"
			then layout.purchasedEquipment[itemId]
			else layout.purchasedFurniture[itemId]
		if purchased then
			return AppTypes.success({ state = "Purchased", price = item.price })
		end
		if not layout.purchasedRooms[item.requiredRoomId] then
			return AppTypes.success({ state = "Locked", price = item.price, code = "RequiredRoomMissing" })
		end
		if layout.occupiedSlots[item.slotId] ~= nil then
			return AppTypes.success({ state = "Locked", price = item.price, code = "EquipmentSlotOccupied" })
		end
		return AppTypes.success({ state = "Available", price = item.price })
	end

	local upgrade = self._upgradeById[itemId]
	if upgrade ~= nil then
		if not layout.purchasedEquipment[upgrade.targetItemId] then
			return AppTypes.success({
				state = "Locked",
				price = 0,
				code = "UpgradeTargetMissing",
				currentLevel = 0,
				maxLevel = upgrade.maxLevel,
			})
		end
		local currentLevel = layout.upgradeLevels[itemId] or 1
		if currentLevel >= upgrade.maxLevel then
			return AppTypes.success({
				state = "MaxLevel",
				price = 0,
				currentLevel = currentLevel,
				maxLevel = upgrade.maxLevel,
			})
		end
		return AppTypes.success({
			state = "Available",
			price = upgrade.pricesByLevel[currentLevel + 1],
			currentLevel = currentLevel,
			maxLevel = upgrade.maxLevel,
		})
	end
	return AppTypes.failure("UnknownOfficeItem", "Office item is not defined", { itemId = itemId })
end

function OfficeProgression.GetTier(self: Progression, id: string): OfficeTypes.TierDefinition?
	return self._tierById[id]
end

function OfficeProgression.GetRoom(self: Progression, id: string): OfficeTypes.RoomDefinition?
	return self._roomById[id]
end

function OfficeProgression.GetItem(self: Progression, id: string): OfficeTypes.ItemDefinition?
	return self._itemById[id]
end

function OfficeProgression.GetUpgrade(self: Progression, id: string): OfficeTypes.UpgradeDefinition?
	return self._upgradeById[id]
end

return table.freeze(OfficeProgression)
