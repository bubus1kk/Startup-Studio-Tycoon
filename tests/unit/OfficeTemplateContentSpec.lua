--!strict

local ServerStorage = game:GetService("ServerStorage")

local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase

local OfficeTemplateContentSpec = {}

local CATEGORY_COUNTS = {
	Tiers = 5,
	Rooms = 9,
	Equipment = 27,
	Furniture = 9,
}

local CATEGORY_MINIMUM_VISIBLE_PARTS = {
	Tiers = 6,
	Rooms = 5,
	Equipment = 4,
	Furniture = 5,
}

type TemplateEnvelope = {
	center: CFrame,
	size: Vector3,
}

local function visibleParts(template: Model, pivot: BasePart): { BasePart }
	local result: { BasePart } = {}
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= pivot and descendant.Transparency < 1 then
			table.insert(result, descendant)
		end
	end
	table.sort(result, function(first: BasePart, second: BasePart): boolean
		return first.Name < second.Name
	end)
	return result
end

local function geometrySignature(template: Model, pivot: BasePart): string
	local values: { string } = {}
	for _, detail in visibleParts(template, pivot) do
		local relative = pivot.CFrame:ToObjectSpace(detail.CFrame)
		table.insert(
			values,
			`{detail.ClassName}|{tostring(detail.Size)}|{tostring(relative)}|{detail.Material.Value}|{tostring(
				detail.Color
			)}|{detail.Transparency}`
		)
	end
	return table.concat(values, ";")
end

local function detailFitsEnvelope(pivot: BasePart, detail: BasePart, envelope: TemplateEnvelope): boolean
	local detailInEnvelope = envelope.center:ToObjectSpace(pivot.CFrame:ToObjectSpace(detail.CFrame))
	local half = envelope.size * 0.5
	local extentX = math.abs(detailInEnvelope.RightVector.X) * detail.Size.X * 0.5
		+ math.abs(detailInEnvelope.UpVector.X) * detail.Size.Y * 0.5
		+ math.abs(detailInEnvelope.LookVector.X) * detail.Size.Z * 0.5
	local extentY = math.abs(detailInEnvelope.RightVector.Y) * detail.Size.X * 0.5
		+ math.abs(detailInEnvelope.UpVector.Y) * detail.Size.Y * 0.5
		+ math.abs(detailInEnvelope.LookVector.Y) * detail.Size.Z * 0.5
	local extentZ = math.abs(detailInEnvelope.RightVector.Z) * detail.Size.X * 0.5
		+ math.abs(detailInEnvelope.UpVector.Z) * detail.Size.Y * 0.5
		+ math.abs(detailInEnvelope.LookVector.Z) * detail.Size.Z * 0.5
	local position = detailInEnvelope.Position
	return math.abs(position.X) + extentX <= half.X + 1e-4
		and math.abs(position.Y) + extentY <= half.Y + 1e-4
		and math.abs(position.Z) + extentZ <= half.Z + 1e-4
end

