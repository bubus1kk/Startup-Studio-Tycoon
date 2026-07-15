--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ConfigLoader = require(ReplicatedStorage.Shared.Config.ConfigLoader)
local DeepFreeze = require(ReplicatedStorage.Shared.Utils.DeepFreeze)
local PayloadValidator = require(ReplicatedStorage.Shared.Validation.PayloadValidator)
local PublicFeatureFlags = require(ReplicatedStorage.Shared.Config.PublicFeatureFlags)
local ServerConfigValidator = require(ServerScriptService.Config.ServerConfigValidator)
local RuntimeEnvironment = require(ServerScriptService.Infrastructure.RuntimeEnvironment)
local TestHarness = require(script.Parent.Parent.TestHarness)

type TestCase = TestHarness.TestCase

local ConfigAndPayloadSpec = {}

local function recursiveConfigFreezeTest()
	local rawConfig = {
		environment = "Test",
		featureFlags = {
			enableServerDebugLogging = false,
		},
	}
	local result = ConfigLoader.validateAndFreeze("ServerConfig", rawConfig, ServerConfigValidator.validate)
	TestHarness.assertTrue(result.ok)
	if not result.ok then
		return
	end

	TestHarness.assertTrue(DeepFreeze.isFrozenRecursive(result.value))
	rawConfig.featureFlags.enableServerDebugLogging = true
	TestHarness.assertEqual(result.value.featureFlags.enableServerDebugLogging, false)

	local mutationSucceeded = pcall(function()
		result.value.featureFlags.enableServerDebugLogging = true
	end)
	TestHarness.assertTrue(not mutationSucceeded)
end

local function featureFlagValidationTest()
	local validResult =
		ConfigLoader.validateAndFreeze("PublicFeatureFlags", PublicFeatureFlags.defaults(), PublicFeatureFlags.validate)
	TestHarness.assertTrue(validResult.ok)

	local invalidResult = PublicFeatureFlags.validate({
		enableClientDebugLogging = false,
		unknownFlag = true,
	})
	TestHarness.assertTrue(not invalidResult.ok)
	if not invalidResult.ok then
		TestHarness.assertEqual(invalidResult.error.code, "ConfigUnknownKey")
	end
end

local function runtimeEnvironmentTest()
	TestHarness.assertEqual(RuntimeEnvironment.resolve(true, "Auto"), "Studio")
	TestHarness.assertEqual(RuntimeEnvironment.resolve(false, "Auto"), "Production")
	TestHarness.assertEqual(RuntimeEnvironment.resolve(false, "Test"), "Test")
	TestHarness.assertEqual(RuntimeEnvironment.resolve(true, "Production"), "Production")
end

local function payloadValidationTest()
	local validator = PayloadValidator.compile(PayloadValidator.record({
		requestId = {
			rule = PayloadValidator.string({ minLength = 1, maxLength = 8 }),
		},
		amount = {
			rule = PayloadValidator.number({ min = 1, max = 10, integer = true }),
		},
		tags = {
			rule = PayloadValidator.array(PayloadValidator.string({ maxLength = 4 }), { maxItems = 2 }),
			optional = true,
		},
	}))

	TestHarness.assertTrue(validator({ requestId = "abc", amount = 2, tags = { "one" } }).ok)
	TestHarness.assertTrue(not validator({ requestId = "", amount = 2 }).ok)
	TestHarness.assertTrue(not validator({ requestId = "abc", amount = math.huge }).ok)
	TestHarness.assertTrue(not validator({ requestId = "abc", amount = 2, unknown = true }).ok)
	TestHarness.assertTrue(not validator({ requestId = "abc", amount = 2, tags = { "a", "b", "c" } }).ok)
	local instancePayload = Instance.new("Folder")
	TestHarness.assertTrue(not validator(instancePayload).ok)
	instancePayload:Destroy()
end

function ConfigAndPayloadSpec.tests(): { TestCase }
	return {
		{ name = "config loader copies and recursively freezes validated config", run = recursiveConfigFreezeTest },
		{ name = "feature flags reject unknown keys", run = featureFlagValidationTest },
		{ name = "runtime environment honors server-controlled settings", run = runtimeEnvironmentTest },
		{ name = "payload validator enforces type range size and keys", run = payloadValidationTest },
	}
end

return table.freeze(ConfigAndPayloadSpec)
