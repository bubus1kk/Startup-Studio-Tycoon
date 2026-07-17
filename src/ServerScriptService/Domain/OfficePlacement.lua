--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local OfficeEntranceGeometry = require(ServerScriptService.Domain.OfficeEntranceGeometry)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)

type Envelope = OfficeTypes.Envelope
type OfficeLayoutState = OfficeTypes.OfficeLayoutState
type Progression = OfficeProgression.Progression
type Result<T> = AppTypes.Result<T>

export type ResolvedEnvelope = {
	id: string,
	kind: "Room" | "Item" | "Doorway" | "Entrance" | "Spawn" | "Reserved",
	roomId: string?,
	cframe: CFrame,
	size: Vector3,
}

type PlacementData = {
	_progression: Progression,
}

local OfficePlacement = {}
OfficePlacement.__index = OfficePlacement
export type Placement = typeof(setmetatable({} :: PlacementData, OfficePlacement))

function OfficePlacement.new(progression: Progression): Placement
	return setmetatable({ _progression = progression }, OfficePlacement)
end

local function resolveEnvelope(origin: CFrame, base: CFrame, definition: Envelope): (CFrame, Vector3)
	return origin * base * definition.localOffset, definition.size
end

function OfficePlacement.ResolveRoom(
	self: Placement,
	tierId: string,
	roomId: string,
	plotOrigin: CFrame
): Result<ResolvedEnvelope>
	local tier = self._progression:GetTier(tierId)
	local room = self._progression:GetRoom(roomId)
	if tier == nil or room == nil then
		return AppTypes.failure("PlacementUnknown", "Room placement definition is missing", { roomId = roomId })
	end
	local anchor = tier.roomAnchors[roomId]
	if anchor == nil then
		return AppTypes.failure("PlacementUnknown", "Room is not allowed in the office tier", { roomId = roomId })
	end
	local cframe, size = resolveEnvelope(plotOrigin, anchor, room.envelope)
	return AppTypes.success({ id = roomId, kind = "Room", roomId = roomId, cframe = cframe, size = size })
end

function OfficePlacement.ResolveItem(
	self: Placement,
	tierId: string,
	itemId: string,
	plotOrigin: CFrame
): Result<ResolvedEnvelope>
	local item = self._progression:GetItem(itemId)
	local room = if item ~= nil then self._progression:GetRoom(item.requiredRoomId) else nil
	local tier = self._progression:GetTier(tierId)
	if item == nil or room == nil or tier == nil then
		return AppTypes.failure("PlacementUnknown", "Item placement definition is missing", { itemId = itemId })
	end
	local roomAnchor = tier.roomAnchors[room.id]
	if roomAnchor == nil then
		return AppTypes.failure("PlacementUnknown", "Owning room has no tier anchor", { itemId = itemId })
	end
	local slot = if item.kind == "Equipment" then room.equipmentSlot else room.furnitureSlot
	local cframe, size = resolveEnvelope(plotOrigin, roomAnchor * slot.localOffset, item.envelope)
	return AppTypes.success({ id = itemId, kind = "Item", roomId = room.id, cframe = cframe, size = size })
end

function OfficePlacement.ResolveLayout(
	self: Placement,
	tierId: string,
	layout: OfficeLayoutState,
	plotOrigin: CFrame,
	spawnCFrame: CFrame,
	spawnSize: Vector3
): Result<{ ResolvedEnvelope }>
	local resolved: { ResolvedEnvelope } = {}
	local tier = self._progression:GetTier(tierId)
	if tier == nil then
		return AppTypes.failure("PlacementUnknown", "Office tier placement definition is missing", { tierId = tierId })
	end
	local shellPosition = tier.shellOffset.Position
	local halfX = tier.shellSize.X * 0.5
	local halfZ = tier.shellSize.Z * 0.5
	local wallY = tier.shellSize.Y * 0.5
	local function reserved(id: string, size: Vector3, offset: Vector3)
		table.insert(resolved, {
			id = id,
			kind = "Reserved",
			cframe = plotOrigin * CFrame.new(shellPosition.X, wallY, shellPosition.Z) * CFrame.new(offset),
			size = size,
		})
	end
	reserved("TierShell.NorthWall", Vector3.new(tier.shellSize.X, tier.shellSize.Y, 1), Vector3.new(0, 0, -halfZ + 0.5))
	reserved("TierShell.SouthWall", Vector3.new(tier.shellSize.X, tier.shellSize.Y, 1), Vector3.new(0, 0, halfZ - 0.5))
	reserved("TierShell.WestWall", Vector3.new(1, tier.shellSize.Y, tier.shellSize.Z), Vector3.new(-halfX + 0.5, 0, 0))
	reserved("TierShell.EastWall", Vector3.new(1, tier.shellSize.Y, tier.shellSize.Z), Vector3.new(halfX - 0.5, 0, 0))
	for roomId in layout.purchasedRooms do
		local roomResult = self:ResolveRoom(tierId, roomId, plotOrigin)
		if not roomResult.ok then
			return roomResult
		end
		table.insert(resolved, roomResult.value)
		local room = self._progression:GetRoom(roomId)
		if room ~= nil then
			local roomAnchor = tier.roomAnchors[roomId]
			if roomAnchor ~= nil then
				table.insert(resolved, {
					id = `{roomId}.doorway`,
					kind = "Doorway",
					roomId = roomId,
					cframe = plotOrigin * roomAnchor * room.doorwayClearance.localOffset,
					size = room.doorwayClearance.size,
				})
			end
		end
	end
	for itemId in layout.purchasedEquipment do
		local itemResult = self:ResolveItem(tierId, itemId, plotOrigin)
		if not itemResult.ok then
			return itemResult
		end
		table.insert(resolved, itemResult.value)
	end
	for itemId in layout.purchasedFurniture do
		local itemResult = self:ResolveItem(tierId, itemId, plotOrigin)
		if not itemResult.ok then
			return itemResult
		end
		table.insert(resolved, itemResult.value)
	end
	local entranceResult = OfficeEntranceGeometry.Resolve(tier, plotOrigin, spawnCFrame, spawnSize)
	if not entranceResult.ok then
		return entranceResult
	end
	local entrance = entranceResult.value
	table.insert(resolved, {
		id = "SpawnLocation",
		kind = "Spawn",
		cframe = entrance.spawnClearanceCFrame,
		size = entrance.spawnClearanceSize,
	})
	table.insert(resolved, {
		id = "EntrancePath",
		kind = "Entrance",
		cframe = entrance.pathCFrame,
		size = entrance.pathSize,
	})
	return AppTypes.success(resolved)
end

return table.freeze(OfficePlacement)
