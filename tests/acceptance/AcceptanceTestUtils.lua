--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)
local OfficeTestUtils = require(ServerScriptService.Stage2Tests.ServerFixtures.OfficeTestUtils)
local PlotDefinitions = require(ServerStorage.Config.PlotDefinitions)

type PlotDefinition = PlotTypes.PlotDefinition

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
export type ClientResult = {
	ok: boolean,
	message: string?,
	traceback: string?,
	data: { [string]: unknown }?,
	tests: { { name: string, status: string, message: string?, traceback: string? } }?,
	metrics: Metrics?,
}
export type Coordination = {
	folder: Folder,
	commandEvent: RemoteEvent,
	resultEvent: RemoteEvent,
	Destroy: (self: Coordination) -> (),
}

type RecorderData = {
	suite: string,
	started: number,
	total: number,
	passed: number,
	failed: number,
	skipped: number,
	failures: { Failure },
}

local Recorder = {}
Recorder.__index = Recorder
export type Recorder = typeof(setmetatable({} :: RecorderData, Recorder))

local AcceptanceTestUtils = {}

local EPSILON = 1e-3
local MINIMUM_WALKABLE_WIDTH = 6
local MAXIMUM_SURFACE_STEP = 0.05

local function tracebackError(errorValue: unknown): { message: string, traceback: string }
	return {
		message = tostring(errorValue),
		traceback = debug.traceback(tostring(errorValue), 2),
	}
end

function AcceptanceTestUtils.NewRecorder(suite: string): Recorder
	return setmetatable({
		suite = suite,
		started = os.clock(),
		total = 0,
		passed = 0,
		failed = 0,
		skipped = 0,
		failures = {},
	}, Recorder)
end

function Recorder.Test(self: Recorder, name: string, callback: () -> ())
	self.total += 1
	local ok, detailValue = xpcall(callback, tracebackError)
	if ok then
		self.passed += 1
		print(`[Stage4Acceptance] PASS {self.suite} :: {name}`)
		return
	end
	local detail = detailValue :: { message: string, traceback: string }
	self.failed += 1
	table.insert(self.failures, {
		test = name,
		message = detail.message,
		traceback = detail.traceback,
	})
	warn(`[Stage4Acceptance] FAIL {self.suite} :: {name} :: {detail.traceback}`)
end

function Recorder.Skip(self: Recorder, name: string, message: string)
	self.total += 1
	self.skipped += 1
	print(`[Stage4Acceptance] SKIPPED {self.suite} :: {name} :: {message}`)
end

function Recorder.MergeClientTests(
	self: Recorder,
	prefix: string,
	tests: { { name: string, status: string, message: string?, traceback: string? } }
)
	for _, test in tests do
		local name = `{prefix} :: {test.name}`
		self.total += 1
		if test.status == "PASS" then
			self.passed += 1
			print(`[Stage4Acceptance] PASS {self.suite} :: {name}`)
		elseif test.status == "SKIPPED" then
			self.skipped += 1
			print(`[Stage4Acceptance] SKIPPED {self.suite} :: {name} :: {test.message or "not available"}`)
		else
			self.failed += 1
			table.insert(self.failures, {
				test = name,
				message = test.message or "Client acceptance failed",
				traceback = test.traceback,
			})
			warn(`[Stage4Acceptance] FAIL {self.suite} :: {name} :: {test.message or "Client acceptance failed"}`)
		end
	end
end

function Recorder.Finish(self: Recorder, metrics: Metrics?): Result
	return {
		ok = self.failed == 0,
		suite = self.suite,
		total = self.total,
		passed = self.passed,
		failed = self.failed,
		skipped = self.skipped,
		durationSeconds = os.clock() - self.started,
		failures = self.failures,
		metrics = metrics or {},
	}
end

function AcceptanceTestUtils.FailResult(suite: string, testName: string, message: string, traceback: string?): Result
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
				test = testName,
				message = message,
				traceback = traceback,
			},
		},
		metrics = {},
	}
end

function AcceptanceTestUtils.WaitFor(
	predicate: () -> boolean,
	timeoutSeconds: number,
	description: string
): (boolean, string?)
	if predicate() then
		return true, nil
	end
	local completed = Instance.new("BindableEvent")
	local resolved = false
	local success = false
	local message: string? = nil
	local function finish(ok: boolean, diagnostic: string?)
		if resolved then
			return
		end
		resolved = true
		success = ok
		message = diagnostic
		completed:Fire()
	end
	local connection = RunService.Heartbeat:Connect(function()
		local ok, value = pcall(predicate)
		if not ok then
			finish(false, `{description}: predicate raised {tostring(value)}`)
		elseif value then
			finish(true, nil)
		end
	end)
	local timeoutThread = task.delay(timeoutSeconds, function()
		finish(false, `{description}: timed out after {timeoutSeconds} seconds`)
	end)
	completed.Event:Wait()
	connection:Disconnect()
	pcall(task.cancel, timeoutThread)
	completed:Destroy()
	return success, message
