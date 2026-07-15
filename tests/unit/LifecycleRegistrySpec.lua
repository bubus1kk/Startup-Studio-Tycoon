--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local TestHarness = require(script.Parent.Parent.TestHarness)

type Definition = LifecycleRegistry.Definition
type Registry = LifecycleRegistry.Registry
type TestCase = TestHarness.TestCase

local LifecycleRegistrySpec = {}

local function register(registry: Registry, definition: Definition)
	local result = registry:Register(definition)
	TestHarness.assertTrue(result.ok, if result.ok then nil else result.error.code)
end

local function definition(
	name: string,
	dependencies: { string },
	trace: { string },
	failInit: boolean?,
	failStart: boolean?,
	failDestroy: boolean?
): Definition
	local value = { name = name }
	return {
		name = name,
		dependencies = dependencies,
		value = value,
		hooks = {
			Init = function(resolver)
				table.insert(trace, `{name}.Init`)
				for _, dependencyName in dependencies do
					TestHarness.assertTrue(resolver:Require(dependencyName) ~= nil)
				end
				if failInit then
					error(`{name} Init failure`)
				end
			end,
			Start = function()
				table.insert(trace, `{name}.Start`)
				if failStart then
					error(`{name} Start failure`)
				end
			end,
			Destroy = function()
				table.insert(trace, `{name}.Destroy`)
				if failDestroy then
					error(`{name} Destroy failure`)
				end
			end,
		},
	}
end

local function deterministicOrderTest()
	local function resolve(registrationOrder: { string }): string
		local registry = LifecycleRegistry.new(nil)
		local trace: { string } = {}
		local definitions: { [string]: Definition } = {
			Alpha = definition("Alpha", {}, trace),
			Beta = definition("Beta", { "Alpha" }, trace),
			Gamma = definition("Gamma", {}, trace),
		}
		for _, name in registrationOrder do
			register(registry, definitions[name])
		end
		local result = registry:ResolveStartupOrder()
		TestHarness.assertTrue(result.ok)
		return table.concat(result.value, ",")
	end

	local first = resolve({ "Gamma", "Beta", "Alpha" })
	local second = resolve({ "Alpha", "Gamma", "Beta" })
	TestHarness.assertEqual(first, "Alpha,Beta,Gamma")
	TestHarness.assertEqual(second, first)
end

local function registrationFailuresTest()
	local trace: { string } = {}
	local duplicateRegistry = LifecycleRegistry.new(nil)
	register(duplicateRegistry, definition("Alpha", {}, trace))
	local duplicateResult = duplicateRegistry:Register(definition("Alpha", {}, trace))
	TestHarness.assertTrue(not duplicateResult.ok)
	if not duplicateResult.ok then
		TestHarness.assertEqual(duplicateResult.error.code, "DuplicateLifecycleObject")
	end

	local missingRegistry = LifecycleRegistry.new(nil)
	register(missingRegistry, definition("Alpha", { "Missing" }, trace))
	local missingResult = missingRegistry:ResolveStartupOrder()
	TestHarness.assertTrue(not missingResult.ok)
	if not missingResult.ok then
		TestHarness.assertEqual(missingResult.error.code, "MissingLifecycleDependency")
	end

	local cycleRegistry = LifecycleRegistry.new(nil)
	register(cycleRegistry, definition("Alpha", { "Beta" }, trace))
	register(cycleRegistry, definition("Beta", { "Alpha" }, trace))
	local cycleResult = cycleRegistry:ResolveStartupOrder()
	TestHarness.assertTrue(not cycleResult.ok)
	if not cycleResult.ok then
		TestHarness.assertEqual(cycleResult.error.code, "LifecycleDependencyCycle")
	end
end

local function initRollbackTest()
	local trace: { string } = {}
	local registry = LifecycleRegistry.new(nil)
	register(registry, definition("Alpha", {}, trace))
	register(registry, definition("Beta", { "Alpha" }, trace, true))
	register(registry, definition("Gamma", { "Beta" }, trace))

	local result = registry:InitAll()
	TestHarness.assertTrue(not result.ok)
	TestHarness.assertEqual(table.concat(trace, ","), "Alpha.Init,Beta.Init,Alpha.Destroy")
	TestHarness.assertEqual(registry:GetState(), "Destroyed")
end

local function startRollbackTest()
	local trace: { string } = {}
	local registry = LifecycleRegistry.new(nil)
	register(registry, definition("Alpha", {}, trace))
	register(registry, definition("Beta", { "Alpha" }, trace, false, true))

	TestHarness.assertTrue(registry:InitAll().ok)
	local result = registry:StartAll()
	TestHarness.assertTrue(not result.ok)
	TestHarness.assertEqual(
		table.concat(trace, ","),
		"Alpha.Init,Beta.Init,Alpha.Start,Beta.Start,Beta.Destroy,Alpha.Destroy"
	)
end

local function cleanupContinuesAndIsIdempotentTest()
	local trace: { string } = {}
	local diagnostics = 0
	local registry = LifecycleRegistry.new(function(errorValue)
		TestHarness.assertEqual(errorValue.code, "LifecycleCleanupFailed")
		diagnostics += 1
	end)
	register(registry, definition("Alpha", {}, trace))
	register(registry, definition("Beta", { "Alpha" }, trace, false, false, true))

	TestHarness.assertTrue(registry:InitAll().ok)
	TestHarness.assertTrue(registry:StartAll().ok)
	TestHarness.assertTrue(registry:DestroyAll().ok)
	TestHarness.assertTrue(registry:DestroyAll().ok)
	TestHarness.assertEqual(diagnostics, 1)
	TestHarness.assertEqual(
		table.concat(trace, ","),
		"Alpha.Init,Beta.Init,Alpha.Start,Beta.Start,Beta.Destroy,Alpha.Destroy"
	)
end

function LifecycleRegistrySpec.tests(): { TestCase }
	return {
		{ name = "lifecycle deterministic startup order", run = deterministicOrderTest },
		{ name = "lifecycle rejects duplicate missing and cyclic definitions", run = registrationFailuresTest },
		{ name = "lifecycle Init rollback destroys only initialized objects", run = initRollbackTest },
		{ name = "lifecycle Start rollback destroys every initialized object", run = startRollbackTest },
		{
			name = "lifecycle cleanup continues and DestroyAll is idempotent",
			run = cleanupContinuesAndIsIdempotentTest,
		},
	}
end

return table.freeze(LifecycleRegistrySpec)
