--!strict

export type TestCase = {
	name: string,
	run: () -> (),
}

export type Failure = {
	test: string,
	message: string,
	traceback: string?,
}

export type Report = {
	total: number,
	passed: number,
	failed: number,
	skipped: number,
	durationSeconds: number,
	failures: { Failure },
}

local TestHarness = {}

type ErrorDetail = {
	message: string,
	traceback: string,
}

local function tracebackError(errorValue: unknown): ErrorDetail
	return {
		message = tostring(errorValue),
		traceback = debug.traceback(tostring(errorValue), 2),
	}
end

function TestHarness.assertTrue(value: boolean, message: string?)
	if not value then
		error(message or "Expected value to be true", 2)
	end
end

function TestHarness.assertEqual<T>(actual: T, expected: T, message: string?)
	if actual ~= expected then
		error(message or `Expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function TestHarness.runAndCollect(testCases: { TestCase }): Report
	local started = os.clock()
	local failures: { Failure } = {}
	local passed = 0

	for _, testCase in testCases do
		local ok, causeValue = xpcall(testCase.run, tracebackError)

		if ok then
<<<<<<< HEAD
			passed += 1
			print(`[Stage4Test] PASS {testCase.name}`)
		else
			local cause = causeValue :: ErrorDetail
			table.insert(failures, {
				test = testCase.name,
				message = cause.message,
				traceback = cause.traceback,
			})
			warn(`[Stage4Test] FAIL {testCase.name}: {cause.traceback}`)
		end
	end

	local report: Report = {
		total = #testCases,
		passed = passed,
		failed = #failures,
		skipped = 0,
		durationSeconds = os.clock() - started,
		failures = failures,
	}
	if report.failed == 0 then
		print(`[Stage4Test] PASS all {report.total} runtime tests`)
=======
			print(`[Stage4Test] PASS {testCase.name}`)
		else
			table.insert(failures, `{testCase.name}: {cause}`)
			warn(`[Stage4Test] FAIL {testCase.name}: {cause}`)
		end
	end

	if #failures > 0 then
		error(`Stage 4 runtime tests failed ({#failures}):\n{table.concat(failures, "\n")}`)
>>>>>>> 94818332a6f52a94409e8f7b68c861c2ad26d4b6
	end
	return report
end

<<<<<<< HEAD
function TestHarness.run(testCases: { TestCase }): Report
	local report = TestHarness.runAndCollect(testCases)

	if report.failed > 0 then
		local messages = {}
		for _, failure in report.failures do
			table.insert(messages, `{failure.test}: {failure.message}`)
		end
		error(`Stage 4 runtime tests failed ({report.failed}):\n{table.concat(messages, "\n")}`)
	end
	return report
=======
	print(`[Stage4Test] PASS all {#testCases} runtime tests`)
>>>>>>> 94818332a6f52a94409e8f7b68c861c2ad26d4b6
end

return table.freeze(TestHarness)
