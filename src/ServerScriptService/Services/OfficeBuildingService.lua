--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local LoggerTypes = require(ReplicatedStorage.Shared.Types.LoggerTypes)
local OfficeRemoteTypes = require(ReplicatedStorage.Shared.Types.OfficeRemoteTypes)
local OfficeCatalog = require(ServerScriptService.Domain.OfficeCatalog)
local OfficeLayoutSerializer = require(ServerScriptService.Domain.OfficeLayoutSerializer)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)
local RequestRateLimiter = require(ServerScriptService.Security.RequestRateLimiter)
local ServerRemoteRegistry = require(ServerScriptService.Infrastructure.ServerRemoteRegistry)
local SessionCurrencyService = require(ServerScriptService.Services.SessionCurrencyService)
local PlotService = require(ServerScriptService.Services.PlotService)
local OfficeLayoutBuilder = require(ServerScriptService.Systems.OfficeLayoutBuilder)

type Catalog = OfficeCatalog.Catalog
type DependencyResolver = LifecycleRegistry.DependencyResolver
type Logger = LoggerTypes.Logger
type OfficeCatalogRequest = OfficeRemoteTypes.OfficeCatalogRequest
type OfficeCatalogResponse = OfficeRemoteTypes.OfficeCatalogResponse
type OfficeCatalogPage = OfficeTypes.OfficeCatalogPage
type OfficeCategoryId = OfficeTypes.OfficeCategoryId
type OfficeConfig = OfficeTypes.OfficeConfig
type OfficeItemState = OfficeTypes.OfficeItemState
type OfficeLayoutState = OfficeTypes.OfficeLayoutState
type OfficePurchaseRequest = OfficeRemoteTypes.OfficePurchaseRequest
type OfficePurchaseResponse = OfficeRemoteTypes.OfficePurchaseResponse
type OfficeRemoteErrorCode = OfficeRemoteTypes.OfficeRemoteErrorCode
type PlotServiceType = PlotService.Service
type Progression = OfficeProgression.Progression
type RemoteRegistry = ServerRemoteRegistry.Registry
type Result<T> = AppTypes.Result<T>
type CurrencyService = SessionCurrencyService.Service
type Builder = OfficeLayoutBuilder.Builder

type CachedResponse = {
	signature: string,
	response: unknown,
}

type OfficeRuntime = {
	userId: number,
	plotId: string,
	plotGenerationToken: number,
	runtimeSessionId: string,
	layout: OfficeLayoutState,
	root: Model,
	pendingItems: { [string]: boolean },
	activeRequestId: string?,
	recentResponses: { [string]: CachedResponse },
	recentOrder: { string },
	isAcceptingPurchases: boolean,
}

type ServiceData = {
	_config: OfficeConfig,
	_progression: Progression,
	_catalog: Catalog,
	_builder: Builder,
	_limiter: RequestRateLimiter.Limiter,
	_logger: Logger,
	_plotService: PlotServiceType?,
	_currencyService: CurrencyService?,
	_remoteRegistry: RemoteRegistry?,
	_runtimes: { [number]: OfficeRuntime },
	_nextSessionId: number,
	_isInitialized: boolean,
	_isStarted: boolean,
	_isDestroyed: boolean,
}

local OfficeBuildingService = {}
OfficeBuildingService.__index = OfficeBuildingService
export type Service = typeof(setmetatable({} :: ServiceData, OfficeBuildingService))

local MAX_RECENT_RESPONSES = 64

