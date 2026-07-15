--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local ConfigValidator = require(ReplicatedStorage.Shared.Config.ConfigValidator)
local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)

type OfficeShellDefinition = PlotTypes.OfficeShellDefinition
export type PlotConfig = PlotTypes.PlotConfig
type PlotDefinition = PlotTypes.PlotDefinition
type Result<T> = AppTypes.Result<T>
type StringMap = { [string]: unknown }

local PlotConfigValidator = {}

local function finiteNumber(value: unknown, path: string, minimum: number?): Result<number>
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return AppTypes.failure("ConfigTypeMismatch", "Expected a finite number", {
			path = path,
			actual = typeof(value),
		})
	end
	if minimum ~= nil and value < minimum then
		return AppTypes.failure("ConfigRangeInvalid", "Configuration number is below its minimum", {
			path = path,
			minimum = tostring(minimum),
			actual = tostring(value),
		})
	end
	return AppTypes.success(value)
end

local function finiteVector2(value: unknown, path: string): Result<Vector2>
	if typeof(value) ~= "Vector2" then
		return AppTypes.failure("ConfigTypeMismatch", "Expected Vector2", {
			path = path,
			actual = typeof(value),
		})
	end
	local vector = value :: Vector2
	if
		vector.X ~= vector.X
		or vector.Y ~= vector.Y
		or math.abs(vector.X) == math.huge
		or math.abs(vector.Y) == math.huge
	then
		return AppTypes.failure("ConfigRangeInvalid", "Vector2 components must be finite", { path = path })
	end
	if vector.X <= 0 or vector.Y <= 0 then
		return AppTypes.failure("ConfigRangeInvalid", "Vector2 components must be positive", { path = path })
	end
	return AppTypes.success(vector)
end

local function finiteCFrame(value: unknown, path: string): Result<CFrame>
	if typeof(value) ~= "CFrame" then
		return AppTypes.failure("ConfigTypeMismatch", "Expected CFrame", {
			path = path,
			actual = typeof(value),
		})
	end
	local cframe = value :: CFrame
	local components = { cframe:GetComponents() }
	for _, component in components do
		if component ~= component or math.abs(component) == math.huge then
			return AppTypes.failure("ConfigRangeInvalid", "CFrame components must be finite", { path = path })
		end
	end
	return AppTypes.success(cframe)
end

local function validateOfficeShell(value: unknown, path: string): Result<OfficeShellDefinition>
	local objectResult = ConfigValidator.expectObject(value, path)
	if not objectResult.ok then
		return objectResult
	end
	local object = objectResult.value
	local keysResult = ConfigValidator.rejectUnknownKeys(object, {
		footprintSize = true,
		localOffset = true,
		wallHeight = true,
		wallThickness = true,
		floorThickness = true,
		entranceWidth = true,
	}, path)
	if not keysResult.ok then
		return keysResult
	end

	local footprintResult = finiteVector2(object.footprintSize, `{path}.footprintSize`)
	local offsetResult = finiteCFrame(object.localOffset, `{path}.localOffset`)
	local wallHeightResult = finiteNumber(object.wallHeight, `{path}.wallHeight`, 1)
	local wallThicknessResult = finiteNumber(object.wallThickness, `{path}.wallThickness`, 0.1)
	local floorThicknessResult = finiteNumber(object.floorThickness, `{path}.floorThickness`, 0.1)
	local entranceWidthResult = finiteNumber(object.entranceWidth, `{path}.entranceWidth`, 1)
	if not footprintResult.ok then
		return footprintResult
	end
	if not offsetResult.ok then
		return offsetResult
	end
	if not wallHeightResult.ok then
		return wallHeightResult
	end
	if not wallThicknessResult.ok then
		return wallThicknessResult
	end
	if not floorThicknessResult.ok then
		return floorThicknessResult
	end
	if not entranceWidthResult.ok then
		return entranceWidthResult
	end

	if entranceWidthResult.value + wallThicknessResult.value * 2 >= footprintResult.value.X then
		return AppTypes.failure("ConfigRangeInvalid", "Office entrance leaves no valid front wall segments", {
			path = `{path}.entranceWidth`,
		})
	end

	return AppTypes.success({
		footprintSize = footprintResult.value,
		localOffset = offsetResult.value,
		wallHeight = wallHeightResult.value,
		wallThickness = wallThicknessResult.value,
		floorThickness = floorThicknessResult.value,
		entranceWidth = entranceWidthResult.value,
	})
end

