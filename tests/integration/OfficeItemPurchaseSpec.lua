--!strict

local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeItemPurchaseSpec = {}

local function equipmentFurnitureAndSlotsTest()
	local fixture = OfficeTestUtils.createFixture(5201, nil)
	local order = OfficeTestUtils.fullProgressionOrder(fixture.config)
	for index = 1, 31 do
		local response = fixture:Purchase(order[index])
		TestHarness.assertTrue(response.ok == true, OfficeTestUtils.purchaseDiagnostic(order[index], response))
	end
	local layout = fixture.office:ExportLayout(fixture.userId)
	TestHarness.assertTrue(layout.ok)
	if layout.ok then
		local equipmentCount = 0
		local furnitureCount = 0
		for _ in layout.value.purchasedEquipment do
			equipmentCount += 1
		end
		for _ in layout.value.purchasedFurniture do
			furnitureCount += 1
		end
		TestHarness.assertEqual(equipmentCount, 9)
		TestHarness.assertEqual(furnitureCount, 9)
	end
	fixture:Destroy()
end

function OfficeItemPurchaseSpec.tests(): { TestCase }
	return { { name = "all equipment and furniture occupy authoritative slots", run = equipmentFurnitureAndSlotsTest } }
end
return table.freeze(OfficeItemPurchaseSpec)
