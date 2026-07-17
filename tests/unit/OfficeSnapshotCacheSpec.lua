--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local OfficeSnapshotCache = require(ServerScriptService.Services.OfficeSnapshotCache)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeSnapshotCacheSpec = {}

local function ttlCapacityAndConsumeTest()
	local now = 10
	local cache = OfficeSnapshotCache.new(function(): number
		return now
	end, 5, 2)
	local layout = OfficeProgression.new(OfficeTestUtils.validatedConfig()):CreateInitialLayout()
	local currency = { balances = { Cash = 250000 } }
	cache:Put(1, layout, currency)
	now = 11
	cache:Put(2, layout, currency)
	now = 12
	cache:Put(3, layout, currency)
	TestHarness.assertTrue(cache:Peek(1) == nil)
	TestHarness.assertEqual(cache:GetCount(), 2)
	TestHarness.assertTrue(cache:Consume(2) ~= nil)
	TestHarness.assertTrue(cache:Peek(2) == nil)
	now = 20
	TestHarness.assertEqual(cache:GetCount(), 0)
	cache:Destroy()
end

function OfficeSnapshotCacheSpec.tests(): { TestCase }
	return { { name = "office snapshot cache uses lazy TTL capacity and consume", run = ttlCapacityAndConsumeTest } }
end
return table.freeze(OfficeSnapshotCacheSpec)
