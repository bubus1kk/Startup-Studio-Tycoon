--!strict

local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeTierTransitionSpec = {}

local function exactFullCatalogFundingTest()
	local fixture = OfficeTestUtils.createFixture(5401, nil)
	local initialBalance = fixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(initialBalance.ok and initialBalance.value == 250000)
	TestHarness.assertEqual(
		#fixture.config.tiers + #fixture.config.rooms + #fixture.config.items + #fixture.config.upgrades,
		41
	)
	local transactionCount = 0
	for _, itemId in OfficeTestUtils.fullProgressionOrder(fixture.config) do
		local response = fixture:Purchase(itemId)
		transactionCount += 1
		TestHarness.assertTrue(response.ok == true, OfficeTestUtils.purchaseDiagnostic(itemId, response))
		TestHarness.assertTrue((response.cash :: number) >= 0)
	end
	TestHarness.assertEqual(transactionCount, 49)
	local balance = fixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(balance.ok)
	if balance.ok then
		TestHarness.assertEqual(balance.value, 44850)
		TestHarness.assertEqual(250000 - balance.value, 205150)
	end
	local layout = fixture.office:ExportLayout(fixture.userId)
	TestHarness.assertTrue(layout.ok and layout.value.officeTierId == "tier_global_hq")
	if layout.ok then
		local rooms = 0
		local equipment = 0
		local furniture = 0
		local completedUpgradeSteps = 0
		for _ in layout.value.purchasedRooms do
			rooms += 1
		end
		for _ in layout.value.purchasedEquipment do
			equipment += 1
		end
		for _ in layout.value.purchasedFurniture do
			furniture += 1
		end
		for _, level in layout.value.upgradeLevels do
			completedUpgradeSteps += level - 1
		end
		TestHarness.assertEqual(rooms, 9)
		TestHarness.assertEqual(equipment, 9)
		TestHarness.assertEqual(furniture, 9)
		TestHarness.assertEqual(completedUpgradeSteps, 18)
	end
	fixture:Destroy()
end

function OfficeTierTransitionSpec.tests(): { TestCase }
	return { { name = "full 205150 catalog leaves exact Production Cash 44850", run = exactFullCatalogFundingTest } }
end
return table.freeze(OfficeTierTransitionSpec)
