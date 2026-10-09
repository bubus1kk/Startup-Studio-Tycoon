--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local EmployeesController = require(script.Parent.Parent.Controllers.EmployeesController)
local EmployeesView = require(script.Parent.Parent.UI.EmployeesView)

type InvokeRemote = EmployeesController.InvokeRemote
type View = EmployeesView.View

type FakeState = {
	statuses: { string },
	pages: { number },
	renderCount: number,
	destroyed: boolean,
	callsAfterDestroy: number,
	markedDismisses: number,
	open: boolean,
}

local EmployeesControllerClientSpec = {}

local function assertTrue(value: boolean, message: string)
	if not value then
		error(message, 2)
	end
end

local function waitUntil(predicate: () -> boolean, message: string)
	local deadline = os.clock() + 3
	while not predicate() and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	if not predicate() then
		error(message, 2)
	end
end

local function hasStatus(state: FakeState, expected: string): boolean
	for _, value in state.statuses do
		if value == expected then
			return true
		end
	end
	return false
end

local function overview(page: number?)
	return {
		candidates = {},
		roster = {},
		rosterPage = page or 1,
		rosterPageCount = 2,
		rosterTotal = 0,
		tierEmployeeCap = 2,
		workstationCapacity = 1,
		occupiedWorkstations = 0,
		payrollRemainingSeconds = 60,
		refreshRemainingSeconds = 0,
		roleWorkSummary = {},
		cash = 1000,
	}
end

local function mutationSuccess(requestId: string)
	return { ok = true, requestId = requestId, overview = overview() }
end

local function overviewSuccess(page: number?)
	local value = overview(page)
	value.ok = true
	return value
end

local function newFakeView(): (View, FakeState)
	local state: FakeState = {
		statuses = {},
		pages = {},
		renderCount = 0,
		destroyed = false,
		callsAfterDestroy = 0,
		markedDismisses = 0,
		open = false,
	}
	local function touched()
		if state.destroyed then
			state.callsAfterDestroy += 1
		end
	end
	local object = {}
	function object:SetStatus(text: string, _isError: boolean)
		touched()
		table.insert(state.statuses, text)
	end
	function object:SetHeader(_cash: number, _payroll: number, _refresh: number)
		touched()
	end
	function object:SetTab(_tab: string)
		touched()
	end
	function object:SetPage(page: number, _pageCount: number)
		touched()
		table.insert(state.pages, page)
	end
	function object:RenderCandidates(_candidates: { unknown }): { [string]: TextButton }
		touched()
		state.renderCount += 1
		return {}
	end
	function object:RenderTeam(_roster: { unknown }): { [string]: EmployeesView.TeamActions }
		touched()
		state.renderCount += 1
		return {}
	end
	function object:MarkDismissConfirm(button: TextButton)
		touched()
		state.markedDismisses += 1
		button.Text = "CONFIRM?"
	end
	function object:IsOpen(): boolean
		return state.open
	end
	function object:SetOpen(value: boolean)
		touched()
		state.open = value
	end
	function object:Destroy()
		state.destroyed = true
	end
	return (object :: unknown) :: View, state
end

local function closingViewDoesNotCancelMutation(player: Player)
	local view, state = newFakeView()
	local remote = Instance.new("RemoteFunction")
	local gate = Instance.new("BindableEvent")
	local started = false
	local invoke: InvokeRemote = function(_remote, payload): unknown
		started = true
		gate.Event:Wait()
		return mutationSuccess((payload :: { requestId: string }).requestId)
	end
	local controller = EmployeesController.new(player, {
		view = view,
		remoteResolver = function(_name: string): RemoteFunction?
			return remote
		end,
		invokeRemote = invoke,
	})
	view:SetOpen(true)
	controller:_mutate("RequestCandidateRefresh", { requestId = "employee-client-close" })
	waitUntil(function(): boolean
		return started
	end, "Employee mutation did not start before close")
	view:SetOpen(false)
	gate:Fire()
	waitUntil(function(): boolean
		return hasStatus(state, "Employee team updated.")
	end, "Closing Employees UI cancelled the server mutation response")
	controller:Destroy()
	gate:Destroy()
	remote:Destroy()
end

local function exceptionCleanupAndRetry(player: Player)
	local view, state = newFakeView()
	local remote = Instance.new("RemoteFunction")
	local attempts = 0
	local invoke: InvokeRemote = function(_remote, payload): unknown
		attempts += 1
		if attempts == 1 then
			error("simulated employee transport exception")
		end
		return mutationSuccess((payload :: { requestId: string }).requestId)
	end
	local controller = EmployeesController.new(player, {
		view = view,
		remoteResolver = function(_name: string): RemoteFunction?
			return remote
		end,
		invokeRemote = invoke,
	})
	controller:_mutate("RequestCandidateRefresh", { requestId = "employee-client-test-1" })
	waitUntil(function(): boolean
		return hasStatus(state, "Employee action failed. Please retry.")
	end, "Employee mutation exception did not clear pending state")
	controller:_mutate("RequestCandidateRefresh", { requestId = "employee-client-test-2" })
	waitUntil(function(): boolean
		return attempts == 2 and hasStatus(state, "Employee team updated.")
	end, "Employee mutation retry remained blocked")
	controller:Destroy()
	remote:Destroy()
end

