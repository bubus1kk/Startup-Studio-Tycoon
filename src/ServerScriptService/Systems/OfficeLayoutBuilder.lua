--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local OfficeGeometryValidator = require(ServerScriptService.Domain.OfficeGeometryValidator)
local OfficePlacement = require(ServerScriptService.Domain.OfficePlacement)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)

type OfficeConfig = OfficeTypes.OfficeConfig
type OfficeLayoutState = OfficeTypes.OfficeLayoutState
type Placement = OfficePlacement.Placement
type PlotContext = PlotTypes.PlotContext
type Progression = OfficeProgression.Progression
type Result<T> = AppTypes.Result<T>

export type BuildHook = (stage: string, id: string) -> ()

type BuilderData = {
	_templates: Instance,
	_config: OfficeConfig,
	_progression: Progression,
	_placement: Placement,
	_buildHook: BuildHook?,
}

local OfficeLayoutBuilder = {}
OfficeLayoutBuilder.__index = OfficeLayoutBuilder
export type Builder = typeof(setmetatable({} :: BuilderData, OfficeLayoutBuilder))

local ENTRANCE_APPROACH_WIDTH = 8
local ENTRANCE_CORRIDOR_HALF_WIDTH = 5
local ENTRANCE_CORRIDOR_START_Z = 12
local FLOOR_THICKNESS = 1

local TIER_COLORS = {
	tier_garage = Color3.fromRGB(84, 94, 112),
	tier_small_loft = Color3.fromRGB(96, 119, 139),
	tier_downtown = Color3.fromRGB(70, 94, 132),
	tier_tech_campus = Color3.fromRGB(64, 112, 126),
	tier_global_hq = Color3.fromRGB(48, 72, 112),
}

local ROOM_COLORS = {
	room_development = Color3.fromRGB(76, 132, 183),
	room_design = Color3.fromRGB(157, 99, 183),
	room_qa = Color3.fromRGB(78, 157, 126),
	room_marketing = Color3.fromRGB(218, 133, 73),
	room_meeting = Color3.fromRGB(81, 121, 154),
	room_server = Color3.fromRGB(74, 91, 110),
	room_recreation = Color3.fromRGB(76, 169, 159),
	room_executive = Color3.fromRGB(155, 118, 66),
	room_research = Color3.fromRGB(93, 119, 190),
}

local function setPartDefaults(part: BasePart)
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function createPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.CanCollide = canCollide
	setPartDefaults(part)
	part.Parent = parent
	return part
end

local function projectedHalfExtent(part: BasePart, worldAxis: Vector3): number
	return math.abs(part.CFrame.RightVector:Dot(worldAxis)) * part.Size.X * 0.5
		+ math.abs(part.CFrame.UpVector:Dot(worldAxis)) * part.Size.Y * 0.5
		+ math.abs(part.CFrame.LookVector:Dot(worldAxis)) * part.Size.Z * 0.5
end

function OfficeLayoutBuilder.new(
	templates: Instance,
	config: OfficeConfig,
	progression: Progression,
	placement: Placement,
	buildHook: BuildHook?
): Builder
	return setmetatable({
		_templates = templates,
		_config = config,
		_progression = progression,
		_placement = placement,
		_buildHook = buildHook,
	}, OfficeLayoutBuilder)
end

function OfficeLayoutBuilder._cloneTemplate(self: Builder, category: string, templateId: string): Result<Model>
	if self._buildHook ~= nil then
		self._buildHook("CloneTemplate", templateId)
	end
	local folder = self._templates:FindFirstChild(category)
	local template = if folder ~= nil then folder:FindFirstChild(templateId) else nil
	if template == nil or not template:IsA("Model") then
		return AppTypes.failure("TemplateMissing", "Office template is missing", { templateId = templateId })
	end
	local clone = template:Clone()
	clone.Name = templateId
	local pivot = clone:FindFirstChild("Pivot")
	if pivot == nil or not pivot:IsA("BasePart") then
		clone:Destroy()
		return AppTypes.failure("TemplateInvalid", "Office template has no Pivot part", { templateId = templateId })
	end
	for _, descendant in clone:GetDescendants() do
		if
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("RemoteEvent")
			or descendant:IsA("RemoteFunction")
			or descendant:IsA("ProximityPrompt")
		then
			clone:Destroy()
			return AppTypes.failure(
				"TemplateInvalid",
				"Office template contains a forbidden instance",
				{ templateId = templateId }
			)
		elseif descendant:IsA("BasePart") then
			setPartDefaults(descendant)
		end
	end
	clone.PrimaryPart = pivot
	return AppTypes.success(clone)
