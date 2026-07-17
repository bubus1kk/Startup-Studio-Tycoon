--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
type OccupiedSlot = OfficeTypes.OccupiedSlot
local OfficeReconstructionSpec = {}

local INSTANCE_BUDGET = 450
local BASE_PART_BUDGET = 300

local function countInstances(root: Instance): (number, number)
	local instances = 1
	local baseParts = if root:IsA("BasePart") then 1 else 0
	for _, descendant in root:GetDescendants() do
		instances += 1
		if descendant:IsA("BasePart") then
			baseParts += 1
		end
	end
	return instances, baseParts
end

local function assertBooleanMapEqual(label: string, actual: { [string]: boolean }, expected: { [string]: boolean })
	local actualCount = 0
	local expectedCount = 0
	for _ in actual do
		actualCount += 1
	end
	for key, value in expected do
		expectedCount += 1
		TestHarness.assertEqual(actual[key], value, `{label} differs at {key}`)
	end
	TestHarness.assertEqual(actualCount, expectedCount, `{label} entry count differs`)
end

local function assertNumberMapEqual(label: string, actual: { [string]: number }, expected: { [string]: number })
	local actualCount = 0
	local expectedCount = 0
	for _ in actual do
		actualCount += 1
	end
	for key, value in expected do
		expectedCount += 1
		TestHarness.assertEqual(actual[key], value, `{label} differs at {key}`)
	end
	TestHarness.assertEqual(actualCount, expectedCount, `{label} entry count differs`)
end

local function assertStringMapEqual(label: string, actual: { [string]: string }, expected: { [string]: string })
	local actualCount = 0
	local expectedCount = 0
	for _ in actual do
		actualCount += 1
	end
	for key, value in expected do
		expectedCount += 1
		TestHarness.assertEqual(actual[key], value, `{label} differs at {key}`)
	end
	TestHarness.assertEqual(actualCount, expectedCount, `{label} entry count differs`)
end

local function assertSlotMapEqual(actual: { [string]: OccupiedSlot }, expected: { [string]: OccupiedSlot })
	local actualCount = 0
	local expectedCount = 0
	for _ in actual do
		actualCount += 1
	end
	for slotId, expectedSlot in expected do
		expectedCount += 1
		local actualSlot = actual[slotId]
		TestHarness.assertTrue(actualSlot ~= nil, `occupiedSlots missing {slotId}`)
		if actualSlot ~= nil then
			TestHarness.assertEqual(actualSlot.itemId, expectedSlot.itemId, `occupiedSlots item differs at {slotId}`)
			TestHarness.assertEqual(
				actualSlot.placementKey,
				expectedSlot.placementKey,
				`occupiedSlots placement differs at {slotId}`
			)
		end
	end
	TestHarness.assertEqual(actualCount, expectedCount, "occupiedSlots entry count differs")
end

local function fullDestroyRebuildRoundTripTest()
	local fixture = OfficeTestUtils.createFixture(5601, nil)
	for _, itemId in OfficeTestUtils.fullProgressionOrder(fixture.config) do
		local response = fixture:Purchase(itemId)
		TestHarness.assertTrue(response.ok == true, OfficeTestUtils.purchaseDiagnostic(itemId, response))
	end
	local exported = fixture.office:ExportLayout(fixture.userId)
	if not exported.ok then
		error(`serialize failed: error.code={exported.error.code}; error.message={exported.error.message}`)
	end
	local expected = exported.value
	local contextBefore = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
	if not contextBefore.ok then
		error(
			`pre-destroy plot context failed: error.code={contextBefore.error.code}; error.message={contextBefore.error.message}`
		)
	end
	local oldRoot = contextBefore.value.model:FindFirstChild("OfficeBuildRoot")
	TestHarness.assertTrue(oldRoot ~= nil, "pre-destroy root invariant failed: OfficeBuildRoot missing")

	local destroyed = fixture.office:CloseSession(fixture.userId)
	if not destroyed.ok then
		error(`destroy failed: error.code={destroyed.error.code}; error.message={destroyed.error.message}`)
	end
	TestHarness.assertTrue(destroyed.value, "destroy result was successful but reported no open session")
	TestHarness.assertTrue(
		oldRoot ~= nil and oldRoot.Parent == nil,
		"destroy failed: previous OfficeBuildRoot is still parented"
	)

	local rebuilt = fixture.office:PrepareSession(fixture.userId, expected)
	if not rebuilt.ok then
		error(`rebuild failed: error.code={rebuilt.error.code}; error.message={rebuilt.error.message}`)
	end
	local actual = rebuilt.value
	TestHarness.assertEqual(actual.schemaVersion, expected.schemaVersion, "layout schemaVersion changed during rebuild")
	TestHarness.assertEqual(actual.configVersion, expected.configVersion, "layout configVersion changed during rebuild")
	TestHarness.assertEqual(actual.revision, expected.revision, "layout revision changed during rebuild")
	TestHarness.assertEqual(actual.officeTierId, expected.officeTierId, "layout officeTierId changed during rebuild")
	assertBooleanMapEqual("purchasedRooms", actual.purchasedRooms, expected.purchasedRooms)
	assertBooleanMapEqual("purchasedEquipment", actual.purchasedEquipment, expected.purchasedEquipment)
	assertBooleanMapEqual("purchasedFurniture", actual.purchasedFurniture, expected.purchasedFurniture)
	assertNumberMapEqual("upgradeLevels", actual.upgradeLevels, expected.upgradeLevels)
	assertStringMapEqual("placementKeys", actual.placementKeys, expected.placementKeys)
	assertSlotMapEqual(actual.occupiedSlots, expected.occupiedSlots)

	local rootInvariant = fixture.office:ValidateRuntimeState(fixture.userId)
	if not rootInvariant.ok then
		error(
			`root invariant failed: error.code={rootInvariant.error.code}; error.message={rootInvariant.error.message}`
		)
	end
	local contextAfter = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
	if not contextAfter.ok then
		error(
			`post-rebuild plot context failed: error.code={contextAfter.error.code}; error.message={contextAfter.error.message}`
		)
	end
	local rebuiltRoot = contextAfter.value.model:FindFirstChild("OfficeBuildRoot")
	TestHarness.assertTrue(rebuiltRoot ~= nil, "post-rebuild root invariant failed: OfficeBuildRoot missing")
	if rebuiltRoot ~= nil then
		local instances, baseParts = countInstances(rebuiltRoot)
		print(
			`[Stage4Test] METRIC reconstruction userId={fixture.userId} plotId={contextAfter.value.definition.id} instances={instances} baseParts={baseParts} instanceBudget={INSTANCE_BUDGET} basePartBudget={BASE_PART_BUDGET}`
		)
		TestHarness.assertTrue(
			instances <= INSTANCE_BUDGET,
			`rebuild Instance count exceeded budget: instances={instances}; budget={INSTANCE_BUDGET}`
		)
		TestHarness.assertTrue(
			baseParts <= BASE_PART_BUDGET,
			`rebuild BasePart count exceeded budget: baseParts={baseParts}; budget={BASE_PART_BUDGET}`
		)
	end
	fixture:Destroy()
end

function OfficeReconstructionSpec.tests(): { TestCase }
	return {
		{ name = "maximum office layout survives destroy rebuild round trip", run = fullDestroyRebuildRoundTripTest },
	}
end
return table.freeze(OfficeReconstructionSpec)