local SAFE_ERROR_CODES: { [string]: OfficeRemoteErrorCode } = {
	InvalidPayload = "InvalidPayload",
	RateLimited = "RateLimited",
	RequestIdConflict = "RequestIdConflict",
	PurchaseInProgress = "PurchaseInProgress",
	OfficeSessionNotReady = "OfficeSessionNotReady",
	UnknownOfficeItem = "UnknownOfficeItem",
	InvalidOfficeCategory = "InvalidOfficeCategory",
	InvalidCatalogPage = "InvalidCatalogPage",
	InsufficientFunds = "InsufficientFunds",
	ItemAlreadyPurchased = "ItemAlreadyPurchased",
	InitialTierAlreadyOwned = "InitialTierAlreadyOwned",
	OfficeTierLocked = "OfficeTierLocked",
	PrerequisiteMissing = "PrerequisiteMissing",
	RequiredRoomMissing = "RequiredRoomMissing",
	EquipmentSlotOccupied = "EquipmentSlotOccupied",
	UpgradeTargetMissing = "UpgradeTargetMissing",
	UpgradeMaxLevel = "UpgradeMaxLevel",
	PlacementOutOfBounds = "OfficeBoundsViolation",
	ItemOutsideRoom = "OfficeBoundsViolation",
	DoorwayBlocked = "OfficeBoundsViolation",
	SpawnClearanceBlocked = "OfficeBoundsViolation",
	EntrancePathBlocked = "OfficeBoundsViolation",
	GeometryOverlap = "OfficeBoundsViolation",
	RoomShellReservedZone = "OfficeBoundsViolation",
	TemplateMissing = "OfficeBuildFailed",
	TemplateInvalid = "OfficeBuildFailed",
	BuildGenerationFailed = "OfficeBuildFailed",
	PlacementUnknown = "OfficeBuildFailed",
	UnknownOfficeTier = "OfficeBuildFailed",
	InvalidPlotSpawn = "OfficeBuildFailed",
	StalePlotGeneration = "TransactionFailed",
	TransactionCommitFailed = "TransactionFailed",
	TransactionIdConflict = "TransactionFailed",
}

local function safeError(internalCode: string): OfficeRemoteTypes.OfficeRemoteError
	local code = SAFE_ERROR_CODES[internalCode] or "InternalError"
	local messages: { [OfficeRemoteErrorCode]: string } = {
		InvalidPayload = "The request was invalid.",
		RateLimited = "Please wait before trying again.",
		RequestIdConflict = "The request identifier was already used.",
		PurchaseInProgress = "Another office purchase is still processing.",
		OfficeSessionNotReady = "Your office is not ready yet.",
		InsufficientFunds = "You do not have enough Cash.",
		ItemAlreadyPurchased = "This item is already purchased.",
		InitialTierAlreadyOwned = "Garage is already unlocked.",
		OfficeTierLocked = "Unlock the required office tier first.",
		PrerequisiteMissing = "Complete the required purchases first.",
		RequiredRoomMissing = "Build the required room first.",
		EquipmentSlotOccupied = "The required slot is occupied.",
		UpgradeTargetMissing = "Purchase the equipment before upgrading it.",
		UpgradeMaxLevel = "This upgrade is already at maximum level.",
		UnknownOfficeItem = "That office item is not available.",
		InvalidOfficeCategory = "That catalog category is not available.",
		InvalidCatalogPage = "That catalog page is not available.",
		OfficeBoundsViolation = "That office layout cannot be built safely.",
		OfficeBuildFailed = "The office model could not be generated.",
		TransactionFailed = "The purchase could not be committed.",
		InternalError = "The office request could not be completed.",
	}
	return { code = code, message = messages[code] }
end

local function remember(runtime: OfficeRuntime, requestId: string, signature: string, response: unknown)
	if runtime.recentResponses[requestId] == nil then
		table.insert(runtime.recentOrder, requestId)
	end
	runtime.recentResponses[requestId] = { signature = signature, response = response }
	while #runtime.recentOrder > MAX_RECENT_RESPONSES do
		local evicted = table.remove(runtime.recentOrder, 1)
		runtime.recentResponses[evicted] = nil
	end
end