end

function OfficeLayoutBuilder._decorateTier(
	_self: Builder,
	model: Model,
	tier: OfficeTypes.TierDefinition,
	origin: CFrame,
	spawn: SpawnLocation
)
	local shellPosition = tier.shellOffset.Position
	local base = origin * CFrame.new(shellPosition.X, 0, shellPosition.Z)
	local size = tier.shellSize
	local color = TIER_COLORS[tier.id]
	local floorColor = color:Lerp(Color3.new(1, 1, 1), 0.42)
	local halfX = size.X * 0.5
	local halfZ = size.Z * 0.5
	local wallThickness = 1
	local backDepth = math.max(1, ENTRANCE_CORRIDOR_START_Z + halfZ)
	local backCenterZ = -halfZ + backDepth * 0.5
	createPart(
		model,
		"FloorBack",
		Vector3.new(size.X, FLOOR_THICKNESS, backDepth),
		base * CFrame.new(0, 0.5, backCenterZ),
		floorColor,
		Enum.Material.SmoothPlastic,
		true
	)

	local plotZAxis = origin:VectorToWorldSpace(Vector3.zAxis)
	local spawnLocalPosition = origin:PointToObjectSpace(spawn.Position)
	local spawnOfficeEdgeZ = spawnLocalPosition.Z - projectedHalfExtent(spawn, plotZAxis)
	local floorEntranceEdgeZ = shellPosition.Z + ENTRANCE_CORRIDOR_START_Z
	local approachDepth = spawnOfficeEdgeZ - floorEntranceEdgeZ
	if approachDepth <= 0 then
		error(`Tier {tier.id} has no positive entrance approach span`, 2)
	end
	createPart(
		model,
		"EntranceApproach",
		Vector3.new(ENTRANCE_APPROACH_WIDTH, FLOOR_THICKNESS, approachDepth),
		base * CFrame.new(0, 0.5, ENTRANCE_CORRIDOR_START_Z + approachDepth * 0.5),
		floorColor,
		Enum.Material.SmoothPlastic,
		true
	)

	local frontDepth = halfZ - ENTRANCE_CORRIDOR_START_Z
	if frontDepth > 0 then
		local sideWidth = halfX - ENTRANCE_CORRIDOR_HALF_WIDTH
		local frontCenterZ = ENTRANCE_CORRIDOR_START_Z + frontDepth * 0.5
		createPart(
			model,
			"FloorFrontLeft",
			Vector3.new(sideWidth, FLOOR_THICKNESS, frontDepth),
			base * CFrame.new(-(ENTRANCE_CORRIDOR_HALF_WIDTH + sideWidth * 0.5), 0.5, frontCenterZ),
			floorColor,
			Enum.Material.SmoothPlastic,
			true
		)
		createPart(
			model,
			"FloorFrontRight",
			Vector3.new(sideWidth, FLOOR_THICKNESS, frontDepth),
			base * CFrame.new(ENTRANCE_CORRIDOR_HALF_WIDTH + sideWidth * 0.5, 0.5, frontCenterZ),
			floorColor,
			Enum.Material.SmoothPlastic,
			true
		)
	end
	local wallY = size.Y * 0.5
	createPart(
		model,
		"BackWall",
		Vector3.new(size.X, size.Y, wallThickness),
		base * CFrame.new(0, wallY, -halfZ + 0.5),
		color,
		Enum.Material.SmoothPlastic,
		true
	)
	createPart(
		model,
		"LeftWall",
		Vector3.new(wallThickness, size.Y, size.Z),
		base * CFrame.new(-halfX + 0.5, wallY, 0),
		color,
		Enum.Material.SmoothPlastic,
		true
	)
	createPart(
		model,
		"RightWall",
		Vector3.new(wallThickness, size.Y, size.Z),
		base * CFrame.new(halfX - 0.5, wallY, 0),
		color,
		Enum.Material.SmoothPlastic,
		true
	)
	createPart(
		model,
		"FrontLeftWall",
		Vector3.new(halfX - ENTRANCE_CORRIDOR_HALF_WIDTH, size.Y, wallThickness),
		base
			* CFrame.new(
				-(ENTRANCE_CORRIDOR_HALF_WIDTH + (halfX - ENTRANCE_CORRIDOR_HALF_WIDTH) * 0.5),
				wallY,
				halfZ - 0.5
			),
		color,
		Enum.Material.SmoothPlastic,
		true
	)
	createPart(
		model,
		"FrontRightWall",
		Vector3.new(halfX - ENTRANCE_CORRIDOR_HALF_WIDTH, size.Y, wallThickness),
		base
			* CFrame.new(
				ENTRANCE_CORRIDOR_HALF_WIDTH + (halfX - ENTRANCE_CORRIDOR_HALF_WIDTH) * 0.5,
				wallY,
				halfZ - 0.5
			),
		color,
		Enum.Material.SmoothPlastic,
		true
	)
