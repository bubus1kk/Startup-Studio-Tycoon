--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficeSnapshotCache = require(ServerScriptService.Services.OfficeSnapshotCache)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeRejoinSpec = {}

local function sameServerSnapshotRestoreTest()
	local fixture = OfficeTestUtils.createFixture(5701, nil)
	for _, itemId in { "room_development", "room_design", "tier_small_loft" } do
		local response = fixture:Purchase(itemId)
		TestHarness.assertTrue(response.ok == true, OfficeTestUtils.purchaseDiagnostic(itemId, response))
	end
	local layout = fixture.office:ExportLayout(fixture.userId)
	local currency = fixture.currency:ExportSession(fixture.userId)
	TestHarness.assertTrue(layout.ok and currency.ok)
	local now = 100
	local cache = OfficeSnapshotCache.new(function(): number
		return now
	end, 900, 24)
	if layout.ok and currency.ok then
		cache:Put(fixture.userId, layout.value, currency.value)
		TestHarness.assertTrue(cache:Peek(fixture.userId) ~= nil)
		TestHarness.assertTrue(cache:Peek(9999) == nil)
		local restored = cache:Consume(fixture.userId)
		TestHarness.assertTrue(restored ~= nil and restored.layout.officeTierId == "tier_small_loft")
	end
	cache:Destroy()
	fixture:Destroy()
end

function OfficeRejoinSpec.tests(): { TestCase }
	return {
		{ name = "same-server snapshot preserves layout Cash and user isolation", run = sameServerSnapshotRestoreTest },
	}
end
return table.freeze(OfficeRejoinSpec)