function OfficeBuildingService.new(
	config: OfficeConfig,
	progression: Progression,
	catalog: Catalog,
	builder: Builder,
	limiter: RequestRateLimiter.Limiter,
	logger: Logger
): Service
	return setmetatable({
		_config = config,
		_progression = progression,
		_catalog = catalog,
		_builder = builder,
		_limiter = limiter,
		_logger = logger,
		_plotService = nil,
		_currencyService = nil,
		_remoteRegistry = nil,
		_runtimes = {},
		_nextSessionId = 0,
		_isInitialized = false,
		_isStarted = false,
		_isDestroyed = false,
	}, OfficeBuildingService)
end

function OfficeBuildingService.Init(self: Service, dependencies: DependencyResolver)
	self._plotService = dependencies:Require("PlotService") :: PlotServiceType
	self._currencyService = dependencies:Require("SessionCurrencyService") :: CurrencyService
	self._remoteRegistry = dependencies:Require("ServerRemoteRegistry") :: RemoteRegistry
	self._isInitialized = true
end

function OfficeBuildingService.Start(self: Service)
	if not self._isInitialized or self._isStarted or self._isDestroyed then
		error("OfficeBuildingService.Start requires one successful Init", 2)
	end
	local remotes = self._remoteRegistry :: RemoteRegistry
	local catalogBinding = remotes:BindFunction(
		"RequestOfficeCatalog",
		function(player: Player, payload: unknown): unknown
			return self:HandleCatalogRequest(player.UserId, payload :: OfficeCatalogRequest)
		end
	)
	if not catalogBinding.ok then
		error(`Could not bind RequestOfficeCatalog: {catalogBinding.error.code}`, 2)
	end
	local purchaseBinding = remotes:BindFunction(
		"RequestOfficePurchase",
		function(player: Player, payload: unknown): unknown
			return self:Purchase(player.UserId, payload :: OfficePurchaseRequest)
		end
	)
	if not purchaseBinding.ok then
		error(`Could not bind RequestOfficePurchase: {purchaseBinding.error.code}`, 2)
	end
	self._isStarted = true
end

function OfficeBuildingService.PrepareSession(
	self: Service,
	userId: number,
	restoredLayout: OfficeLayoutState?
): Result<OfficeLayoutState>
	if self._runtimes[userId] ~= nil then
		return AppTypes.failure("OfficeSessionAlreadyOpen", "Office session is already open", nil)
	end
	local plotService = self._plotService :: PlotServiceType
	local contextResult = plotService:GetOwnedPlotContextForUserId(userId)
	if not contextResult.ok then
		return contextResult
	end
	local layout = if restoredLayout ~= nil
		then OfficeLayoutSerializer.Copy(restoredLayout)
		else self._progression:CreateInitialLayout()
	local validationResult =
		OfficeLayoutSerializer.Validate(layout, self._config.schemaVersion, self._config.configVersion)
	if not validationResult.ok then
		return validationResult
	end
	local buildResult = self._builder:BuildReplacementRoot(contextResult.value, layout)
	if not buildResult.ok then
		return buildResult
	end
	local root = buildResult.value
	if contextResult.value.model:FindFirstChild("OfficeBuildRoot") ~= nil then
		root:Destroy()
		return AppTypes.failure("BuildCommitFailed", "Plot already contains an office root", nil)
	end
	root.Name = "OfficeBuildRoot"
	root.Parent = contextResult.value.model
	self._nextSessionId += 1
	self._runtimes[userId] = {
		userId = userId,
		plotId = contextResult.value.definition.id,
		plotGenerationToken = contextResult.value.generationToken,
		runtimeSessionId = tostring(self._nextSessionId),
		layout = layout,
		root = root,
		pendingItems = {},
		activeRequestId = nil,
		recentResponses = {},
		recentOrder = {},
		isAcceptingPurchases = true,
	}
	return AppTypes.success(OfficeLayoutSerializer.Copy(layout))
end