end

function OfficeLayoutBuilder._decorateRoom(
	_self: Builder,
	model: Model,
	room: OfficeTypes.RoomDefinition,
	cframe: CFrame
)
	local color = ROOM_COLORS[room.id]
	createPart(
		model,
		"RoomFloor",
		Vector3.new(15, 0.3, 15),
		cframe * CFrame.new(0, 0.15, 0),
		color:Lerp(Color3.new(1, 1, 1), 0.55),
		Enum.Material.SmoothPlastic,
		false
	)
	createPart(
		model,
		"BackPartition",
		Vector3.new(15, 6, 0.35),
		cframe * CFrame.new(0, 3, -7.3),
		color,
		Enum.Material.SmoothPlastic,
		false
	)
	createPart(
		model,
		"AccentLeft",
		Vector3.new(0.35, 4, 8),
		cframe * CFrame.new(-7.3, 2, -3),
		color,
		Enum.Material.Neon,
		false
	)
end

function OfficeLayoutBuilder._decorateItem(
	_self: Builder,
	model: Model,
	item: OfficeTypes.ItemDefinition,
	cframe: CFrame,
	level: number
)
	local roomColor = ROOM_COLORS[item.requiredRoomId]
	if item.kind == "Equipment" then
		createPart(
			model,
			"Body",
			Vector3.new(5.5, 2.5, 3.5),
			cframe * CFrame.new(0, 1.25, 0),
			roomColor,
			Enum.Material.Metal,
			true
		)
		createPart(
			model,
			"WorkSurface",
			Vector3.new(5.8, 0.3, 3.8),
			cframe * CFrame.new(0, 2.65, 0),
			Color3.fromRGB(220, 224, 232),
			Enum.Material.SmoothPlastic,
			true
		)
		for screenIndex = 1, level do
			createPart(
				model,
				`Display{screenIndex}`,
				Vector3.new(1.4, 1.4, 0.2),
				cframe * CFrame.new((screenIndex - (level + 1) * 0.5) * 1.6, 3.5, -1),
				roomColor:Lerp(Color3.new(1, 1, 1), 0.25),
				Enum.Material.Neon,
				false
			)
		end
	else
		createPart(
			model,
			"FurnitureBody",
			Vector3.new(3.6, 2.8, 2.4),
			cframe * CFrame.new(0, 1.4, 0),
			roomColor:Lerp(Color3.new(1, 1, 1), 0.35),
			Enum.Material.Wood,
			true
		)
		createPart(
			model,
			"FurnitureAccent",
			Vector3.new(3.2, 0.25, 2),
			cframe * CFrame.new(0, 2.95, 0),
			roomColor,
			Enum.Material.Neon,
			false
		)
	end
end

