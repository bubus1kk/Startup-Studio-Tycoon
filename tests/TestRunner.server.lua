--!strict

local TestHarness = require(script.Parent.TestHarness)

local StudioTestService = game:GetService("StudioTestService")

local ClientDependencyResolverSpec = require(script.Parent.Unit.ClientDependencyResolverSpec)
local ConfigAndPayloadSpec = require(script.Parent.Unit.ConfigAndPayloadSpec)
local LifecycleRegistrySpec = require(script.Parent.Unit.LifecycleRegistrySpec)
local PlotBoundsSpec = require(script.Parent.Unit.PlotBoundsSpec)
local PlotConfigSpec = require(script.Parent.Unit.PlotConfigSpec)
local OfficeCatalogSpec = require(script.Parent.Unit.OfficeCatalogSpec)
local OfficeConfigSpec = require(script.Parent.Unit.OfficeConfigSpec)
local OfficeGeometryValidatorSpec = require(script.Parent.Unit.OfficeGeometryValidatorSpec)
local OfficeLayoutSerializerSpec = require(script.Parent.Unit.OfficeLayoutSerializerSpec)
local OfficePlacementSpec = require(script.Parent.Unit.OfficePlacementSpec)
local OfficeProgressionSpec = require(script.Parent.Unit.OfficeProgressionSpec)
local OfficeSnapshotCacheSpec = require(script.Parent.Unit.OfficeSnapshotCacheSpec)
local OfficeTemplateContentSpec = require(script.Parent.Unit.OfficeTemplateContentSpec)
local RequestRateLimiterSpec = require(script.Parent.Unit.RequestRateLimiterSpec)
local SessionCurrencyServiceSpec = require(script.Parent.Unit.SessionCurrencyServiceSpec)

local PlotServiceIntegrationSpec = require(script.Parent.Integration.PlotServiceIntegrationSpec)
local ProductionPlotRuntimeSpec = require(script.Parent.Integration.ProductionPlotRuntimeSpec)
local RemoteRegistryIntegrationSpec = require(script.Parent.Integration.RemoteRegistryIntegrationSpec)
local OfficeEntranceApproachSpec = require(script.Parent.Integration.OfficeEntranceApproachSpec)
local OfficeFullLayoutPerformanceSpec = require(script.Parent.Integration.OfficeFullLayoutPerformanceSpec)
local OfficeItemPurchaseSpec = require(script.Parent.Integration.OfficeItemPurchaseSpec)
local OfficeMultiplayerSpec = require(script.Parent.Integration.OfficeMultiplayerSpec)
local OfficeReconstructionSpec = require(script.Parent.Integration.OfficeReconstructionSpec)
local OfficeRejoinSpec = require(script.Parent.Integration.OfficeRejoinSpec)
local OfficeRemoteSpec = require(script.Parent.Integration.OfficeRemoteSpec)
local OfficeRollbackSpec = require(script.Parent.Integration.OfficeRollbackSpec)
local OfficeRoomPurchaseSpec = require(script.Parent.Integration.OfficeRoomPurchaseSpec)
local OfficeTierTransitionSpec = require(script.Parent.Integration.OfficeTierTransitionSpec)
local OfficeUpgradeSpec = require(script.Parent.Integration.OfficeUpgradeSpec)
local ProductionOfficeRuntimeSpec = require(script.Parent.Integration.ProductionOfficeRuntimeSpec)

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

for _, testCase in PlotBoundsSpec.tests() do
	table.insert(testCases, testCase)
end

for _, testCase in PlotConfigSpec.tests() do
	table.insert(testCases, testCase)
end

for _, spec in
	{
		OfficeConfigSpec,
		OfficeCatalogSpec,
		OfficeProgressionSpec,
		OfficePlacementSpec,
		OfficeLayoutSerializerSpec,
		SessionCurrencyServiceSpec,
		OfficeSnapshotCacheSpec,
		RequestRateLimiterSpec,
		OfficeGeometryValidatorSpec,
		OfficeTemplateContentSpec,
	}
do
	for _, testCase in spec.tests() do
		table.insert(testCases, testCase)
	end
end

for _, testCase in PlotServiceIntegrationSpec.tests() do
	table.insert(testCases, testCase)
end

for _, testCase in RemoteRegistryIntegrationSpec.tests() do
	table.insert(testCases, testCase)
end

for _, testCase in ProductionPlotRuntimeSpec.tests() do
	table.insert(testCases, testCase)
end

for _, spec in
	{
		OfficeRoomPurchaseSpec,
		OfficeEntranceApproachSpec,
		OfficeItemPurchaseSpec,
		OfficeUpgradeSpec,
		OfficeTierTransitionSpec,
		OfficeRollbackSpec,
		OfficeReconstructionSpec,
		OfficeRejoinSpec,
		OfficeRemoteSpec,
		OfficeMultiplayerSpec,
		OfficeFullLayoutPerformanceSpec,
		ProductionOfficeRuntimeSpec,
	}
do
	for _, testCase in spec.tests() do
		table.insert(testCases, testCase)
	end
end

local ok, cause = xpcall(function()
	TestHarness.run(testCases)
end, function(errorValue: unknown): string
	return debug.traceback(tostring(errorValue), 2)
end)

if StudioTestService:GetTestArgs() == "Stage4RuntimeGate" then
	StudioTestService:EndTest({
		ok = ok,
		cause = if ok then "none" else cause,
	})
end

if not ok then
	error(cause, 0)
end
