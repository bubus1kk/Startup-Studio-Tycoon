--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)

type Result<T> = AppTypes.Result<T>
type TierDefinition = OfficeTypes.TierDefinition

export type EntranceGeometry = {
	approachCFrame: CFrame,
	approachSize: Vector3,
	pathCFrame: CFrame,
	pathSize: Vector3,
	spawnClearanceCFrame: CFrame,
	spawnClearanceSize: Vector3,
	floorEdgeZ: number,
	spawnEdgeZ: number,
}

local OfficeEntranceGeometry = {}

OfficeEntranceGeometry.APPROACH_WIDTH = 8
OfficeEntranceGeometry.CORRIDOR_HALF_WIDTH = 5
OfficeEntranceGeometry.CORRIDOR_START_Z = 12
OfficeEntranceGeometry.FLOOR_THICKNESS = 1
OfficeEntranceGeometry.CLEARANCE_HEIGHT = 8

local function projectedHalfExtent(cframe: CFrame, size: Vector3, worldAxis: Vector3): number
	return math.abs(cframe.RightVector:Dot(worldAxis)) * size.X * 0.5
		+ math.abs(cframe.UpVector:Dot(worldAxis)) * size.Y * 0.5
		+ math.abs(cframe.LookVector:Dot(worldAxis)) * size.Z * 0.5
end

function OfficeEntranceGeometry.Resolve(
	tier: TierDefinition,
	plotOrigin: CFrame,
	spawnCFrame: CFrame,
	spawnSize: Vector3
): Result<EntranceGeometry>
	if spawnSize.X <= 0 or spawnSize.Y <= 0 or spawnSize.Z <= 0 then
		return AppTypes.failure("InvalidPlotSpawn", "Plot spawn size must be positive", nil)
	end

	local shellPosition = tier.shellOffset.Position
	local tierBase = plotOrigin * CFrame.new(shellPosition.X, 0, shellPosition.Z)
	local plotZAxis = plotOrigin:VectorToWorldSpace(Vector3.zAxis)
	local spawnLocalPosition = plotOrigin:PointToObjectSpace(spawnCFrame.Position)
	local spawnEdgeZ = spawnLocalPosition.Z - projectedHalfExtent(spawnCFrame, spawnSize, plotZAxis)
	local floorEdgeZ = shellPosition.Z + OfficeEntranceGeometry.CORRIDOR_START_Z
	local approachDepth = spawnEdgeZ - floorEdgeZ
	if approachDepth <= 0 then
		return AppTypes.failure("InvalidEntranceGeometry", "Tier has no positive entrance approach span", {
			tierId = tier.id,
		})
	end

	local approachCenterZ = OfficeEntranceGeometry.CORRIDOR_START_Z + approachDepth * 0.5
	local approachSize =
		Vector3.new(OfficeEntranceGeometry.APPROACH_WIDTH, OfficeEntranceGeometry.FLOOR_THICKNESS, approachDepth)
	local pathSize =
		Vector3.new(OfficeEntranceGeometry.APPROACH_WIDTH, OfficeEntranceGeometry.CLEARANCE_HEIGHT, approachDepth)
	local spawnClearanceSize =
		Vector3.new(spawnSize.X, math.max(spawnSize.Y, OfficeEntranceGeometry.CLEARANCE_HEIGHT), spawnSize.Z)
	local spawnClearanceYOffset = (spawnClearanceSize.Y - spawnSize.Y) * 0.5

	return AppTypes.success({
		approachCFrame = tierBase * CFrame.new(0, approachSize.Y * 0.5, approachCenterZ),
		approachSize = approachSize,
		pathCFrame = tierBase * CFrame.new(0, pathSize.Y * 0.5, approachCenterZ),
		pathSize = pathSize,
		spawnClearanceCFrame = spawnCFrame * CFrame.new(0, spawnClearanceYOffset, 0),
		spawnClearanceSize = spawnClearanceSize,
		floorEdgeZ = floorEdgeZ,
		spawnEdgeZ = spawnEdgeZ,
	})
end

return table.freeze(OfficeEntranceGeometry)