function OfficeBuildingService.GetCatalogPage(
	self: Service,
	userId: number,
	categoryId: OfficeCategoryId,
	page: number
): Result<OfficeCatalogPage>
	local runtime = self._runtimes[userId]
	if runtime == nil then
		return AppTypes.failure("OfficeSessionNotReady", "Office session is not open", nil)
	end
	local balanceResult = (self._currencyService :: CurrencyService):GetBalance(userId, "Cash")
	if not balanceResult.ok then
		return AppTypes.failure(balanceResult.error.code, balanceResult.error.message, nil)
	end
	return self._catalog:GetPage(runtime.layout, balanceResult.value, categoryId, page, runtime.pendingItems)
end

function OfficeBuildingService.HandleCatalogRequest(
	self: Service,
	userId: number,
	request: OfficeCatalogRequest
): OfficeCatalogResponse
	local runtime = self._runtimes[userId]
	local signature = `{request.categoryId}:{request.page}`
	if runtime == nil then
		return {
			ok = false,
			requestId = request.requestId,
			categoryId = request.categoryId,
			page = request.page,
			pageCount = 0,
			totalItems = 0,
			revision = 0,
			currentTierId = "tier_garage",
			cash = 0,
			items = {},
			error = safeError("OfficeSessionNotReady"),
		}
	end
	local cached = runtime.recentResponses[request.requestId]
	if cached ~= nil then
		if cached.signature ~= signature then
			return {
				ok = false,
				requestId = request.requestId,
				categoryId = request.categoryId,
				page = request.page,
				pageCount = 0,
				totalItems = 0,
				revision = runtime.layout.revision,
				currentTierId = runtime.layout.officeTierId,
				cash = 0,
				items = {},
				error = safeError("RequestIdConflict"),
			}
		end
		return cached.response :: OfficeCatalogResponse
	end
	if not self._limiter:Allow(userId, "catalog", 4, 1) then
		local response: OfficeCatalogResponse = {
			ok = false,
			requestId = request.requestId,
			categoryId = request.categoryId,
			page = request.page,
			pageCount = 0,
			totalItems = 0,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = 0,
			items = {},
			error = safeError("RateLimited"),
		}
		remember(runtime, request.requestId, signature, response)
		return response
	end
	local pageResult = self:GetCatalogPage(userId, request.categoryId, request.page)
	if not pageResult.ok then
		local counts = self._catalog:GetCategoryCounts()
		local totalItems = counts[request.categoryId] or 0
		local pageCount = math.ceil(totalItems / self._config.pageSize)
		local balanceResult = (self._currencyService :: CurrencyService):GetBalance(userId, "Cash")
		local response: OfficeCatalogResponse = {
			ok = false,
			requestId = request.requestId,
			categoryId = request.categoryId,
			page = request.page,
			pageCount = pageCount,
			totalItems = totalItems,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = if balanceResult.ok then balanceResult.value else 0,
			items = {},
			error = safeError(pageResult.error.code),
		}
		remember(runtime, request.requestId, signature, response)
		return response
	end
	local page = pageResult.value
	local response: OfficeCatalogResponse = {
		ok = true,
		requestId = request.requestId,
		categoryId = page.categoryId,
		page = page.page,
		pageCount = page.pageCount,
		totalItems = page.totalItems,
		revision = page.revision,
		currentTierId = page.currentTierId,
		cash = page.cash,
		items = page.items :: { unknown },
	}
	remember(runtime, request.requestId, signature, response)
	return response
end

