--!strict

local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeUpgradeSpec = {}

local function allUpgradeChainsReachMaxTest()
	local fixture = OfficeTestUtils.createFixture(5301, nil)
	for _, itemId in OfficeTestUtils.fullProgressionOrder(fixture.config) do
		local response = fixture:Purchase(itemId)
		TestHarness.assertTrue(response.ok == true, OfficeTestUtils.purchaseDiagnostic(itemId, response))
	end
	for _, upgrade in fixture.config.upgrades do
		local layoutResult = fixture.office:ExportLayout(fixture.userId)
		TestHarness.assertTrue(layoutResult.ok)
		if layoutResult.ok then
			local evaluation = fixture.progression:Evaluate(layoutResult.value, upgrade.id, false)
			TestHarness.assertTrue(evaluation.ok and evaluation.value.state == "MaxLevel")
		end
		local rejected = fixture:Purchase(upgrade.id)
		TestHarness.assertTrue(
			rejected.ok == false and rejected.state == "MaxLevel",
			OfficeTestUtils.purchaseDiagnostic(upgrade.id, rejected)
		)
	end
	fixture:Destroy()
end

function OfficeUpgradeSpec.tests(): { TestCase }
	return { { name = "all nine visual upgrade chains reach L3 and reject L4", run = allUpgradeChainsReachMaxTest } }
end
return table.freeze(OfficeUpgradeSpec)