end

function AcceptanceTestUtils.Delay(seconds: number, timeoutSeconds: number, description: string)
	local started = os.clock()
	local ok, message = AcceptanceTestUtils.WaitFor(function(): boolean
		return os.clock() - started >= seconds
	end, timeoutSeconds, description)
	if not ok then
		error(message or `{description}: delay failed`, 2)
	end
end

function AcceptanceTestUtils.CallWithTimeout(
	callback: () -> unknown,
	timeoutSeconds: number,
	description: string
): (boolean, unknown, string?)
	local completed = Instance.new("BindableEvent")
	local resolved = false
	local callOk = false
	local value: unknown = nil
	local callTraceback: string? = nil
	local function finish(ok: boolean, resultValue: unknown, tracebackValue: string?)
		if resolved then
			return
		end
		resolved = true
		callOk = ok
		value = resultValue
		callTraceback = tracebackValue
		completed:Fire()
	end
	task.spawn(function()
		local ok, detail = xpcall(callback, tracebackError)
		if ok then
			finish(true, detail, nil)
		else
			local errorDetail = detail :: { message: string, traceback: string }
			finish(false, errorDetail.message, errorDetail.traceback)
		end
	end)
	local timeoutThread = task.delay(timeoutSeconds, function()
		finish(false, `{description}: timed out after {timeoutSeconds} seconds`, nil)
	end)
	completed.Event:Wait()
	pcall(task.cancel, timeoutThread)
	completed:Destroy()
	return callOk, value, callTraceback
end

function AcceptanceTestUtils.CreateCoordination(): Coordination
	local existing = ReplicatedStorage:FindFirstChild("Stage4AcceptanceRemotes")
	if existing ~= nil then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Stage4AcceptanceRemotes"
	local commandEvent = Instance.new("RemoteEvent")
	commandEvent.Name = "Command"
	commandEvent.Parent = folder
	local resultEvent = Instance.new("RemoteEvent")
	resultEvent.Name = "Result"
	resultEvent.Parent = folder
	folder.Parent = ReplicatedStorage
	local coordination: Coordination
	coordination = {
		folder = folder,
		commandEvent = commandEvent,
		resultEvent = resultEvent,
		Destroy = function(self: Coordination)
			self.folder:Destroy()
		end,
	}
	return coordination
end

function AcceptanceTestUtils.RequestClients(
	coordination: Coordination,
	players: { Player },
	command: string,
	payloadFactory: (Player) -> { [string]: unknown },
	timeoutSeconds: number
): { [number]: ClientResult }
	local commandId = `acceptance-{command}-{math.floor(os.clock() * 1000000)}`
	local expected: { [number]: boolean } = {}
	local results: { [number]: ClientResult } = {}
	local resultCount = 0
	for _, player in players do
		expected[player.UserId] = true
	end
	local connection = coordination.resultEvent.OnServerEvent:Connect(
		function(player: Player, incomingCommandId: unknown, responseValue: unknown)
			if incomingCommandId ~= commandId or not expected[player.UserId] or results[player.UserId] ~= nil then
				return
			end
			if typeof(responseValue) ~= "table" then
				results[player.UserId] = {
					ok = false,
					message = "Client returned a non-table response",
				}
			else
				results[player.UserId] = responseValue :: ClientResult
			end
			resultCount += 1
		end
	)
	for _, player in players do
		coordination.commandEvent:FireClient(player, commandId, command, payloadFactory(player))
	end
	local ready, message = AcceptanceTestUtils.WaitFor(function(): boolean
		return resultCount == #players
	end, timeoutSeconds, `{command} responses ({resultCount}/{#players})`)
	connection:Disconnect()
	if not ready then
		error(message or `{command}: client response timeout`, 2)
	end
	return results
end

function AcceptanceTestUtils.RequestClient(
	coordination: Coordination,
	player: Player,
	command: string,
	payload: { [string]: unknown },
	timeoutSeconds: number
): ClientResult
	local results = AcceptanceTestUtils.RequestClients(
		coordination,
		{ player },
		command,
		function(): { [string]: unknown }
			return payload
		end,
		timeoutSeconds
	)
	local result = results[player.UserId]
	if result == nil then
		error(`{command}: missing client result for userId={player.UserId}`, 2)
	end
	return result
