--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local testArgs = StudioTestService:GetTestArgs()
if typeof(testArgs) ~= "table" or testArgs.stage ~= 4 or typeof(testArgs.suite) ~= "string" then
	return
end

type TestResult = {
	name: string,
	status: string,
	message: string?,
	traceback: string?,
}
type CommandResult = {
	ok: boolean,
	message: string?,
	traceback: string?,
	data: { [string]: unknown }?,
	tests: { TestResult }?,
	metrics: { [string]: number | string | boolean }?,
	leaveAfterResponse: boolean?,
}
type VirtualInputLike = {
	SendKey: (self: VirtualInputLike, isPressed: boolean, keyCode: Enum.KeyCode, isRepeatedKey: boolean) -> (),
}

local localPlayer = Players.LocalPlayer
local requestIndex = 0
local COMMAND_TIMEOUT_SECONDS = 90
local REMOTE_CALL_TIMEOUT_SECONDS = 8

local function tracebackError(errorValue: unknown): { message: string, traceback: string }
	return {
		message = tostring(errorValue),
		traceback = debug.traceback(tostring(errorValue), 2),
	}
end

local function waitFor(predicate: () -> boolean, timeoutSeconds: number, description: string)
	if predicate() then
		return
	end
	local completed = Instance.new("BindableEvent")
	local resolved = false
	local success = false
	local message = ""
	local function finish(ok: boolean, diagnostic: string)
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
			finish(true, "")
		end
	end)
	local timeoutThread = task.delay(timeoutSeconds, function()
		finish(false, `{description}: timed out after {timeoutSeconds} seconds`)
	end)
	completed.Event:Wait()
	connection:Disconnect()
	pcall(task.cancel, timeoutThread)
	completed:Destroy()
	if not success then
		error(message, 2)
	end
end

local function boundedDelay(seconds: number, deadline: number, description: string)
	local started = os.clock()
	waitFor(function(): boolean
		return os.clock() - started >= seconds
	end, math.max(0.1, deadline - os.clock()), description)
end

