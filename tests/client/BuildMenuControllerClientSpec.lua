--!strict

local Players = game:GetService("Players")

local BuildMenuController = require(script.Parent.Parent.Controllers.BuildMenuController)
local BuildMenuView = require(script.Parent.Parent.UI.BuildMenuView)

type InvokeRemote = BuildMenuController.InvokeRemote
type OfficeCatalogRequest = {
	requestId: string,
	categoryId: "Tiers" | "Rooms" | "Equipment" | "Furniture" | "Upgrades",
	page: number,
}
type OfficePurchaseRequest = {
	requestId: string,
	itemId: string,
}
type View = BuildMenuView.View

type FakeViewState = {
	statuses: { string },
	renderCount: number,
	lastCategory: string?,
	lastPage: number?,
	destroyed: boolean,
	callsAfterDestroy: number,
}

local BuildMenuControllerClientSpec = {}

local function assertTrue(value: boolean, message: string)
	if not value then
		error(message, 2)
	end
end

local function waitUntil(predicate: () -> boolean, message: string)
	local deadline = os.clock() + 3
	while not predicate() do
		if os.clock() >= deadline then
			error(message, 2)
		end
		task.wait()
	end
end

local function newFakeView(): (View, FakeViewState)
	local state: FakeViewState = {
		statuses = {},
		renderCount = 0,
		lastCategory = nil,
		lastPage = nil,
		destroyed = false,
		callsAfterDestroy = 0,
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
	function object:SetHeader(_cash: number, _tierId: string)
		touched()
	end
	function object:SetCategory(categoryId: string)
		touched()
		state.lastCategory = categoryId
	end
	function object:SetPage(page: number, _pageCount: number)
		touched()
		state.lastPage = page
	end
	function object:RenderItems(_items: { BuildMenuView.CatalogItem }): { [string]: TextButton }
		touched()
		state.renderCount += 1
		return {}
	end
	function object:Destroy()
		state.destroyed = true
	end
	local view = (object :: unknown) :: View
	return view, state
end

local function hasStatus(state: FakeViewState, expected: string): boolean
	for _, status in state.statuses do
		if status == expected then
			return true
		end
	end
	return false
end

local function purchaseExceptionCleanupAndRetryTest(player: Player)
	local view, state = newFakeView()
	local purchaseRemote = Instance.new("RemoteFunction")
	purchaseRemote.Name = "RequestOfficePurchase"
	local attempts = 0
	local invoke: InvokeRemote = function(_remote, payload): unknown
		local request = payload :: OfficePurchaseRequest
		attempts += 1
		if attempts == 1 then
			error("simulated transport exception")
		end
		return {
			ok = true,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = 2,
			currentTierId = "tier_garage",
			cash = 249400,
			state = "Purchased",
		}
	end
	local controller = BuildMenuController.new(player, {
		view = view,
		remoteResolver = function(name: string): RemoteFunction?
			return if name == "RequestOfficePurchase" then purchaseRemote else nil
		end,
		invokeRemote = invoke,
	})

	controller:Purchase("room_development")
	waitUntil(function(): boolean
		return hasStatus(state, "Purchase request failed. Please try again.")
	end, "InvokeServer exception did not replace Purchase pending with a safe error")
	controller:Purchase("room_development")
	waitUntil(function(): boolean
		return attempts == 2 and hasStatus(state, "Office updated.")
	end, "Purchase retry remained blocked after exception cleanup")
	assertTrue(attempts == 2, "Purchase pending state was not cleared for retry")
	controller:Destroy()
	purchaseRemote:Destroy()
	print("[Stage4Test] PASS client purchase exception clears pending and permits retry")
end

local function outOfOrderCatalogResponseTest(player: Player)
	local view, state = newFakeView()
	local catalogRemote = Instance.new("RemoteFunction")
	catalogRemote.Name = "RequestOfficeCatalog"
	local gates: { BindableEvent } = {}
	local requestCount = 0
	local invoke: InvokeRemote = function(_remote, payload): unknown
		local request = payload :: OfficeCatalogRequest
		requestCount += 1
		local index = requestCount
		local gate = Instance.new("BindableEvent")
		gates[index] = gate
		gate.Event:Wait()
		return {
			ok = true,
			requestId = request.requestId,
			categoryId = request.categoryId,
			page = request.page,
			pageCount = 2,
			totalItems = 6,
			revision = 1,
			currentTierId = "tier_garage",
			cash = 250000,
			items = { { itemId = `{request.categoryId}-{request.page}` } },
		}
	end
	local controller = BuildMenuController.new(player, {
		view = view,
		remoteResolver = function(name: string): RemoteFunction?
			return if name == "RequestOfficeCatalog" then catalogRemote else nil
		end,
		invokeRemote = invoke,
	})

	controller:Refresh()
	waitUntil(function(): boolean
		return requestCount == 1
	end, "First catalog request did not start")
	controller:_navigate("Rooms", 2)
	waitUntil(function(): boolean
		return requestCount == 2
	end, "Second catalog request did not start")
	gates[2]:Fire()
	waitUntil(function(): boolean
		return state.lastCategory == "Rooms" and state.lastPage == 2 and state.renderCount == 1
	end, "Newer catalog response did not render")
	gates[1]:Fire()
	task.wait()
	assertTrue(state.renderCount == 1, "Stale catalog response redrew a newer category/page")
	assertTrue(state.lastCategory == "Rooms" and state.lastPage == 2, "Stale response changed catalog location")
	controller:Destroy()
	for _, gate in gates do
		gate:Destroy()
	end
	catalogRemote:Destroy()
	print("[Stage4Test] PASS out-of-order catalog response cannot redraw newer page")
end

local function destroyDuringPendingRequestTest(player: Player)
	local view, state = newFakeView()
	local purchaseRemote = Instance.new("RemoteFunction")
	purchaseRemote.Name = "RequestOfficePurchase"
	local gate = Instance.new("BindableEvent")
	local started = false
	local invoke: InvokeRemote = function(_remote, payload): unknown
		local request = payload :: OfficePurchaseRequest
		started = true
		gate.Event:Wait()
		return {
			ok = true,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = 2,
			currentTierId = "tier_garage",
			cash = 249400,
			state = "Purchased",
		}
	end
	local controller = BuildMenuController.new(player, {
		view = view,
		remoteResolver = function(_name: string): RemoteFunction?
			return purchaseRemote
		end,
		invokeRemote = invoke,
	})
	controller:Purchase("room_development")
	waitUntil(function(): boolean
		return started
	end, "Pending purchase did not start")
	controller:Destroy()
	gate:Fire()
	task.wait()
	assertTrue(state.destroyed, "Destroy did not release build-menu view")
	assertTrue(state.callsAfterDestroy == 0, "Pending request touched a destroyed build-menu view")
	gate:Destroy()
	purchaseRemote:Destroy()
	print("[Stage4Test] PASS destroy invalidates pending build-menu callbacks")
end

function BuildMenuControllerClientSpec.run()
	local player = Players.LocalPlayer
	assertTrue(player ~= nil, "BuildMenuController client spec requires LocalPlayer")
	if player == nil then
		return
	end
	player:SetAttribute("OfficeSessionReady", true)
	purchaseExceptionCleanupAndRetryTest(player)
	outOfOrderCatalogResponseTest(player)
	destroyDuringPendingRequestTest(player)
end

return table.freeze(BuildMenuControllerClientSpec)