end

function AcceptanceTestUtils.GetPlayers(count: number, timeoutSeconds: number): { Player }
	local ready, message = AcceptanceTestUtils.WaitFor(function(): boolean
		return #Players:GetPlayers() == count
	end, timeoutSeconds, `expected exactly {count} players`)
	if not ready then
		error(message or `Expected {count} players`, 2)
	end
	local players = Players:GetPlayers()
	table.sort(players, function(first: Player, second: Player): boolean
		return first.UserId < second.UserId
	end)
	return players
end

function AcceptanceTestUtils.WaitForReady(player: Player, timeoutSeconds: number)
	local ready, message = AcceptanceTestUtils.WaitFor(function(): boolean
		return player.Parent == Players
			and player:GetAttribute("OfficeSessionReady") == true
			and typeof(player:GetAttribute("AssignedPlotId")) == "string"
	end, timeoutSeconds, `office session readiness for userId={player.UserId}`)
	if not ready then
		error(message or `Player {player.UserId} did not become ready`, 2)
	end
end

function AcceptanceTestUtils.GetRuntimePlot(player: Player): Model
	local plotId = player:GetAttribute("AssignedPlotId")
	if typeof(plotId) ~= "string" then
		error(`Player {player.UserId} has no AssignedPlotId`, 2)
	end
	local map = Workspace:FindFirstChild("Map")
	local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
	local plot = if plots ~= nil then plots:FindFirstChild(plotId) else nil
	if plot == nil or not plot:IsA("Model") then
		error(`Runtime plot {plotId} is missing for userId={player.UserId}`, 2)
	end
	return plot
end

function AcceptanceTestUtils.GetOfficeRoot(plot: Model): Model
	local root = plot:FindFirstChild("OfficeBuildRoot")
	if root == nil or not root:IsA("Model") then
		error(`OfficeBuildRoot is missing under {plot:GetFullName()}`, 2)
	end
	return root
end

function AcceptanceTestUtils.CountNamedDescendants(root: Instance, name: string): number
	local count = if root.Name == name then 1 else 0
	for _, descendant in root:GetDescendants() do
		if descendant.Name == name then
			count += 1
		end
	end
	return count
end

function AcceptanceTestUtils.CountInstances(root: Instance): (number, number)
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

function AcceptanceTestUtils.FullProgressionOrder(): { string }
	local config = OfficeTestUtils.validatedConfig()
	return OfficeTestUtils.fullProgressionOrder(config)
end

local function projectedHalfExtent(part: BasePart, worldAxis: Vector3): number
	return math.abs(part.CFrame.RightVector:Dot(worldAxis)) * part.Size.X * 0.5
		+ math.abs(part.CFrame.UpVector:Dot(worldAxis)) * part.Size.Y * 0.5
		+ math.abs(part.CFrame.LookVector:Dot(worldAxis)) * part.Size.Z * 0.5
end

local function localAxisRange(part: BasePart, origin: CFrame, localAxis: Vector3): (number, number)
	local worldAxis = origin:VectorToWorldSpace(localAxis)
	local localCenter = origin:PointToObjectSpace(part.Position)
	local center = localCenter:Dot(localAxis)
	local halfExtent = projectedHalfExtent(part, worldAxis)
	return center - halfExtent, center + halfExtent
end

local function topSurface(part: BasePart): number
	return part.Position.Y + projectedHalfExtent(part, Vector3.yAxis)
end

local function getPlotDefinition(plotId: string): PlotDefinition
	for _, definition in PlotDefinitions.definitions do
		if definition.id == plotId then
			return definition :: PlotDefinition
		end
	end
	error(`Unknown plot definition {plotId}`, 2)
end