local function validateDefinition(value: unknown, path: string): Result<PlotDefinition>
	local objectResult = ConfigValidator.expectObject(value, path)
	if not objectResult.ok then
		return objectResult
	end
	local object = objectResult.value
	local keysResult = ConfigValidator.rejectUnknownKeys(object, {
		id = true,
		origin = true,
		footprintSize = true,
		maxHeight = true,
		spawnOffset = true,
		officeShell = true,
	}, path)
	if not keysResult.ok then
		return keysResult
	end

	if typeof(object.id) ~= "string" or string.match(object.id, "^plot_%d%d$") == nil then
		return AppTypes.failure("ConfigValueInvalid", "Plot ID must use the plot_NN format", {
			path = `{path}.id`,
			actual = tostring(object.id),
		})
	end
	local originResult = finiteCFrame(object.origin, `{path}.origin`)
	local footprintResult = finiteVector2(object.footprintSize, `{path}.footprintSize`)
	local heightResult = finiteNumber(object.maxHeight, `{path}.maxHeight`, 1)
	local spawnResult = finiteCFrame(object.spawnOffset, `{path}.spawnOffset`)
	local shellResult = validateOfficeShell(object.officeShell, `{path}.officeShell`)
	if not originResult.ok then
		return originResult
	end
	if not footprintResult.ok then
		return footprintResult
	end
	if not heightResult.ok then
		return heightResult
	end
	if not spawnResult.ok then
		return spawnResult
	end
	if not shellResult.ok then
		return shellResult
	end

	if originResult.value.UpVector:Dot(Vector3.yAxis) < 1 - 1e-4 then
		return AppTypes.failure("ConfigValueInvalid", "Plot origin may rotate only around the Y axis", {
			path = `{path}.origin`,
		})
	end

	local definition: PlotDefinition = {
		id = object.id :: string,
		origin = originResult.value,
		footprintSize = footprintResult.value,
		maxHeight = heightResult.value,
		spawnOffset = spawnResult.value,
		officeShell = shellResult.value,
	}
	local spawnWorldPoint = definition.origin:PointToWorldSpace(definition.spawnOffset.Position)
	local spawnPlatformCFrame = definition.origin * definition.spawnOffset * CFrame.new(0, 0.5, 0)
	if
		not PlotBounds.containsPoint(definition, spawnWorldPoint)
		or not PlotBounds.containsBox(definition, spawnPlatformCFrame, Vector3.new(8, 1, 8))
	then
		return AppTypes.failure("PlotSpawnOutOfBounds", "Plot spawn must remain inside its boundaries", {
			path = `{path}.spawnOffset`,
		})
	end

	local shell = definition.officeShell
	local shellBoundsHeight = shell.floorThickness + shell.wallHeight
	local shellBoundsCFrame = definition.origin * shell.localOffset * CFrame.new(0, shellBoundsHeight * 0.5, 0)
	local shellBoundsSize = Vector3.new(shell.footprintSize.X, shellBoundsHeight, shell.footprintSize.Y)
	if not PlotBounds.containsBox(definition, shellBoundsCFrame, shellBoundsSize) then
		return AppTypes.failure("PlotOfficeOutOfBounds", "Starter office shell must remain inside its plot", {
			path = `{path}.officeShell`,
		})
	end

	return AppTypes.success(definition)
end

function PlotConfigValidator.validate(value: unknown): Result<PlotConfig>
	local rootResult = ConfigValidator.expectObject(value, "PlotConfig")
	if not rootResult.ok then
		return rootResult
	end
	local root = rootResult.value
	local keysResult = ConfigValidator.rejectUnknownKeys(root, {
		maxPlayers = true,
		centerSpacing = true,
		plotGap = true,
		definitions = true,
	}, "PlotConfig")
	if not keysResult.ok then
		return keysResult
	end

	local maxPlayersResult = finiteNumber(root.maxPlayers, "PlotConfig.maxPlayers", 1)
	local spacingResult = finiteNumber(root.centerSpacing, "PlotConfig.centerSpacing", 1)
	local gapResult = finiteNumber(root.plotGap, "PlotConfig.plotGap", 0)
	if not maxPlayersResult.ok then
		return maxPlayersResult
	end
	if maxPlayersResult.value % 1 ~= 0 then
		return AppTypes.failure("ConfigRangeInvalid", "maxPlayers must be an integer", {
			path = "PlotConfig.maxPlayers",
		})
	end
	if not spacingResult.ok then
		return spacingResult
	end
	if not gapResult.ok then
		return gapResult
	end
	if typeof(root.definitions) ~= "table" then
		return AppTypes.failure("ConfigTypeMismatch", "Plot definitions must be an array", {
			path = "PlotConfig.definitions",
			actual = typeof(root.definitions),
		})
	end

	local rawDefinitions = root.definitions :: { unknown }
	local definitionKeyCount = 0
	for key in root.definitions :: { [string | number]: unknown } do
		definitionKeyCount += 1
		if typeof(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #rawDefinitions then
			return AppTypes.failure("ConfigTypeMismatch", "Plot definitions must be a sequential array", {
				path = "PlotConfig.definitions",
			})
		end
	end
	if definitionKeyCount ~= #rawDefinitions then
		return AppTypes.failure("ConfigTypeMismatch", "Plot definitions cannot contain holes", {
			path = "PlotConfig.definitions",
		})
	end
	if #rawDefinitions ~= maxPlayersResult.value then
		return AppTypes.failure("PlotCapacityMismatch", "Plot count must equal max players", {
			plots = tostring(#rawDefinitions),
			maxPlayers = tostring(maxPlayersResult.value),
		})
	end

	local definitions: { PlotDefinition } = {}
	local ids: { [string]: boolean } = {}
	for index, rawDefinition in rawDefinitions do
		local definitionResult = validateDefinition(rawDefinition, `PlotConfig.definitions[{index}]`)
		if not definitionResult.ok then
			return definitionResult
		end
		local definition = definitionResult.value
		if ids[definition.id] then
			return AppTypes.failure("DuplicatePlotId", "Plot IDs must be unique", { plotId = definition.id })
		end
		ids[definition.id] = true
		table.insert(definitions, definition)
	end

	for firstIndex = 1, #definitions do
		for secondIndex = firstIndex + 1, #definitions do
			local first = definitions[firstIndex]
			local second = definitions[secondIndex]
			if PlotBounds.footprintsOverlap(first, second, gapResult.value) then
				return AppTypes.failure("OverlappingPlotDefinitions", "Plot definitions overlap or violate plotGap", {
					firstPlotId = first.id,
					secondPlotId = second.id,
				})
			end
		end
	end

	return AppTypes.success({
		maxPlayers = maxPlayersResult.value,
		centerSpacing = spacingResult.value,
		plotGap = gapResult.value,
		definitions = definitions,
	})
end

return table.freeze(PlotConfigValidator)
