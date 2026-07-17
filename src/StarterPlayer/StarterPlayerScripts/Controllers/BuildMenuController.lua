--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local OfficeRemoteTypes = require(ReplicatedStorage.Shared.Types.OfficeRemoteTypes)
local BuildMenuView = require(script.Parent.Parent.UI.BuildMenuView)
local RemoteClient = require(script.Parent.Parent.Infrastructure.RemoteClient)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type OfficeCatalogResponse = OfficeRemoteTypes.OfficeCatalogResponse
type OfficeCategoryId = OfficeRemoteTypes.OfficeCategoryId
type OfficePurchaseResponse = OfficeRemoteTypes.OfficePurchaseResponse
type RemoteClientType = RemoteClient.Client
type View = BuildMenuView.View

type ControllerData = {
	_player: Player,
	_remoteClient: RemoteClientType?,
	_view: View?,
	_connections: { RBXScriptConnection },
	_itemConnections: { RBXScriptConnection },
	_categoryId: OfficeCategoryId,
	_page: number,
	_pageCount: number,
	_pendingItemId: string?,
	_nextRequestId: number,
	_isInitialized: boolean,
	_isStarted: boolean,
}

local BuildMenuController = {}
BuildMenuController.__index = BuildMenuController
export type Controller = typeof(setmetatable({} :: ControllerData, BuildMenuController))

function BuildMenuController.new(player: Player): Controller
	return setmetatable({
		_player = player,
		_remoteClient = nil,
		_view = nil,
		_connections = {},
		_itemConnections = {},
		_categoryId = "Tiers",
		_page = 1,
		_pageCount = 0,
		_pendingItemId = nil,
		_nextRequestId = 0,
		_isInitialized = false,
		_isStarted = false,
	}, BuildMenuController)
end

function BuildMenuController.Init(self: Controller, dependencies: DependencyResolver)
	self._remoteClient = dependencies:Require("RemoteClient") :: RemoteClientType
	self._isInitialized = true
end

function BuildMenuController._requestId(self: Controller): string
	self._nextRequestId += 1
	return `client-{self._nextRequestId}`
end

function BuildMenuController._disconnectItems(self: Controller)
	for _, connection in self._itemConnections do
		connection:Disconnect()
	end
	table.clear(self._itemConnections)
end

function BuildMenuController.Refresh(self: Controller)
	local view = self._view
	local remoteClient = self._remoteClient
	if view == nil or remoteClient == nil or not self._player:GetAttribute("OfficeSessionReady") then
		return
	end
	local remote = remoteClient:GetFunction("RequestOfficeCatalog")
	if remote == nil then
		view:SetStatus("Catalog remote is unavailable.", true)
		return
	end
	local response = remote:InvokeServer({
		requestId = self:_requestId(),
		categoryId = self._categoryId,
		page = self._page,
	}) :: OfficeCatalogResponse
	if not response.ok then
		if response.error ~= nil and response.error.code == "InvalidCatalogPage" and self._page > 1 then
			self._page = math.max(1, response.pageCount)
			self:Refresh()
			return
		end
		view:SetStatus(if response.error ~= nil then response.error.message else "Catalog request failed.", true)
		return
	end
	if #response.items == 0 and self._page > 1 then
		self._page = math.max(1, math.min(self._page - 1, response.pageCount))
		self:Refresh()
		return
	end
	self._page = response.page
	self._pageCount = response.pageCount
	view:SetHeader(response.cash, response.currentTierId)
	view:SetCategory(response.categoryId)
	view:SetPage(response.page, response.pageCount)
	self:_disconnectItems()
	local actionButtons = view:RenderItems(response.items :: { BuildMenuView.CatalogItem })
	for itemId, actionButton in actionButtons do
		table.insert(
			self._itemConnections,
			actionButton.Activated:Connect(function()
				self:Purchase(itemId)
			end)
		)
	end
end

function BuildMenuController.Purchase(self: Controller, itemId: string)
	if self._pendingItemId ~= nil then
		return
	end
	local remoteClient = self._remoteClient
	local view = self._view
	if remoteClient == nil or view == nil then
		return
	end
	local remote = remoteClient:GetFunction("RequestOfficePurchase")
	if remote == nil then
		view:SetStatus("Purchase remote is unavailable.", true)
		return
	end
	self._pendingItemId = itemId
	view:SetStatus("Purchase pending…", false)
	task.spawn(function()
		local response =
			remote:InvokeServer({ requestId = self:_requestId(), itemId = itemId }) :: OfficePurchaseResponse
		self._pendingItemId = nil
		if response.ok then
			view:SetStatus("Office updated.", false)
		else
			view:SetStatus(if response.error ~= nil then response.error.message else "Purchase failed.", true)
		end
		self:Refresh()
	end)
end

function BuildMenuController.Start(self: Controller)
	if not self._isInitialized or self._isStarted then
		error("BuildMenuController.Start requires one successful Init", 2)
	end
	local playerGuiInstance = self._player:WaitForChild("PlayerGui", 10)
	if playerGuiInstance == nil or not playerGuiInstance:IsA("PlayerGui") then
		error("PlayerGui was not available for BuildMenuController", 2)
	end
	local view = BuildMenuView.new(playerGuiInstance)
	self._view = view
	local function updateReady()
		view:SetReady(self._player:GetAttribute("OfficeSessionReady") == true)
	end
	table.insert(self._connections, self._player:GetAttributeChangedSignal("OfficeSessionReady"):Connect(updateReady))
	table.insert(
		self._connections,
		view:GetBuildButton().Activated:Connect(function()
			if self._player:GetAttribute("OfficeSessionReady") == true then
				view:SetOpen(not view:IsOpen())
				if view:IsOpen() then
					self:Refresh()
				end
			end
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
		view:GetPreviousButton().Activated:Connect(function()
			if self._page > 1 then
				self._page -= 1
				self:Refresh()
			end
		end)
	)
	table.insert(
		self._connections,
		view:GetNextButton().Activated:Connect(function()
			if self._page < self._pageCount then
				self._page += 1
				self:Refresh()
			end
		end)
	)
	for category, categoryButton in view:GetCategoryButtons() do
		table.insert(
			self._connections,
			categoryButton.Activated:Connect(function()
				self._categoryId = category :: OfficeCategoryId
				self._page = 1
				self:Refresh()
			end)
		)
	end
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if
				not processed
				and input.KeyCode == Enum.KeyCode.B
				and self._player:GetAttribute("OfficeSessionReady") == true
			then
				view:SetOpen(not view:IsOpen())
				if view:IsOpen() then
					self:Refresh()
				end
			end
		end)
	)
	updateReady()
	self._isStarted = true
end

function BuildMenuController.Destroy(self: Controller)
	self:_disconnectItems()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	if self._view ~= nil then
		self._view:Destroy()
	end
	self._view = nil
	self._remoteClient = nil
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(BuildMenuController)
