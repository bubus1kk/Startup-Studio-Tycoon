--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local OfficeGeometryValidator = require(ServerScriptService.Domain.OfficeGeometryValidator)
local OfficeEntranceGeometry = require(ServerScriptService.Domain.OfficeEntranceGeometry)
local OfficePlacement = require(ServerScriptService.Domain.OfficePlacement)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)
local OfficeLayoutBuilder = require(ServerScriptService.Systems.OfficeLayoutBuilder)
local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local PlotRuntimeBuilder = require(ServerScriptService.Systems.PlotRuntimeBuilder)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)
local PlotTestUtils = require(script.Parent.Parent.ServerFixtures.PlotTestUtils)

type TestCase = TestHarness.TestCase
local OfficeGeometryValidatorSpec = {}

local function maximumLayoutForTier(
	config: OfficeTypes.OfficeConfig,
	progression: OfficeProgression.Progression,
	tierId: string
): OfficeTypes.OfficeLayoutState
	local layout = progression:CreateInitialLayout()
	local tier = progression:GetTier(tierId)
	TestHarness.assertTrue(tier ~= nil, `Unknown test tier {tierId}`)
	if tier == nil then
		return layout
	end
	layout.officeTierId = tierId
	local allowedRooms: { [string]: boolean } = {}
	for _, roomId in tier.allowedRooms do
		allowedRooms[roomId] = true
		local room = progression:GetRoom(roomId)
		TestHarness.assertTrue(room ~= nil, `Unknown test room {roomId}`)
		if room ~= nil then
			layout.purchasedRooms[roomId] = true
			layout.placementKeys[roomId] = room.placementKey
		end
	end
	for _, item in config.items do
		if allowedRooms[item.requiredRoomId] then
			if item.kind == "Equipment" then
				layout.purchasedEquipment[item.id] = true
			else
				layout.purchasedFurniture[item.id] = true
			end
			layout.occupiedSlots[item.slotId] = { itemId = item.id, placementKey = item.placementKey }
			layout.placementKeys[item.id] = item.placementKey
		end
	end
	for _, upgrade in config.upgrades do
		if layout.purchasedEquipment[upgrade.targetItemId] then
			layout.upgradeLevels[upgrade.id] = upgrade.maxLevel
		end
	end
	return layout
end