function OfficeLayoutBuilder.BuildReplacementRoot(
	self: Builder,
	context: PlotContext,
	layout: OfficeLayoutState
): Result<Model>
	local root = Instance.new("Model")
	root.Name = "PendingOfficeBuildRoot"
	local ok, result = xpcall(function(): Result<Model>
		local tier = self._progression:GetTier(layout.officeTierId)
		if tier == nil then
			return AppTypes.failure("UnknownOfficeTier", "Office layout tier is invalid", nil)
		end
		local spawn = context.model:FindFirstChild("SpawnLocation")
		if spawn == nil or not spawn:IsA("SpawnLocation") then
			return AppTypes.failure("InvalidPlotSpawn", "Plot spawn is missing", nil)
		end
		local tierResult = self:_cloneTemplate("Tiers", tier.templateId)
		if not tierResult.ok then
			return tierResult
		end
		local tierModel = tierResult.value
		tierModel.Name = "TierShell"
		tierModel:PivotTo(context.definition.origin * tier.shellOffset)
		tierModel.Parent = root
		self:_decorateTier(tierModel, tier, context.definition.origin, spawn)

		local roomsFolder = Instance.new("Folder")
		roomsFolder.Name = "Rooms"
		roomsFolder.Parent = root
		local equipmentFolder = Instance.new("Folder")
		equipmentFolder.Name = "Equipment"
		equipmentFolder.Parent = root
		local furnitureFolder = Instance.new("Folder")
		furnitureFolder.Name = "Furniture"
		furnitureFolder.Parent = root

		for _, room in self._config.rooms do
			if layout.purchasedRooms[room.id] then
				local placementResult =
					self._placement:ResolveRoom(layout.officeTierId, room.id, context.definition.origin)
				if not placementResult.ok then
					return placementResult
				end
				local cloneResult = self:_cloneTemplate("Rooms", room.templateId)
				if not cloneResult.ok then
					return cloneResult
				end
				local model = cloneResult.value
				local roomBase = placementResult.value.cframe * room.envelope.localOffset:Inverse()
				model.Name = room.id
				model:PivotTo(roomBase)
				self:_decorateRoom(model, room, roomBase)
				model.Parent = roomsFolder
			end
		end

		for _, item in self._config.items do
			local purchased = if item.kind == "Equipment"
				then layout.purchasedEquipment[item.id]
				else layout.purchasedFurniture[item.id]
			if purchased then
				local placementResult =
					self._placement:ResolveItem(layout.officeTierId, item.id, context.definition.origin)
				if not placementResult.ok then
					return placementResult
				end
				local level = 1
				local templateId = item.templateId
				if item.kind == "Equipment" then
					for _, upgrade in self._config.upgrades do
						if upgrade.targetItemId == item.id then
							level = layout.upgradeLevels[upgrade.id] or 1
							templateId = upgrade.templateIdsByLevel[level]
							break
						end
					end
				end
				local cloneResult =
					self:_cloneTemplate(if item.kind == "Equipment" then "Equipment" else "Furniture", templateId)
				if not cloneResult.ok then
					return cloneResult
				end
				local model = cloneResult.value
				local itemBase = placementResult.value.cframe * item.envelope.localOffset:Inverse()
				model.Name = item.id
				model:PivotTo(itemBase)
				self:_decorateItem(model, item, itemBase, level)
				model.Parent = if item.kind == "Equipment" then equipmentFolder else furnitureFolder
			end
		end

		local envelopesResult = self._placement:ResolveLayout(
			layout.officeTierId,
			layout,
			context.definition.origin,
			spawn.CFrame * CFrame.new(0, 3.5, 0)
		)
		if not envelopesResult.ok then
			return envelopesResult
		end
		local geometryResult = OfficeGeometryValidator.ValidateLayout(context.definition, envelopesResult.value)
		if not geometryResult.ok then
			return geometryResult
		end
		local modelResult = OfficeGeometryValidator.ValidateRuntimeModel(context.definition, root)
		if not modelResult.ok then
			return modelResult
		end
		return AppTypes.success(root)
	end, function(errorValue: unknown): string
		return debug.traceback(tostring(errorValue), 2)
	end)

	if not ok then
		root:Destroy()
		return AppTypes.failure(
			"BuildGenerationFailed",
			"Office generation raised an error",
			{ cause = tostring(result) }
		)
	end
	local buildResult = result :: Result<Model>
	if not buildResult.ok then
		root:Destroy()
	end
	return buildResult
end

return table.freeze(OfficeLayoutBuilder)
