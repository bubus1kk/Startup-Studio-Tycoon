--!strict

export type TestCase = {
	name: string,
	run: () -> (),
}

local TestHarness = {}

local function tracebackError(errorValue: unknown): string
	return debug.traceback(tostring(errorValue), 2)
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

function TestHarness.run(testCases: { TestCase })
	local failures: { string } = {}
	for _, testCase in testCases do
		local ok, cause = xpcall(testCase.run, tracebackError)
		if ok then
			print(`[Stage2Test] PASS {testCase.name}`)
		else
			table.insert(failures, `{testCase.name}: {cause}`)
			warn(`[Stage2Test] FAIL {testCase.name}: {cause}`)
		end
	end

	if #failures > 0 then
		error(`Stage 2 runtime tests failed ({#failures}):\n{table.concat(failures, "\n")}`)
	end

	print(`[Stage2Test] PASS all {#testCases} runtime tests`)
end

return table.freeze(TestHarness)