local function copyWithPurchase(
	config: OfficeConfig,
	progression: Progression,
	layout: OfficeLayoutState,
	itemId: string
): Result<OfficeLayoutState>
	local nextLayout = OfficeLayoutSerializer.Copy(layout)
	local tier = progression:GetTier(itemId)
	if tier ~= nil then
		nextLayout.officeTierId = tier.id
	elseif progression:GetRoom(itemId) ~= nil then
		local room = progression:GetRoom(itemId) :: OfficeTypes.RoomDefinition
		nextLayout.purchasedRooms[itemId] = true
		nextLayout.placementKeys[itemId] = room.placementKey
	elseif progression:GetItem(itemId) ~= nil then
		local item = progression:GetItem(itemId) :: OfficeTypes.ItemDefinition
		if item.kind == "Equipment" then
			nextLayout.purchasedEquipment[item.id] = true
		else
			nextLayout.purchasedFurniture[item.id] = true
		end
		nextLayout.occupiedSlots[item.slotId] = { itemId = item.id, placementKey = item.placementKey }
		nextLayout.placementKeys[item.id] = item.placementKey
		if item.kind == "Equipment" then
			for _, upgrade in config.upgrades do
				if upgrade.targetItemId == item.id then
					nextLayout.upgradeLevels[upgrade.id] = 1
					break
				end
			end
		end
	elseif progression:GetUpgrade(itemId) ~= nil then
		nextLayout.upgradeLevels[itemId] = (nextLayout.upgradeLevels[itemId] or 1) + 1
	else
		return AppTypes.failure("UnknownOfficeItem", "Office item is not defined", nil)
	end
	nextLayout.revision += 1
	return AppTypes.success(nextLayout)
end

