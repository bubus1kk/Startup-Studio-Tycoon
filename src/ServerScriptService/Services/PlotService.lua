--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local LoggerTypes = require(ReplicatedStorage.Shared.Types.LoggerTypes)
local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)
local OfficeShellBuilder = require(ServerScriptService.Systems.OfficeShellBuilder)

type Builder = OfficeShellBuilder.Builder
type DependencyResolver = LifecycleRegistry.DependencyResolver
type Logger = LoggerTypes.Logger
type PlotAllocation = PlotTypes.PlotAllocation
type PlotAllocationSnapshot = PlotTypes.PlotAllocationSnapshot
type PlotConfig = PlotTypes.PlotConfig
type PlotContext = PlotTypes.PlotContext
type PlotDefinition = PlotTypes.PlotDefinition
type PlotSpawnContext = PlotTypes.PlotSpawnContext
type Result<T> = AppTypes.Result<T>

type ServiceData = {
	_workspaceRoot: Instance,
	_config: PlotConfig,
	_builder: Builder,
	_logger: Logger,
	_definitionById: { [string]: PlotDefinition },
	_playerToPlot: { [number]: string },
	_plotToPlayer: { [string]: number },
	_allocations: { [string]: PlotAllocation },
	_nextGenerationToken: number,
	_mapFolder: Folder?,
	_plotsFolder: Folder?,
	_ownsMapFolder: boolean,
	_ownsPlotsFolder: boolean,
	_isInitialized: boolean,
	_isStarted: boolean,
	_isDestroyed: boolean,
}

local PlotService = {}
PlotService.__index = PlotService

export type Service = typeof(setmetatable({} :: ServiceData, PlotService))

local function snapshot(allocation: PlotAllocation): PlotAllocationSnapshot
	return {
		plotId = allocation.plotId,
		userId = allocation.userId,
		state = allocation.state,
	}
end

local function ensureFolder(parent: Instance, name: string): (Folder, boolean)
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		if not existing:IsA("Folder") then
			error(`{parent:GetFullName()}.{name} must be a Folder`, 2)
		end
		return existing, false
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder, true
end

function PlotService.new(workspaceRoot: Instance, config: PlotConfig, builder: Builder, logger: Logger): Service
	local definitionById: { [string]: PlotDefinition } = {}
	for _, definition in config.definitions do
		definitionById[definition.id] = definition
	end

	return setmetatable({
		_workspaceRoot = workspaceRoot,
		_config = config,
		_builder = builder,
		_logger = logger,
		_definitionById = definitionById,
		_playerToPlot = {},
		_plotToPlayer = {},
		_allocations = {},
		_nextGenerationToken = 0,
		_mapFolder = nil,
		_plotsFolder = nil,
		_ownsMapFolder = false,
		_ownsPlotsFolder = false,
		_isInitialized = false,
		_isStarted = false,
		_isDestroyed = false,
	}, PlotService)
end

function PlotService.Init(self: Service, _dependencies: DependencyResolver)
	if self._isInitialized or self._isDestroyed then
		error("PlotService.Init can only run once", 2)
	end

	local mapFolder, ownsMapFolder = ensureFolder(self._workspaceRoot, "Map")
	local plotsOk, plotsFolderOrError, ownsPlotsFolder = pcall(function(): (Folder, boolean)
		return ensureFolder(mapFolder, "Plots")
	end)
	if not plotsOk then
		if ownsMapFolder then
			mapFolder:Destroy()
		end
		error(tostring(plotsFolderOrError), 2)
	end
	local plotsFolder = plotsFolderOrError :: Folder
	self._mapFolder = mapFolder
	self._plotsFolder = plotsFolder
	self._ownsMapFolder = ownsMapFolder
	self._ownsPlotsFolder = ownsPlotsFolder :: boolean
	self._isInitialized = true
end

function PlotService.Start(self: Service)
	if not self._isInitialized or self._isStarted or self._isDestroyed then
		error("PlotService.Start requires one successful Init", 2)
	end
	self._isStarted = true
	self._logger:Info("plot_service_started", {
		plotCount = #self._config.definitions,
		maxPlayers = self._config.maxPlayers,
	})