local function productionTierAnchorMapsTest()
	local definition = PlotTestUtils.validatedConfig().definitions[1]
	local config = OfficeTestUtils.validatedConfig()
	local progression = OfficeProgression.new(config)
	local placement = OfficePlacement.new(progression)
	local spawnCFrame = definition.origin * definition.spawnOffset * CFrame.new(0, 0.5, 0)
	local spawnSize = Vector3.new(8, 1, 8)
	local templates = ServerStorage:FindFirstChild("OfficeTemplates")
	TestHarness.assertTrue(templates ~= nil, "OfficeTemplates missing from test DataModel")
	if templates == nil then
		return
	end
	local builder = OfficeLayoutBuilder.new(templates, config, progression, placement, nil)
	local plotResult = PlotRuntimeBuilder.new(nil):Build(definition)
	if not plotResult.ok then
		error(`plot build failed: error.code={plotResult.error.code}; error.message={plotResult.error.message}`)
	end

	for _, tierId in { "tier_downtown", "tier_tech_campus", "tier_global_hq" } do
		local layout = maximumLayoutForTier(config, progression, tierId)
		local envelopesResult = placement:ResolveLayout(tierId, layout, definition.origin, spawnCFrame, spawnSize)
		if not envelopesResult.ok then
			error(
				`{tierId} placement failed: error.code={envelopesResult.error.code}; error.message={envelopesResult.error.message}`
			)
		end
		local geometryResult = OfficeGeometryValidator.ValidateLayout(definition, envelopesResult.value)
		if not geometryResult.ok then
			error(
				`{tierId} maximum geometry failed: error.code={geometryResult.error.code}; error.message={geometryResult.error.message}`
			)
		end
		local buildResult = builder:BuildReplacementRoot({
			definition = definition,
			model = plotResult.value,
			generationToken = 1,
		}, layout)
		if not buildResult.ok then
			error(
				`{tierId} maximum template build failed: error.code={buildResult.error.code}; error.message={buildResult.error.message}`
			)
		end
		buildResult.value:Destroy()
	end

	local downtownLayout = maximumLayoutForTier(config, progression, "tier_downtown")
	local downtownEnvelopes =
		placement:ResolveLayout("tier_downtown", downtownLayout, definition.origin, spawnCFrame, spawnSize)
	if not downtownEnvelopes.ok then
		error(
			`Downtown placement failed: error.code={downtownEnvelopes.error.code}; error.message={downtownEnvelopes.error.message}`
		)
	end
	local oldAnchorEnvelopes: { OfficePlacement.ResolvedEnvelope } = {}
	local recreationEnvelope: OfficePlacement.ResolvedEnvelope? = nil
	for _, envelope in downtownEnvelopes.value do
		local copy = table.clone(envelope)
		if copy.id == "room_recreation" then
			copy.cframe = definition.origin * CFrame.new(-20, 6, 18)
			recreationEnvelope = envelope
		end
		table.insert(oldAnchorEnvelopes, copy)
	end
	TestHarness.assertTrue(recreationEnvelope ~= nil, "Downtown recreation envelope missing")
	if recreationEnvelope ~= nil then
		local localPosition = definition.origin:PointToObjectSpace(recreationEnvelope.cframe.Position)
		TestHarness.assertEqual(localPosition, Vector3.new(-20, 6, 16), "Downtown recreation anchor regressed")
	end
	local oldGeometry = OfficeGeometryValidator.ValidateLayout(definition, oldAnchorEnvelopes)
	local oldGeometryDiagnostic = if oldGeometry.ok
		then "legacy Downtown recreation anchor unexpectedly passed"
		else `legacy Downtown recreation anchor: error.code={oldGeometry.error.code}; error.message={oldGeometry.error.message}`
	TestHarness.assertTrue(
		not oldGeometry.ok and oldGeometry.error.code == "RoomShellReservedZone",
		oldGeometryDiagnostic
	)
	plotResult.value:Destroy()
end

local function overlapBoundsAndRotationTest()
	local definition = PlotTestUtils.validatedConfig().definitions[1]
	local valid = OfficeGeometryValidator.ValidateLayout(definition, {
		{
			id = "a",
			kind = "Room",
			roomId = "a",
			cframe = definition.origin * CFrame.new(-10, 6, -8),
			size = Vector3.new(16, 12, 16),
		},
		{
			id = "b",
			kind = "Room",
			roomId = "b",
			cframe = definition.origin * CFrame.new(10, 6, -8),
			size = Vector3.new(16, 12, 16),
		},
	})
	TestHarness.assertTrue(valid.ok)
	local overlap = OfficeGeometryValidator.ValidateLayout(definition, {
		{
			id = "a",
			kind = "Room",
			roomId = "a",
			cframe = definition.origin * CFrame.new(0, 6, 0),
			size = Vector3.new(16, 12, 16),
		},
		{
			id = "b",
			kind = "Room",
			roomId = "b",
			cframe = definition.origin * CFrame.new(1, 6, 0),
			size = Vector3.new(16, 12, 16),
		},
	})
	TestHarness.assertTrue(not overlap.ok and overlap.error.code == "GeometryOverlap")
	local reservedZone = OfficeGeometryValidator.ValidateLayout(definition, {
		{
			id = "room",
			kind = "Room",
			roomId = "room",
			cframe = definition.origin * CFrame.new(0, 6, 0),
			size = Vector3.new(16, 12, 16),
		},
		{
			id = "shell.reserved",
			kind = "Reserved",
			cframe = definition.origin * CFrame.new(0, 6, 0),
			size = Vector3.new(1, 12, 16),
		},
	})
	TestHarness.assertTrue(not reservedZone.ok and reservedZone.error.code == "RoomShellReservedZone")
	local rotatedDefinition = table.clone(definition)
	rotatedDefinition.origin = CFrame.new(20, 0, 20) * CFrame.Angles(0, math.rad(35), 0)
	local rotated = OfficeGeometryValidator.ValidateLayout(rotatedDefinition, {
		{
			id = "rotated",
			kind = "Room",
			roomId = "rotated",
			cframe = rotatedDefinition.origin * CFrame.new(0, 6, 0),
			size = Vector3.new(16, 12, 16),
		},
	})
	TestHarness.assertTrue(rotated.ok)
