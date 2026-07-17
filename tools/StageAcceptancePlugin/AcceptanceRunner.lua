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
}

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

function AcceptanceRunner._runDefinition(self: Runner, definition: Definition, fullStarted: number?): (Result, boolean)
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
			or (fullStarted ~= nil and fullElapsed >= FULL_TIMEOUT_SECONDS)
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
	if definition.expectedSuite == "Stage4Runtime" and result.total < 57 then
		local failure = AcceptanceTypes.FailureResult(
			definition.expectedSuite,
			"runtime test count gate",
			`Only {result.total} runtime tests executed; Stage 4 requires at least 57`,
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
			local result, continueRun = self:_runDefinition(definition, fullStarted)
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
	end
	local definition = DEFINITIONS[runName]
	if definition == nil then
		return AcceptanceTypes.FailureResult("Stage4Plugin", "suite routing", `Unknown run {runName}`, nil)
	end
	local result = self:_runDefinition(definition, nil)
	return result
end

return table.freeze(AcceptanceRunner)