local function callWithTimeout(callback: () -> unknown, timeoutSeconds: number, description: string): unknown
	local completed = Instance.new("BindableEvent")
	local resolved = false
	local ok = false
	local value: unknown = nil
	local traceback: string? = nil
	local function finish(callOk: boolean, resultValue: unknown, tracebackValue: string?)
		if resolved then
			return
		end
		resolved = true
		ok = callOk
		value = resultValue
		traceback = tracebackValue
		completed:Fire()
	end
	task.spawn(function()
		local callOk, detail = xpcall(callback, tracebackError)
		if callOk then
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
	if not ok then
		error(traceback or tostring(value), 2)
	end
	return value
end

local function nextRequestId(prefix: string): string
	requestIndex += 1
	return `{prefix}-{requestIndex}`
end

local function getRemoteFunction(name: string): RemoteFunction
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
	if not remotes:IsA("Folder") then
		error("ReplicatedStorage.Remotes is unavailable", 2)
	end
	local remote = remotes:WaitForChild(name, 15)
	if not remote:IsA("RemoteFunction") then
		error(`Production remote {name} is unavailable`, 2)
	end
	return remote
end

local function catalog(categoryId: string, page: number): { [string]: unknown }
	local remote = getRemoteFunction("RequestOfficeCatalog")
	local deadline = os.clock() + 20
	while os.clock() < deadline do
		local requestId = nextRequestId("accept-cat")
		local responseValue = callWithTimeout(
			function(): unknown
				return remote:InvokeServer({
					requestId = requestId,
					categoryId = categoryId,
					page = page,
				})
			end,
			math.min(REMOTE_CALL_TIMEOUT_SECONDS, math.max(0.1, deadline - os.clock())),
			`catalog {categoryId} page {page}`
		)
		if typeof(responseValue) ~= "table" then
			error(`Catalog {categoryId} page {page} returned a non-table response`, 2)
		end
		local response = responseValue :: { [string]: unknown }
		if response.ok == true then
			return response
		end
		local errorValue = response.error
		local code = if typeof(errorValue) == "table" then errorValue.code else "unknown"
		if code ~= "RateLimited" then
			error(`Catalog {categoryId} page {page} failed: {tostring(code)}`, 2)
		end
		boundedDelay(1.05, deadline, `catalog rate-limit retry for {categoryId} page {page}`)
	end
	error(`Catalog {categoryId} page {page} exceeded its deadline`, 2)
end

local function purchase(itemId: string, deadline: number): { [string]: unknown }
	local remote = getRemoteFunction("RequestOfficePurchase")
	while os.clock() < deadline do
		local requestId = nextRequestId("accept-buy")
		local responseValue = callWithTimeout(function(): unknown
			return remote:InvokeServer({ requestId = requestId, itemId = itemId })
		end, math.min(REMOTE_CALL_TIMEOUT_SECONDS, math.max(0.1, deadline - os.clock())), `purchase {itemId}`)
		if typeof(responseValue) ~= "table" then
			error(`Purchase {itemId} returned a non-table response`, 2)
		end
		local response = responseValue :: { [string]: unknown }
		if response.ok == true then
			return response
		end
		local errorValue = response.error
		local code = if typeof(errorValue) == "table" then errorValue.code else "unknown"
		if code ~= "RateLimited" then
			error(`Purchase {itemId} failed: {tostring(code)}`, 2)
		end
		boundedDelay(0.55, deadline, `rate-limit retry for {itemId}`)
	end
	error(`Purchase {itemId} exceeded its command deadline`, 2)
end

local function getLocalPlot(): Model
	local plotId = localPlayer:GetAttribute("AssignedPlotId")
	if typeof(plotId) ~= "string" then
		error("Local player has no AssignedPlotId", 2)
	end
	local map = Workspace:FindFirstChild("Map")
	local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
	local plot = if plots ~= nil then plots:FindFirstChild(plotId) else nil
	if plot == nil or not plot:IsA("Model") then
		error(`Local runtime plot {plotId} is missing`, 2)
	end
	return plot
end

local function countNamed(root: Instance, name: string): number
	local count = if root.Name == name then 1 else 0
	for _, descendant in root:GetDescendants() do
		if descendant.Name == name then
			count += 1
		end
	end
	return count
end

local function officeSignature(plot: Model): string
	local root = plot:FindFirstChild("OfficeBuildRoot")
	local spawn = plot:FindFirstChild("SpawnLocation")
	if root == nil or spawn == nil or not spawn:IsA("BasePart") then
		return "missing"
	end
	local entries = {}
	for _, descendant in root:GetDescendants() do
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
	local position = spawn.Position
	table.insert(entries, string.format("spawn:%.3f:%.3f:%.3f", position.X, position.Y, position.Z))
	return table.concat(entries, "|")
end

local function snapshot(): { [string]: unknown }
	waitFor(function(): boolean
		return localPlayer:GetAttribute("OfficeSessionReady") == true
	end, 20, "local office session readiness")
	local tiers = catalog("Tiers", 1)
	local upgradesOne = catalog("Upgrades", 1)
	local upgradesTwo = catalog("Upgrades", 2)
	local plot = getLocalPlot()
	local root = plot:FindFirstChild("OfficeBuildRoot")
	if root == nil or not root:IsA("Model") then
		error("Local OfficeBuildRoot is missing", 2)
	end
	local rooms = root:FindFirstChild("Rooms")
	local equipment = root:FindFirstChild("Equipment")
	local furniture = root:FindFirstChild("Furniture")
	if rooms == nil or equipment == nil or furniture == nil then
		error("Office content folders are missing", 2)
	end
	local upgradesMaxLevel = 0
	for _, pageValue in { upgradesOne, upgradesTwo } do
		local itemsValue = pageValue.items
		if typeof(itemsValue) == "table" then
			for _, itemValue in itemsValue do
				if typeof(itemValue) == "table" and itemValue.state == "MaxLevel" and itemValue.currentLevel == 3 then
					upgradesMaxLevel += 1
				end
			end
		end
	end
	local map = Workspace:FindFirstChild("Map")
	local plots = if map ~= nil then map:FindFirstChild("Plots") else nil
	local replicatedPlotIds = {}
	if plots ~= nil then
		for _, child in plots:GetChildren() do
			local childPlotId = child:GetAttribute("PlotId")
			if child:IsA("Model") and typeof(childPlotId) == "string" then
				table.insert(replicatedPlotIds, childPlotId)
			end
		end
	end
	table.sort(replicatedPlotIds)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	return {
		cash = tiers.cash,
		currentTierId = tiers.currentTierId,
		assignedPlotId = localPlayer:GetAttribute("AssignedPlotId"),
		ownerUserId = plot:GetAttribute("OwnerUserId"),
		rooms = #rooms:GetChildren(),
		equipment = #equipment:GetChildren(),
		furniture = #furniture:GetChildren(),
		upgradesMaxLevel = upgradesMaxLevel,
		rootCount = countNamed(plot, "OfficeBuildRoot"),
		spawnCount = countNamed(plot, "SpawnLocation"),
		anchorCount = countNamed(plot, "PlotAnchor"),
		approachCount = countNamed(plot, "EntranceApproach"),
		plotCount = #replicatedPlotIds,
		replicatedPlotIds = replicatedPlotIds,
		guiCount = if playerGui ~= nil then countNamed(playerGui, "OfficeBuildGui") else 0,
		signature = officeSignature(plot),
	}
end

local function runTest(tests: { TestResult }, name: string, callback: () -> ())
	local ok, detailValue = xpcall(callback, tracebackError)
	if ok then
		table.insert(tests, { name = name, status = "PASS" })
		return
	end
	local detail = detailValue :: { message: string, traceback: string }
	table.insert(tests, {
		name = name,
		status = "FAIL",
		message = detail.message,
		traceback = detail.traceback,
	})
end

local function runUiAcceptance(): { TestResult }
	local tests: { TestResult } = {}
	runTest(tests, "one persistent Build button and five categories", function()
		local playerGui = localPlayer:WaitForChild("PlayerGui", 15)
		assert(playerGui:IsA("PlayerGui"), "PlayerGui is unavailable")
		waitFor(function(): boolean
			return countNamed(playerGui, "OfficeBuildGui") == 1
		end, 15, "one production OfficeBuildGui")
		local gui = playerGui:FindFirstChild("OfficeBuildGui")
		assert(gui ~= nil and gui:IsA("ScreenGui"), "OfficeBuildGui is missing")
		assert(countNamed(gui, "BuildButton") == 1, "Build button is duplicated")
		local categories = gui:FindFirstChild("Categories", true)
		assert(categories ~= nil and categories:IsA("Frame"), "Categories frame is missing")
		local categoryCount = 0
		for _, category in { "Tiers", "Rooms", "Equipment", "Furniture", "Upgrades" } do
			local button = categories:FindFirstChild(category)
			assert(button ~= nil and button:IsA("TextButton"), `Category {category} is missing`)
			categoryCount += 1
		end
		assert(categoryCount == 5, "Expected five build categories")
	end)
	runTest(tests, "view states and pagination buttons", function()
		local BuildMenuView = require(script.Parent.UI.BuildMenuView)
		local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
		assert(playerGui ~= nil, "PlayerGui is unavailable")
		local view = BuildMenuView.new(playerGui)
		local buttons = view:RenderItems({
			{
				itemId = "locked",
				displayName = "Locked",
				description = "Locked state",
				price = 1,
				state = "Locked",
				lockText = "Prerequisite",
			},
			{
				itemId = "purchased",
				displayName = "Purchased",
				description = "Purchased state",
				price = 1,
				state = "Purchased",
			},
			{
				itemId = "max",
				displayName = "Max",
				description = "Max state",
				price = 1,
				state = "MaxLevel",
				currentLevel = 3,
				maxLevel = 3,
			},
		})
		assert(not buttons.locked.Active and buttons.locked.Text == "Locked", "Locked action state is wrong")
		assert(
			not buttons.purchased.Active and buttons.purchased.Text == "Purchased",
			"Purchased action state is wrong"
		)
		assert(not buttons.max.Active and buttons.max.Text == "MaxLevel", "Max-level action state is wrong")
		view:SetPage(1, 2)
		assert(not view:GetPreviousButton().Active and view:GetNextButton().Active, "Page 1 controls are wrong")
		view:SetPage(2, 2)
		assert(view:GetPreviousButton().Active and not view:GetNextButton().Active, "Page 2 controls are wrong")
		view:Destroy()
	end)
	runTest(tests, "controller toggle, Next/Previous, pending and stale recovery", function()
		local clientSpecs = script.Parent:WaitForChild("ClientSpecs", 15)
		assert(clientSpecs:IsA("Folder"), "ClientSpecs folder is unavailable")
		local spec = require(clientSpecs.BuildMenuControllerClientSpec)
		spec.run()
	end)

	local virtualInputOk, virtualInputValue = pcall(function(): unknown
		return UserInputService:CreateVirtualInput()
	end)
	if not virtualInputOk or virtualInputValue == nil then
		table.insert(tests, {
			name = "optional VirtualInput B shortcut",
			status = "SKIPPED",
			message = "UserInputService:CreateVirtualInput() is unavailable",
		})
	else
		runTest(tests, "optional VirtualInput B shortcut", function()
			local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
			assert(playerGui ~= nil, "PlayerGui is unavailable")
			local panel = playerGui:FindFirstChild("BuildPanel", true)
			assert(panel ~= nil and panel:IsA("Frame"), "Production BuildPanel is missing")
			local initialVisible = panel.Visible
			local virtualInput = (virtualInputValue :: unknown) :: VirtualInputLike
			virtualInput:SendKey(true, Enum.KeyCode.B, false)
			virtualInput:SendKey(false, Enum.KeyCode.B, false)
			waitFor(function(): boolean
				return panel.Visible ~= initialVisible
			end, 3, "B shortcut first toggle")
			virtualInput:SendKey(true, Enum.KeyCode.B, false)
			virtualInput:SendKey(false, Enum.KeyCode.B, false)
			waitFor(function(): boolean
				return panel.Visible == initialVisible
			end, 3, "B shortcut second toggle")
		end)
	end
	return tests
end

local function handleCommand(command: string, payload: { [string]: unknown }): CommandResult
	if command == "Snapshot" then
		return { ok = true, data = snapshot() }
	elseif command == "PurchaseOrder" then
		local orderValue = payload.order
		if typeof(orderValue) ~= "table" then
			error("PurchaseOrder requires an order array", 2)
		end
		local deadline = os.clock() + COMMAND_TIMEOUT_SECONDS
		local totalDebit = 0
		local lastCash: number? = nil
		for _, itemValue in orderValue do
			if typeof(itemValue) ~= "string" then
				error("PurchaseOrder contains a non-string item ID", 2)
			end
			local response = purchase(itemValue, deadline)
			if typeof(response.cash) == "number" then
				lastCash = response.cash
			end
		end
		local finalSnapshot = snapshot()
		if typeof(finalSnapshot.cash) == "number" then
			totalDebit = 250000 - finalSnapshot.cash
		end
		finalSnapshot.totalDebit = totalDebit
		finalSnapshot.lastPurchaseCash = lastCash
		return { ok = true, data = finalSnapshot }
	elseif command == "ForeignMutation" then
		local foreignPlotId = payload.foreignPlotId
		if typeof(foreignPlotId) ~= "string" then
			error("ForeignMutation requires foreignPlotId", 2)
		end
		local purchaseRemote = getRemoteFunction("RequestOfficePurchase")
		local responseValue = callWithTimeout(function(): unknown
			return purchaseRemote:InvokeServer({
				requestId = nextRequestId("accept-foreign"),
				itemId = "room_development",
				plotId = foreignPlotId,
			})
		end, REMOTE_CALL_TIMEOUT_SECONDS, "foreign ownership mutation")
		if typeof(responseValue) ~= "table" then
			error("Foreign mutation returned a non-table response", 2)
		end
		local response = responseValue :: { [string]: unknown }
		local errorValue = response.error
		local code = if typeof(errorValue) == "table" then errorValue.code else nil
		assert(response.ok == false and code == "InvalidPayload", `Foreign mutation was not rejected: {tostring(code)}`)
		return { ok = true, data = { code = code, foreignPlotId = foreignPlotId } }
	elseif command == "RunUI" then
		return { ok = true, tests = runUiAcceptance() }
	elseif command == "Leave" then
		local canLeave = StudioTestService:CanLeaveTest()
		if not canLeave then
			error("StudioTestService:CanLeaveTest() returned false on the client", 2)
		end
		return { ok = true, data = { canLeave = true }, leaveAfterResponse = true }
	end
	error(`Unknown acceptance client command {command}`, 2)
end

local acceptanceFolder = ReplicatedStorage:WaitForChild("Stage4AcceptanceRemotes", 30)
if not acceptanceFolder:IsA("Folder") then
	error("Stage4AcceptanceRemotes folder is unavailable")
end
local commandEvent = acceptanceFolder:WaitForChild("Command", 15)
local resultEvent = acceptanceFolder:WaitForChild("Result", 15)
if not commandEvent:IsA("RemoteEvent") or not resultEvent:IsA("RemoteEvent") then
	error("Stage 4 acceptance coordination remotes are invalid")
end

commandEvent.OnClientEvent:Connect(function(commandIdValue: unknown, commandValue: unknown, payloadValue: unknown)
	if typeof(commandIdValue) ~= "string" or typeof(commandValue) ~= "string" or typeof(payloadValue) ~= "table" then
		return
	end
	task.spawn(function()
		local ok, detailValue = xpcall(function(): CommandResult
			return handleCommand(commandValue, payloadValue :: { [string]: unknown })
		end, tracebackError)
		local result: CommandResult
		if ok then
			result = detailValue :: CommandResult
		else
			local detail = detailValue :: { message: string, traceback: string }
			result = {
				ok = false,
				message = detail.message,
				traceback = detail.traceback,
			}
		end
		resultEvent:FireServer(commandIdValue, result)
		if result.leaveAfterResponse then
			task.defer(function()
				boundedDelay(0.05, os.clock() + 1, "LeaveTest response flush")
				if StudioTestService:CanLeaveTest() then
					StudioTestService:LeaveTest()
				end
			end)
		end
	end)
end)

print(`[Stage4Acceptance] client ready userId={localPlayer.UserId} suite={testArgs.suite}`)
