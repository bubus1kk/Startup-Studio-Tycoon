--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficeLayoutSerializer = require(ServerScriptService.Domain.OfficeLayoutSerializer)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeLayoutSerializerSpec = {}

local function independentCopyAndVersionTest()
	local progression = OfficeProgression.new(OfficeTestUtils.validatedConfig())
	local original = progression:CreateInitialLayout()
	local copy = OfficeLayoutSerializer.Copy(original)
	copy.purchasedRooms.room_development = true
	TestHarness.assertTrue(not original.purchasedRooms.room_development)
	TestHarness.assertTrue(OfficeLayoutSerializer.Validate(copy, 1, 1).ok)
	TestHarness.assertTrue(not OfficeLayoutSerializer.Validate(copy, 2, 1).ok)
end

function OfficeLayoutSerializerSpec.tests(): { TestCase }
	return { { name = "office layout copies data only and enforces versions", run = independentCopyAndVersionTest } }
end
return table.freeze(OfficeLayoutSerializerSpec)
