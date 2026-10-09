--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local EmployeeRemoteTypes = require(ReplicatedStorage.Shared.Types.EmployeeRemoteTypes)
local RemoteClient = require(script.Parent.Parent.Infrastructure.RemoteClient)
local EmployeesView = require(script.Parent.Parent.UI.EmployeesView)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type EmployeeMutationResponse = EmployeeRemoteTypes.EmployeeMutationResponse
type EmployeeOverview = EmployeeRemoteTypes.EmployeeOverview
type EmployeeOverviewResponse = EmployeeRemoteTypes.EmployeeOverviewResponse
type RemoteClientType = RemoteClient.Client
type View = EmployeesView.View

export type RemoteResolver = (name: string) -> RemoteFunction?
export type InvokeRemote = (remote: RemoteFunction, payload: unknown) -> unknown
export type Overrides = { view: View?, remoteResolver: RemoteResolver?, invokeRemote: InvokeRemote? }

type ControllerData = {
	_player: Player,
	_remoteClient: RemoteClientType?,
	_view: View?,
	_connections: { RBXScriptConnection },
	_cardConnections: { RBXScriptConnection },
	_tab: "Candidates" | "Team",
	_rosterPage: number,
	_rosterPageCount: number,
	_pending: boolean,
	_nextRequestId: number,
	_overviewVersion: number,
	_mutationVersion: number,
	_dismissConfirmEmployeeId: string?,
	_dismissConfirmExpiresAt: number,
	_remoteResolver: RemoteResolver?,
	_invokeRemote: InvokeRemote,
	_heartbeatAccumulator: number,
	_isDestroyed: boolean,
	_isInitialized: boolean,
	_isStarted: boolean,
}

local EmployeesController = {}
EmployeesController.__index = EmployeesController
export type Controller = typeof(setmetatable({} :: ControllerData, EmployeesController))

local function invokeServer(remote: RemoteFunction, payload: unknown): unknown
	return remote:InvokeServer(payload)
end

function EmployeesController.new(player: Player, overrides: Overrides?): Controller
	return setmetatable({
		_player = player,
		_remoteClient = nil,
		_view = if overrides ~= nil then overrides.view else nil,
		_connections = {},
		_cardConnections = {},
		_tab = "Candidates",
		_rosterPage = 1,
		_rosterPageCount = 0,
		_pending = false,
		_nextRequestId = 0,
		_overviewVersion = 0,
		_mutationVersion = 0,
		_dismissConfirmEmployeeId = nil,
		_dismissConfirmExpiresAt = 0,
		_remoteResolver = if overrides ~= nil then overrides.remoteResolver else nil,
		_invokeRemote = if overrides ~= nil and overrides.invokeRemote ~= nil
			then overrides.invokeRemote
			else invokeServer,
		_heartbeatAccumulator = 0,
		_isDestroyed = false,
		_isInitialized = false,
		_isStarted = false,
	}, EmployeesController)
end

function EmployeesController.Init(self: Controller, dependencies: DependencyResolver)
	self._remoteClient = dependencies:Require("RemoteClient") :: RemoteClientType
	self._isInitialized = true
end

function EmployeesController._requestId(self: Controller): string
	self._nextRequestId += 1
	return `employee-client-{self._nextRequestId}`
end

function EmployeesController._getRemote(self: Controller, name: string): RemoteFunction?
	if self._remoteResolver ~= nil then
		return self._remoteResolver(name)
	end
	return if self._remoteClient ~= nil then self._remoteClient:GetFunction(name) else nil
end

function EmployeesController._disconnectCards(self: Controller)
	for _, connection in self._cardConnections do
		connection:Disconnect()
	end
	table.clear(self._cardConnections)
end

function EmployeesController._isCurrentView(self: Controller, view: View): boolean
	return not self._isDestroyed and self._view == view
end

