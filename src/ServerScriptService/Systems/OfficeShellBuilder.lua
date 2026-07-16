--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)

type PlotDefinition = PlotTypes.PlotDefinition
type Result<T> = AppTypes.Result<T>

export type PartCreationHook = (partName: string, partIndex: number) -> ()

type BuilderData = {
	_partCreationHook: PartCreationHook?,
}

local OfficeShellBuilder = {}
OfficeShellBuilder.__index = OfficeShellBuilder

export type Builder = typeof(setmetatable({} :: BuilderData, OfficeShellBuilder))

local OFFICE_COLOR = Color3.fromRGB(205, 208, 214)
local FLOOR_COLOR = Color3.fromRGB(151, 156, 166)
local BOUNDARY_COLOR = Color3.fromRGB(112, 117, 125)
local SPAWN_COLOR = Color3.fromRGB(126, 176, 191)

function OfficeShellBuilder.new(partCreationHook: PartCreationHook?): Builder
	return setmetatable({
		_partCreationHook = partCreationHook,
	}, OfficeShellBuilder)
end

function OfficeShellBuilder.Build(self: Builder, definition: PlotDefinition): Result<Model>
	local plotModel = Instance.new("Model")
	plotModel.Name = "PendingPlot"
	local createdPartCount = 0

	local function beforePartCreation(name: string)
		createdPartCount += 1
		local hook = self._partCreationHook
		if hook ~= nil then
			hook(name, createdPartCount)
		end
	end

	local function createPart(
		parent: Instance,
		name: string,
		size: Vector3,
		cframe: CFrame,
		color: Color3,
		transparency: number?,
		canCollide: boolean?
	): Part
		beforePartCreation(name)

		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Transparency = transparency or 0
		part.CanCollide = if canCollide == nil then true else canCollide
		part.Parent = parent
		return part
	end

	local buildOk, buildCause = xpcall(function()
		local shellDefinition = definition.officeShell
		local shellModel = Instance.new("Model")
		shellModel.Name = "OfficeShell"
		shellModel.Parent = plotModel

		local shellCFrame = definition.origin * shellDefinition.localOffset
		local footprintX = shellDefinition.footprintSize.X
		local footprintZ = shellDefinition.footprintSize.Y
		local floorThickness = shellDefinition.floorThickness
		local wallHeight = shellDefinition.wallHeight
		local wallThickness = shellDefinition.wallThickness
		local wallCenterY = floorThickness + wallHeight * 0.5

		local floor = createPart(
			shellModel,
			"Floor",
			Vector3.new(footprintX, floorThickness, footprintZ),
			shellCFrame * CFrame.new(0, floorThickness * 0.5, 0),
			FLOOR_COLOR,
			nil,
			nil
		)
		createPart(
			shellModel,
			"BackWall",
			Vector3.new(footprintX, wallHeight, wallThickness),
			shellCFrame * CFrame.new(0, wallCenterY, -footprintZ * 0.5 + wallThickness * 0.5),
			OFFICE_COLOR,
			nil,
			nil
		)
		createPart(
			shellModel,
			"LeftWall",
			Vector3.new(wallThickness, wallHeight, footprintZ),
			shellCFrame * CFrame.new(-footprintX * 0.5 + wallThickness * 0.5, wallCenterY, 0),
			OFFICE_COLOR,
			nil,
			nil
		)
		createPart(
			shellModel,
			"RightWall",
			Vector3.new(wallThickness, wallHeight, footprintZ),
			shellCFrame * CFrame.new(footprintX * 0.5 - wallThickness * 0.5, wallCenterY, 0),
			OFFICE_COLOR,
			nil,
			nil
		)

		local frontSegmentWidth = (footprintX - shellDefinition.entranceWidth) * 0.5
		local frontSegmentOffset = shellDefinition.entranceWidth * 0.5 + frontSegmentWidth * 0.5
		local frontZ = footprintZ * 0.5 - wallThickness * 0.5
		createPart(
			shellModel,
			"FrontLeftWall",
			Vector3.new(frontSegmentWidth, wallHeight, wallThickness),
			shellCFrame * CFrame.new(-frontSegmentOffset, wallCenterY, frontZ),
			OFFICE_COLOR,
			nil,
			nil
		)
		createPart(
			shellModel,
			"FrontRightWall",
			Vector3.new(frontSegmentWidth, wallHeight, wallThickness),
			shellCFrame * CFrame.new(frontSegmentOffset, wallCenterY, frontZ),
			OFFICE_COLOR,
			nil,
			nil
		)

		local boundaryModel = Instance.new("Model")
		boundaryModel.Name = "Boundary"
		boundaryModel.Parent = plotModel
		local boundaryThickness = 0.5
		local boundaryHeight = 0.5
		local plotX = definition.footprintSize.X
		local plotZ = definition.footprintSize.Y
		local edgeX = plotX * 0.5 - boundaryThickness * 0.5
		local edgeZ = plotZ * 0.5 - boundaryThickness * 0.5
		local boundaryY = boundaryHeight * 0.5
		createPart(
			boundaryModel,
			"NorthEdge",
			Vector3.new(plotX, boundaryHeight, boundaryThickness),
			definition.origin * CFrame.new(0, boundaryY, -edgeZ),
			BOUNDARY_COLOR,
			0.15,
			false
		)
		createPart(
			boundaryModel,
			"SouthEdge",
			Vector3.new(plotX, boundaryHeight, boundaryThickness),
			definition.origin * CFrame.new(0, boundaryY, edgeZ),
			BOUNDARY_COLOR,
			0.15,
			false
		)
		createPart(
			boundaryModel,
			"WestEdge",
			Vector3.new(boundaryThickness, boundaryHeight, plotZ),
			definition.origin * CFrame.new(-edgeX, boundaryY, 0),
			BOUNDARY_COLOR,
			0.15,
			false
		)
		createPart(
			boundaryModel,
			"EastEdge",
			Vector3.new(boundaryThickness, boundaryHeight, plotZ),
			definition.origin * CFrame.new(edgeX, boundaryY, 0),
			BOUNDARY_COLOR,
			0.15,
			false
		)

		beforePartCreation("SpawnLocation")
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "SpawnLocation"
		spawnLocation.Anchored = true
		spawnLocation.Size = Vector3.new(8, 1, 8)
		spawnLocation.CFrame = definition.origin * definition.spawnOffset * CFrame.new(0, 0.5, 0)
		spawnLocation.Color = FLOOR_COLOR
		spawnLocation.Material = Enum.Material.SmoothPlastic
		spawnLocation.TopSurface = Enum.SurfaceType.Smooth
		spawnLocation.BottomSurface = Enum.SurfaceType.Smooth
		spawnLocation.CanCollide = true
		spawnLocation.CanTouch = false
		spawnLocation.Neutral = true
		spawnLocation.Enabled = true
		spawnLocation.AllowTeamChangeOnTouch = false
		spawnLocation.Duration = 0
		spawnLocation.Parent = plotModel
		local spawnMarker = createPart(
			plotModel,
			"SpawnMarker",
			Vector3.new(6, 0.2, 6),
			definition.origin * definition.spawnOffset * CFrame.new(0, 1.1, 0),
			SPAWN_COLOR,
			0.35,
			false
		)
		spawnMarker.CanTouch = false
		plotModel.PrimaryPart = floor
	end, function(errorValue: unknown): string
		return debug.traceback(tostring(errorValue), 2)
	end)

	if not buildOk then
		plotModel:Destroy()
		return AppTypes.failure("OfficeShellBuildFailed", "Starter office shell generation failed", {
			plotId = definition.id,
			cause = buildCause,
		})
	end

	return AppTypes.success(plotModel)
end

return table.freeze(OfficeShellBuilder)
