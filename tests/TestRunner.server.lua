--!strict

local TestHarness = require(script.Parent.TestHarness)
local ClientDependencyResolverSpec = require(script.Parent.Unit.ClientDependencyResolverSpec)
local ConfigAndPayloadSpec = require(script.Parent.Unit.ConfigAndPayloadSpec)
local LifecycleRegistrySpec = require(script.Parent.Unit.LifecycleRegistrySpec)
local RemoteRegistryIntegrationSpec = require(script.Parent.Integration.RemoteRegistryIntegrationSpec)

local testCases: { TestHarness.TestCase } = {}

for _, testCase in ClientDependencyResolverSpec.tests() do
	table.insert(testCases, testCase)
end
for _, testCase in LifecycleRegistrySpec.tests() do
	table.insert(testCases, testCase)
end
for _, testCase in ConfigAndPayloadSpec.tests() do
	table.insert(testCases, testCase)
end
for _, testCase in RemoteRegistryIntegrationSpec.tests() do
	table.insert(testCases, testCase)
end

TestHarness.run(testCases)
