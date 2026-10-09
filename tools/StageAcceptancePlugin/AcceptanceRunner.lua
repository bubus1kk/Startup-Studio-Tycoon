--!strict

local StudioTestService = game:GetService("StudioTestService")

local AcceptanceTypes = require(script.Parent.AcceptanceTypes)

type Result = AcceptanceTypes.Result
type Definition = {
	displayName: string,
	expectedSuite: string,
	players: number?,
	args: unknown,
	timeoutSeconds: number,
}

export type Executor = {
	Clock: (self: Executor) -> number,
	IsEditModeActive: (self: Executor) -> boolean,
	WaitForEditMode: (
		self: Executor,
		timeoutSeconds: number,
		stabilizationSeconds: number,
		context: string
	) -> (boolean, string?),
	ExecutePlayModeAsync: (self: Executor, args: unknown) -> unknown,
	ExecuteMultiplayerTestAsync: (self: Executor, numPlayers: number, args: unknown) -> unknown,
}

type RunnerData = {
	_executor: Executor,
}

local AcceptanceRunner = {}
AcceptanceRunner.__index = AcceptanceRunner
export type Runner = typeof(setmetatable({} :: RunnerData, AcceptanceRunner))

local EDIT_MODE_TIMEOUT_SECONDS = 30
local EDIT_MODE_STABILIZATION_SECONDS = 0.5
local EDIT_MODE_POLL_SECONDS = 0.05
local FULL_TIMEOUT_SECONDS = 480
local STAGE5_FULL_SAFETY_MARGIN_SECONDS = 300

local DEFINITIONS: { [string]: Definition } = {
	Runtime = {
		displayName = "Stage 4 Runtime",
		expectedSuite = "Stage4Runtime",
		players = nil,
		args = "Stage4RuntimeGate",
		timeoutSeconds = 90,
	},
	Solo = {
		displayName = "Stage 4 Solo",
		expectedSuite = "Stage4Solo",
		players = nil,
		args = { stage = 4, suite = "Stage4Solo", watchdogSeconds = 120 },
		timeoutSeconds = 120,
	},
	Multiplayer3 = {
		displayName = "Stage 4 Multiplayer 3",
		expectedSuite = "Stage4Multiplayer3",
		players = 3,
		args = { stage = 4, suite = "Stage4Multiplayer3", watchdogSeconds = 180 },
		timeoutSeconds = 180,
	},
	Performance6 = {
		displayName = "Stage 4 Performance 6",
		expectedSuite = "Stage4Performance6",
		players = 6,
		args = { stage = 4, suite = "Stage4Performance6", watchdogSeconds = 240 },
		timeoutSeconds = 240,
	},
	Stage5Runtime = {
		displayName = "Stage 5 Runtime",
		expectedSuite = "Stage5Runtime",
		players = nil,
		args = "Stage5RuntimeGate",
		timeoutSeconds = 120,
	},
	Stage5Solo = {
		displayName = "Stage 5 Solo",
		expectedSuite = "Stage5Solo",
		players = nil,
		args = { stage = 5, suite = "Stage5Solo", watchdogSeconds = 180 },
		timeoutSeconds = 180,
	},
	Stage5Multiplayer3 = {
		displayName = "Stage 5 Multiplayer 3",
		expectedSuite = "Stage5Multiplayer3",
		players = 3,
		args = { stage = 5, suite = "Stage5Multiplayer3", watchdogSeconds = 240 },
		timeoutSeconds = 240,
	},
	Stage5Npc10 = {
		displayName = "Stage 5 NPC 10",
		expectedSuite = "Stage5Npc10",
		players = nil,
		args = { stage = 5, suite = "Stage5Npc10", employeeCount = 10, watchdogSeconds = 300 },
		timeoutSeconds = 300,
	},
	Stage5Npc30 = {
		displayName = "Stage 5 NPC 30",
		expectedSuite = "Stage5Npc30",
		players = nil,
		args = { stage = 5, suite = "Stage5Npc30", employeeCount = 30, watchdogSeconds = 480 },
		timeoutSeconds = 480,
	},
	Stage5BlockedPath = {
		displayName = "Stage 5 Blocked Path",
		expectedSuite = "Stage5BlockedPath",
		players = nil,
		args = { stage = 5, suite = "Stage5BlockedPath", watchdogSeconds = 180 },
		timeoutSeconds = 180,
	},
}

