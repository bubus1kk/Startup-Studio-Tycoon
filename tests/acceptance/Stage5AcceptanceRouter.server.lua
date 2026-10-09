--!strict

local StudioTestService = game:GetService("StudioTestService")

local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)
local Stage5BlockedPathAcceptance = require(script.Parent.Stage5BlockedPathAcceptance)
local Stage5MultiplayerAcceptance = require(script.Parent.Stage5MultiplayerAcceptance)
local Stage5NpcAcceptance = require(script.Parent.Stage5NpcAcceptance)
local Stage5SoloAcceptance = require(script.Parent.Stage5SoloAcceptance)

type Result = AcceptanceTestUtils.Result
type SuiteModule = {
	Run: (
		recorder: AcceptanceTestUtils.Recorder,
		coordination: AcceptanceTestUtils.Coordination,
		args: { [string]: unknown }
	) -> { [string]: number | string | boolean },
}

local testArgsValue = StudioTestService:GetTestArgs()
if typeof(testArgsValue) ~= "table" or testArgsValue.stage ~= 5 or typeof(testArgsValue.suite) ~= "string" then
	return
end
local testArgs = testArgsValue :: { [string]: unknown }
local suiteName = testArgs.suite :: string
local suites: { [string]: SuiteModule } = {
	Stage5Solo = Stage5SoloAcceptance,
	Stage5Multiplayer3 = Stage5MultiplayerAcceptance,
	Stage5Npc10 = Stage5NpcAcceptance,
	Stage5Npc30 = Stage5NpcAcceptance,
	Stage5BlockedPath = Stage5BlockedPathAcceptance,
}
local finalized = false
local coordination: AcceptanceTestUtils.Coordination? = nil
local function finalizeOnce(result: Result, reason: string)
	if finalized then
		return
	end
	finalized = true
	if coordination ~= nil then
		local active = coordination :: AcceptanceTestUtils.Coordination
		coordination = nil
		local ok, cause = pcall(function()
			active:Destroy()
		end)
		if not ok then
			result.ok = false
			result.total += 1
			result.failed += 1
			table.insert(result.failures, { test = "acceptance coordination cleanup", message = tostring(cause) })
		end
	end
	print(`[Stage5Acceptance] FINALIZE suite={suiteName} reason={reason} ok={result.ok}`)
	local ok, cause = pcall(function()
		StudioTestService:EndTest(result)
	end)
	if not ok then
		warn(`[Stage5Acceptance] EndTest failed for {suiteName}: {tostring(cause)}`)
	end
end
local watchdogValue = testArgs.watchdogSeconds
local watchdogSeconds = if typeof(watchdogValue) == "number" then math.clamp(watchdogValue, 30, 600) else 240
local watchdogThread = task.delay(watchdogSeconds, function()
	local result =
		AcceptanceTestUtils.FailResult(suiteName, "acceptance watchdog", `Suite exceeded {watchdogSeconds}s`, nil)
	result.durationSeconds = watchdogSeconds
	result.metrics.watchdogExpired = true
	result.metrics.timeoutSeconds = watchdogSeconds
	finalizeOnce(result, "watchdog")
end)
local suite = suites[suiteName]
if suite == nil then
	pcall(task.cancel, watchdogThread)
	finalizeOnce(
		AcceptanceTestUtils.FailResult(suiteName, "suite routing", `Unknown Stage 5 suite {suiteName}`, nil),
		"unknown suite"
	)
	return
end
local recorder = AcceptanceTestUtils.NewRecorder(suiteName)
local ok, value = xpcall(function(): Result
	coordination = AcceptanceTestUtils.CreateCoordination()
	local metrics = suite.Run(recorder, coordination :: AcceptanceTestUtils.Coordination, testArgs)
	return recorder:Finish(metrics)
end, function(errorValue: unknown): { message: string, traceback: string }
	return { message = tostring(errorValue), traceback = debug.traceback(tostring(errorValue), 2) }
end)
pcall(task.cancel, watchdogThread)
if ok then
	finalizeOnce(value :: Result, "suite completed")
else
	local detail = value :: { message: string, traceback: string }
	finalizeOnce(
		AcceptanceTestUtils.FailResult(suiteName, "suite exception", detail.message, detail.traceback),
		"suite exception"
	)
end