function EmployeesController._nextWorkstation(employee: EmployeeRemoteTypes.EmployeeView): string
	local index = 0
	if employee.assignedWorkstationId ~= nil then
		local parsed = string.match(employee.assignedWorkstationId, ":(%d+)$")
		if parsed ~= nil then
			index = tonumber(parsed) or 0
		end
	end
	return `workstation:{employee.roleId}:{index % 5 + 1}`
end

function EmployeesController._confirmDismiss(
	self: Controller,
	view: View,
	employeeId: string,
	dismissButton: TextButton
)
	local now = os.clock()
	if self._dismissConfirmEmployeeId == employeeId and now <= self._dismissConfirmExpiresAt then
		self._dismissConfirmEmployeeId = nil
		self:_mutate("RequestEmployeeDismiss", { requestId = self:_requestId(), employeeId = employeeId })
	else
		self._dismissConfirmEmployeeId = employeeId
		self._dismissConfirmExpiresAt = now + 3
		view:MarkDismissConfirm(dismissButton)
	end
end

function EmployeesController._render(self: Controller, view: View, overview: EmployeeOverview)
	view:SetHeader(overview.cash, overview.payrollRemainingSeconds, overview.refreshRemainingSeconds)
	view:SetTab(self._tab)
	view:SetPage(overview.rosterPage, overview.rosterPageCount)
	self._rosterPage = overview.rosterPage
	self._rosterPageCount = overview.rosterPageCount
	self:_disconnectCards()
	if self._tab == "Candidates" then
		local buttons = view:RenderCandidates(overview.candidates)
		for candidateId, action in buttons do
			table.insert(
				self._cardConnections,
				action.Activated:Connect(function()
					self:_mutate("RequestEmployeeHire", { requestId = self:_requestId(), candidateId = candidateId })
				end)
			)
		end
	else
		local employeeById = {}
		for _, employee in overview.roster do
			employeeById[employee.employeeId] = employee
		end
		local actions = view:RenderTeam(overview.roster)
		for employeeId, employeeActions in actions do
			table.insert(
				self._cardConnections,
				employeeActions.reassign.Activated:Connect(function()
					local employee = employeeById[employeeId]
					if employee ~= nil then
						self:_mutate("RequestEmployeeAssignment", {
							requestId = self:_requestId(),
							employeeId = employeeId,
							workstationId = self:_nextWorkstation(employee),
						})
					end
				end)
			)
			table.insert(
				self._cardConnections,
				employeeActions.dismiss.Activated:Connect(function()
					self:_confirmDismiss(view, employeeId, employeeActions.dismiss)
				end)
			)
		end
	end
end

function EmployeesController.Refresh(self: Controller)
	local view = self._view
	if
		view == nil
		or self._isDestroyed
		or self._pending
		or self._player:GetAttribute("EmployeeSessionReady") ~= true
	then
		return
	end
	local remote = self:_getRemote("RequestEmployeeOverview")
	if remote == nil then
		view:SetStatus("Employee overview is unavailable.", true)
		return
	end
	self._overviewVersion += 1
	local version = self._overviewVersion
	local page = self._rosterPage
	task.spawn(function()
		local ok, value = pcall(self._invokeRemote, remote, { rosterPage = page })
		if not self:_isCurrentView(view) or version ~= self._overviewVersion then
			return
		end
		if not ok or typeof(value) ~= "table" then
			view:SetStatus("Employee overview failed. Please retry.", true)
			return
		end
		local response = value :: EmployeeOverviewResponse
		if not response.ok then
			view:SetStatus(if response.error ~= nil then response.error.message else "Employee overview failed.", true)
			return
		end
		self:_render(view, response)
	end)
end