local STAGE5_FULL_SEQUENCE = {
	"Runtime",
	"Solo",
	"Multiplayer3",
	"Performance6",
	"Stage5Runtime",
	"Stage5Solo",
	"Stage5Multiplayer3",
	"Stage5Npc10",
	"Stage5Npc30",
	"Stage5BlockedPath",
}

local function sumSuiteTimeouts(sequence: { string }): number
	local total = 0
	for _, name in sequence do
		total += assert(DEFINITIONS[name], `Missing suite definition {name}`).timeoutSeconds
	end
	return total
end

local STAGE5_FULL_SUITE_TIMEOUT_SECONDS = sumSuiteTimeouts(STAGE5_FULL_SEQUENCE)
local STAGE5_FULL_EDIT_MODE_BARRIER_BUDGET_SECONDS = #STAGE5_FULL_SEQUENCE * 2 * EDIT_MODE_TIMEOUT_SECONDS
local STAGE5_FULL_TIMEOUT_SECONDS = STAGE5_FULL_SUITE_TIMEOUT_SECONDS
	+ STAGE5_FULL_EDIT_MODE_BARRIER_BUDGET_SECONDS
	+ STAGE5_FULL_SAFETY_MARGIN_SECONDS

local function setStage5FullMetrics(result: Result)
	result.metrics.fullSuiteTimeoutSeconds = STAGE5_FULL_SUITE_TIMEOUT_SECONDS
	result.metrics.fullEditModeBarrierBudgetSeconds = STAGE5_FULL_EDIT_MODE_BARRIER_BUDGET_SECONDS
	result.metrics.fullSafetyMarginSeconds = STAGE5_FULL_SAFETY_MARGIN_SECONDS
	result.metrics.fullTimeoutSeconds = STAGE5_FULL_TIMEOUT_SECONDS
end

local DEFAULT_EXECUTOR: Executor = {
	Clock = function(_self: Executor): number
		return os.clock()
	end,
	IsEditModeActive = function(_self: Executor): boolean
		return StudioTestService.EditModeActive
	end,
	WaitForEditMode = function(
		self: Executor,
		timeoutSeconds: number,
		stabilizationSeconds: number,
		context: string
	): (boolean, string?)
		local started = self:Clock()
		while not self:IsEditModeActive() do
			local elapsed = self:Clock() - started
			if elapsed >= timeoutSeconds then
				return false,
					string.format(
						"Timed out after %.3fs waiting for Edit Mode (%s); EditModeActive=false",
						elapsed,
						context
					)
			end
			task.wait(math.min(EDIT_MODE_POLL_SECONDS, timeoutSeconds - elapsed))
		end

		local stabilizationStarted = self:Clock()
		while self:Clock() - stabilizationStarted < stabilizationSeconds do
			local elapsed = self:Clock() - started
			if elapsed >= timeoutSeconds then
				return false,
					string.format(
						"Timed out after %.3fs stabilizing Edit Mode (%s); EditModeActive=%s",
						elapsed,
						context,
						tostring(self:IsEditModeActive())
					)
			end
			if not self:IsEditModeActive() then
				stabilizationStarted = self:Clock()
			end
			task.wait(EDIT_MODE_POLL_SECONDS)
		end
		return true, nil
	end,
	ExecutePlayModeAsync = function(_self: Executor, args: unknown): unknown
		return StudioTestService:ExecutePlayModeAsync(args)
	end,
	ExecuteMultiplayerTestAsync = function(_self: Executor, numPlayers: number, args: unknown): unknown
		return StudioTestService:ExecuteMultiplayerTestAsync(numPlayers, args)
	end,
}

local function failureResult(
	suite: string,
	test: string,
	message: string,
	traceback: string?,
	durationSeconds: number,
	metricName: string
): Result
	local result = AcceptanceTypes.FailureResult(suite, test, message, traceback)
	result.durationSeconds = durationSeconds
	result.metrics.infrastructureFailure = true
	result.metrics[metricName] = true
	return result
end

local function shouldContinue(result: Result): boolean
	return result.metrics.infrastructureFailure ~= true and result.metrics.watchdogExpired ~= true
end

function AcceptanceRunner.new(executor: Executor?): Runner
	return setmetatable({
		_executor = executor or DEFAULT_EXECUTOR,
	}, AcceptanceRunner)