local function outOfOrderRosterPageCannotRedraw(player: Player)
	local view, state = newFakeView()
	local remote = Instance.new("RemoteFunction")
	local gates = { Instance.new("BindableEvent"), Instance.new("BindableEvent") }
	local calls = 0
	local invoke: InvokeRemote = function(_remote, payload): unknown
		calls += 1
		local index = calls
		gates[index].Event:Wait()
		return overviewSuccess((payload :: { rosterPage: number }).rosterPage)
	end
	local controller = EmployeesController.new(player, {
		view = view,
		remoteResolver = function(_name: string): RemoteFunction?
			return remote
		end,
		invokeRemote = invoke,
	})
	controller:Refresh()
	waitUntil(function(): boolean
		return calls == 1
	end, "First employee overview did not start")
	controller._rosterPage = 2
	controller:Refresh()
	waitUntil(function(): boolean
		return calls == 2
	end, "Second employee overview did not start")
	gates[2]:Fire()
	waitUntil(function(): boolean
		return state.renderCount == 1 and state.pages[1] == 2
	end, "Newest employee overview did not render")
	gates[1]:Fire()
	RunService.Heartbeat:Wait()
	assertTrue(state.renderCount == 1 and #state.pages == 1, "Out-of-order roster page redrew stale data")
	controller:Destroy()
	for _, gate in gates do
		gate:Destroy()
	end
	remote:Destroy()
end

local function dismissConfirmDoesNotEnterPayload(player: Player)
	local view, state = newFakeView()
	local remote = Instance.new("RemoteFunction")
	local calls = 0
	local lastPayload: { [string]: unknown }? = nil
	local invoke: InvokeRemote = function(_remote, payload): unknown
		calls += 1
		lastPayload = payload :: { [string]: unknown }
		return mutationSuccess((lastPayload :: { [string]: unknown }).requestId :: string)
	end
	local controller = EmployeesController.new(player, {
		view = view,
		remoteResolver = function(_name: string): RemoteFunction?
			return remote
		end,
		invokeRemote = invoke,
	})
	local button = Instance.new("TextButton")
	controller:_confirmDismiss(view, "employee-confirm", button)
	assertTrue(calls == 0 and state.markedDismisses == 1, "First dismiss click bypassed local confirmation")
	controller:_confirmDismiss(view, "employee-confirm", button)
	waitUntil(function(): boolean
		return calls == 1
	end, "Confirmed dismiss did not invoke the server")
	assertTrue(lastPayload ~= nil, "Dismiss payload was not captured")
	if lastPayload ~= nil then
		assertTrue(lastPayload.employeeId == "employee-confirm", "Dismiss payload lost the employee ID")
		assertTrue(lastPayload.confirmed == nil and lastPayload.confirm == nil, "Local confirm leaked as authority")
	end
	controller:Destroy()
	button:Destroy()
	remote:Destroy()
end

local function destroyInvalidatesPending(player: Player)
	local view, state = newFakeView()
	local remote = Instance.new("RemoteFunction")
	local gate = Instance.new("BindableEvent")
	local started = false
	local invoke: InvokeRemote = function(_remote, payload): unknown
		started = true
		gate.Event:Wait()
		return mutationSuccess((payload :: { requestId: string }).requestId)
	end
	local controller = EmployeesController.new(player, {
		view = view,
		remoteResolver = function(_name: string): RemoteFunction?
			return remote
		end,
		invokeRemote = invoke,
	})
	controller:_mutate("RequestCandidateRefresh", { requestId = "employee-client-destroy" })
	waitUntil(function(): boolean
		return started
	end, "Pending employee mutation did not start")
	controller:Destroy()
	gate:Fire()
	RunService.Heartbeat:Wait()
	assertTrue(state.destroyed, "Employees controller did not destroy its view")
	assertTrue(state.callsAfterDestroy == 0, "Pending employee mutation touched a destroyed view")
	gate:Destroy()
	remote:Destroy()
end

local function expiredCountdownDisablesHire()
	local guiRoot = Instance.new("Folder")
	local view = EmployeesView.new((guiRoot :: unknown) :: PlayerGui)
	local buttons = view:RenderCandidates({
		{
			candidateId = "candidate-countdown",
			displayName = "Alex",
			roleId = "Developer",
			grade = "Trainee",
			speed = 5,
			quality = 5,
			reliability = 5,
			traitId = "Focused",
			hiringCost = 250,
			salaryPerCycle = 10,
			expiresInSeconds = 0.25,
		},
	})
	view:TickCountdowns(1)
	local button = buttons["candidate-countdown"]
	assertTrue(
		button ~= nil and not button.Active and button.Text == "EXPIRED",
		"Expired candidate remained actionable"
	)
	view:Destroy()
	guiRoot:Destroy()
end

function EmployeesControllerClientSpec.run()
	local player = Players.LocalPlayer
	assertTrue(player ~= nil, "EmployeesController client spec requires LocalPlayer")
	if player == nil then
		return
	end
	player:SetAttribute("EmployeeSessionReady", true)
	exceptionCleanupAndRetry(player)
	outOfOrderRosterPageCannotRedraw(player)
	destroyInvalidatesPending(player)
	dismissConfirmDoesNotEnterPayload(player)
	closingViewDoesNotCancelMutation(player)
	expiredCountdownDisablesHire()
	print("[Stage5Test] PASS employee UI exception, stale response and destroy safety")
end

return table.freeze(EmployeesControllerClientSpec)
