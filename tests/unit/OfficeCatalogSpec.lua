--!strict

local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase

local OfficeCatalogSpec = {}

local function paginationAndInvalidPageTest()
	local config = OfficeTestUtils.validatedConfig()
	local progression = require(game:GetService("ServerScriptService").Domain.OfficeProgression).new(config)
	local catalog = require(game:GetService("ServerScriptService").Domain.OfficeCatalog).new(config, progression)
	local counts = catalog:GetCategoryCounts()
	TestHarness.assertEqual(counts.Tiers, 5)
	TestHarness.assertEqual(counts.Rooms, 9)
	TestHarness.assertEqual(counts.Equipment, 9)
	TestHarness.assertEqual(counts.Furniture, 9)
	TestHarness.assertEqual(counts.Upgrades, 9)
	local layout = progression:CreateInitialLayout()
	local first = catalog:GetPage(layout, 250000, "Rooms", 1, {})
	TestHarness.assertTrue(first.ok)
	if first.ok then
		TestHarness.assertEqual(#first.value.items, 5)
		TestHarness.assertEqual(first.value.pageCount, 2)
		TestHarness.assertEqual(first.value.totalItems, 9)
	end
	local invalid = catalog:GetPage(layout, 250000, "Rooms", 3, {})
	TestHarness.assertTrue(not invalid.ok)
	if not invalid.ok then
		TestHarness.assertEqual(invalid.error.details and invalid.error.details.pageCount, "2")
		TestHarness.assertEqual(invalid.error.details and invalid.error.details.page, "3")
	end
	local emptyConfig = table.clone(config)
	emptyConfig.items = {}
	emptyConfig.upgrades = {}
	local emptyProgression = require(game:GetService("ServerScriptService").Domain.OfficeProgression).new(emptyConfig)
	local emptyCatalog =
		require(game:GetService("ServerScriptService").Domain.OfficeCatalog).new(emptyConfig, emptyProgression)
	local emptyFirst = emptyCatalog:GetPage(emptyProgression:CreateInitialLayout(), 250000, "Equipment", 1, {})
	TestHarness.assertTrue(emptyFirst.ok and emptyFirst.value.pageCount == 0 and #emptyFirst.value.items == 0)
	local emptySecond = emptyCatalog:GetPage(emptyProgression:CreateInitialLayout(), 250000, "Equipment", 2, {})
	TestHarness.assertTrue(not emptySecond.ok and emptySecond.error.code == "InvalidCatalogPage")
end

function OfficeCatalogSpec.tests(): { TestCase }
	return {
		{
			name = "catalog category pagination and invalid page metadata are bounded",
			run = paginationAndInvalidPageTest,
		},
	}
end

return table.freeze(OfficeCatalogSpec)
