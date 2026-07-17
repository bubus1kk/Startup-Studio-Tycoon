--!strict

local Players = game:GetService("Players")
local StudioTestService = game:GetService("StudioTestService")
local Workspace = game:GetService("Workspace")

local AcceptanceTestUtils = require(script.Parent.AcceptanceTestUtils)

type Coordination = AcceptanceTestUtils.Coordination
type Recorder = AcceptanceTestUtils.Recorder
type ClientResult = AcceptanceTestUtils.ClientResult

local Stage4MultiplayerAcceptance = {}

local function clientData(result: ClientResult, description: string): { [string]: unknown }
	if not result.ok then
		error(`{description}: {result.message or "unknown client failure"}\n{result.traceback or ""}`, 2)
	end
	if result.data == nil then
		error(`{description}: client returned no data`, 2)
	end
	return result.data
end

local function snapshots(coordination: Coordination, players: { Player }): { [number]: { [string]: unknown } }
	local results = AcceptanceTestUtils.RequestClients(
		coordination,
		players,
		"Snapshot",
		function(): { [string]: unknown }
			return {}
		end,
		35
	)
	local dataByUserId: { [number]: { [string]: unknown } } = {}
	for _, player in players do
		dataByUserId[player.UserId] = clientData(results[player.UserId], `Snapshot userId={player.UserId}`)
	end
	return dataByUserId
end

local function signature(plot: Model): string
	local entries = {}
	for _, descendant in plot:GetDescendants() do
		if descendant:IsA("BasePart") then
			local position = descendant.Position
			table.insert(
				entries,
				string.format("%s:%.3f:%.3f:%.3f", descendant.Name, position.X, position.Y, position.Z)
			)
		else
			table.insert(entries, `{descendant.ClassName}:{descendant.Name}`)
		end
	end
	table.sort(entries)
	return table.concat(entries, "|")
end

local function assertCash(data: { [string]: unknown }, expected: number, description: string)
	assert(data.cash == expected, `{description}: expected Cash {expected}, got {tostring(data.cash)}`)
end