end

function PlotService.AssignPlayer(self: Service, userId: number): Result<PlotAllocationSnapshot>
	if not self._isInitialized or self._isDestroyed then
		return AppTypes.failure("PlotServiceUnavailable", "Plot service is not available", nil)
	end
	-- Studio multi-client sessions use stable negative test UserIds. Zero is the
	-- only invalid sentinel; production identities remain positive integers.
	if userId == 0 or userId % 1 ~= 0 then
		return AppTypes.failure("InvalidUserId", "User ID must be a non-zero integer", {
			userId = tostring(userId),
		})
	end

	local existingPlotId = self._playerToPlot[userId]
	if existingPlotId ~= nil then
		local existingAllocation = self._allocations[existingPlotId]
		if existingAllocation ~= nil and existingAllocation.userId == userId then
			return AppTypes.success(snapshot(existingAllocation))
		end
		return AppTypes.failure("PlotOwnershipInvariantFailed", "Player ownership map is inconsistent", {
			userId = tostring(userId),
			plotId = existingPlotId,
		})
	end

	local selectedDefinition: PlotDefinition? = nil
	for _, definition in self._config.definitions do
		if self._plotToPlayer[definition.id] == nil then
			selectedDefinition = definition
			break
		end
	end
	if selectedDefinition == nil then
		self._logger:Warn("plot_capacity_exhausted", {
			userId = userId,
			plotCount = #self._config.definitions,
		})
		return AppTypes.failure("NoAvailablePlot", "No office plot is available", nil)
	end

	self._nextGenerationToken += 1
	local allocation: PlotAllocation = {
		plotId = selectedDefinition.id,
		userId = userId,
		state = "Reserved",
		generationToken = self._nextGenerationToken,
		model = nil,
	}

	-- This reservation is intentionally synchronous and non-yielding. A plot is
	-- unavailable to the next PlayerAdded callback before generation begins.
	self._playerToPlot[userId] = selectedDefinition.id
	self._plotToPlayer[selectedDefinition.id] = userId
	self._allocations[selectedDefinition.id] = allocation

	local buildCallOk, rawBuildResult = pcall(function()
		return self._builder:Build(selectedDefinition :: PlotDefinition)
	end)
	if not buildCallOk then
		self:ReleasePlayer(userId)
		return AppTypes.failure("PlotGenerationFailed", "Starter office generation raised an error", {
			plotId = selectedDefinition.id,
			cause = tostring(rawBuildResult),
		})
	end

	local buildResult = rawBuildResult :: Result<Model>
	if not buildResult.ok then
		self:ReleasePlayer(userId)
		return AppTypes.failure("PlotGenerationFailed", "Starter office generation failed", {
			plotId = selectedDefinition.id,
			cause = buildResult.error.code,
		})
	end

	local model = buildResult.value
	allocation.model = model
	local isInsideBounds, invalidPart = PlotBounds.validateModel(selectedDefinition, model)
	if not isInsideBounds then
		self:ReleasePlayer(userId)
		return AppTypes.failure("PlotGenerationOutOfBounds", "Generated office escaped plot boundaries", {
			plotId = selectedDefinition.id,
			part = invalidPart or "unknown",
		})
	end

	local currentAllocation = self._allocations[selectedDefinition.id]
	if
		currentAllocation ~= allocation
		or currentAllocation.generationToken ~= allocation.generationToken
		or self._playerToPlot[userId] ~= selectedDefinition.id
		or self._plotToPlayer[selectedDefinition.id] ~= userId
	then
		model:Destroy()
		return AppTypes.failure("StalePlotGeneration", "Plot generation reservation is no longer current", {
			plotId = selectedDefinition.id,
		})
	end

	local plotsFolder = self._plotsFolder
	if plotsFolder == nil then
		self:ReleasePlayer(userId)
		return AppTypes.failure("PlotServiceUnavailable", "Runtime plot container is missing", nil)
	end
	if plotsFolder:FindFirstChild(selectedDefinition.id) ~= nil then
		self:ReleasePlayer(userId)
		return AppTypes.failure("PlotModelCollision", "Runtime plot model already exists", {
			plotId = selectedDefinition.id,
		})
	end

	model.Name = selectedDefinition.id
	model:SetAttribute("PlotId", selectedDefinition.id)
	model:SetAttribute("OwnerUserId", userId)
	model.Parent = plotsFolder
	allocation.state = "Active"

	self._logger:Info("plot_assigned", {
		plotId = selectedDefinition.id,
		userId = userId,
	})
	return AppTypes.success(snapshot(allocation))
