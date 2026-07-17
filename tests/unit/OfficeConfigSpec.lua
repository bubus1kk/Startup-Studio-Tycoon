--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local OfficeConfigValidator = require(ServerScriptService.Config.OfficeConfigValidator)
local SessionCurrencyConfigValidator = require(ServerScriptService.Config.SessionCurrencyConfigValidator)
local OfficeDefinitions = require(ServerStorage.Config.OfficeDefinitions)
local SessionCurrencyConfig = require(ServerStorage.Config.SessionCurrencyConfig)
local TestHarness = require(script.Parent.Parent.TestHarness)
local InvalidOfficeDefinitions = require(game:GetService("ReplicatedStorage").TestSupport.InvalidOfficeDefinitions)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase

local OfficeConfigSpec = {}

local function productionCatalogContractTest()
	local config = OfficeTestUtils.validatedConfig()
	TestHarness.assertEqual(#config.tiers, 5)
	TestHarness.assertEqual(#config.rooms, 9)
	TestHarness.assertEqual(#config.items, 18)
	TestHarness.assertEqual(#config.upgrades, 9)
	TestHarness.assertEqual(config.tiers[1].id, "tier_garage")
	TestHarness.assertEqual(config.tiers[1].price, 0)
	local total = 0
	for index, tier in config.tiers do
		if index > 1 then
			TestHarness.assertTrue(tier.price > 0 and tier.price % 1 == 0)
		end
		total += tier.price
	end
	for _, room in config.rooms do
		total += room.price
	end
	for _, item in config.items do
		total += item.price
	end
	for _, upgrade in config.upgrades do
		total += upgrade.pricesByLevel[2] + upgrade.pricesByLevel[3]
	end
	TestHarness.assertEqual(total, 205150)
	local currencyResult = SessionCurrencyConfigValidator.validate(SessionCurrencyConfig)
	TestHarness.assertTrue(currencyResult.ok)
	if currencyResult.ok then
		TestHarness.assertEqual(currencyResult.value.initialCashByEnvironment.Production, 250000)
		TestHarness.assertTrue(total <= currencyResult.value.initialCashByEnvironment.Production)
	end
end

local function invalidConfigRejectedTest()
	local result = OfficeConfigValidator.validate(InvalidOfficeDefinitions.empty)
	TestHarness.assertTrue(not result.ok)
	local invalidInitialTier = table.clone(OfficeDefinitions)
	invalidInitialTier.tiers = table.clone(OfficeDefinitions.tiers)
	invalidInitialTier.tiers[1] = table.clone(OfficeDefinitions.tiers[1])
	invalidInitialTier.tiers[1].price = 1
	local initialResult = OfficeConfigValidator.validate(invalidInitialTier)
	TestHarness.assertTrue(not initialResult.ok and initialResult.error.code == "InitialTierInvalid")
end

function OfficeConfigSpec.tests(): { TestCase }
	return {
		{
			name = "office production config has complete counts prices and exact total",
			run = productionCatalogContractTest,
		},
		{ name = "invalid office configuration is rejected", run = invalidConfigRejectedTest },
	}
end

return table.freeze(OfficeConfigSpec)