function AcceptanceTestUtils.AssertEntranceGeometry(plot: Model)
	local plotIdValue = plot:GetAttribute("PlotId")
	if typeof(plotIdValue) ~= "string" then
		error("Runtime plot has no PlotId attribute", 2)
	end
	local definition = getPlotDefinition(plotIdValue)
	local root = AcceptanceTestUtils.GetOfficeRoot(plot)
	local tierShell = root:FindFirstChild("TierShell")
	local spawn = plot:FindFirstChild("SpawnLocation")
	local approach = if tierShell ~= nil then tierShell:FindFirstChild("EntranceApproach") else nil
	local floorBack = if tierShell ~= nil then tierShell:FindFirstChild("FloorBack") else nil
	assert(tierShell ~= nil and tierShell:IsA("Model"), "TierShell is missing")
	assert(spawn ~= nil and spawn:IsA("SpawnLocation"), "SpawnLocation is missing")
	assert(approach ~= nil and approach:IsA("BasePart"), "EntranceApproach is missing from TierShell")
	assert(floorBack ~= nil and floorBack:IsA("BasePart"), "TierShell.FloorBack is missing")
	local typedSpawn = spawn :: SpawnLocation
	local typedApproach = approach :: BasePart
	local typedFloor = floorBack :: BasePart
	assert(not typedSpawn:IsDescendantOf(root), "SpawnLocation must stay outside OfficeBuildRoot")
	assert(typedApproach.Parent == tierShell, "EntranceApproach must be a direct TierShell child")
	assert(typedApproach.CanCollide, "EntranceApproach must be collidable")
	assert(typedApproach.Size.X >= MINIMUM_WALKABLE_WIDTH, "EntranceApproach is too narrow")
	assert(
		PlotBounds.containsBox(definition, typedApproach.CFrame, typedApproach.Size),
		"EntranceApproach exceeds plot bounds"
	)
	assert(
		typedApproach.CFrame.RightVector:Dot(definition.origin.RightVector) > 0.999,
		"EntranceApproach lost the rotated local-space contract"
	)
	local _, floorMaximumZ = localAxisRange(typedFloor, definition.origin, Vector3.zAxis)
	local approachMinimumZ, approachMaximumZ = localAxisRange(typedApproach, definition.origin, Vector3.zAxis)
	local spawnMinimumZ = localAxisRange(typedSpawn, definition.origin, Vector3.zAxis)
	local floorGap = approachMinimumZ - floorMaximumZ
	local spawnGap = spawnMinimumZ - approachMaximumZ
	assert(math.abs(floorGap) <= EPSILON, `Positive floor gap detected: {floorGap}`)
	assert(math.abs(spawnGap) <= EPSILON, `Positive spawn gap detected: {spawnGap}`)
	assert(
		math.abs(topSurface(typedApproach) - topSurface(typedSpawn)) <= MAXIMUM_SURFACE_STEP,
		"Spawn and approach top surfaces differ"
	)
	assert(
		math.abs(topSurface(typedApproach) - topSurface(typedFloor)) <= MAXIMUM_SURFACE_STEP,
		"Approach and office floor top surfaces differ"
	)
end

function AcceptanceTestUtils.AssertCanonicalRoot(plot: Model)
	assert(AcceptanceTestUtils.CountNamedDescendants(plot, "OfficeBuildRoot") == 1, "Expected one OfficeBuildRoot")
	for _, descendant in plot:GetDescendants() do
		local lowered = string.lower(descendant.Name)
		assert(not string.find(lowered, "pending", 1, true), `Pending root remains: {descendant:GetFullName()}`)
		assert(not string.find(lowered, "temporary", 1, true), `Temporary root remains: {descendant:GetFullName()}`)
		assert(not string.find(lowered, "transaction", 1, true), `Transaction root remains: {descendant:GetFullName()}`)
		assert(not string.find(lowered, "replacement", 1, true), `Replacement root remains: {descendant:GetFullName()}`)
		assert(not string.find(lowered, "__old__", 1, true), `Old root remains: {descendant:GetFullName()}`)
	end
end

function AcceptanceTestUtils.OfficeCounts(plot: Model): (number, number, number)
	local root = AcceptanceTestUtils.GetOfficeRoot(plot)
	local rooms = root:FindFirstChild("Rooms")
	local equipment = root:FindFirstChild("Equipment")
	local furniture = root:FindFirstChild("Furniture")
	assert(rooms ~= nil and rooms:IsA("Folder"), "Rooms folder is missing")
	assert(equipment ~= nil and equipment:IsA("Folder"), "Equipment folder is missing")
	assert(furniture ~= nil and furniture:IsA("Folder"), "Furniture folder is missing")
	return #rooms:GetChildren(), #equipment:GetChildren(), #furniture:GetChildren()
end

function AcceptanceTestUtils.Median(values: { number }): number
	assert(#values > 0, "Median requires at least one value")
	local sorted = table.clone(values)
	table.sort(sorted)
	local middle = math.floor(#sorted / 2) + 1
	if #sorted % 2 == 1 then
		return sorted[middle]
	end
	return (sorted[middle - 1] + sorted[middle]) * 0.5
end

return table.freeze(AcceptanceTestUtils)
