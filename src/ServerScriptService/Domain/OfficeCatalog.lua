--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)

type OfficeCatalogItem = OfficeTypes.OfficeCatalogItem
type OfficeCatalogPage = OfficeTypes.OfficeCatalogPage
type OfficeCategoryId = OfficeTypes.OfficeCategoryId
type OfficeConfig = OfficeTypes.OfficeConfig
type OfficeLayoutState = OfficeTypes.OfficeLayoutState
type Progression = OfficeProgression.Progression
type Result<T> = AppTypes.Result<T>

type CatalogData = {
	_config: OfficeConfig,
	_progression: Progression,
	_idsByCategory: { [OfficeCategoryId]: { string } },
}

local OfficeCatalog = {}
OfficeCatalog.__index = OfficeCatalog
export type Catalog = typeof(setmetatable({} :: CatalogData, OfficeCatalog))

local categories: { OfficeCategoryId } = { "Tiers", "Rooms", "Equipment", "Furniture", "Upgrades" }

function OfficeCatalog.new(config: OfficeConfig, progression: Progression): Catalog
	local idsByCategory: { [OfficeCategoryId]: { string } } = {
		Tiers = {},
		Rooms = {},
		Equipment = {},
		Furniture = {},
		Upgrades = {},
	}
	local sortOrderById: { [string]: number } = {}
	for _, tier in config.tiers do
		table.insert(idsByCategory.Tiers, tier.id)
		sortOrderById[tier.id] = tier.sortOrder
	end
	for _, room in config.rooms do
		table.insert(idsByCategory.Rooms, room.id)
		sortOrderById[room.id] = room.sortOrder
	end
	for _, item in config.items do
		table.insert(if item.kind == "Equipment" then idsByCategory.Equipment else idsByCategory.Furniture, item.id)
		sortOrderById[item.id] = item.sortOrder
	end
	for _, upgrade in config.upgrades do
		table.insert(idsByCategory.Upgrades, upgrade.id)
		sortOrderById[upgrade.id] = upgrade.sortOrder
	end
	for _, category in categories do
		table.sort(idsByCategory[category], function(first: string, second: string): boolean
			local firstOrder = sortOrderById[first] or math.huge
			local secondOrder = sortOrderById[second] or math.huge
			return if firstOrder == secondOrder then first < second else firstOrder < secondOrder
		end)
	end
	return setmetatable({
		_config = config,
		_progression = progression,
		_idsByCategory = idsByCategory,
	}, OfficeCatalog)
end

function OfficeCatalog.GetCategoryCounts(self: Catalog): { [OfficeCategoryId]: number }
	local counts = {} :: { [OfficeCategoryId]: number }
	for _, category in categories do
		counts[category] = #self._idsByCategory[category]
	end
	return counts
end

local function lockText(code: string?): string?
	if code == "OfficeTierLocked" then
		return "Unlock the required office tier first."
	elseif code == "RequiredRoomMissing" then
		return "Build the required room first."
	elseif code == "UpgradeTargetMissing" then
		return "Purchase the equipment before upgrading it."
	elseif code ~= nil then
		return "Complete the listed prerequisites first."
	end
	return nil
end

function OfficeCatalog.GetItem(
	self: Catalog,
	layout: OfficeLayoutState,
	itemId: string,
	isPending: boolean
): Result<OfficeCatalogItem>
	local evaluationResult = self._progression:Evaluate(layout, itemId, isPending)
	if not evaluationResult.ok then
		return evaluationResult
	end
	local evaluation = evaluationResult.value
	local tier = self._progression:GetTier(itemId)
	if tier ~= nil then
		return AppTypes.success({
			itemId = tier.id,
			displayName = tier.displayName,
			description = tier.description,
			categoryId = "Tiers",
			price = evaluation.price,
			state = evaluation.state,
			lockCode = evaluation.code,
			lockText = lockText(evaluation.code),
			prerequisiteIds = table.clone(tier.prerequisites),
		})
	end
	local room = self._progression:GetRoom(itemId)
	if room ~= nil then
		return AppTypes.success({
			itemId = room.id,
			displayName = room.displayName,
			description = room.description,
			categoryId = "Rooms",
			price = evaluation.price,
			state = evaluation.state,
			lockCode = evaluation.code,
			lockText = lockText(evaluation.code),
			requiredTierId = room.requiredTierId,
			prerequisiteIds = table.clone(room.prerequisites),
		})
	end
	local item = self._progression:GetItem(itemId)
	if item ~= nil then
		return AppTypes.success({
			itemId = item.id,
			displayName = item.displayName,
			description = item.description,
			categoryId = item.kind,
			price = evaluation.price,
			state = evaluation.state,
			lockCode = evaluation.code,
			lockText = lockText(evaluation.code),
			requiredTierId = item.requiredTierId,
			requiredRoomId = item.requiredRoomId,
			prerequisiteIds = table.clone(item.prerequisites),
			slotId = item.slotId,
		})
	end
	local upgrade = self._progression:GetUpgrade(itemId)
	if upgrade == nil then
		return AppTypes.failure("UnknownOfficeItem", "Office item is not defined", { itemId = itemId })
	end
	local target = self._progression:GetItem(upgrade.targetItemId)
	return AppTypes.success({
		itemId = upgrade.id,
		displayName = upgrade.displayName,
		description = upgrade.description,
		categoryId = "Upgrades",
		price = evaluation.price,
		state = evaluation.state,
		lockCode = evaluation.code,
		lockText = lockText(evaluation.code),
		requiredTierId = upgrade.requiredTierId,
		requiredRoomId = if target ~= nil then target.requiredRoomId else nil,
		prerequisiteIds = table.clone(upgrade.prerequisites),
		slotId = if target ~= nil then target.slotId else nil,
		currentLevel = evaluation.currentLevel,
		maxLevel = evaluation.maxLevel,
	})
end

function OfficeCatalog.GetPage(
	self: Catalog,
	layout: OfficeLayoutState,
	cash: number,
	categoryId: OfficeCategoryId,
	page: number,
	pendingItems: { [string]: boolean }
): Result<OfficeCatalogPage>
	local ids = self._idsByCategory[categoryId]
	if ids == nil then
		return AppTypes.failure("InvalidOfficeCategory", "Office category is invalid", nil)
	end
	local totalItems = #ids
	local pageCount = math.ceil(totalItems / self._config.pageSize)
	if page < 1 or (pageCount > 0 and page > pageCount) or (pageCount == 0 and page ~= 1) then
		return AppTypes.failure("InvalidCatalogPage", "Catalog page is outside the category range", {
			page = tostring(page),
			pageCount = tostring(pageCount),
		})
	end
	local items: { OfficeCatalogItem } = {}
	local first = (page - 1) * self._config.pageSize + 1
	local last = math.min(first + self._config.pageSize - 1, totalItems)
	for index = first, last do
		local itemResult = self:GetItem(layout, ids[index], pendingItems[ids[index]] == true)
		if not itemResult.ok then
			return itemResult
		end
		table.insert(items, itemResult.value)
	end
	return AppTypes.success({
		categoryId = categoryId,
		page = page,
		pageCount = pageCount,
		totalItems = totalItems,
		revision = layout.revision,
		currentTierId = layout.officeTierId,
		cash = cash,
		items = items,
	})
end

return table.freeze(OfficeCatalog)
