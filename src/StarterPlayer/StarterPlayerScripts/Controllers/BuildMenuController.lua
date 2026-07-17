--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local OfficeRemoteTypes = require(ReplicatedStorage.Shared.Types.OfficeRemoteTypes)
local BuildMenuView = require(script.Parent.Parent.UI.BuildMenuView)
local RemoteClient = require(script.Parent.Parent.Infrastructure.RemoteClient)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type OfficeCatalogResponse = OfficeRemoteTypes.OfficeCatalogResponse
type OfficeCatalogRequest = OfficeRemoteTypes.OfficeCatalogRequest
type OfficeCategoryId = OfficeRemoteTypes.OfficeCategoryId
type OfficePurchaseRequest = OfficeRemoteTypes.OfficePurchaseRequest
type OfficePurchaseResponse = OfficeRemoteTypes.OfficePurchaseResponse
type RemoteClientType = RemoteClient.Client
type View = BuildMenuView.View

export type RemoteResolver = (name: string) -> RemoteFunction?
export type InvokeRemote = (remote: RemoteFunction, payload: OfficeCatalogRequest | OfficePurchaseRequest) -> unknown
export type Overrides = {
	view: View?,
	remoteResolver: RemoteResolver?,
	invokeRemote: InvokeRemote?,
}

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
	_catalogRequestVersion: number,
	_purchaseRequestVersion: number,
	_remoteResolver: RemoteResolver?,
	_invokeRemote: InvokeRemote,
	_isDestroyed: boolean,
	_isInitialized: boolean,
	_isStarted: boolean,
}

local BuildMenuController = {}
BuildMenuController.__index = BuildMenuController
export type Controller = typeof(setmetatable({} :: ControllerData, BuildMenuController))

local function invokeServer(remote: RemoteFunction, payload: OfficeCatalogRequest | OfficePurchaseRequest): unknown
	return remote:InvokeServer(payload)
end

