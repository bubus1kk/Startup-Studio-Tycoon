--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local OfficePlacement = require(ServerScriptService.Domain.OfficePlacement)
local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)

type PlotDefinition = PlotTypes.PlotDefinition
type ResolvedEnvelope = OfficePlacement.ResolvedEnvelope
type Result<T> = AppTypes.Result<T>

local OfficeGeometryValidator = {}
local EPSILON = 1e-4

local function finiteVector(value: Vector3): boolean
	return value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

local function overlaps(first: ResolvedEnvelope, second: ResolvedEnvelope): boolean
	local relative = first.cframe:ToObjectSpace(second.cframe)
	local firstHalf = first.size * 0.5
	local secondHalf = second.size * 0.5
	return math.abs(relative.Position.X) < firstHalf.X + secondHalf.X - EPSILON
		and math.abs(relative.Position.Y) < firstHalf.Y + secondHalf.Y - EPSILON
		and math.abs(relative.Position.Z) < firstHalf.Z + secondHalf.Z - EPSILON
end

function OfficeGeometryValidator.ValidateLayout(
	definition: PlotDefinition,
	envelopes: { ResolvedEnvelope }
): Result<true>
	for index, envelope in envelopes do
		if not finiteVector(envelope.size) or envelope.size.X <= 0 or envelope.size.Y <= 0 or envelope.size.Z <= 0 then
			return AppTypes.failure("OfficeEnvelopeInvalid", "Office envelope must be finite and positive", {
				id = envelope.id,
			})
		end
		if not PlotBounds.containsBox(definition, envelope.cframe, envelope.size) then
			return AppTypes.failure("PlacementOutOfBounds", "Office envelope escaped plot bounds", {
				id = envelope.id,
			})
		end
		if envelope.kind == "Item" then
			local owningRoom: ResolvedEnvelope? = nil
			for _, candidate in envelopes do
				if candidate.kind == "Room" and candidate.id == envelope.roomId then
					owningRoom = candidate
					break
				end
			end
			if owningRoom == nil then
				return AppTypes.failure("RequiredRoomMissing", "Office item has no owning room envelope", {
					id = envelope.id,
				})
			end
			local relative = owningRoom.cframe:ToObjectSpace(envelope.cframe).Position
			local roomHalf = owningRoom.size * 0.5
			local itemHalf = envelope.size * 0.5
			if
				math.abs(relative.X) + itemHalf.X > roomHalf.X + EPSILON
				or math.abs(relative.Y) + itemHalf.Y > roomHalf.Y + EPSILON
				or math.abs(relative.Z) + itemHalf.Z > roomHalf.Z + EPSILON
			then
				return AppTypes.failure("ItemOutsideRoom", "Office item escaped its owning room envelope", {
					id = envelope.id,
				})
			end
		end
		for secondIndex = index + 1, #envelopes do
			local second = envelopes[secondIndex]
			if overlaps(envelope, second) then
				if envelope.kind == "Room" and second.kind == "Room" then
					return AppTypes.failure(
						"GeometryOverlap",
						"Office rooms overlap",
						{ first = envelope.id, second = second.id }
					)
				end
				if
					envelope.kind == "Room" and second.kind == "Reserved"
					or envelope.kind == "Reserved" and second.kind == "Room"
				then
					return AppTypes.failure(
						"RoomShellReservedZone",
						"Office room overlaps a reserved tier-shell zone",
						{ first = envelope.id, second = second.id }
					)
				end
				if envelope.kind == "Item" and second.kind == "Item" then
					return AppTypes.failure(
						"GeometryOverlap",
						"Office items overlap",
						{ first = envelope.id, second = second.id }
					)
				end
				if
					envelope.kind == "Item" and second.kind == "Doorway"
					or envelope.kind == "Doorway" and second.kind == "Item"
				then
					return AppTypes.failure("DoorwayBlocked", "Office item blocks a room doorway", {
						first = envelope.id,
						second = second.id,
					})
				end
				if
					envelope.kind == "Room" and second.kind == "Spawn"
					or envelope.kind == "Spawn" and second.kind == "Room"
				then
					return AppTypes.failure("SpawnClearanceBlocked", "Office room blocks the plot spawn", nil)
				end
				if
					envelope.kind == "Room" and second.kind == "Entrance"
					or envelope.kind == "Entrance" and second.kind == "Room"
				then
					return AppTypes.failure("EntrancePathBlocked", "Office room blocks the entrance path", nil)
				end
			end
		end
	end
	return AppTypes.success(true)
end

function OfficeGeometryValidator.ValidateRuntimeModel(definition: PlotDefinition, root: Model): Result<true>
	local valid, invalidPart = PlotBounds.validateModel(definition, root)
	if not valid then
		return AppTypes.failure("PlacementOutOfBounds", "Office model escaped plot bounds", {
			part = invalidPart or "unknown",
		})
	end
	return AppTypes.success(true)
end

return table.freeze(OfficeGeometryValidator)