end

local function entranceEnvelopeCoverageTest()
	local definition = table.clone(PlotTestUtils.validatedConfig().definitions[1])
	definition.origin = CFrame.new(31, 0, -27) * CFrame.Angles(0, math.rad(37), 0)
	local config = OfficeTestUtils.validatedConfig()
	local progression = OfficeProgression.new(config)
	local placement = OfficePlacement.new(progression)
	local spawnCFrame = definition.origin * definition.spawnOffset * CFrame.new(0, 0.5, 0)
	local spawnSize = Vector3.new(8, 1, 8)

	for _, tier in config.tiers do
		local geometryResult = OfficeEntranceGeometry.Resolve(tier, definition.origin, spawnCFrame, spawnSize)
		if not geometryResult.ok then
			error(`{tier.id}: shared entrance geometry failed: {geometryResult.error.code}`)
		end
		local layout = progression:CreateInitialLayout()
		layout.officeTierId = tier.id
		local placementResult = placement:ResolveLayout(tier.id, layout, definition.origin, spawnCFrame, spawnSize)
		if not placementResult.ok then
			error(`{tier.id}: entrance placement failed: {placementResult.error.code}`)
		end

		local entrance: OfficePlacement.ResolvedEnvelope? = nil
		for _, envelope in placementResult.value do
			if envelope.id == "EntrancePath" then
				entrance = envelope
				break
			end
		end
		TestHarness.assertTrue(entrance ~= nil, `{tier.id}: EntrancePath envelope missing`)
		if entrance == nil then
			continue
		end
		local geometry = geometryResult.value
		TestHarness.assertEqual(entrance.size, geometry.pathSize, `{tier.id}: path size differs from walkway route`)
		TestHarness.assertTrue(
			(entrance.cframe.Position - geometry.pathCFrame.Position).Magnitude < 0.001,
			`{tier.id}: path center differs from walkway route`
		)
		TestHarness.assertTrue(
			entrance.cframe.RightVector:Dot(definition.origin.RightVector) > 0.999,
			`{tier.id}: entrance envelope lost rotated plot orientation`
		)
		TestHarness.assertTrue(
			PlotBounds.containsBox(definition, entrance.cframe, entrance.size),
			`{tier.id}: shared entrance envelope escaped plot bounds`
		)

		for label, fraction in { beginning = 0.08, middle = 0.5, nearSpawn = 0.92 } do
			local overlapEnvelopes = table.clone(placementResult.value)
			table.insert(overlapEnvelopes, {
				id = `probe_{label}`,
				kind = "Room",
				roomId = `probe_{label}`,
				cframe = entrance.cframe * CFrame.new(0, 0, (fraction - 0.5) * entrance.size.Z),
				size = Vector3.new(1, 1, math.min(0.5, entrance.size.Z * 0.05)),
			})
			local validation = OfficeGeometryValidator.ValidateLayout(definition, overlapEnvelopes)
			local diagnostic = if validation.ok
				then `{tier.id}/{label}: entrance overlap unexpectedly passed`
				else `{tier.id}/{label}: error.code={validation.error.code}; error.message={validation.error.message}`
			TestHarness.assertTrue(not validation.ok and validation.error.code == "EntrancePathBlocked", diagnostic)
		end
	end
end

