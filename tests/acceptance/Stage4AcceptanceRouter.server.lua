--!strict

local StudioTestService = game:GetService("StudioTestService")

local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)
local Stage4MultiplayerAcceptance = require(script.Parent.Stage4MultiplayerAcceptance)
local Stage4PerformanceAcceptance = require(script.Parent.Stage4PerformanceAcceptance)
local Stage4SoloAcceptance = require(script.Parent.Stage4SoloAcceptance)

type Result = AcceptanceTestUtils.Result
type SuiteModule = {
	Run: (
		recorder: AcceptanceTestUtils.Recorder,
		coordination: AcceptanceTestUtils.Coordination,
		args: { [string]: unknown }
	) -> { [string]: number | string | boolean },
}

local testArgsValue = StudioTestService:GetTestArgs()
if typeof(testArgsValue) ~= "table" or testArgsValue.stage ~= 4 or typeof(testArgsValue.suite) ~= "string" then
	return
end

local testArgs = testArgsValue :: { [string]: unknown }
local suiteName = testArgs.suite :: string
local suites: { [string]: SuiteModule } = {
	Stage4Solo = Stage4SoloAcceptance,
	Stage4Multiplayer3 = Stage4MultiplayerAcceptance,
	Stage4Performance6 = Stage4PerformanceAcceptance,
}

local finalized = false
local coordination: AcceptanceTestUtils.Coordination? = nil

local function finalizeOnce(result: Result, reason: string)
	if finalized then
		return
	end
	finalized = true
	if coordination ~= nil then
		local activeCoordination = coordination :: AcceptanceTestUtils.Coordination
		coordination = nil
		local cleanupOk, cleanupCause = pcall(function()
			activeCoordination:Destroy()
		end)
		if not cleanupOk then
			result.ok = false
			result.total += 1
			result.failed += 1
			table.insert(result.failures, {
				test = "acceptance coordination cleanup",
				message = tostring(cleanupCause),
				traceback = debug.traceback(tostring(cleanupCause), 2),
			})
		end
	end
	print(`[Stage4Acceptance] FINALIZE suite={suiteName} reason={reason} ok={result.ok}`)
	local ok, cause = pcall(function()
		StudioTestService:EndTest(result)
	end)
	if not ok then
		warn(`[Stage4Acceptance] EndTest failed for {suiteName}: {tostring(cause)}`)
	end
end

local watchdogValue = testArgs.watchdogSeconds
local watchdogSeconds = if typeof(watchdogValue) == "number" then math.clamp(watchdogValue, 30, 600) else 180
local watchdogThread = task.delay(watchdogSeconds, function()
	local timeoutResult = AcceptanceTestUtils.FailResult(
		suiteName,
		"acceptance watchdog",
		`Suite exceeded its {watchdogSeconds} second watchdog timeout`,
		nil
	)
	timeoutResult.durationSeconds = watchdogSeconds
	timeoutResult.metrics.watchdogExpired = true
	timeoutResult.metrics.timeoutSeconds = watchdogSeconds
	finalizeOnce(timeoutResult, "watchdog")
end)

local suite = suites[suiteName]
if suite == nil then
	pcall(task.cancel, watchdogThread)
	finalizeOnce(
		AcceptanceTestUtils.FailResult(suiteName, "suite routing", `Unknown Stage 4 suite {suiteName}`, nil),
		"unknown suite"
	)
	return
end

local recorder = AcceptanceTestUtils.NewRecorder(suiteName)
local ok, resultValue = xpcall(function(): Result
	coordination = AcceptanceTestUtils.CreateCoordination()
	local metrics = suite.Run(recorder, coordination :: AcceptanceTestUtils.Coordination, testArgs)
	return recorder:Finish(metrics)
end, function(errorValue: unknown): { message: string, traceback: string }
	return {
		message = tostring(errorValue),
		traceback = debug.traceback(tostring(errorValue), 2),
	}
end)

pcall(task.cancel, watchdogThread)
if ok then
	finalizeOnce(resultValue :: Result, "suite completed")
else
	local detail = resultValue :: { message: string, traceback: string }
	finalizeOnce(
		AcceptanceTestUtils.FailResult(suiteName, "suite exception", detail.message, detail.traceback),
		"suite exception"
	)
end
