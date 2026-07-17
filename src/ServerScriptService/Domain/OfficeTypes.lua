--!strict

export type OfficeCategoryId = "Tiers" | "Rooms" | "Equipment" | "Furniture" | "Upgrades"
export type OfficeItemKind = "Tier" | "Room" | "Equipment" | "Furniture" | "Upgrade"
export type OfficeItemState = "Available" | "Purchased" | "Locked" | "MaxLevel" | "Pending"

export type Envelope = {
	size: Vector3,
	localOffset: CFrame,
}

export type SlotDefinition = {
	id: string,
	placementKey: string,
	localOffset: CFrame,
	envelope: Envelope,
}

export type TierDefinition = {
	id: string,
	displayName: string,
	description: string,
	sortOrder: number,
	price: number,
	prerequisites: { string },
	templateId: string,
	shellSize: Vector3,
	shellOffset: CFrame,
	roomAnchors: { [string]: CFrame },
	allowedRooms: { string },
}

export type RoomDefinition = {
	id: string,
	displayName: string,
	description: string,
	sortOrder: number,
	price: number,
	requiredTierId: string,
	prerequisites: { string },
	templateId: string,
	placementKey: string,
	envelope: Envelope,
	doorwayClearance: Envelope,
	equipmentSlot: SlotDefinition,
	furnitureSlot: SlotDefinition,
}

export type ItemDefinition = {
	id: string,
	displayName: string,
	description: string,
	sortOrder: number,
	kind: "Equipment" | "Furniture",
	price: number,
	requiredTierId: string,
	requiredRoomId: string,
	prerequisites: { string },
	templateId: string,
	slotId: string,
	placementKey: string,
	envelope: Envelope,
}

export type UpgradeDefinition = {
	id: string,
	displayName: string,
	description: string,
	sortOrder: number,
	targetItemId: string,
	requiredTierId: string,
	prerequisites: { string },
	maxLevel: number,
	pricesByLevel: { [number]: number },
	templateIdsByLevel: { [number]: string },
}

export type OfficeConfig = {
	schemaVersion: number,
	configVersion: number,
	pageSize: number,
	tiers: { TierDefinition },
	rooms: { RoomDefinition },
	items: { ItemDefinition },
	upgrades: { UpgradeDefinition },
}

export type OccupiedSlot = {
	itemId: string,
	placementKey: string,
}

export type OfficeLayoutState = {
	schemaVersion: number,
	configVersion: number,
	officeTierId: string,
	purchasedRooms: { [string]: boolean },
	purchasedEquipment: { [string]: boolean },
	purchasedFurniture: { [string]: boolean },
	upgradeLevels: { [string]: number },
	occupiedSlots: { [string]: OccupiedSlot },
	placementKeys: { [string]: string },
	revision: number,
}

export type OfficeCatalogItem = {
	itemId: string,
	displayName: string,
	description: string,
	categoryId: OfficeCategoryId,
	price: number,
	state: OfficeItemState,
	lockCode: string?,
	lockText: string?,
	requiredTierId: string?,
	requiredRoomId: string?,
	prerequisiteIds: { string },
	slotId: string?,
	currentLevel: number?,
	maxLevel: number?,
}

export type OfficeCatalogPage = {
	categoryId: OfficeCategoryId,
	page: number,
	pageCount: number,
	totalItems: number,
	revision: number,
	currentTierId: string,
	cash: number,
	items: { OfficeCatalogItem },
}

return table.freeze({})