function BuildMenuController.new(player: Player, overrides: Overrides?): Controller
	return setmetatable({
		_player = player,
		_remoteClient = nil,
		_view = if overrides ~= nil then overrides.view else nil,
		_connections = {},
		_itemConnections = {},
		_categoryId = "Tiers",
		_page = 1,
		_pageCount = 0,
		_pendingItemId = nil,
		_nextRequestId = 0,
		_catalogRequestVersion = 0,
		_purchaseRequestVersion = 0,
		_remoteResolver = if overrides ~= nil then overrides.remoteResolver else nil,
		_invokeRemote = if overrides ~= nil and overrides.invokeRemote ~= nil
			then overrides.invokeRemote
			else invokeServer,
		_isDestroyed = false,
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

function BuildMenuController._getRemote(self: Controller, name: string): RemoteFunction?
	if self._remoteResolver ~= nil then
		return self._remoteResolver(name)
	end
	return if self._remoteClient ~= nil then self._remoteClient:GetFunction(name) else nil
end

function BuildMenuController._isCurrentView(self: Controller, view: View): boolean
	return not self._isDestroyed and self._view == view
end

function BuildMenuController._navigate(self: Controller, categoryId: OfficeCategoryId, page: number)
	self._categoryId = categoryId
	self._page = math.max(1, page)
	self:Refresh()
end

function BuildMenuController.ToggleMenu(self: Controller)
	local view = self._view
	if view == nil or self._isDestroyed or self._player:GetAttribute("OfficeSessionReady") ~= true then
		return
	end
	view:SetOpen(not view:IsOpen())
	if view:IsOpen() then
		self:Refresh()
	end
end

function BuildMenuController.PreviousPage(self: Controller)
	if self._page > 1 then
		self:_navigate(self._categoryId, self._page - 1)
	end
end

function BuildMenuController.NextPage(self: Controller)
	if self._page < self._pageCount then
		self:_navigate(self._categoryId, self._page + 1)
	end
end

function BuildMenuController.Refresh(self: Controller)
	local view = self._view
	if view == nil or self._isDestroyed or not self._player:GetAttribute("OfficeSessionReady") then
		return
	end
	local remote = self:_getRemote("RequestOfficeCatalog")
	if remote == nil then
		view:SetStatus("Catalog remote is unavailable.", true)
		return
	end
	self._catalogRequestVersion += 1
	local requestVersion = self._catalogRequestVersion
	local categoryId = self._categoryId
	local page = self._page
	local requestId = self:_requestId()
	local request: OfficeCatalogRequest = {
		requestId = requestId,
		categoryId = categoryId,
		page = page,
	}
	task.spawn(function()
		local invokeOk, responseValue = pcall(self._invokeRemote, remote, request)
		if
			not self:_isCurrentView(view)
			or requestVersion ~= self._catalogRequestVersion
			or self._categoryId ~= categoryId
			or self._page ~= page
		then
			return
		end
		if not invokeOk then
			view:SetStatus("Catalog request failed. Please try again.", true)
			return
		end
		if typeof(responseValue) ~= "table" then
			view:SetStatus("Catalog returned an invalid response.", true)
			return
		end
		local response = responseValue :: OfficeCatalogResponse
		if response.requestId ~= requestId or response.categoryId ~= categoryId or response.page ~= page then
			view:SetStatus("Catalog returned a mismatched response.", true)
			return
		end
		if not response.ok then
			if response.error ~= nil and response.error.code == "InvalidCatalogPage" and page > 1 then
				self:_navigate(categoryId, math.max(1, response.pageCount))
				return
			end
			view:SetStatus(if response.error ~= nil then response.error.message else "Catalog request failed.", true)
			return
		end
		if #response.items == 0 and page > 1 then
			self:_navigate(categoryId, math.max(1, math.min(page - 1, response.pageCount)))
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
	end)
end

function BuildMenuController.Purchase(self: Controller, itemId: string)
	if self._pendingItemId ~= nil or self._isDestroyed then
		return
	end
	local view = self._view
	if view == nil then
		return
	end
	local remote = self:_getRemote("RequestOfficePurchase")
	if remote == nil then
		view:SetStatus("Purchase remote is unavailable.", true)
		return
	end
	self._pendingItemId = itemId
	self._purchaseRequestVersion += 1
	local requestVersion = self._purchaseRequestVersion
	view:SetStatus("Purchase pending…", false)
	local request: OfficePurchaseRequest = { requestId = self:_requestId(), itemId = itemId }
	task.spawn(function()
		local invokeOk, responseValue = pcall(self._invokeRemote, remote, request)
		if requestVersion == self._purchaseRequestVersion and self._pendingItemId == itemId then
			self._pendingItemId = nil
		end
		if requestVersion ~= self._purchaseRequestVersion or not self:_isCurrentView(view) then
			return
		end
		if not invokeOk then
			view:SetStatus("Purchase request failed. Please try again.", true)
			return
		end
		if typeof(responseValue) ~= "table" then
			view:SetStatus("Purchase returned an invalid response.", true)
			return
		end
		local response = responseValue :: OfficePurchaseResponse
		if response.requestId ~= request.requestId or response.itemId ~= itemId then
			view:SetStatus("Purchase returned a mismatched response.", true)
			return
		end
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
	self._isDestroyed = false
	local view = BuildMenuView.new(playerGuiInstance)
	self._view = view
	local function updateReady()
		view:SetReady(self._player:GetAttribute("OfficeSessionReady") == true)
	end
	table.insert(self._connections, self._player:GetAttributeChangedSignal("OfficeSessionReady"):Connect(updateReady))
	table.insert(
		self._connections,
		view:GetBuildButton().Activated:Connect(function()
			self:ToggleMenu()
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
			self:PreviousPage()
		end)
	)
	table.insert(
		self._connections,
		view:GetNextButton().Activated:Connect(function()
			self:NextPage()
		end)
	)
	for category, categoryButton in view:GetCategoryButtons() do
		table.insert(
			self._connections,
			categoryButton.Activated:Connect(function()
				self:_navigate(category :: OfficeCategoryId, 1)
			end)
		)
	end
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.KeyCode == Enum.KeyCode.B then
				self:ToggleMenu()
			end
		end)
	)
	updateReady()
	self._isStarted = true
end

function BuildMenuController.Destroy(self: Controller)
	self._isDestroyed = true
	self._catalogRequestVersion += 1
	self._purchaseRequestVersion += 1
	self._pendingItemId = nil
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
	self._remoteResolver = nil
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(BuildMenuController)
