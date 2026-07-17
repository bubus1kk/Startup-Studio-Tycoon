--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefinitions = require(ReplicatedStorage.Shared.Remotes.RemoteDefinitions)
local RemoteTypes = require(ReplicatedStorage.Shared.Remotes.RemoteTypes)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type RemoteDefinition = RemoteTypes.RemoteDefinition
type TestCase = TestHarness.TestCase
local OfficeRemoteSpec = {}

local function invalidPageAndRequestConflictTest()
	local fixture = OfficeTestUtils.createFixture(5801, nil)
	local domainInvalid = fixture.office:GetCatalogPage(fixture.userId, "Rooms", 3)
	TestHarness.assertTrue(not domainInvalid.ok)
	local invalid = fixture.office:HandleCatalogRequest(fixture.userId, {
		requestId = "invalid-page",
		categoryId = "Rooms",
		page = 3,
	})
	TestHarness.assertTrue(not invalid.ok)
	TestHarness.assertEqual(invalid.pageCount, 2)
	TestHarness.assertEqual(invalid.totalItems, 9)
	TestHarness.assertEqual(#invalid.items, 0)
	TestHarness.assertTrue(invalid.error ~= nil and invalid.error.code == "InvalidCatalogPage")
	local invalidConflict = fixture.office:HandleCatalogRequest(fixture.userId, {
		requestId = "invalid-page",
		categoryId = "Equipment",
		page = 1,
	})
	TestHarness.assertTrue(
		not invalidConflict.ok and invalidConflict.error ~= nil and invalidConflict.error.code == "RequestIdConflict"
	)
	local first = fixture.office:HandleCatalogRequest(fixture.userId, {
		requestId = "catalog-conflict",
		categoryId = "Rooms",
		page = 1,
	})
	TestHarness.assertTrue(first.ok)
	local conflict = fixture.office:HandleCatalogRequest(fixture.userId, {
		requestId = "catalog-conflict",
		categoryId = "Rooms",
		page = 2,
	})
	TestHarness.assertTrue(not conflict.ok and conflict.error ~= nil and conflict.error.code == "RequestIdConflict")
	fixture:Destroy()
end

local function boundedCatalogResponseTest()
	local catalogDefinition: RemoteDefinition? = nil
	for _, definition in RemoteDefinitions.definitions do
		if definition.name == "RequestOfficeCatalog" then
			catalogDefinition = definition
			break
		end
	end
	TestHarness.assertTrue(catalogDefinition ~= nil and catalogDefinition.responseValidator ~= nil)
	if catalogDefinition == nil or catalogDefinition.responseValidator == nil then
		return
	end
	local function item(index: number)
		return {
			itemId = `equipment_test_{index}`,
			displayName = "Bounded item",
			description = "Worst-case bounded catalog response item.",
			categoryId = "Equipment",
			price = 100,
			state = "Locked",
			lockCode = "PrerequisiteMissing",
			lockText = "Complete prerequisites.",
			requiredTierId = "tier_test",
			requiredRoomId = "room_test",
			prerequisiteIds = { "a", "b", "c", "d" },
			slotId = "test.main.01",
			currentLevel = 1,
			maxLevel = 3,
		}
	end
	local items = {}
	for index = 1, 5 do
		table.insert(items, item(index))
	end
	local payload = {
		ok = false,
		requestId = "bounded-response",
		categoryId = "Equipment",
		page = 1,
		pageCount = 2,
		totalItems = 9,
		revision = 1,
		currentTierId = "tier_garage",
		cash = 250000,
		items = items,
		error = { code = "InternalError", message = "Bounded error." },
	}
	TestHarness.assertTrue(catalogDefinition.responseValidator(payload).ok)
	table.insert(items, item(6))
	TestHarness.assertTrue(not catalogDefinition.responseValidator(payload).ok)
end

function OfficeRemoteSpec.tests(): { TestCase }
	return {
		{
			name = "office catalog remote metadata and request conflicts are safe",
			run = invalidPageAndRequestConflictTest,
		},
		{
			name = "office catalog response accepts 109-node page and rejects oversized page",
			run = boundedCatalogResponseTest,
		},
	}
end
return table.freeze(OfficeRemoteSpec)
