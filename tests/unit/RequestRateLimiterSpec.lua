--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local RequestRateLimiter = require(ServerScriptService.Security.RequestRateLimiter)
local TestHarness = require(script.Parent.Parent.TestHarness)

type TestCase = TestHarness.TestCase
local RequestRateLimiterSpec = {}

local function burstRefillAndIsolationTest()
	local now = 0
	local limiter = RequestRateLimiter.new(function(): number
		return now
	end)
	TestHarness.assertTrue(limiter:Allow(1, "purchase", 2, 1))
	TestHarness.assertTrue(limiter:Allow(1, "purchase", 2, 1))
	TestHarness.assertTrue(not limiter:Allow(1, "purchase", 2, 1))
	TestHarness.assertTrue(limiter:Allow(2, "purchase", 2, 1))
	now = 1
	TestHarness.assertTrue(limiter:Allow(1, "purchase", 2, 1))
	limiter:ClearPlayer(1)
	TestHarness.assertTrue(limiter:Allow(1, "purchase", 2, 1))
end

function RequestRateLimiterSpec.tests(): { TestCase }
	return { { name = "request limiter enforces burst refill and player isolation", run = burstRefillAndIsolationTest } }
end
return table.freeze(RequestRateLimiterSpec)
