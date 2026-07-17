--!strict

export type OfficeCategoryId = "Tiers" | "Rooms" | "Equipment" | "Furniture" | "Upgrades"
export type OfficeItemState = "Available" | "Purchased" | "Locked" | "MaxLevel" | "Pending"

export type OfficeRemoteErrorCode =
	"InvalidPayload"
	| "RateLimited"
	| "RequestIdConflict"
	| "PurchaseInProgress"
	| "OfficeSessionNotReady"
	| "UnknownOfficeItem"
	| "InvalidOfficeCategory"
	| "InvalidCatalogPage"
	| "InsufficientFunds"
	| "ItemAlreadyPurchased"
	| "InitialTierAlreadyOwned"
	| "OfficeTierLocked"
	| "PrerequisiteMissing"
	| "RequiredRoomMissing"
	| "EquipmentSlotOccupied"
	| "UpgradeTargetMissing"
	| "UpgradeMaxLevel"
	| "OfficeBoundsViolation"
	| "OfficeBuildFailed"
	| "TransactionFailed"
	| "InternalError"

export type OfficeRemoteError = {
	code: OfficeRemoteErrorCode,
	message: string,
}

export type OfficeCatalogRequest = {
	requestId: string,
	categoryId: OfficeCategoryId,
	page: number,
}

export type OfficePurchaseRequest = {
	requestId: string,
	itemId: string,
}

export type OfficeCatalogResponse = {
	ok: boolean,
	requestId: string,
	categoryId: OfficeCategoryId,
	page: number,
	pageCount: number,
	totalItems: number,
	revision: number,
	currentTierId: string,
	cash: number,
	items: { unknown },
	error: OfficeRemoteError?,
}

export type OfficePurchaseResponse = {
	ok: boolean,
	requestId: string,
	itemId: string,
	revision: number,
	currentTierId: string,
	cash: number,
	state: OfficeItemState,
	currentLevel: number?,
	error: OfficeRemoteError?,
}

return table.freeze({})