end

function PlotService.ReleasePlayer(self: Service, userId: number): Result<boolean>
	local plotId = self._playerToPlot[userId]
	if plotId == nil then
		return AppTypes.success(false)
	end

	local allocation = self._allocations[plotId]
	if allocation ~= nil and allocation.userId == userId then
		allocation.state = "Releasing"
		self._nextGenerationToken += 1
		allocation.generationToken = self._nextGenerationToken
	end

	self._playerToPlot[userId] = nil
	if self._plotToPlayer[plotId] == userId then
		self._plotToPlayer[plotId] = nil
	end
	if allocation ~= nil and allocation.userId == userId then
		local model = allocation.model
		allocation.model = nil
		self._allocations[plotId] = nil
		if model ~= nil then
			model:Destroy()
		end
	end

	self._logger:Info("plot_released", {
		plotId = plotId,
		userId = userId,
	})
	return AppTypes.success(true)
end

function PlotService.GetPlotIdForUserId(self: Service, userId: number): string?
	return self._playerToPlot[userId]
end

function PlotService.GetOwnerUserId(self: Service, plotId: string): number?
	return self._plotToPlayer[plotId]
end

function PlotService.GetRuntimePlotModel(self: Service, plotId: string): Model?
	local allocation = self._allocations[plotId]
	return if allocation ~= nil and allocation.state == "Active" then allocation.model else nil
end

function PlotService.GetSpawnCFrameForUserId(self: Service, userId: number): CFrame?
	local spawnContext = self:GetSpawnContextForUserId(userId)
	return if spawnContext ~= nil then spawnContext.spawnCFrame else nil
end

function PlotService.GetSpawnContextForUserId(self: Service, userId: number): PlotSpawnContext?
	local plotId = self._playerToPlot[userId]
	if plotId == nil or self._plotToPlayer[plotId] ~= userId then
		return nil
	end
	local allocation = self._allocations[plotId]
	local definition = self._definitionById[plotId]
	if
		allocation == nil
		or allocation.userId ~= userId
		or allocation.state ~= "Active"
		or allocation.model == nil
		or definition == nil
	then
		return nil
	end

	local spawnInstance = allocation.model:FindFirstChild("SpawnLocation")
	if spawnInstance == nil or not spawnInstance:IsA("SpawnLocation") then
		return nil
	end

	return {
		plotId = plotId,
		userId = userId,
		generationToken = allocation.generationToken,
		spawnCFrame = definition.origin * definition.spawnOffset * CFrame.new(0, 4, 0),
		spawnLocation = spawnInstance,
	}
end

function PlotService.RequireOwnership(self: Service, userId: number, plotId: string): Result<PlotContext>
	local definition = self._definitionById[plotId]
	if definition == nil then
		return AppTypes.failure("UnknownPlot", "Plot ID is not defined", { plotId = plotId })
	end

	local assignedPlotId = self._playerToPlot[userId]
	if assignedPlotId == nil then
		return AppTypes.failure("PlayerHasNoPlot", "Player has no assigned plot", {
			userId = tostring(userId),
		})
	end
	if assignedPlotId ~= plotId or self._plotToPlayer[plotId] ~= userId then
		return AppTypes.failure("PlotOwnershipMismatch", "Player does not own the requested plot", {
			userId = tostring(userId),
			plotId = plotId,
		})
	end

	local allocation = self._allocations[plotId]
	local model = if allocation ~= nil then allocation.model else nil
	if allocation == nil or allocation.state ~= "Active" or model == nil then
		return AppTypes.failure("PlotNotActive", "Owned plot is not active", { plotId = plotId })
	end

	return AppTypes.success({
		definition = definition,
		model = model,
	})
