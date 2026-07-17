--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local AcceptanceRunGuard = require(script.Parent.AcceptanceRunGuard)
local AcceptanceRunner = require(script.Parent.AcceptanceRunner)
local AcceptanceTypes = require(script.Parent.AcceptanceTypes)
local TestHarness = require(ServerScriptService.Stage2Tests.TestHarness)

type Result = AcceptanceTypes.Result
type Runner = AcceptanceRunner.Runner
type Executor = AcceptanceRunner.Executor
type TestCase = TestHarness.TestCase
type FakeData = {
	now: number,
	executions: { string },
	barriers: { string },
	durations: { [string]: number },
	nilSuite: string?,
	exceptionSuite: string?,
	timeoutSuite: string?,
	barrierFailureAt: number?,
}

local FakeExecutor = {}
FakeExecutor.__index = FakeExecutor
type Fake = typeof(setmetatable({} :: FakeData, FakeExecutor))

local function passingResult(suite: string): Result
	local total = if suite == "Stage4Runtime" then 57 else 1
	return {
		ok = true,
		suite = suite,
		total = total,
		passed = total,
		failed = 0,
		skipped = 0,
		durationSeconds = 1,
		failures = {},
		metrics = {},
	}
end

local function suiteFromArgs(args: unknown): string
	if args == "Stage4RuntimeGate" then
		return "Stage4Runtime"
	end
	assert(typeof(args) == "table", "Expected table test args")
	local suite = (args :: { [string]: unknown }).suite
	assert(typeof(suite) == "string", "Expected suite test arg")
	return suite
end

function FakeExecutor.new(): Fake
	return setmetatable({
		now = 0,
		executions = {},
		barriers = {},
		durations = {},
		nilSuite = nil,
		exceptionSuite = nil,
		timeoutSuite = nil,
		barrierFailureAt = nil,
	}, FakeExecutor)
end

function FakeExecutor.Clock(self: Fake): number
	return self.now
end

function FakeExecutor.IsEditModeActive(_self: Fake): boolean
	return true
end

function FakeExecutor.WaitForEditMode(
	self: Fake,
	_timeoutSeconds: number,
	_stabilizationSeconds: number,
	context: string
): (boolean, string?)
	table.insert(self.barriers, context)
	if self.barrierFailureAt == #self.barriers then
		return false, `synthetic barrier timeout: {context}`
	end
	return true, nil
end

function FakeExecutor._execute(self: Fake, args: unknown): unknown
	local suite = suiteFromArgs(args)
	table.insert(self.executions, suite)
	self.now += self.durations[suite] or 1
	if self.exceptionSuite == suite then
		error(`synthetic executor exception: {suite}`)
	end
	if self.nilSuite == suite then
		return nil
	end
	if self.timeoutSuite == suite then
		local result = AcceptanceTypes.FailureResult(suite, "acceptance watchdog", "synthetic timeout", nil)
		result.metrics.watchdogExpired = true
		return result
	end
	return passingResult(suite)
end

function FakeExecutor.ExecutePlayModeAsync(self: Fake, args: unknown): unknown
	return self:_execute(args)
end

function FakeExecutor.ExecuteMultiplayerTestAsync(self: Fake, _numPlayers: number, args: unknown): unknown
	return self:_execute(args)
end

local function newRunner(fake: Fake): Runner
	return AcceptanceRunner.new((fake :: unknown) :: Executor)
end

local function fullOrderAndBarrierTest()
	local fake = FakeExecutor.new()
	local result = newRunner(fake):Run("Full")
	TestHarness.assertTrue(result.ok)
	TestHarness.assertEqual(
		table.concat(fake.executions, ","),
		"Stage4Runtime,Stage4Solo,Stage4Multiplayer3,Stage4Performance6"
	)
	TestHarness.assertEqual(
		table.concat(fake.barriers, ","),
		table.concat({
			"Stage4Runtime before Execute",
			"Stage4Runtime after Execute",
			"Stage4Solo before Execute",
			"Stage4Solo after Execute",
			"Stage4Multiplayer3 before Execute",
			"Stage4Multiplayer3 after Execute",
			"Stage4Performance6 before Execute",
			"Stage4Performance6 after Execute",
		}, ",")
	)
end

local function nilIsInfrastructureFailureTest()
	local fake = FakeExecutor.new()
	fake.nilSuite = "Stage4Performance6"
	local result = newRunner(fake):Run("Performance6")
	TestHarness.assertTrue(not result.ok)
	TestHarness.assertEqual(result.failures[1].test, "StudioTestService result validation")
	TestHarness.assertTrue(result.metrics.infrastructureFailure == true)
	TestHarness.assertTrue(result.metrics.invalidResult == true)
end

local function executorExceptionStopsFullTest()
	local fake = FakeExecutor.new()
	fake.exceptionSuite = "Stage4Multiplayer3"
	local result = newRunner(fake):Run("Full")
	TestHarness.assertTrue(not result.ok)
	TestHarness.assertEqual(table.concat(fake.executions, ","), "Stage4Runtime,Stage4Solo,Stage4Multiplayer3")
	TestHarness.assertTrue(result.metrics["Stage4Multiplayer3.infrastructureFailure"] == true)
end

