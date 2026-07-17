--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)

type OfficeLayoutState = OfficeTypes.OfficeLayoutState
type Result<T> = AppTypes.Result<T>

local OfficeLayoutSerializer = {}

function OfficeLayoutSerializer.Copy(layout: OfficeLayoutState): OfficeLayoutState
	local occupiedSlots: { [string]: OfficeTypes.OccupiedSlot } = {}
	for slotId, value in layout.occupiedSlots do
		occupiedSlots[slotId] = { itemId = value.itemId, placementKey = value.placementKey }
	end
	return {
		schemaVersion = layout.schemaVersion,
		configVersion = layout.configVersion,
		officeTierId = layout.officeTierId,
		purchasedRooms = table.clone(layout.purchasedRooms),
		purchasedEquipment = table.clone(layout.purchasedEquipment),
		purchasedFurniture = table.clone(layout.purchasedFurniture),
		upgradeLevels = table.clone(layout.upgradeLevels),
		occupiedSlots = occupiedSlots,
		placementKeys = table.clone(layout.placementKeys),
		revision = layout.revision,
	}
end

function OfficeLayoutSerializer.Validate(
	layout: OfficeLayoutState,
	schemaVersion: number,
	configVersion: number
): Result<true>
	if layout.schemaVersion ~= schemaVersion then
		return AppTypes.failure("SnapshotInvalid", "Office layout schema version is incompatible", nil)
	end
	if layout.configVersion ~= configVersion then
		return AppTypes.failure("SnapshotInvalid", "Office layout config version is incompatible", nil)
	end
	if layout.revision < 0 or layout.revision % 1 ~= 0 then
		return AppTypes.failure("SnapshotInvalid", "Office layout revision is invalid", nil)
	end
	return AppTypes.success(true)
end

return table.freeze(OfficeLayoutSerializer)