function Stage4MultiplayerAcceptance.Run(
	recorder: Recorder,
	coordination: Coordination,
	_args: { [string]: unknown }
): { [string]: number | string | boolean }
	local players: { Player } = {}
	local initial: { [number]: { [string]: unknown } } = {}
	local afterPlayerOne: { [number]: { [string]: unknown } } = {}
	local afterPlayerTwo: { [number]: { [string]: unknown } } = {}
	local initialPlots: { [number]: Model } = {}
	local initialSpawns: { [number]: Instance } = {}
	local initialSignatures: { [number]: string } = {}

	recorder:Test("three clients receive distinct ready plot and currency sessions", function()
		players = AcceptanceTestUtils.GetPlayers(3, 25)
		local seenPlots: { [string]: boolean } = {}
		for _, player in players do
			AcceptanceTestUtils.WaitForReady(player, 20)
			local plotId = player:GetAttribute("AssignedPlotId")
			assert(typeof(plotId) == "string", `AssignedPlotId missing for userId={player.UserId}`)
			assert(not seenPlots[plotId], `AssignedPlotId duplicated: {plotId}`)
			seenPlots[plotId] = true
			local plot = AcceptanceTestUtils.GetRuntimePlot(player)
			initialPlots[player.UserId] = plot
			local spawn = plot:FindFirstChild("SpawnLocation")
			assert(spawn ~= nil and spawn:IsA("SpawnLocation"), `Spawn missing for userId={player.UserId}`)
			initialSpawns[player.UserId] = spawn
			initialSignatures[player.UserId] = signature(plot)
		end
		initial = snapshots(coordination, players)
		for _, player in players do
			local data = initial[player.UserId]
			assertCash(data, 250000, `initial userId={player.UserId}`)
			assert(data.currentTierId == "tier_garage", `userId={player.UserId} did not start in Garage`)
			assert(data.plotCount == 3, `userId={player.UserId} does not see three replicated offices`)
			assert(data.assignedPlotId == player:GetAttribute("AssignedPlotId"), "Client/server plot IDs differ")
		end
	end)

	recorder:Test("Player 1 reaches full Global HQ without changing Players 2 or 3", function()
		assert(#players == 3, "Three-player setup did not complete")
		local playerOne = players[1]
		local result = AcceptanceTestUtils.RequestClient(coordination, playerOne, "PurchaseOrder", {
			order = AcceptanceTestUtils.FullProgressionOrder(),
		}, 80)
		local playerOneData = clientData(result, "Player 1 full progression")
		assertCash(playerOneData, 44850, "Player 1 final")
		assert(playerOneData.currentTierId == "tier_global_hq", "Player 1 did not reach Global HQ")
		afterPlayerOne = snapshots(coordination, players)
		for index = 2, 3 do
			local player = players[index]
			local data = afterPlayerOne[player.UserId]
			assertCash(data, 250000, `Player {index} after Player 1 purchases`)
			assert(data.currentTierId == "tier_garage", `Player {index} layout changed with Player 1`)
			assert(
				signature(initialPlots[player.UserId]) == initialSignatures[player.UserId],
				`Player {index} root changed`
			)
			assert(
				initialPlots[player.UserId]:FindFirstChild("SpawnLocation") == initialSpawns[player.UserId],
				`Player {index} spawn changed`
			)
		end
	end)

	recorder:Test("Player 2 reaches Small Loft while Players 1 and 3 remain independent", function()
		assert(#players == 3, "Three-player setup did not complete")
		local playerTwo = players[2]
		local result = AcceptanceTestUtils.RequestClient(coordination, playerTwo, "PurchaseOrder", {
			order = { "room_development", "room_design", "tier_small_loft" },
		}, 35)
		local playerTwoData = clientData(result, "Player 2 Small Loft progression")
		assert(playerTwoData.currentTierId == "tier_small_loft", "Player 2 did not reach Small Loft")
		afterPlayerTwo = snapshots(coordination, players)
		local playerOneData = afterPlayerTwo[players[1].UserId]
		local playerThreeData = afterPlayerTwo[players[3].UserId]
		assertCash(playerOneData, 44850, "Player 1 after Player 2 purchases")
		assert(playerOneData.currentTierId == "tier_global_hq", "Player 1 layout changed with Player 2")
		assertCash(playerThreeData, 250000, "Player 3 after Player 2 purchases")
		assert(playerThreeData.currentTierId == "tier_garage", "Player 3 did not remain in Garage")
	end)

	recorder:Test("foreign ownership payload is rejected without target root or spawn mutation", function()
		assert(#players == 3, "Three-player setup did not complete")
		local actor = players[1]
		local target = players[2]
		local targetPlot = AcceptanceTestUtils.GetRuntimePlot(target)
		local targetSignature = signature(targetPlot)
		local targetRoot = AcceptanceTestUtils.GetOfficeRoot(targetPlot)
		local targetSpawn = targetPlot:FindFirstChild("SpawnLocation")
		local foreignPlotId = target:GetAttribute("AssignedPlotId")
		assert(typeof(foreignPlotId) == "string", "Foreign plot ID is missing")
		local result = AcceptanceTestUtils.RequestClient(coordination, actor, "ForeignMutation", {
			foreignPlotId = foreignPlotId,
		}, 20)
		clientData(result, "foreign mutation")
		assert(signature(targetPlot) == targetSignature, "Foreign mutation changed the target plot")
		assert(AcceptanceTestUtils.GetOfficeRoot(targetPlot) == targetRoot, "Foreign mutation replaced target root")
		assert(targetPlot:FindFirstChild("SpawnLocation") == targetSpawn, "Foreign mutation replaced target spawn")
	end)

	local departedUserId = 0
	local freedPlotId = ""
	local replacementUserId = 0
	recorder:Test("client leave cleans its plot and AddPlayers creates a clean replacement", function()
		assert(#players == 3, "Three-player setup did not complete")
		local departing = players[2]
		departedUserId = departing.UserId
		local plotIdValue = departing:GetAttribute("AssignedPlotId")
		assert(typeof(plotIdValue) == "string", "Departing player plot ID is missing")
		freedPlotId = plotIdValue
		local leaveResult = AcceptanceTestUtils.RequestClient(coordination, departing, "Leave", {}, 15)
		clientData(leaveResult, "client LeaveTest")
		local left, leftMessage = AcceptanceTestUtils.WaitFor(function(): boolean
			return #Players:GetPlayers() == 2 and departing.Parent == nil
		end, 20, "departing client cleanup")
		assert(left, leftMessage)
		local map = Workspace:FindFirstChild("Map")
		local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
		assert(plots ~= nil and plots:FindFirstChild(freedPlotId) == nil, "Departed client's plot was not cleaned")

		StudioTestService:AddPlayers(1)
		local currentPlayers = AcceptanceTestUtils.GetPlayers(3, 30)
		local replacement: Player? = nil
		for _, candidate in currentPlayers do
			if candidate.UserId ~= players[1].UserId and candidate.UserId ~= players[3].UserId then
				replacement = candidate
				break
			end
		end
		assert(replacement ~= nil, "AddPlayers did not create a new client")
		AcceptanceTestUtils.WaitForReady(replacement :: Player, 20)
		replacementUserId = (replacement :: Player).UserId
		assert(replacementUserId ~= departedUserId, "AddPlayers unexpectedly reused the departed UserId")
		assert((replacement :: Player):GetAttribute("AssignedPlotId") == freedPlotId, "Freed plot was not reused")
		local replacementData = clientData(
			AcceptanceTestUtils.RequestClient(coordination, replacement :: Player, "Snapshot", {}, 30),
			"replacement Snapshot"
		)
		assertCash(replacementData, 250000, "replacement client")
		assert(replacementData.currentTierId == "tier_garage", "Replacement client did not receive Garage")
		assert(replacementData.rooms == 0, "Replacement client inherited previous rooms")
		assert(replacementData.equipment == 0, "Replacement client inherited previous equipment")
		assert(replacementData.furniture == 0, "Replacement client inherited previous furniture")
	end)

	return {
		initialPlayers = 3,
		addedPlayers = 1,
		departedUserId = departedUserId,
		replacementUserId = replacementUserId,
		freedPlotReused = freedPlotId ~= "",
		sameUserSnapshotRestore = "OfficeRejoinSpec fixed test userId; AddPlayers is a new UserId",
	}
end

return table.freeze(Stage4MultiplayerAcceptance)