function EmployeesController._mutate(self: Controller, remoteName: string, payload: unknown)
	if self._pending or self._isDestroyed then
		return
	end
	local view = self._view
	if view == nil then
		return
	end
	local remote = self:_getRemote(remoteName)
	if remote == nil then
		view:SetStatus("Employee action is unavailable.", true)
		return
	end
	self._pending = true
	self._mutationVersion += 1
	local version = self._mutationVersion
	self._overviewVersion += 1
	local overviewVersion = self._overviewVersion
	view:SetStatus("Employee action pending…", false)
	task.spawn(function()
		local ok, value = pcall(self._invokeRemote, remote, payload)
		if version == self._mutationVersion then
			self._pending = false
		end
		if
			version ~= self._mutationVersion
			or overviewVersion ~= self._overviewVersion
			or not self:_isCurrentView(view)
		then
			return
		end
		if not ok or typeof(value) ~= "table" then
			view:SetStatus("Employee action failed. Please retry.", true)
			return
		end
		local response = value :: EmployeeMutationResponse
		if not response.ok or response.overview == nil then
			view:SetStatus(if response.error ~= nil then response.error.message else "Employee action failed.", true)
			return
		end
		view:SetStatus("Employee team updated.", false)
		self:_render(view, response.overview)
	end)
end

function EmployeesController.Toggle(self: Controller)
	local view = self._view
	if view == nil or self._isDestroyed or self._player:GetAttribute("EmployeeSessionReady") ~= true then
		return
	end
	view:SetOpen(not view:IsOpen())
	if view:IsOpen() then
		self:Refresh()
	end
end

function EmployeesController.Start(self: Controller)
	if not self._isInitialized or self._isStarted then
		error("EmployeesController.Start requires one successful Init", 2)
	end
	local playerGui = self._player:WaitForChild("PlayerGui", 10)
	if playerGui == nil or not playerGui:IsA("PlayerGui") then
		error("PlayerGui was not available for EmployeesController", 2)
	end
	local view = self._view or EmployeesView.new(playerGui)
	self._view = view
	self._isDestroyed = false
	local function updateReady()
		view:SetReady(self._player:GetAttribute("EmployeeSessionReady") == true)
	end
	table.insert(self._connections, self._player:GetAttributeChangedSignal("EmployeeSessionReady"):Connect(updateReady))
	table.insert(
		self._connections,
		view:GetEmployeesButton().Activated:Connect(function()
			self:Toggle()
		end)
	)
	table.insert(
		self._connections,
		view:GetCloseButton().Activated:Connect(function()
			view:SetOpen(false)
		end)
	)
	table.insert(
		self._connections,
		view:GetCandidateTab().Activated:Connect(function()
			self._tab = "Candidates"
			self:Refresh()
		end)
	)
	table.insert(
		self._connections,
		view:GetTeamTab().Activated:Connect(function()
			self._tab = "Team"
			self:Refresh()
		end)
	)
	table.insert(
		self._connections,
		view:GetRefreshButton().Activated:Connect(function()
			self:_mutate("RequestCandidateRefresh", { requestId = self:_requestId() })
		end)
	)
	table.insert(
		self._connections,
		view:GetPreviousButton().Activated:Connect(function()
			if self._rosterPage > 1 then
				self._rosterPage -= 1
				self:Refresh()
			end
		end)
	)
	table.insert(
		self._connections,
		view:GetNextButton().Activated:Connect(function()
			if self._rosterPage < self._rosterPageCount then
				self._rosterPage += 1
				self:Refresh()
			end
		end)
	)
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.KeyCode == Enum.KeyCode.E then
				self:Toggle()
			end
		end)
	)
	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function(deltaSeconds: number)
			if self._view ~= view or self._isDestroyed then
				return
			end
			view:TickCountdowns(deltaSeconds)
			self._heartbeatAccumulator += deltaSeconds
			if view:IsOpen() and self._heartbeatAccumulator >= 5 then
				self._heartbeatAccumulator = 0
				self:Refresh()
			end
		end)
	)
	updateReady()
	self._isStarted = true
end

function EmployeesController.Destroy(self: Controller)
	self._isDestroyed = true
	self._overviewVersion += 1
	self._mutationVersion += 1
	self._pending = false
	self:_disconnectCards()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	if self._view ~= nil then
		self._view:Destroy()
	end
	self._view = nil
	self._remoteClient = nil
	self._remoteResolver = nil
	self._isInitialized = false
	self._isStarted = false
end

return table.freeze(EmployeesController)