function OfficeBuildingService.Purchase(
	self: Service,
	userId: number,
	request: OfficePurchaseRequest
): OfficePurchaseResponse
	local runtime = self._runtimes[userId]
	if runtime == nil or not runtime.isAcceptingPurchases then
		return {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = 0,
			currentTierId = "tier_garage",
			cash = 0,
			state = "Locked",
			error = safeError("OfficeSessionNotReady"),
		}
	end
	local cached = runtime.recentResponses[request.requestId]
	if cached ~= nil then
		if cached.signature ~= request.itemId then
			return {
				ok = false,
				requestId = request.requestId,
				itemId = request.itemId,
				revision = runtime.layout.revision,
				currentTierId = runtime.layout.officeTierId,
				cash = 0,
				state = "Locked",
				error = safeError("RequestIdConflict"),
			}
		end
		return cached.response :: OfficePurchaseResponse
	end
	if not self._limiter:Allow(userId, "purchase", 6, 2) then
		return {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = 0,
			state = "Locked",
			error = safeError("RateLimited"),
		}
	end
	if runtime.activeRequestId ~= nil then
		return {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = 0,
			state = "Pending",
			error = safeError("PurchaseInProgress"),
		}
	end

	local currency = self._currencyService :: CurrencyService
	local balanceResult = currency:GetBalance(userId, "Cash")
	local evaluationResult = self._progression:Evaluate(runtime.layout, request.itemId, false)
	if not balanceResult.ok or not evaluationResult.ok then
		return {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = if balanceResult.ok then balanceResult.value else 0,
			state = "Locked",
			error = safeError(if evaluationResult.ok then "InternalError" else evaluationResult.error.code),
		}
	end
	local evaluation = evaluationResult.value
	if evaluation.state ~= "Available" then
		local code = if request.itemId == "tier_garage"
			then "InitialTierAlreadyOwned"
			elseif evaluation.state == "MaxLevel" then "UpgradeMaxLevel"
			elseif evaluation.state == "Purchased" then "ItemAlreadyPurchased"
			else evaluation.code or "PrerequisiteMissing"
		local response: OfficePurchaseResponse = {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = balanceResult.value,
			state = evaluation.state,
			currentLevel = evaluation.currentLevel,
			error = safeError(code),
		}
		remember(runtime, request.requestId, request.itemId, response)
		return response
	end

	runtime.activeRequestId = request.requestId
	runtime.pendingItems[request.itemId] = true
	local transactionId = `office:{userId}:{runtime.runtimeSessionId}:{request.requestId}`
	local reserveResult =
		currency:ReserveDebit(userId, "Cash", evaluation.price, `OfficePurchase:{request.itemId}`, transactionId)
	if not reserveResult.ok then
		runtime.activeRequestId = nil
		runtime.pendingItems[request.itemId] = nil
		local response: OfficePurchaseResponse = {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = balanceResult.value,
			state = "Available",
			currentLevel = evaluation.currentLevel,
			error = safeError(reserveResult.error.code),
		}
		remember(runtime, request.requestId, request.itemId, response)
		return response
	end
	local reservation = reserveResult.value
	local previousLayout = runtime.layout
	local nextLayoutResult = copyWithPurchase(self._config, self._progression, runtime.layout, request.itemId)
	local plotService = self._plotService :: PlotServiceType
	local contextResult = plotService:GetOwnedPlotContextForUserId(userId)
	if
		not nextLayoutResult.ok
		or not contextResult.ok
		or contextResult.value.generationToken ~= runtime.plotGenerationToken
	then
		currency:ReleaseDebit(reservation.reservationId)
		runtime.activeRequestId = nil
		runtime.pendingItems[request.itemId] = nil
		local response: OfficePurchaseResponse = {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = balanceResult.value,
			state = "Available",
			error = safeError("StalePlotGeneration"),
		}
		remember(runtime, request.requestId, request.itemId, response)
		return response
	end
	local nextLayout = nextLayoutResult.value
	local buildResult = self._builder:BuildReplacementRoot(contextResult.value, nextLayout)
	if not buildResult.ok then
		currency:ReleaseDebit(reservation.reservationId)
		runtime.activeRequestId = nil
		runtime.pendingItems[request.itemId] = nil
		local response: OfficePurchaseResponse = {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = balanceResult.value,
			state = "Available",
			error = safeError(buildResult.error.code),
		}
		remember(runtime, request.requestId, request.itemId, response)
		return response
	end

	local pendingRoot = buildResult.value
	local oldRoot = runtime.root
	pendingRoot.Name = `OfficeBuildRoot__tx__{request.requestId}`
	local commitResult = currency:CommitDebit(reservation.reservationId)
	if not commitResult.ok then
		pendingRoot:Destroy()
		currency:ReleaseDebit(reservation.reservationId)
		runtime.activeRequestId = nil
		runtime.pendingItems[request.itemId] = nil
		local response: OfficePurchaseResponse = {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = runtime.layout.revision,
			currentTierId = runtime.layout.officeTierId,
			cash = balanceResult.value,
			state = "Available",
			error = safeError("TransactionCommitFailed"),
		}
		remember(runtime, request.requestId, request.itemId, response)
		return response
	end

	local publishOk, publishCause = xpcall(function()
		oldRoot.Name = `OfficeBuildRoot__old__{request.requestId}`
		pendingRoot.Name = "OfficeBuildRoot"
		pendingRoot.Parent = contextResult.value.model
		oldRoot:Destroy()
	end, function(errorValue: unknown): string
		return debug.traceback(tostring(errorValue), 2)
	end)
	if not publishOk then
		local cleanupOk, cleanupCause = pcall(function()
			pendingRoot:Destroy()
		end)
		if oldRoot.Parent ~= nil then
			oldRoot.Name = "OfficeBuildRoot"
		end
		runtime.layout = previousLayout
		runtime.root = oldRoot
		local compensationResult = currency:RollbackCommittedDebit(reservation.reservationId)
		self._logger:Error("office_visual_commit_failed", {
			userId = userId,
			itemId = request.itemId,
			cause = publishCause,
			cleanupSucceeded = cleanupOk,
			cleanupCause = if cleanupOk then "none" else tostring(cleanupCause),
			compensationSucceeded = compensationResult.ok,
		})
		runtime.activeRequestId = nil
		runtime.pendingItems[request.itemId] = nil
		local response: OfficePurchaseResponse = {
			ok = false,
			requestId = request.requestId,
			itemId = request.itemId,
			revision = previousLayout.revision,
			currentTierId = previousLayout.officeTierId,
			cash = if compensationResult.ok then compensationResult.value.balances.Cash else balanceResult.value,
			state = "Available",
			error = safeError("TransactionCommitFailed"),
		}
		remember(runtime, request.requestId, request.itemId, response)
		return response
	end
	runtime.layout = nextLayout
	runtime.root = pendingRoot
	runtime.activeRequestId = nil
	runtime.pendingItems[request.itemId] = nil
	local finalEvaluation = self._progression:Evaluate(runtime.layout, request.itemId, false)
	local finalState: OfficeItemState = if finalEvaluation.ok then finalEvaluation.value.state else "Purchased"
	local response: OfficePurchaseResponse = {
		ok = true,
		requestId = request.requestId,
		itemId = request.itemId,
		revision = runtime.layout.revision,
		currentTierId = runtime.layout.officeTierId,
		cash = commitResult.value.balances.Cash,
		state = finalState,
		currentLevel = if finalEvaluation.ok then finalEvaluation.value.currentLevel else nil,
	}
	remember(runtime, request.requestId, request.itemId, response)
	return response