end

function AcceptanceRunner._runDefinition(
	self: Runner,
	definition: Definition,
	fullStarted: number?,
	fullTimeoutSeconds: number?
): (Result, boolean)
	local executor = self._executor
	local suiteStarted = executor:Clock()
	local beforeContext = `{definition.expectedSuite} before Execute`
	print(`[StageAcceptancePlugin] START suite={definition.expectedSuite}`)
	local editReady, editMessage =
		executor:WaitForEditMode(EDIT_MODE_TIMEOUT_SECONDS, EDIT_MODE_STABILIZATION_SECONDS, beforeContext)

	print(`[StageAcceptancePlugin] editModeActive={executor:IsEditModeActive()}`)
	print(`[StageAcceptancePlugin] timeoutSeconds={definition.timeoutSeconds}`)
	if not editReady then
		local elapsed = executor:Clock() - suiteStarted
		local failure = failureResult(
			definition.expectedSuite,
			"Edit Mode barrier before Execute",
			editMessage or `Edit Mode barrier failed ({beforeContext})`,
			nil,
			elapsed,
			"editModeBarrierFailed"
		)
		warn(AcceptanceTypes.Format(failure))
		return failure, false
	end

	local executeOk, rawResult = xpcall(function(): unknown
		if definition.players ~= nil then
			return executor:ExecuteMultiplayerTestAsync(definition.players, definition.args)
		end
		return executor:ExecutePlayModeAsync(definition.args)
	end, function(errorValue: unknown): { message: string, traceback: string }
		return {
			message = tostring(errorValue),
			traceback = debug.traceback(tostring(errorValue), 2),
		}
	end)

	local returnedElapsed = executor:Clock() - suiteStarted
	print(
		string.format(
			"[StageAcceptancePlugin] RETURN suite=%s elapsedSeconds=%.3f",
			definition.expectedSuite,
			returnedElapsed
		)
	)
	print(`[StageAcceptancePlugin] resultType={if executeOk then typeof(rawResult) else "exception"}`)

	local afterContext = `{definition.expectedSuite} after Execute`
	local editRestored, restoreMessage =
		executor:WaitForEditMode(EDIT_MODE_TIMEOUT_SECONDS, EDIT_MODE_STABILIZATION_SECONDS, afterContext)
	local elapsed = executor:Clock() - suiteStarted
	if not editRestored then
		local failure = failureResult(
			definition.expectedSuite,
			"Edit Mode barrier after Execute",
			restoreMessage or `Edit Mode barrier failed ({afterContext})`,
			nil,
			elapsed,
			"editModeBarrierFailed"
		)
		warn(AcceptanceTypes.Format(failure))
		return failure, false
	end

	if not executeOk then
		local detail = rawResult :: { message: string, traceback: string }
		local failure = failureResult(
			definition.expectedSuite,
			"plugin call",
			detail.message,
			detail.traceback,
			elapsed,
			"pluginCallFailed"
		)
		warn(AcceptanceTypes.Format(failure))
		return failure, false
	end

	local valid, result, message = AcceptanceTypes.Validate(rawResult, definition.expectedSuite)
	if not valid or result == nil then
		local fullElapsed = if fullStarted ~= nil then executor:Clock() - fullStarted else elapsed
		local watchdogExpired = elapsed >= definition.timeoutSeconds
			or (fullStarted ~= nil and fullElapsed >= (fullTimeoutSeconds or FULL_TIMEOUT_SECONDS))
		warn(`[StageAcceptancePlugin] NIL_OR_INVALID_RESULT suite={definition.expectedSuite}`)
		warn(string.format("[StageAcceptancePlugin] elapsedSeconds=%.3f", elapsed))
		warn(`[StageAcceptancePlugin] editModeActive={executor:IsEditModeActive()}`)
		warn(string.format("[StageAcceptancePlugin] fullElapsedSeconds=%.3f", fullElapsed))
		warn(`[StageAcceptancePlugin] watchdogExpired={watchdogExpired}`)
		local failure = failureResult(
			definition.expectedSuite,
			"StudioTestService result validation",
			message or "Unknown invalid result",
			nil,
			elapsed,
			"invalidResult"
		)
		failure.metrics.watchdogExpired = watchdogExpired
		warn(AcceptanceTypes.Format(failure))
		return failure, false
	end
	if definition.expectedSuite == "Stage4Runtime" and result.total < 72 then
		local failure = AcceptanceTypes.FailureResult(
			definition.expectedSuite,
			"runtime test count gate",
			`Only {result.total} runtime tests executed; Stage 4 requires at least 72`,
			nil
		)
		failure.durationSeconds = elapsed
		failure.metrics.runtimeTestsExecuted = result.total
		warn(AcceptanceTypes.Format(failure))
		return failure, true
	end
	if definition.expectedSuite == "Stage5Runtime" and result.total < 98 then
		local failure = AcceptanceTypes.FailureResult(
			definition.expectedSuite,
			"runtime test count gate",
			`Only {result.total} runtime tests executed; Stage 5 requires at least 98`,
			nil
		)
		failure.durationSeconds = elapsed
		failure.metrics.runtimeTestsExecuted = result.total
		warn(AcceptanceTypes.Format(failure))
		return failure, true
	end
	print(AcceptanceTypes.Format(result))
	return result, shouldContinue(result)
