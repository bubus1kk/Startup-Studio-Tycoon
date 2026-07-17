--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeProgressionSpec = {}

local function graphAndUpgradeStatesTest()
	local progression = OfficeProgression.new(OfficeTestUtils.validatedConfig())
	local layout = progression:CreateInitialLayout()
	local garage = progression:Evaluate(layout, "tier_garage", false)
	TestHarness.assertTrue(garage.ok and garage.value.state == "Purchased")
	local design = progression:Evaluate(layout, "room_design", false)
	TestHarness.assertTrue(design.ok and design.value.state == "Locked")
	layout.purchasedRooms.room_development = true
	design = progression:Evaluate(layout, "room_design", false)
	TestHarness.assertTrue(design.ok and design.value.state == "Available")
	local upgrade = progression:Evaluate(layout, "upgrade_dev_workstation", false)
	TestHarness.assertTrue(upgrade.ok and upgrade.value.state == "Locked")
	layout.purchasedEquipment.equipment_dev_workstation = true
	layout.upgradeLevels.upgrade_dev_workstation = 2
	upgrade = progression:Evaluate(layout, "upgrade_dev_workstation", false)
	TestHarness.assertTrue(upgrade.ok and upgrade.value.state == "Available" and upgrade.value.price == 1600)
	layout.upgradeLevels.upgrade_dev_workstation = 3
	upgrade = progression:Evaluate(layout, "upgrade_dev_workstation", false)
	TestHarness.assertTrue(upgrade.ok and upgrade.value.state == "MaxLevel")
end

function OfficeProgressionSpec.tests(): { TestCase }
	return { { name = "office prerequisites and upgrade states are authoritative", run = graphAndUpgradeStatesTest } }
end
return table.freeze(OfficeProgressionSpec)