end

function PlotService.ValidateRuntimeState(self: Service): Result<true>
	for userId, plotId in self._playerToPlot do
		if self._plotToPlayer[plotId] ~= userId then
			return AppTypes.failure("PlotOwnershipInvariantFailed", "Forward ownership has no reverse entry", {
				userId = tostring(userId),
				plotId = plotId,
			})
		end
	end
	for plotId, userId in self._plotToPlayer do
		if self._playerToPlot[userId] ~= plotId then
			return AppTypes.failure("PlotOwnershipInvariantFailed", "Reverse ownership has no forward entry", {
				userId = tostring(userId),
				plotId = plotId,
			})
		end
	end

	local plotsFolder = self._plotsFolder
	if plotsFolder == nil then
		local mapInstance = self._workspaceRoot:FindFirstChild("Map")
		if mapInstance ~= nil and mapInstance:IsA("Folder") then
			local plotsInstance = mapInstance:FindFirstChild("Plots")
			if plotsInstance ~= nil and plotsInstance:IsA("Folder") then
				plotsFolder = plotsInstance
			end
		end
	end
	if plotsFolder == nil then
		if next(self._allocations) == nil then
			return AppTypes.success(true)
		end
		return AppTypes.failure("OrphanedPlotAllocation", "Allocations exist without a runtime container", nil)
	end

	local seenModels: { [string]: boolean } = {}
	for _, child in plotsFolder:GetChildren() do
		if not child:IsA("Model") then
			return AppTypes.failure("UnexpectedPlotInstance", "Runtime plot container contains a non-Model", {
				name = child.Name,
			})
		end
		local plotId = child:GetAttribute("PlotId")
		local ownerUserId = child:GetAttribute("OwnerUserId")
		if typeof(plotId) ~= "string" or typeof(ownerUserId) ~= "number" then
			return AppTypes.failure("OrphanedPlotModel", "Runtime plot model has invalid ownership attributes", {
				name = child.Name,
			})
		end
		if seenModels[plotId] then
			return AppTypes.failure("DuplicatePlotModel", "More than one runtime model has the same plot ID", {
				plotId = plotId,
			})
		end
		seenModels[plotId] = true

		local allocation = self._allocations[plotId]
		if
			allocation == nil
			or allocation.state ~= "Active"
			or allocation.model ~= child
			or allocation.userId ~= ownerUserId
			or self._plotToPlayer[plotId] ~= ownerUserId
		then
			return AppTypes.failure("OrphanedPlotModel", "Runtime plot model has no matching allocation", {
				plotId = plotId,
			})
		end
		local spawnInstance = child:FindFirstChild("SpawnLocation")
		if spawnInstance == nil or not spawnInstance:IsA("SpawnLocation") then
			return AppTypes.failure("InvalidPlotSpawn", "Active plot has no SpawnLocation", {
				plotId = plotId,
			})
		end
	end

	for plotId, allocation in self._allocations do
		if allocation.state == "Active" then
			if allocation.model == nil or not seenModels[plotId] then
				return AppTypes.failure("OrphanedPlotAllocation", "Active allocation has no runtime model", {
					plotId = plotId,
				})
			end
		end
	end

	return AppTypes.success(true)
end

function PlotService.Destroy(self: Service)
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true

	local userIds: { number } = {}
	for userId in self._playerToPlot do
		table.insert(userIds, userId)
	end
	for _, userId in userIds do
		self:ReleasePlayer(userId)
	end

	local plotsFolder = self._plotsFolder
	if self._ownsPlotsFolder and plotsFolder ~= nil then
		plotsFolder:Destroy()
	end
	self._plotsFolder = nil

	local mapFolder = self._mapFolder
	if self._ownsMapFolder and mapFolder ~= nil and #mapFolder:GetChildren() == 0 then
		mapFolder:Destroy()
	end
	self._mapFolder = nil
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(PlotService)