end

function AcceptanceRunner.Run(self: Runner, runName: string): Result
	if runName == "Full" then
		local results: { Result } = {}
		local fullStarted = self._executor:Clock()
		for index, name in { "Runtime", "Solo", "Multiplayer3", "Performance6" } do
			local fullElapsed = self._executor:Clock() - fullStarted
			if index > 1 and fullElapsed >= FULL_TIMEOUT_SECONDS then
				local failure = failureResult(
					"Stage4Full",
					"Full orchestration timeout",
					`Full orchestration exceeded {FULL_TIMEOUT_SECONDS}s before starting {name}; no active suite was interrupted`,
					nil,
					fullElapsed,
					"fullWatchdogExpired"
				)
				failure.metrics.fullTimeoutSeconds = FULL_TIMEOUT_SECONDS
				table.insert(results, failure)
				break
			end

			local definition = assert(DEFINITIONS[name], `Missing suite definition {name}`)
			local result, continueRun = self:_runDefinition(definition, fullStarted, FULL_TIMEOUT_SECONDS)
			table.insert(results, result)
			if not continueRun then
				break
			end
		end
		local aggregate = AcceptanceTypes.Aggregate("Stage4Full", results)
		aggregate.durationSeconds = self._executor:Clock() - fullStarted
		aggregate.metrics.fullElapsedSeconds = aggregate.durationSeconds
		aggregate.metrics.fullTimeoutSeconds = FULL_TIMEOUT_SECONDS
		print(AcceptanceTypes.Format(aggregate))
		return aggregate
	elseif runName == "Stage5Full" then
		local results: { Result } = {}
		local fullStarted = self._executor:Clock()
		for index, name in STAGE5_FULL_SEQUENCE do
			local fullElapsed = self._executor:Clock() - fullStarted
			if index > 1 and fullElapsed >= STAGE5_FULL_TIMEOUT_SECONDS then
				local failure = failureResult(
					"Stage5Full",
					"Full orchestration timeout",
					`Stage 5 Full exceeded {STAGE5_FULL_TIMEOUT_SECONDS}s before starting {name}`,
					nil,
					fullElapsed,
					"fullWatchdogExpired"
				)
				setStage5FullMetrics(failure)
				table.insert(results, failure)
				break
			end
			local definition = assert(DEFINITIONS[name], `Missing suite definition {name}`)
			local result, continueRun = self:_runDefinition(definition, fullStarted, STAGE5_FULL_TIMEOUT_SECONDS)
			table.insert(results, result)
			if not continueRun then
				break
			end
		end
		local aggregate = AcceptanceTypes.Aggregate("Stage5Full", results)
		aggregate.durationSeconds = self._executor:Clock() - fullStarted
		aggregate.metrics.fullElapsedSeconds = aggregate.durationSeconds
		setStage5FullMetrics(aggregate)
		print(AcceptanceTypes.Format(aggregate))
		return aggregate
	end
	local definition = DEFINITIONS[runName]
	if definition == nil then
		return AcceptanceTypes.FailureResult("Stage4Plugin", "suite routing", `Unknown run {runName}`, nil)
	end
	local result = self:_runDefinition(definition, nil, nil)
	return result
end

return table.freeze(AcceptanceRunner)
