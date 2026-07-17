--!strict

local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeRoomPurchaseSpec = {}

local function allRoomsPurchaseThroughGraphTest()
	local fixture = OfficeTestUtils.createFixture(5101, nil)
	for _, itemId in
		{
			"room_development",
			"room_design",
			"tier_small_loft",
			"room_qa",
			"room_marketing",
			"room_meeting",
			"tier_downtown",
			"room_server",
			"room_recreation",
			"tier_tech_campus",
			"room_executive",
			"room_research",
		}
	do
		local response = fixture:Purchase(itemId)
		TestHarness.assertTrue(response.ok == true, OfficeTestUtils.purchaseDiagnostic(itemId, response))
	end
	local duplicate = fixture:Purchase("room_development")
	TestHarness.assertTrue(duplicate.ok == false, OfficeTestUtils.purchaseDiagnostic("room_development", duplicate))
	TestHarness.assertTrue(fixture.office:ValidateRuntimeState(fixture.userId).ok)
	fixture:Destroy()
end

local function requestIdempotencyAndConflictTest()
	local fixture = OfficeTestUtils.createFixture(5102, nil)
	local request = { requestId = "duplicate-room-request", itemId = "room_development" }
	local first = fixture.office:Purchase(fixture.userId, request)
	local duplicate = fixture.office:Purchase(fixture.userId, request)
	TestHarness.assertTrue(first.ok, OfficeTestUtils.purchaseDiagnostic("room_development", first))
	TestHarness.assertTrue(duplicate.ok, OfficeTestUtils.purchaseDiagnostic("room_development", duplicate))
	TestHarness.assertEqual(duplicate.revision, first.revision)
	TestHarness.assertEqual(duplicate.cash, first.cash)
	local conflict = fixture.office:Purchase(fixture.userId, {
		requestId = "duplicate-room-request",
		itemId = "room_design",
	})
	TestHarness.assertTrue(
		not conflict.ok and conflict.error ~= nil and conflict.error.code == "RequestIdConflict",
		OfficeTestUtils.purchaseDiagnostic("room_design", conflict)
	)
	local balance = fixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(balance.ok and balance.value == 249400)
	TestHarness.assertTrue(fixture.office:ValidateRuntimeState(fixture.userId).ok)
	fixture:Destroy()
end

local function authoritativeFundingStatesTest()
	local insufficientFixture = OfficeTestUtils.createFixture(5103, nil, 500)
	local initialTier = insufficientFixture:Purchase("tier_garage")
	TestHarness.assertTrue(
		not initialTier.ok
			and initialTier.state == "Purchased"
			and initialTier.error ~= nil
			and initialTier.error.code == "InitialTierAlreadyOwned",
		OfficeTestUtils.purchaseDiagnostic("tier_garage", initialTier)
	)
	local insufficient = insufficientFixture:Purchase("room_development")
	TestHarness.assertTrue(
		not insufficient.ok
			and insufficient.state == "Available"
			and insufficient.error ~= nil
			and insufficient.error.code == "InsufficientFunds",
		OfficeTestUtils.purchaseDiagnostic("room_development", insufficient)
	)
	local insufficientLayout = insufficientFixture.office:ExportLayout(insufficientFixture.userId)
	local insufficientBalance = insufficientFixture.currency:GetBalance(insufficientFixture.userId, "Cash")
	TestHarness.assertTrue(insufficientLayout.ok and not insufficientLayout.value.purchasedRooms.room_development)
	TestHarness.assertTrue(insufficientBalance.ok and insufficientBalance.value == 500)
	insufficientFixture:Destroy()

	local exactFixture = OfficeTestUtils.createFixture(5104, nil, 600)
	local exact = exactFixture:Purchase("room_development")
	TestHarness.assertTrue(
		exact.ok and exact.state == "Purchased" and exact.cash == 0,
		OfficeTestUtils.purchaseDiagnostic("room_development", exact)
	)
	exactFixture:Destroy()
end

function OfficeRoomPurchaseSpec.tests(): { TestCase }
	return {
		{ name = "all nine rooms follow the production prerequisite graph", run = allRoomsPurchaseThroughGraphTest },
		{
			name = "duplicate office request is idempotent and conflicting reuse is rejected",
			run = requestIdempotencyAndConflictTest,
		},
		{
			name = "server funding keeps insufficient item available and permits exact debit",
			run = authoritativeFundingStatesTest,
		},
	}
end
return table.freeze(OfficeRoomPurchaseSpec)