end

function OfficeBuildingService.StopPurchases(self: Service, userId: number): Result<true>
	local runtime = self._runtimes[userId]
	if runtime == nil then
		return AppTypes.failure("OfficeSessionNotReady", "Office session is not open", nil)
	end
	runtime.isAcceptingPurchases = false
	return AppTypes.success(true)
end

function OfficeBuildingService.ExportLayout(self: Service, userId: number): Result<OfficeLayoutState>
	local runtime = self._runtimes[userId]
	if runtime == nil or runtime.activeRequestId ~= nil then
		return AppTypes.failure("OfficeSessionNotReady", "Office layout cannot be exported", nil)
	end
	return AppTypes.success(OfficeLayoutSerializer.Copy(runtime.layout))
end

function OfficeBuildingService.CloseSession(self: Service, userId: number): Result<boolean>
	local runtime = self._runtimes[userId]
	if runtime == nil then
		return AppTypes.success(false)
	end
	runtime.root:Destroy()
	self._runtimes[userId] = nil
	self._limiter:ClearPlayer(userId)
	return AppTypes.success(true)
end

function OfficeBuildingService.AbortSession(self: Service, userId: number): Result<boolean>
	return self:CloseSession(userId)
end

function OfficeBuildingService.ValidateRuntimeState(self: Service, userId: number): Result<true>
	local runtime = self._runtimes[userId]
	if runtime == nil then
		return AppTypes.failure("OfficeSessionNotReady", "Office session is not open", nil)
	end
	local contextResult = (self._plotService :: PlotServiceType):GetOwnedPlotContextForUserId(userId)
	if not contextResult.ok then
		return contextResult
	end
	local canonicalCount = 0
	for _, child in contextResult.value.model:GetChildren() do
		if child.Name == "OfficeBuildRoot" then
			canonicalCount += 1
		elseif string.find(child.Name, "OfficeBuildRoot__", 1, true) == 1 then
			return AppTypes.failure("OrphanedOfficeRoot", "Temporary office root remains", { name = child.Name })
		end
	end
	if
		canonicalCount ~= 1
		or runtime.root.Name ~= "OfficeBuildRoot"
		or runtime.root.Parent ~= contextResult.value.model
	then
		return AppTypes.failure("OfficeRootInvariantFailed", "Office root ownership is inconsistent", nil)
	end
	return AppTypes.success(true)
end

function OfficeBuildingService.Destroy(self: Service)
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true
	local userIds = {}
	for userId in self._runtimes do
		table.insert(userIds, userId)
	end
	for _, userId in userIds do
		self:CloseSession(userId)
	end
	self._limiter:Destroy()
	self._plotService = nil
	self._currencyService = nil
	self._remoteRegistry = nil
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(OfficeBuildingService)
