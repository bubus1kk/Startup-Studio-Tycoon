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

local PlotRuntimeBuilder = {}
PlotRuntimeBuilder.__index = PlotRuntimeBuilder
export type Builder = typeof(setmetatable({} :: BuilderData, PlotRuntimeBuilder))

local BOUNDARY_COLOR = Color3.fromRGB(112, 117, 125)
local FLOOR_COLOR = Color3.fromRGB(151, 156, 166)
local SPAWN_COLOR = Color3.fromRGB(126, 176, 191)

function PlotRuntimeBuilder.new(partCreationHook: PartCreationHook?): Builder
	return setmetatable({ _partCreationHook = partCreationHook }, PlotRuntimeBuilder)
end

function PlotRuntimeBuilder.Build(self: Builder, definition: PlotDefinition): Result<Model>
	local plotModel = Instance.new("Model")
	plotModel.Name = "PendingPlot"
	local createdPartCount = 0

	local function beforePartCreation(name: string)
		createdPartCount += 1
		if self._partCreationHook ~= nil then
			self._partCreationHook(name, createdPartCount)
		end
	end

	local function createPart(
		parent: Instance,
		name: string,
		size: Vector3,
		cframe: CFrame,
		color: Color3,
		transparency: number,
		canCollide: boolean,
		canQuery: boolean
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
		part.Transparency = transparency
		part.CanCollide = canCollide
		part.CanTouch = false
		part.CanQuery = canQuery
		part.Parent = parent
		return part
	end

	local ok, cause = xpcall(function()
		local anchor = createPart(
			plotModel,
			"PlotAnchor",
			Vector3.new(1, 1, 1),
			definition.origin * CFrame.new(0, 0.5, 0),
			Color3.new(1, 1, 1),
			1,
			false,
			false
		)

		local boundary = Instance.new("Model")
		boundary.Name = "PlotBoundary"
		boundary.Parent = plotModel
		local thickness = 0.5
		local height = 0.5
		local plotX = definition.footprintSize.X
		local plotZ = definition.footprintSize.Y
		local edgeX = plotX * 0.5 - thickness * 0.5
		local edgeZ = plotZ * 0.5 - thickness * 0.5
		createPart(
			boundary,
			"NorthEdge",
			Vector3.new(plotX, height, thickness),
			definition.origin * CFrame.new(0, height * 0.5, -edgeZ),
			BOUNDARY_COLOR,
			0.15,
			false,
			true
		)
		createPart(
			boundary,
			"SouthEdge",
			Vector3.new(plotX, height, thickness),
			definition.origin * CFrame.new(0, height * 0.5, edgeZ),
			BOUNDARY_COLOR,
			0.15,
			false,
			true
		)
		createPart(
			boundary,
			"WestEdge",
			Vector3.new(thickness, height, plotZ),
			definition.origin * CFrame.new(-edgeX, height * 0.5, 0),
			BOUNDARY_COLOR,
			0.15,
			false,
			true
		)
		createPart(
			boundary,
			"EastEdge",
			Vector3.new(thickness, height, plotZ),
			definition.origin * CFrame.new(edgeX, height * 0.5, 0),
			BOUNDARY_COLOR,
			0.15,
			false,
			true
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

		createPart(
			plotModel,
			"SpawnMarker",
			Vector3.new(6, 0.2, 6),
			definition.origin * definition.spawnOffset * CFrame.new(0, 1.1, 0),
			SPAWN_COLOR,
			0.35,
			false,
			false
		)
		plotModel.PrimaryPart = anchor
	end, function(errorValue: unknown): string
		return debug.traceback(tostring(errorValue), 2)
	end)

	if not ok then
		plotModel:Destroy()
		return AppTypes.failure("PlotRuntimeBuildFailed", "Plot runtime generation failed", {
			plotId = definition.id,
			cause = cause,
		})
	end
	return AppTypes.success(plotModel)
end

return table.freeze(PlotRuntimeBuilder)
