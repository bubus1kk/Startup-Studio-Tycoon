--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficePlacement = require(ServerScriptService.Domain.OfficePlacement)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficePlacementSpec = {}

local function rotatedPlacementTest()
	local progression = OfficeProgression.new(OfficeTestUtils.validatedConfig())
	local placement = OfficePlacement.new(progression)
	local origin = CFrame.new(40, 0, -20) * CFrame.Angles(0, math.rad(90), 0)
	local result = placement:ResolveRoom("tier_garage", "room_development", origin)
	TestHarness.assertTrue(result.ok)
	if result.ok then
		local expected = origin * CFrame.new(-10, 6, -8)
		TestHarness.assertTrue((result.value.cframe.Position - expected.Position).Magnitude < 0.001)
		TestHarness.assertTrue(result.value.cframe.LookVector:FuzzyEq(expected.LookVector, 0.001))
	end
end

function OfficePlacementSpec.tests(): { TestCase }
	return { { name = "office placement preserves rotated plot origin", run = rotatedPlacementTest } }
end
return table.freeze(OfficePlacementSpec)
