--!strict

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)
local OfficeTestUtils = require(ServerScriptService.Stage2Tests.ServerFixtures.OfficeTestUtils)

type Coordination = AcceptanceTestUtils.Coordination
type Recorder = AcceptanceTestUtils.Recorder
type Fixture = OfficeTestUtils.Fixture

local Stage4PerformanceAcceptance = {}

local INSTANCE_BUDGET_PER_OFFICE = 450
local BASE_PART_BUDGET_PER_OFFICE = 300
local TOTAL_INSTANCE_BUDGET = 2700
local TOTAL_BASE_PART_BUDGET = 1800
local REBUILD_COUNT = 10

local function requireData(result: AcceptanceTestUtils.ClientResult, description: string): { [string]: unknown }
	if not result.ok then
		error(`{description}: {result.message or "unknown client error"}\n{result.traceback or ""}`, 2)
	end
	if result.data == nil then
		error(`{description}: no client data`, 2)
	end
	return result.data
end

function Stage4PerformanceAcceptance.Run(
	recorder: Recorder,
	coordination: Coordination,
	_args: { [string]: unknown }
): { [string]: number | string | boolean }
	local players: { Player } = {}
	local fixtures: { Fixture } = {}
	local rebuildDurations: { number } = {}
	local instancesPerOffice = 0
	local basePartsPerOffice = 0
	local instancesTotal = 0
	local basePartsTotal = 0
	local cleanupSeconds = 0

	recorder:Test("six production clients start independent Garage sessions", function()
		players = AcceptanceTestUtils.GetPlayers(6, 30)
		local seenPlots: { [string]: boolean } = {}
		for _, player in players do
			AcceptanceTestUtils.WaitForReady(player, 25)
			local plotId = player:GetAttribute("AssignedPlotId")
			assert(typeof(plotId) == "string" and not seenPlots[plotId], `Duplicate/missing plot for {player.UserId}`)
			seenPlots[plotId] = true
		end
		local results = AcceptanceTestUtils.RequestClients(
			coordination,
			players,
			"Snapshot",
			function(): { [string]: unknown }
				return {}
			end,
			40
		)
		for _, player in players do
			local data = requireData(results[player.UserId], `initial Snapshot userId={player.UserId}`)
			assert(data.cash == 250000, `userId={player.UserId} initial Cash is {tostring(data.cash)}`)
			assert(data.currentTierId == "tier_garage", `userId={player.UserId} did not start in Garage`)
			assert(data.plotCount == 6, `userId={player.UserId} does not see six offices`)
		end
	end)

	recorder:Test("six production offices reach maximum-content Global HQ", function()
		assert(#players == 6, "Six-player setup did not complete")
		local order = AcceptanceTestUtils.FullProgressionOrder()
		local results = AcceptanceTestUtils.RequestClients(
			coordination,
			players,
			"PurchaseOrder",
			function(): { [string]: unknown }
				return { order = order }
			end,
			95
		)
		for _, player in players do
			local data = requireData(results[player.UserId], `full progression userId={player.UserId}`)
			assert(data.cash == 44850, `userId={player.UserId} final Cash is {tostring(data.cash)}`)
			assert(data.currentTierId == "tier_global_hq", `userId={player.UserId} did not reach Global HQ`)
			assert(data.rooms == 9, `userId={player.UserId} room count is {tostring(data.rooms)}`)
			assert(data.equipment == 9, `userId={player.UserId} equipment count is {tostring(data.equipment)}`)
			assert(data.furniture == 9, `userId={player.UserId} furniture count is {tostring(data.furniture)}`)
			assert(
				data.upgradesMaxLevel == 9,
				`userId={player.UserId} L3 upgrade count is {tostring(data.upgradesMaxLevel)}`
			)
		end
	end)

	recorder:Test("production office instance budgets hold at six-player maximum", function()
		instancesTotal = 0
		basePartsTotal = 0
		for _, player in players do
			local plot = AcceptanceTestUtils.GetRuntimePlot(player)
			local root = AcceptanceTestUtils.GetOfficeRoot(plot)
			local instances, baseParts = AcceptanceTestUtils.CountInstances(root)
			instancesPerOffice = math.max(instancesPerOffice, instances)
			basePartsPerOffice = math.max(basePartsPerOffice, baseParts)
			instancesTotal += instances
			basePartsTotal += baseParts
			assert(instances <= INSTANCE_BUDGET_PER_OFFICE, `userId={player.UserId} has {instances} instances`)
			assert(baseParts <= BASE_PART_BUDGET_PER_OFFICE, `userId={player.UserId} has {baseParts} BaseParts`)
			AcceptanceTestUtils.AssertCanonicalRoot(plot)
		end
		assert(instancesTotal <= TOTAL_INSTANCE_BUDGET, `Six offices have {instancesTotal} instances`)
		assert(basePartsTotal <= TOTAL_BASE_PART_BUDGET, `Six offices have {basePartsTotal} BaseParts`)
	end)

	recorder:Test("service contract rebuilds six maximum layouts ten times without monotonic growth", function()
		for index = 1, 6 do
			local fixture = OfficeTestUtils.createFixture(8000 + index, nil)
			table.insert(fixtures, fixture)
			for _, itemId in AcceptanceTestUtils.FullProgressionOrder() do
				local response = fixture:Purchase(itemId)
				assert(response.ok == true, OfficeTestUtils.purchaseDiagnostic(itemId, response))
			end
		end
		local baselineInstances = 0
		local baselineBaseParts = 0
		for _, fixture in fixtures do
			local context = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
			assert(context.ok, "Fixture plot context failed")
			if context.ok then
				local root = AcceptanceTestUtils.GetOfficeRoot(context.value.model)
				local instances, baseParts = AcceptanceTestUtils.CountInstances(root)
				baselineInstances += instances
				baselineBaseParts += baseParts
			end
		end
		for rebuildNumber = 1, REBUILD_COUNT do
			local started = os.clock()
			local rebuildInstances = 0
			local rebuildBaseParts = 0
			for _, fixture in fixtures do
				local layout = fixture.office:ExportLayout(fixture.userId)
				assert(layout.ok, `rebuild {rebuildNumber}: layout export failed`)
				local closeResult = fixture.office:CloseSession(fixture.userId)
				assert(closeResult.ok and closeResult.value, `rebuild {rebuildNumber}: close failed`)
				if layout.ok then
					local prepareResult = fixture.office:PrepareSession(fixture.userId, layout.value)
					assert(prepareResult.ok, `rebuild {rebuildNumber}: prepare failed`)
				end
				local invariant = fixture.office:ValidateRuntimeState(fixture.userId)
				assert(invariant.ok, `rebuild {rebuildNumber}: runtime invariant failed`)
				local context = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
				assert(context.ok, `rebuild {rebuildNumber}: plot context failed`)
				if context.ok then
					local root = AcceptanceTestUtils.GetOfficeRoot(context.value.model)
					local instances, baseParts = AcceptanceTestUtils.CountInstances(root)
					rebuildInstances += instances
					rebuildBaseParts += baseParts
					assert(
						instances <= INSTANCE_BUDGET_PER_OFFICE,
						`rebuild {rebuildNumber}: office instances={instances}`
					)
					assert(
						baseParts <= BASE_PART_BUDGET_PER_OFFICE,
						`rebuild {rebuildNumber}: office BaseParts={baseParts}`
					)
				end
			end
			table.insert(rebuildDurations, os.clock() - started)
			assert(rebuildInstances <= baselineInstances, `rebuild {rebuildNumber}: monotonic instance growth`)
			assert(rebuildBaseParts <= baselineBaseParts, `rebuild {rebuildNumber}: monotonic BasePart growth`)
			assert(rebuildInstances <= TOTAL_INSTANCE_BUDGET, `rebuild {rebuildNumber}: total instance budget exceeded`)
			assert(
				rebuildBaseParts <= TOTAL_BASE_PART_BUDGET,
				`rebuild {rebuildNumber}: total BasePart budget exceeded`
			)
		end
		assert(#rebuildDurations == REBUILD_COUNT, "Not all rebuild timings were recorded")
	end)

	recorder:Test("fixtures and departing performance clients clean up before EndTest", function()
		local started = os.clock()
		for _, fixture in fixtures do
			fixture:Destroy()
		end
		table.clear(fixtures)
		if #players > 1 then
			local departingPlayers: { Player } = {}
			for index = 1, #players - 1 do
				table.insert(departingPlayers, players[index])
			end
			local leaveResults = AcceptanceTestUtils.RequestClients(
				coordination,
				departingPlayers,
				"Leave",
				function(): { [string]: unknown }
					return {}
				end,
				20
			)
			for _, player in departingPlayers do
				requireData(leaveResults[player.UserId], `cleanup Leave userId={player.UserId}`)
			end
			local cleaned, message = AcceptanceTestUtils.WaitFor(function(): boolean
				if #Players:GetPlayers() ~= 1 then
					return false
				end
				local map = Workspace:FindFirstChild("Map")
				local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
				return plots ~= nil and #plots:GetChildren() == 1
			end, 25, "departing performance-client plot cleanup")
			assert(cleaned, message)
			assert(Players:GetPlayers()[1] == players[#players], "The designated EndTest survivor changed")
		end
		cleanupSeconds = os.clock() - started
	end)

	local rebuildMinimum = if #rebuildDurations > 0 then math.min(table.unpack(rebuildDurations)) else 0
	local rebuildMaximum = if #rebuildDurations > 0 then math.max(table.unpack(rebuildDurations)) else 0
	local rebuildMedian = if #rebuildDurations > 0 then AcceptanceTestUtils.Median(rebuildDurations) else 0
	return {
		instancesPerOffice = instancesPerOffice,
		basePartsPerOffice = basePartsPerOffice,
		instancesTotal = instancesTotal,
		basePartsTotal = basePartsTotal,
		rebuildCount = #rebuildDurations,
		rebuildMinimumSeconds = rebuildMinimum,
		rebuildMedianSeconds = rebuildMedian,
		rebuildMaximumSeconds = rebuildMaximum,
		cleanupSeconds = cleanupSeconds,
	}
end

return table.freeze(Stage4PerformanceAcceptance)
