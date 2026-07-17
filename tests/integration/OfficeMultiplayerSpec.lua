--!strict

local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeMultiplayerSpec = {}

local function threeIndependentLayoutsTest()
	local fixtures = {
		OfficeTestUtils.createFixture(5901, nil),
		OfficeTestUtils.createFixture(5902, nil),
		OfficeTestUtils.createFixture(5903, nil),
	}
	for index, fixture in fixtures do
		local development = fixture:Purchase("room_development")
		TestHarness.assertTrue(
			development.ok == true,
			OfficeTestUtils.purchaseDiagnostic("room_development", development)
		)
		if index >= 2 then
			local design = fixture:Purchase("room_design")
			TestHarness.assertTrue(design.ok == true, OfficeTestUtils.purchaseDiagnostic("room_design", design))
		end
	end
	local first = fixtures[1].office:ExportLayout(fixtures[1].userId)
	local second = fixtures[2].office:ExportLayout(fixtures[2].userId)
	TestHarness.assertTrue(first.ok and second.ok)
	if first.ok and second.ok then
		TestHarness.assertTrue(not first.value.purchasedRooms.room_design)
		TestHarness.assertTrue(second.value.purchasedRooms.room_design)
	end
	local foreign = fixtures[1].office:Purchase(fixtures[2].userId, {
		requestId = "foreign-office-attempt",
		itemId = "room_design",
	})
	TestHarness.assertTrue(
		not foreign.ok and foreign.error ~= nil and foreign.error.code == "OfficeSessionNotReady",
		OfficeTestUtils.purchaseDiagnostic("room_design", foreign)
	)
	local firstAfter = fixtures[1].office:ExportLayout(fixtures[1].userId)
	TestHarness.assertTrue(firstAfter.ok and not firstAfter.value.purchasedRooms.room_design)
	for _, fixture in fixtures do
		fixture:Destroy()
	end
end

function OfficeMultiplayerSpec.tests(): { TestCase }
	return {
		{ name = "three players keep independent authoritative office layouts", run = threeIndependentLayoutsTest },
	}
end
return table.freeze(OfficeMultiplayerSpec)
