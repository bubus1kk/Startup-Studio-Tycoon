--!strict

local TestHarness = require(script.Parent.Parent.TestHarness)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)

type TestCase = TestHarness.TestCase
local OfficeFullLayoutPerformanceSpec = {}

type Fixture = OfficeTestUtils.Fixture

local INSTANCE_BUDGET_PER_PLOT = 450
local BASE_PART_BUDGET_PER_PLOT = 300
local TOTAL_INSTANCE_BUDGET = 2700
local TOTAL_BASE_PART_BUDGET = 1800
local REBUILD_TIME_BUDGET_SECONDS = 5

local function countInstances(root: Instance): (number, number)
	local instances = 1
	local baseParts = if root:IsA("BasePart") then 1 else 0
	for _, descendant in root:GetDescendants() do
		instances += 1
		if descendant:IsA("BasePart") then
			baseParts += 1
		end
	end
	return instances, baseParts
end

local function sixPlotMaximumContentRebuildTest()
	local fixtures: { Fixture } = {}
	local rebuildDurations: { number } = {}
	for index = 1, 6 do
		local fixture = OfficeTestUtils.createFixture(6000 + index, nil)
		local context = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
		if not context.ok then
			error(
				`userId={fixture.userId}; plot context failed before purchases; error.code={context.error.code}; error.message={context.error.message}`
			)
		end
		local plotId = context.value.definition.id
		for _, itemId in OfficeTestUtils.fullProgressionOrder(fixture.config) do
			local response = fixture:Purchase(itemId)
			TestHarness.assertTrue(
				response.ok == true,
				`userId={fixture.userId}; plotId={plotId}; rebuild=0; {OfficeTestUtils.purchaseDiagnostic(
					itemId,
					response
				)}`
			)
		end
		table.insert(fixtures, fixture)
	end
	local totalInstances = 0
	local totalParts = 0
	for _, fixture in fixtures do
		local context = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
		if not context.ok then
			error(
				`userId={fixture.userId}; rebuild=0; plot context failed; error.code={context.error.code}; error.message={context.error.message}; instances={totalInstances}; baseParts={totalParts}`
			)
		end
		local plotId = context.value.definition.id
		local root = context.value.model:FindFirstChild("OfficeBuildRoot")
		TestHarness.assertTrue(
			root ~= nil,
			`userId={fixture.userId}; plotId={plotId}; rebuild=0; OfficeBuildRoot missing`
		)
		if root ~= nil then
			local instances, parts = countInstances(root)
			print(
				`[Stage4Test] METRIC performance userId={fixture.userId} plotId={plotId} rebuild=0 instances={instances} baseParts={parts} instanceBudget={INSTANCE_BUDGET_PER_PLOT} basePartBudget={BASE_PART_BUDGET_PER_PLOT}`
			)
			TestHarness.assertTrue(
				instances <= INSTANCE_BUDGET_PER_PLOT,
				`userId={fixture.userId}; plotId={plotId}; rebuild=0; instances={instances}; instanceBudget={INSTANCE_BUDGET_PER_PLOT}; baseParts={parts}; basePartBudget={BASE_PART_BUDGET_PER_PLOT}`
			)
			TestHarness.assertTrue(
				parts <= BASE_PART_BUDGET_PER_PLOT,
				`userId={fixture.userId}; plotId={plotId}; rebuild=0; instances={instances}; instanceBudget={INSTANCE_BUDGET_PER_PLOT}; baseParts={parts}; basePartBudget={BASE_PART_BUDGET_PER_PLOT}`
			)
			totalInstances += instances
			totalParts += parts
		end
	end
	print(
		`[Stage4Test] METRIC performance totals rebuild=0 instances={totalInstances} baseParts={totalParts} instanceBudget={TOTAL_INSTANCE_BUDGET} basePartBudget={TOTAL_BASE_PART_BUDGET}`
	)
	TestHarness.assertTrue(
		totalInstances <= TOTAL_INSTANCE_BUDGET,
		`rebuild=0; instances={totalInstances}; instanceBudget={TOTAL_INSTANCE_BUDGET}; baseParts={totalParts}; basePartBudget={TOTAL_BASE_PART_BUDGET}`
	)
	TestHarness.assertTrue(
		totalParts <= TOTAL_BASE_PART_BUDGET,
		`rebuild=0; instances={totalInstances}; instanceBudget={TOTAL_INSTANCE_BUDGET}; baseParts={totalParts}; basePartBudget={TOTAL_BASE_PART_BUDGET}`
	)
	for rebuildNumber = 1, 10 do
		local started = os.clock()
		for _, fixture in fixtures do
			local context = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
			if not context.ok then
				error(
					`userId={fixture.userId}; rebuild={rebuildNumber}; plot context failed; error.code={context.error.code}; error.message={context.error.message}`
				)
			end
			local plotId = context.value.definition.id
			local layout = fixture.office:ExportLayout(fixture.userId)
			if not layout.ok then
				error(
					`userId={fixture.userId}; plotId={plotId}; rebuild={rebuildNumber}; serialize failed; error.code={layout.error.code}; error.message={layout.error.message}`
				)
			end
			local closeResult = fixture.office:CloseSession(fixture.userId)
			if not closeResult.ok then
				error(
					`userId={fixture.userId}; plotId={plotId}; rebuild={rebuildNumber}; destroy failed; error.code={closeResult.error.code}; error.message={closeResult.error.message}`
				)
			end
			TestHarness.assertTrue(
				closeResult.value,
				`userId={fixture.userId}; plotId={plotId}; rebuild={rebuildNumber}; destroy reported no open session`
			)
			local prepareResult = fixture.office:PrepareSession(fixture.userId, layout.value)
			if not prepareResult.ok then
				error(
					`userId={fixture.userId}; plotId={plotId}; rebuild={rebuildNumber}; rebuild failed; error.code={prepareResult.error.code}; error.message={prepareResult.error.message}`
				)
			end
			local invariant = fixture.office:ValidateRuntimeState(fixture.userId)
			if not invariant.ok then
				error(
					`userId={fixture.userId}; plotId={plotId}; rebuild={rebuildNumber}; root invariant failed; error.code={invariant.error.code}; error.message={invariant.error.message}`
				)
			end
			local root = context.value.model:FindFirstChild("OfficeBuildRoot")
			TestHarness.assertTrue(
				root ~= nil,
				`userId={fixture.userId}; plotId={plotId}; rebuild={rebuildNumber}; OfficeBuildRoot missing`
			)
			if root ~= nil then
				local instances, parts = countInstances(root)
				TestHarness.assertTrue(
					instances <= INSTANCE_BUDGET_PER_PLOT,
					`userId={fixture.userId}; plotId={plotId}; rebuild={rebuildNumber}; instances={instances}; instanceBudget={INSTANCE_BUDGET_PER_PLOT}; baseParts={parts}; basePartBudget={BASE_PART_BUDGET_PER_PLOT}`
				)
				TestHarness.assertTrue(
					parts <= BASE_PART_BUDGET_PER_PLOT,
					`userId={fixture.userId}; plotId={plotId}; rebuild={rebuildNumber}; instances={instances}; instanceBudget={INSTANCE_BUDGET_PER_PLOT}; baseParts={parts}; basePartBudget={BASE_PART_BUDGET_PER_PLOT}`
				)
			end
		end
		local duration = os.clock() - started
		table.insert(rebuildDurations, duration)
		print(
			`[Stage4Test] METRIC performance rebuild={rebuildNumber} durationSeconds={duration} timeBudgetSeconds={REBUILD_TIME_BUDGET_SECONDS}`
		)
		TestHarness.assertTrue(
			duration <= REBUILD_TIME_BUDGET_SECONDS,
			`rebuild={rebuildNumber}; durationSeconds={duration}; timeBudgetSeconds={REBUILD_TIME_BUDGET_SECONDS}; instances={totalInstances}; baseParts={totalParts}`
		)
	end
	TestHarness.assertEqual(#rebuildDurations, 10)
	for _, fixture in fixtures do
		fixture:Destroy()
	end
end

function OfficeFullLayoutPerformanceSpec.tests(): { TestCase }
	return {
		{
			name = "six maximum-content plots rebuild ten times within instance budgets",
			run = sixPlotMaximumContentRebuildTest,
		},
	}
end
return table.freeze(OfficeFullLayoutPerformanceSpec)
