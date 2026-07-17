--!strict

export type MetricValue = number | string | boolean
export type Metrics = { [string]: MetricValue }
export type Failure = {
	test: string,
	message: string,
	traceback: string?,
}
export type Result = {
	ok: boolean,
	suite: string,
	total: number,
	passed: number,
	failed: number,
	skipped: number,
	durationSeconds: number,
	failures: { Failure },
	metrics: Metrics,
}

local AcceptanceTypes = {}

local function isNonNegativeInteger(value: unknown): boolean
	return typeof(value) == "number" and value >= 0 and value % 1 == 0
end

function AcceptanceTypes.Validate(value: unknown, expectedSuite: string?): (boolean, Result?, string?)
	if typeof(value) ~= "table" then
		return false, nil, if value == nil then "StudioTestService returned nil" else "Result is not a table"
	end
	local candidate = value :: { [string]: unknown }
	if typeof(candidate.ok) ~= "boolean" then
		return false, nil, "Result.ok must be boolean"
	end
	if typeof(candidate.suite) ~= "string" or candidate.suite == "" then
		return false, nil, "Result.suite must be a non-empty string"
	end
	if expectedSuite ~= nil and candidate.suite ~= expectedSuite then
		return false, nil, `Expected suite {expectedSuite}, got {candidate.suite}`
	end
	local suite = candidate.suite :: string
	for _, field in { "total", "passed", "failed", "skipped" } do
		if not isNonNegativeInteger(candidate[field]) then
			return false, nil, `Result.{field} must be a non-negative integer`
		end
	end
	if typeof(candidate.durationSeconds) ~= "number" or candidate.durationSeconds < 0 then
		return false, nil, "Result.durationSeconds must be a non-negative number"
	end
	local total = candidate.total :: number
	local passed = candidate.passed :: number
	local failed = candidate.failed :: number
	local skipped = candidate.skipped :: number
	local durationSeconds = candidate.durationSeconds :: number
	if total ~= passed + failed + skipped then
		return false, nil, "Result counts do not add up to total"
	end
	if typeof(candidate.failures) ~= "table" then
		return false, nil, "Result.failures must be an array"
	end
	local failures: { Failure } = {}
	for _, failureValue in candidate.failures do
		if typeof(failureValue) ~= "table" then
			return false, nil, "Each failure must be a table"
		end
		local failure = failureValue :: { [string]: unknown }
		if typeof(failure.test) ~= "string" or typeof(failure.message) ~= "string" then
			return false, nil, "Each failure needs string test and message fields"
		end
		if failure.traceback ~= nil and typeof(failure.traceback) ~= "string" then
			return false, nil, "Failure.traceback must be string or nil"
		end
		table.insert(failures, {
			test = failure.test,
			message = failure.message,
			traceback = failure.traceback :: string?,
		})
	end
	if #failures ~= failed then
		return false, nil, "Result.failed must match the number of failure records"
	end
	if typeof(candidate.metrics) ~= "table" then
		return false, nil, "Result.metrics must be a table"
	end
	local metrics: Metrics = {}
	for key, metricValue in candidate.metrics do
		if typeof(key) ~= "string" then
			return false, nil, "Metric keys must be strings"
		end
		local valueType = typeof(metricValue)
		if valueType ~= "number" and valueType ~= "string" and valueType ~= "boolean" then
			return false, nil, `Metric {key} has unsupported type {valueType}`
		end
		metrics[key] = metricValue :: MetricValue
	end
	local result: Result = {
		ok = candidate.ok :: boolean,
		suite = suite,
		total = total,
		passed = passed,
		failed = failed,
		skipped = skipped,
		durationSeconds = durationSeconds,
		failures = failures,
		metrics = metrics,
	}
	if result.ok ~= (result.failed == 0) then
		return false, nil, "Result.ok must be true exactly when failed is zero"
	end
	return true, result, nil
end

function AcceptanceTypes.FailureResult(suite: string, test: string, message: string, traceback: string?): Result
	return {
		ok = false,
		suite = suite,
		total = 1,
		passed = 0,
		failed = 1,
		skipped = 0,
		durationSeconds = 0,
		failures = {
			{
				test = test,
				message = message,
				traceback = traceback,
			},
		},
		metrics = {},
	}
end

function AcceptanceTypes.Status(result: Result): string
	if not result.ok or result.failed > 0 then
		return "FAIL"
	elseif result.passed == 0 and result.skipped > 0 then
		return "SKIPPED"
	end
	return "PASS"
end

function AcceptanceTypes.Aggregate(suite: string, results: { Result }): Result
	local aggregate: Result = {
		ok = true,
		suite = suite,
		total = 0,
		passed = 0,
		failed = 0,
		skipped = 0,
		durationSeconds = 0,
		failures = {},
		metrics = {},
	}
	for _, result in results do
		aggregate.total += result.total
		aggregate.passed += result.passed
		aggregate.failed += result.failed
		aggregate.skipped += result.skipped
		aggregate.durationSeconds += result.durationSeconds
		for _, failure in result.failures do
			table.insert(aggregate.failures, {
				test = `{result.suite} :: {failure.test}`,
				message = failure.message,
				traceback = failure.traceback,
			})
		end
		for key, metricValue in result.metrics do
			aggregate.metrics[`{result.suite}.{key}`] = metricValue
		end
	end
	aggregate.ok = aggregate.failed == 0
	return aggregate
end

function AcceptanceTypes.Format(result: Result): string
	local lines = {
		`[{AcceptanceTypes.Status(result)}] {result.suite}`,
		string.format("Duration: %.3fs", result.durationSeconds),
		`Counts: total={result.total}, passed={result.passed}, failed={result.failed}, skipped={result.skipped}`,
	}
	if #result.failures > 0 then
		table.insert(lines, "Failures:")
		for index, failure in result.failures do
			table.insert(lines, `{index}. {failure.test}: {failure.message}`)
			if failure.traceback ~= nil and failure.traceback ~= "" then
				table.insert(lines, failure.traceback)
			end
		end
	end
	local metricKeys = {}
	for key in result.metrics do
		table.insert(metricKeys, key)
	end
	table.sort(metricKeys)
	if #metricKeys > 0 then
		table.insert(lines, "Metrics:")
		for _, key in metricKeys do
			table.insert(lines, `{key}={tostring(result.metrics[key])}`)
		end
	end
	return table.concat(lines, "\n")
end

return table.freeze(AcceptanceTypes)