local function entranceOverlapPurchaseRollbackTest()
	local sourceConfig = OfficeTestUtils.validatedConfig()
	local config = table.clone(sourceConfig)
	config.tiers = table.clone(sourceConfig.tiers)
	local garage = table.clone(sourceConfig.tiers[1])
	garage.roomAnchors = table.clone(sourceConfig.tiers[1].roomAnchors)
	garage.roomAnchors.room_development = CFrame.new(0, 1, 0)
	config.tiers[1] = garage

	local fixture = OfficeTestUtils.createFixture(6201, nil, 250000, config)
	local response = fixture:Purchase("room_development")
	TestHarness.assertTrue(not response.ok, OfficeTestUtils.purchaseDiagnostic("room_development", response))
	TestHarness.assertTrue(
		response.error ~= nil and response.error.code == "OfficeBoundsViolation",
		OfficeTestUtils.purchaseDiagnostic("room_development", response)
	)
	TestHarness.assertEqual(response.cash, 250000, "Entrance-overlap rejection must release debit reservation")
	local layoutResult = fixture.office:ExportLayout(fixture.userId)
	TestHarness.assertTrue(layoutResult.ok, "Layout unavailable after entrance-overlap rejection")
	if layoutResult.ok then
		TestHarness.assertTrue(
			layoutResult.value.purchasedRooms.room_development ~= true,
			"Rejected entrance-overlap purchase entered authoritative layout"
		)
	end
	fixture:Destroy()
end

local function rotatedRuntimePartsTest()
	local definition = table.clone(PlotTestUtils.validatedConfig().definitions[1])
	definition.origin = CFrame.new(20, 0, 20) * CFrame.Angles(0, math.rad(35), 0)
	local plotResult = PlotRuntimeBuilder.new(nil):Build(definition)
	TestHarness.assertTrue(plotResult.ok)
	if not plotResult.ok then
		return
	end
	local plotModel = plotResult.value
	local anchor = plotModel:FindFirstChild("PlotAnchor")
	local boundary = plotModel:FindFirstChild("PlotBoundary")
	local northEdge = if boundary ~= nil then boundary:FindFirstChild("NorthEdge") else nil
	TestHarness.assertTrue(plotModel.PrimaryPart == anchor)
	TestHarness.assertTrue(northEdge ~= nil and northEdge:IsA("BasePart"))
	if northEdge ~= nil and northEdge:IsA("BasePart") then
		TestHarness.assertTrue(northEdge.CFrame.RightVector:Dot(definition.origin.RightVector) > 0.999)
	end

	local config = OfficeTestUtils.validatedConfig()
	local progression = OfficeProgression.new(config)
	local placement = OfficePlacement.new(progression)
	local templates = ServerStorage:FindFirstChild("OfficeTemplates")
	TestHarness.assertTrue(templates ~= nil)
	if templates ~= nil then
		local builder = OfficeLayoutBuilder.new(templates, config, progression, placement, nil)
		local rootResult = builder:BuildReplacementRoot({
			definition = definition,
			model = plotModel,
			generationToken = 1,
		}, progression:CreateInitialLayout())
		TestHarness.assertTrue(rootResult.ok)
		if rootResult.ok then
			local tierShell = rootResult.value:FindFirstChild("TierShell")
			local floorBack = if tierShell ~= nil then tierShell:FindFirstChild("FloorBack") else nil
			TestHarness.assertTrue(floorBack ~= nil and floorBack:IsA("BasePart"))
			if floorBack ~= nil and floorBack:IsA("BasePart") then
				TestHarness.assertTrue(floorBack.CFrame.RightVector:Dot(definition.origin.RightVector) > 0.999)
			end
			rootResult.value:Destroy()
		end
	end
	plotModel:Destroy()
end

function OfficeGeometryValidatorSpec.tests(): { TestCase }
	return {
		{
			name = "office geometry rejects overlap and supports rotated local bounds",
			run = overlapBoundsAndRotationTest,
		},
		{
			name = "rotated plot runtime and tier BaseParts preserve plot origin rotation",
			run = rotatedRuntimePartsTest,
		},
		{
			name = "production tier anchor maps fit maximum content and reject legacy recreation overlap",
			run = productionTierAnchorMapsTest,
		},
		{
			name = "shared entrance envelope covers beginning middle and spawn end for all rotated tiers",
			run = entranceEnvelopeCoverageTest,
		},
		{
			name = "room entrance overlap rejects purchase and releases debit before commit",
			run = entranceOverlapPurchaseRollbackTest,
		},
	}
end
return table.freeze(OfficeGeometryValidatorSpec)
