--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local DeepFreeze = require(ReplicatedStorage.Shared.Utils.DeepFreeze)
local EmployeeConfigValidator = require(ServerScriptService.Config.EmployeeConfigValidator)
local EmployeeDefinitions = require(ServerStorage.Config.EmployeeDefinitions)
local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local EmployeeConfigSpec = {}

local function completeFrozenConfigTest()
	local config = EmployeeTestUtils.validatedConfig()
	TestHarness.assertEqual(#config.roles, 9)
	TestHarness.assertEqual(#config.grades, 4)
	TestHarness.assertEqual(#config.traits, 12)
	TestHarness.assertEqual(#config.workstations, 9)
	TestHarness.assertEqual(config.grades[1].maxLevel, 5)
	TestHarness.assertEqual(config.grades[2].maxLevel, 10)
	TestHarness.assertEqual(config.grades[3].maxLevel, 15)
	TestHarness.assertEqual(config.grades[4].maxLevel, 20)
	TestHarness.assertEqual(config.tierEmployeeCaps.tier_garage, 2)
	TestHarness.assertEqual(config.tierEmployeeCaps.tier_global_hq, 30)
	TestHarness.assertEqual(config.morale.initial, 80)
	TestHarness.assertEqual(config.payroll.intervalSeconds, 60)
	TestHarness.assertTrue(string.match(config.movement.animationIds.idle, "^rbxassetid://%d+$") ~= nil)
	TestHarness.assertTrue(string.match(config.movement.animationIds.walk, "^rbxassetid://%d+$") ~= nil)
	TestHarness.assertTrue(string.match(config.movement.animationIds.work, "^rbxassetid://%d+$") ~= nil)
	TestHarness.assertTrue(DeepFreeze.isFrozenRecursive(config))
	local l3Total = 0
	for _, definition in config.workstations do
		l3Total += definition.capacities[3]
	end
	TestHarness.assertEqual(l3Total, 30)
end

local function malformedConfigRejectedTest()
	local invalid = table.clone(EmployeeDefinitions)
	invalid.traits = table.clone(EmployeeDefinitions.traits)
	invalid.traits[2] = table.clone(EmployeeDefinitions.traits[1])
	local result = EmployeeConfigValidator.validate(invalid, OfficeTestUtils.validatedConfig())
	TestHarness.assertTrue(not result.ok and result.error.code == "DuplicateEmployeeTrait")
	local invalidCapacity = table.clone(EmployeeDefinitions)
	invalidCapacity.workstations = table.clone(EmployeeDefinitions.workstations)
	invalidCapacity.workstations[1] = table.clone(EmployeeDefinitions.workstations[1])
	invalidCapacity.workstations[1].capacities = { [1] = 1, [2] = 3, [3] = 4 }
	local capacityResult = EmployeeConfigValidator.validate(invalidCapacity, OfficeTestUtils.validatedConfig())
	TestHarness.assertTrue(not capacityResult.ok)
	local invalidSpacing = table.clone(EmployeeDefinitions)
	invalidSpacing.workstations = table.clone(EmployeeDefinitions.workstations)
	invalidSpacing.workstations[1] = table.clone(EmployeeDefinitions.workstations[1])
	invalidSpacing.workstations[1].slots = table.clone(EmployeeDefinitions.workstations[1].slots)
	invalidSpacing.workstations[1].slots[2] = table.clone(EmployeeDefinitions.workstations[1].slots[2])
	invalidSpacing.workstations[1].slots[2].workOffset = EmployeeDefinitions.workstations[1].slots[1].workOffset
	local spacingResult = EmployeeConfigValidator.validate(invalidSpacing, OfficeTestUtils.validatedConfig())
	TestHarness.assertTrue(not spacingResult.ok and spacingResult.error.code == "EmployeeWorkstationSpacingInvalid")
	local invalidNumber = table.clone(EmployeeDefinitions)
	invalidNumber.scheduler = table.clone(EmployeeDefinitions.scheduler)
	invalidNumber.scheduler.productivitySeconds = 0 / 0
	local numberResult = EmployeeConfigValidator.validate(invalidNumber, OfficeTestUtils.validatedConfig())
	TestHarness.assertTrue(not numberResult.ok and numberResult.error.code == "EmployeeConfigUnsafeValue")
	local invalidBias = table.clone(EmployeeDefinitions)
	invalidBias.roles = table.clone(EmployeeDefinitions.roles)
	invalidBias.roles[1] = table.clone(EmployeeDefinitions.roles[1])
	invalidBias.roles[1].statBias = { speed = 1, quality = 0, reliability = 0 }
	local biasResult = EmployeeConfigValidator.validate(invalidBias, OfficeTestUtils.validatedConfig())
	TestHarness.assertTrue(not biasResult.ok and biasResult.error.code == "EmployeeRoleInvalid")
	local invalidTraitEffect = table.clone(EmployeeDefinitions)
	invalidTraitEffect.traits = table.clone(EmployeeDefinitions.traits)
	invalidTraitEffect.traits[1] = table.clone(EmployeeDefinitions.traits[1])
	invalidTraitEffect.traits[1].xpMultiplier = 1.1
	local traitResult = EmployeeConfigValidator.validate(invalidTraitEffect, OfficeTestUtils.validatedConfig())
	TestHarness.assertTrue(not traitResult.ok and traitResult.error.code == "EmployeeTraitEffectInvalid")
	local invalidTierWeight = table.clone(EmployeeDefinitions)
	invalidTierWeight.gradeWeightsByTier = table.clone(EmployeeDefinitions.gradeWeightsByTier)
	invalidTierWeight.gradeWeightsByTier.tier_garage = { Trainee = 60, Junior = 40 }
	local weightResult = EmployeeConfigValidator.validate(invalidTierWeight, OfficeTestUtils.validatedConfig())
	TestHarness.assertTrue(not weightResult.ok and weightResult.error.code == "EmployeeTierWeightInvalid")
	local invalidAnimation = table.clone(EmployeeDefinitions)
	invalidAnimation.movement = table.clone(EmployeeDefinitions.movement)
	invalidAnimation.movement.animationIds = {
		idle = "https://untrusted.example/animation",
		walk = "rbxassetid://507777826",
		work = "rbxassetid://507768375",
	}
	local animationResult = EmployeeConfigValidator.validate(invalidAnimation, OfficeTestUtils.validatedConfig())
	TestHarness.assertTrue(not animationResult.ok and animationResult.error.code == "EmployeeAnimationIdInvalid")
end

function EmployeeConfigSpec.tests(): { TestCase }
	return {
		{ name = "employee config validates 9 roles 4 grades 12 traits and 30 slots", run = completeFrozenConfigTest },
		{
			name = "employee config rejects contract drift unsafe values and invalid workstation prefixes",
			run = malformedConfigRejectedTest,
		},
	}
end

return table.freeze(EmployeeConfigSpec)
