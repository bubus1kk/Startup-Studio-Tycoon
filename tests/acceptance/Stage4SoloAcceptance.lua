--!strict

local Workspace = game:GetService("Workspace")

local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)

type Coordination = AcceptanceTestUtils.Coordination
type Recorder = AcceptanceTestUtils.Recorder

local Stage4SoloAcceptance = {}

local function requireClientData(result: AcceptanceTestUtils.ClientResult, command: string): { [string]: unknown }
	if not result.ok then
		error(`{command} failed: {result.message or "unknown client error"}\n{result.traceback or ""}`, 2)
	end
	if result.data == nil then
		error(`{command} returned no data`, 2)
	end
	return result.data
end

local function assertNumber(value: unknown, expected: number, description: string)
	assert(value == expected, `{description}: expected {expected}, got {tostring(value)}`)
end

function Stage4SoloAcceptance.Run(
	recorder: Recorder,
	coordination: Coordination,
	_args: { [string]: unknown }
): { [string]: number | string | boolean }
	local player: Player? = nil
	local plot: Model? = nil
	local initialSnapshot: { [string]: unknown }? = nil
	local finalSnapshot: { [string]: unknown }? = nil

	recorder:Test("player session becomes ready on one assigned plot", function()
		local players = AcceptanceTestUtils.GetPlayers(1, 20)
		player = players[1]
		AcceptanceTestUtils.WaitForReady(player :: Player, 20)
		assert((player :: Player):GetAttribute("OfficeSessionReady") == true, "OfficeSessionReady is not true")
		assert(typeof((player :: Player):GetAttribute("AssignedPlotId")) == "string", "AssignedPlotId is missing")
		local map = Workspace:FindFirstChild("Map")
		local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
		assert(plots ~= nil and #plots:GetChildren() == 1, "Expected exactly one production PlotRuntimeModel")
		plot = AcceptanceTestUtils.GetRuntimePlot(player :: Player)
	end)

	recorder:Test("Garage runtime structure and initial Cash are canonical", function()
		assert(player ~= nil and plot ~= nil, "Player/plot setup did not complete")
		local typedPlayer = player :: Player
		local typedPlot = plot :: Model
		local anchor = typedPlot:FindFirstChild("PlotAnchor")
		local spawn = typedPlot:FindFirstChild("SpawnLocation")
		local root = AcceptanceTestUtils.GetOfficeRoot(typedPlot)
		local tierShell = root:FindFirstChild("TierShell")
		assert(anchor ~= nil and anchor:IsA("BasePart"), "Expected one PlotAnchor")
		assert(AcceptanceTestUtils.CountNamedDescendants(typedPlot, "PlotAnchor") == 1, "PlotAnchor is duplicated")
		assert(typedPlot.PrimaryPart == anchor, "PlotRuntimeModel.PrimaryPart is not PlotAnchor")
		assert(spawn ~= nil and spawn:IsA("SpawnLocation"), "Expected one SpawnLocation")
		assert(
			AcceptanceTestUtils.CountNamedDescendants(typedPlot, "SpawnLocation") == 1,
			"SpawnLocation is duplicated"
		)
		assert(not (spawn :: SpawnLocation):IsDescendantOf(root), "SpawnLocation moved inside OfficeBuildRoot")
		assert(tierShell ~= nil and tierShell:IsA("Model"), "TierShell is missing")
		local approach = tierShell:FindFirstChild("EntranceApproach")
		assert(approach ~= nil and approach:IsA("BasePart"), "EntranceApproach is not inside TierShell")
		assert(typedPlayer.RespawnLocation == spawn, "Player RespawnLocation is not the plot SpawnLocation")
		AcceptanceTestUtils.AssertCanonicalRoot(typedPlot)
		AcceptanceTestUtils.AssertEntranceGeometry(typedPlot)
		initialSnapshot = requireClientData(
			AcceptanceTestUtils.RequestClient(coordination, typedPlayer, "Snapshot", {}, 25),
			"initial Snapshot"
		)
		assertNumber((initialSnapshot :: { [string]: unknown }).cash, 250000, "initial Cash")
		assert(
			(initialSnapshot :: { [string]: unknown }).currentTierId == "tier_garage",
			"Garage is not the active initial tier"
		)
	end)

	local clientUiResult: AcceptanceTestUtils.ClientResult? = nil
	recorder:Test("client controller/view acceptance completes", function()
		assert(player ~= nil, "Player setup did not complete")
		clientUiResult = AcceptanceTestUtils.RequestClient(coordination, player :: Player, "RunUI", {}, 35)
		assert(
			(clientUiResult :: AcceptanceTestUtils.ClientResult).ok,
			(clientUiResult :: AcceptanceTestUtils.ClientResult).message
		)
		assert((clientUiResult :: AcceptanceTestUtils.ClientResult).tests ~= nil, "Client UI returned no tests")
	end)
	if clientUiResult ~= nil and clientUiResult.ok and clientUiResult.tests ~= nil then
		recorder:MergeClientTests("client UI", clientUiResult.tests)
	end

	recorder:Test("production remote contract purchases the complete catalog", function()
		assert(player ~= nil, "Player setup did not complete")
		local order = AcceptanceTestUtils.FullProgressionOrder()
		assert(#order > 0, "Full progression order is empty")
		finalSnapshot = requireClientData(
			AcceptanceTestUtils.RequestClient(coordination, player :: Player, "PurchaseOrder", { order = order }, 80),
			"full catalog PurchaseOrder"
		)
		local data = finalSnapshot :: { [string]: unknown }
		assertNumber(data.totalDebit, 205150, "total debit")
		assertNumber(data.cash, 44850, "final Cash")
		assert(data.currentTierId == "tier_global_hq", "Global HQ is not active")
		assertNumber(data.rooms, 9, "room count")
		assertNumber(data.equipment, 9, "equipment count")
		assertNumber(data.furniture, 9, "furniture count")
		assertNumber(data.upgradesMaxLevel, 9, "L3 upgrade count")
	end)

	recorder:Test("Global HQ root, entrance, bounds and local-space contract are clean", function()
		assert(player ~= nil, "Player setup did not complete")
		plot = AcceptanceTestUtils.GetRuntimePlot(player :: Player)
		local typedPlot = plot :: Model
		local rooms, equipment, furniture = AcceptanceTestUtils.OfficeCounts(typedPlot)
		assert(rooms == 9 and equipment == 9 and furniture == 9, "Runtime maximum-content counts are wrong")
		AcceptanceTestUtils.AssertCanonicalRoot(typedPlot)
		AcceptanceTestUtils.AssertEntranceGeometry(typedPlot)
		assert(
			AcceptanceTestUtils.CountNamedDescendants(typedPlot, "EntranceApproach") == 1,
			"EntranceApproach is duplicated"
		)
	end)

	recorder:Test("five respawns preserve plot, Cash, layout, roots and Build GUI", function()
		assert(player ~= nil and finalSnapshot ~= nil, "Full progression setup did not complete")
		local typedPlayer = player :: Player
		local baseline = finalSnapshot :: { [string]: unknown }
		local baselinePlotId = typedPlayer:GetAttribute("AssignedPlotId")
		local baselineSignature = baseline.signature
		for respawnNumber = 1, 5 do
			local previousCharacter = typedPlayer.Character
			local callOk, callValue, callTraceback = AcceptanceTestUtils.CallWithTimeout(function(): unknown
				return typedPlayer:LoadCharacterAsync()
			end, 15, `respawn {respawnNumber}`)
			assert(callOk, callTraceback or tostring(callValue))
			local ready, message = AcceptanceTestUtils.WaitFor(function(): boolean
				local character = typedPlayer.Character
				return character ~= nil
					and character ~= previousCharacter
					and character:FindFirstChild("HumanoidRootPart") ~= nil
					and typedPlayer:GetAttribute("OfficeSessionReady") == true
			end, 15, `respawn {respawnNumber} character readiness`)
			assert(ready, message)
			local data = requireClientData(
				AcceptanceTestUtils.RequestClient(coordination, typedPlayer, "Snapshot", {}, 25),
				`respawn {respawnNumber} Snapshot`
			)
			assert(typedPlayer:GetAttribute("AssignedPlotId") == baselinePlotId, `Respawn {respawnNumber} changed plot`)
			assertNumber(data.cash, 44850, `respawn {respawnNumber} Cash`)
			assert(data.currentTierId == "tier_global_hq", `Respawn {respawnNumber} changed tier`)
			assertNumber(data.rooms, 9, `respawn {respawnNumber} rooms`)
			assertNumber(data.equipment, 9, `respawn {respawnNumber} equipment`)
			assertNumber(data.furniture, 9, `respawn {respawnNumber} furniture`)
			assertNumber(data.rootCount, 1, `respawn {respawnNumber} root count`)
			assertNumber(data.guiCount, 1, `respawn {respawnNumber} Build GUI count`)
			assert(data.signature == baselineSignature, `Respawn {respawnNumber} changed layout signature`)
			AcceptanceTestUtils.AssertCanonicalRoot(AcceptanceTestUtils.GetRuntimePlot(typedPlayer))
		end
	end)

	return {
		respawnCount = 5,
		totalDebit = 205150,
		finalCash = 44850,
		fullCatalogPurchases = #AcceptanceTestUtils.FullProgressionOrder(),
	}
end

return table.freeze(Stage4SoloAcceptance)