local function productionTemplateContentTest()
	local templates = ServerStorage:FindFirstChild("OfficeTemplates")
	TestHarness.assertTrue(templates ~= nil, "OfficeTemplates missing from ServerStorage")
	if templates == nil then
		return
	end

	local config = OfficeTestUtils.validatedConfig()
	local reachable: { [string]: boolean } = {}
	local envelopes: { [string]: TemplateEnvelope } = {}
	for _, tier in config.tiers do
		local path = `Tiers/{tier.templateId}`
		reachable[path] = true
		envelopes[path] = { center = CFrame.identity, size = tier.shellSize }
	end
	for _, room in config.rooms do
		local path = `Rooms/{room.templateId}`
		reachable[path] = true
		envelopes[path] = { center = room.envelope.localOffset, size = room.envelope.size }
	end
	for _, item in config.items do
		local path = `{if item.kind == "Equipment" then "Equipment" else "Furniture"}/{item.templateId}`
		reachable[path] = true
		envelopes[path] = { center = item.envelope.localOffset, size = item.envelope.size }
	end
	for _, upgrade in config.upgrades do
		local targetEnvelope: TemplateEnvelope? = nil
		for _, item in config.items do
			if item.id == upgrade.targetItemId then
				targetEnvelope = { center = item.envelope.localOffset, size = item.envelope.size }
				break
			end
		end
		TestHarness.assertTrue(targetEnvelope ~= nil, `{upgrade.id}: target item missing`)
		for level = 1, upgrade.maxLevel do
			local templateId = upgrade.templateIdsByLevel[level]
			TestHarness.assertTrue(templateId ~= nil, `{upgrade.id}: missing level {level} template`)
			if templateId ~= nil then
				local path = `Equipment/{templateId}`
				reachable[path] = true
				if targetEnvelope ~= nil then
					envelopes[path] = targetEnvelope
				end
			end
		end
	end

	local actualCount = 0
	local signatures: { [string]: string } = {}
	for category, expectedCount in CATEGORY_COUNTS do
		local folder = templates:FindFirstChild(category)
		TestHarness.assertTrue(folder ~= nil, `{category}: template folder missing`)
		if folder == nil then
			continue
		end
		local children = folder:GetChildren()
		TestHarness.assertEqual(#children, expectedCount, `{category}: production template count changed`)
		for _, child in children do
			actualCount += 1
			TestHarness.assertTrue(child:IsA("Model"), `{category}/{child.Name}: template root must be Model`)
			if not child:IsA("Model") then
				continue
			end
			local pivot = child:FindFirstChild("Pivot")
			TestHarness.assertTrue(
				pivot ~= nil and pivot:IsA("BasePart"),
				`{category}/{child.Name}: stable template Pivot missing`
			)
			if pivot == nil or not pivot:IsA("BasePart") then
				continue
			end
			local details = visibleParts(child, pivot)
			local path = `{category}/{child.Name}`
			local envelope = envelopes[path]
			TestHarness.assertTrue(envelope ~= nil, `{path}: authoritative content envelope missing`)
			local minimum = CATEGORY_MINIMUM_VISIBLE_PARTS[category]
			TestHarness.assertTrue(
				#details >= minimum,
				`{category}/{child.Name}: visibleParts={#details}; required={minimum}; Pivot plus marker is forbidden`
			)
			TestHarness.assertTrue(
				reachable[path] == true,
				`{category}/{child.Name}: template is unreachable from production catalog`
			)
			if envelope ~= nil then
				for _, detail in details do
					TestHarness.assertTrue(
						detailFitsEnvelope(pivot, detail, envelope),
						`{path}/{detail.Name}: visual geometry escaped its authoritative envelope`
					)
				end
			end
			local signature = geometrySignature(child, pivot)
			TestHarness.assertTrue(
				signatures[signature] == nil,
				`{category}/{child.Name}: duplicates geometry from {signatures[signature] or "unknown"}`
			)
			signatures[signature] = `{category}/{child.Name}`
			if category == "Equipment" then
				local levelText = string.match(child.Name, "L([123])$")
				local level = if levelText ~= nil then tonumber(levelText) else nil
				TestHarness.assertTrue(level ~= nil, `{child.Name}: equipment level suffix missing`)
				if level ~= nil then
					TestHarness.assertTrue(
						#details >= level + 3,
						`{child.Name}: level {level} needs structural detail beyond repeated displays`
					)
				end
			end
		end
	end

	local reachableCount = 0
	for path in reachable do
		reachableCount += 1
		local separator = string.find(path, "/", 1, true)
		if separator ~= nil then
			local category = string.sub(path, 1, separator - 1)
			local templateId = string.sub(path, separator + 1)
			local folder = templates:FindFirstChild(category)
			TestHarness.assertTrue(
				folder ~= nil and folder:FindFirstChild(templateId) ~= nil,
				`Catalog template missing: {path}`
			)
		end
	end
	TestHarness.assertEqual(reachableCount, 50, "Catalog must reach exactly 50 production templates")
	TestHarness.assertEqual(actualCount, 50, "ServerStorage must contain exactly 50 production templates")
end

function OfficeTemplateContentSpec.tests(): { TestCase }
	return {
		{
			name = "all 50 catalog templates contain distinct category-specific production geometry",
			run = productionTemplateContentTest,
		},
	}
end

return table.freeze(OfficeTemplateContentSpec)
