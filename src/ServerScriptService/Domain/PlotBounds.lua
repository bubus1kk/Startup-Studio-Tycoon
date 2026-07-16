--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PlotTypes = require(ServerScriptService.Domain.PlotTypes)

type PlotDefinition = PlotTypes.PlotDefinition

local EPSILON = 1e-4

local PlotBounds = {}

local function localFootprintCorners(definition: PlotDefinition, extraMargin: number): { Vector3 }
	local halfX = definition.footprintSize.X * 0.5 + extraMargin
	local halfZ = definition.footprintSize.Y * 0.5 + extraMargin
	return {
		definition.origin:PointToWorldSpace(Vector3.new(-halfX, 0, -halfZ)),
		definition.origin:PointToWorldSpace(Vector3.new(-halfX, 0, halfZ)),
		definition.origin:PointToWorldSpace(Vector3.new(halfX, 0, -halfZ)),
		definition.origin:PointToWorldSpace(Vector3.new(halfX, 0, halfZ)),
	}
end

local function horizontalAxis(worldAxis: Vector3): Vector2
	local axis = Vector2.new(worldAxis.X, worldAxis.Z)
	return axis.Unit
end

local function projectedRange(corners: { Vector3 }, axis: Vector2): (number, number)
	local first = corners[1]
	local firstProjection = first.X * axis.X + first.Z * axis.Y
	local minimum = firstProjection
	local maximum = firstProjection

	for index = 2, #corners do
		local corner = corners[index]
		local projection = corner.X * axis.X + corner.Z * axis.Y
		minimum = math.min(minimum, projection)
		maximum = math.max(maximum, projection)
	end

	return minimum, maximum
end

function PlotBounds.containsPoint(definition: PlotDefinition, worldPoint: Vector3): boolean
	local localPoint = definition.origin:PointToObjectSpace(worldPoint)
	local halfX = definition.footprintSize.X * 0.5
	local halfZ = definition.footprintSize.Y * 0.5
	return math.abs(localPoint.X) <= halfX + EPSILON
		and localPoint.Y >= -EPSILON
		and localPoint.Y <= definition.maxHeight + EPSILON
		and math.abs(localPoint.Z) <= halfZ + EPSILON
end

function PlotBounds.containsBox(definition: PlotDefinition, boxCFrame: CFrame, boxSize: Vector3): boolean
	local half = boxSize * 0.5
	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local corner = boxCFrame:PointToWorldSpace(Vector3.new(half.X * xSign, half.Y * ySign, half.Z * zSign))
				if not PlotBounds.containsPoint(definition, corner) then
					return false
				end
			end
		end
	end

	return true
end

function PlotBounds.footprintsOverlap(
	firstDefinition: PlotDefinition,
	secondDefinition: PlotDefinition,
	minimumGap: number
): boolean
	local expansion = minimumGap * 0.5
	local firstCorners = localFootprintCorners(firstDefinition, expansion)
	local secondCorners = localFootprintCorners(secondDefinition, expansion)
	local axes = {
		horizontalAxis(firstDefinition.origin.RightVector),
		horizontalAxis(firstDefinition.origin:VectorToWorldSpace(Vector3.zAxis)),
		horizontalAxis(secondDefinition.origin.RightVector),
		horizontalAxis(secondDefinition.origin:VectorToWorldSpace(Vector3.zAxis)),
	}

	for _, axis in axes do
		local firstMinimum, firstMaximum = projectedRange(firstCorners, axis)
		local secondMinimum, secondMaximum = projectedRange(secondCorners, axis)
		if firstMaximum <= secondMinimum + EPSILON or secondMaximum <= firstMinimum + EPSILON then
			return false
		end
	end

	return true
end

function PlotBounds.validateModel(definition: PlotDefinition, model: Model): (boolean, string?)
	local partCount = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			partCount += 1
			if not PlotBounds.containsBox(definition, descendant.CFrame, descendant.Size) then
				return false, descendant:GetFullName()
			end
		end
	end

	if partCount == 0 then
		return false, "model contains no BaseParts"
	end

	return true, nil
end

return table.freeze(PlotBounds)