local function suiteTimeoutStopsFullTest()
	local fake = FakeExecutor.new()
	fake.timeoutSuite = "Stage4Solo"
	local result = newRunner(fake):Run("Full")
	TestHarness.assertTrue(not result.ok)
	TestHarness.assertEqual(table.concat(fake.executions, ","), "Stage4Runtime,Stage4Solo")
	TestHarness.assertTrue(result.metrics["Stage4Solo.watchdogExpired"] == true)
end

local function fullDeadlineDoesNotCutActiveLastSuiteTest()
	local fake = FakeExecutor.new()
	fake.durations.Stage4Runtime = 80
	fake.durations.Stage4Solo = 100
	fake.durations.Stage4Multiplayer3 = 180
	fake.durations.Stage4Performance6 = 240
	local result = newRunner(fake):Run("Full")
	TestHarness.assertTrue(result.ok)
	TestHarness.assertEqual(#fake.executions, 4)
	TestHarness.assertEqual(result.durationSeconds, 600)
end

local function aggregatePreservesCompletedSuitesTest()
	local fake = FakeExecutor.new()
	fake.nilSuite = "Stage4Multiplayer3"
	local result = newRunner(fake):Run("Full")
	TestHarness.assertTrue(not result.ok)
	TestHarness.assertEqual(result.total, 59)
	TestHarness.assertEqual(result.passed, 58)
	TestHarness.assertEqual(result.failed, 1)
	TestHarness.assertEqual(table.concat(fake.executions, ","), "Stage4Runtime,Stage4Solo,Stage4Multiplayer3")
	TestHarness.assertEqual(result.failures[1].test, "Stage4Multiplayer3 :: StudioTestService result validation")
end

local function barrierTimeoutStopsBeforeExecuteTest()
	local fake = FakeExecutor.new()
	fake.barrierFailureAt = 3
	local result = newRunner(fake):Run("Full")
	TestHarness.assertTrue(not result.ok)
	TestHarness.assertEqual(table.concat(fake.executions, ","), "Stage4Runtime")
	TestHarness.assertTrue(result.metrics["Stage4Solo.editModeBarrierFailed"] == true)
end

local function assertButtonsReenabled(callback: () -> unknown): (boolean, unknown)
	local enabled = true
	local guard = AcceptanceRunGuard.new(function(value: boolean)
		enabled = value
	end)
	TestHarness.assertTrue(guard:Begin())
	TestHarness.assertTrue(not enabled)
	local ok, value = guard:RunActive(callback)
	TestHarness.assertTrue(enabled)
	TestHarness.assertTrue(not guard:IsRunning())
	return ok, value
end

local function buttonsReenabledAfterSuccessTest()
	local ok = assertButtonsReenabled(function(): unknown
		return passingResult("Stage4Solo")
	end)
	TestHarness.assertTrue(ok)
end

local function buttonsReenabledAfterNilTest()
	local ok, value = assertButtonsReenabled(function(): unknown
		return nil
	end)
	TestHarness.assertTrue(ok)
	TestHarness.assertEqual(value, nil)
end

local function buttonsReenabledAfterExceptionTest()
	local ok = assertButtonsReenabled(function(): unknown
		error("synthetic plugin exception")
	end)
	TestHarness.assertTrue(not ok)
end

local function buttonsReenabledAfterTimeoutTest()
	local ok, value = assertButtonsReenabled(function(): unknown
		local result = AcceptanceTypes.FailureResult("Stage4Solo", "acceptance watchdog", "synthetic timeout", nil)
		result.metrics.watchdogExpired = true
		return result
	end)
	TestHarness.assertTrue(ok)
	TestHarness.assertTrue((value :: Result).metrics.watchdogExpired == true)
end

local AcceptanceRunnerSpec = {}

function AcceptanceRunnerSpec.tests(): { TestCase }
	return {
		{ name = "acceptance plugin Full preserves suite order and Edit Mode barriers", run = fullOrderAndBarrierTest },
		{
			name = "acceptance plugin treats nil StudioTestService result as infrastructure FAIL",
			run = nilIsInfrastructureFailureTest,
		},
		{
			name = "acceptance plugin executor exception stops Full before the next suite",
			run = executorExceptionStopsFullTest,
		},
		{ name = "acceptance plugin suite timeout stops Full before the next suite", run = suiteTimeoutStopsFullTest },
		{
			name = "acceptance plugin Full deadline never cuts a completing last suite",
			run = fullDeadlineDoesNotCutActiveLastSuiteTest,
		},
		{
			name = "acceptance plugin aggregate preserves completed suite results",
			run = aggregatePreservesCompletedSuitesTest,
		},
		{
			name = "acceptance plugin Edit Mode timeout stops before Execute",
			run = barrierTimeoutStopsBeforeExecuteTest,
		},
		{ name = "acceptance plugin buttons re-enable after success", run = buttonsReenabledAfterSuccessTest },
		{ name = "acceptance plugin buttons re-enable after nil", run = buttonsReenabledAfterNilTest },
		{ name = "acceptance plugin buttons re-enable after exception", run = buttonsReenabledAfterExceptionTest },
		{ name = "acceptance plugin buttons re-enable after timeout", run = buttonsReenabledAfterTimeoutTest },
	}
end

return table.freeze(AcceptanceRunnerSpec)
