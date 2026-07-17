--!strict

local TestHarness = require(script.Parent.TestHarness)

local StudioTestService = game:GetService("StudioTestService")
local testArgs = StudioTestService:GetTestArgs()

-- The acceptance router owns structured Stage 4 suite runs. Preserve the
-- legacy no-args runtime behavior and the explicit Stage4RuntimeGate string.
if typeof(testArgs) == "table" and testArgs.stage == 4 and typeof(testArgs.suite) == "string" then
	return
end

local runtimeGateEnded = false
local function endRuntimeGate(result: { [string]: unknown })
	if runtimeGateEnded then
		return
	end
	runtimeGateEnded = true
	StudioTestService:EndTest(result)
end

local runtimeWatchdog: thread? = nil
if testArgs == "Stage4RuntimeGate" then
	runtimeWatchdog = task.delay(90, function()
		endRuntimeGate({
			ok = false,
			suite = "Stage4Runtime",
			total = 1,
			passed = 0,
			failed = 1,
			skipped = 0,
			durationSeconds = 90,
			failures = {
				{
					test = "runtime watchdog",
					message = "Runtime suite exceeded the 90 second watchdog timeout",
				},
			},
			metrics = {
				watchdogExpired = true,
				timeoutSeconds = 90,
			},
		})
	end)
end

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
local AcceptanceRunnerSpec = require(script.Parent.Parent.Stage4Acceptance.PluginRunnerUnderTest.AcceptanceRunnerSpec)

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

for _, testCase in AcceptanceRunnerSpec.tests() do
	table.insert(testCases, testCase)
end

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

local report: TestHarness.Report? = nil
local ok, cause = xpcall(function()
	report = TestHarness.runAndCollect(testCases)
	if (report :: TestHarness.Report).failed > 0 then
		error(`Stage 4 runtime tests failed ({(report :: TestHarness.Report).failed})`)
	end
end, function(errorValue: unknown): string
	return debug.traceback(tostring(errorValue), 2)
end)

if testArgs == "Stage4RuntimeGate" then
	if runtimeWatchdog ~= nil then
		pcall(task.cancel, runtimeWatchdog)
	end
	local finalReport = report
	if finalReport == nil then
		finalReport = {
			total = 1,
			passed = 0,
			failed = 1,
			skipped = 0,
			durationSeconds = 0,
			failures = {
				{
					test = "runtime suite execution",
					message = cause,
					traceback = cause,
				},
			},
		}
	end
	endRuntimeGate({
		ok = ok and finalReport.failed == 0,
		suite = "Stage4Runtime",
		total = finalReport.total,
		passed = finalReport.passed,
		failed = finalReport.failed,
		skipped = finalReport.skipped,
		durationSeconds = finalReport.durationSeconds,
		failures = finalReport.failures,
		metrics = {
			runtimeTestsExecuted = finalReport.total,
		},
	})
end

if not ok then
	error(cause, 0)
end
