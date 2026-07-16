--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local LoggerTypes = require(ReplicatedStorage.Shared.Types.LoggerTypes)
local PlotTypes = require(ServerScriptService.Domain.PlotTypes)
local PlotService = require(ServerScriptService.Services.PlotService)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type Logger = LoggerTypes.Logger
type PlotSpawnContext = PlotTypes.PlotSpawnContext
type PlotServiceType = PlotService.Service
type Result<T> = AppTypes.Result<T>

type PlayerSession = {
	player: Player,
	plotId: string,
	generationToken: number,
	spawnLocation: SpawnLocation,
	pendingCharacter: Model?,
	characterConnection: RBXScriptConnection,
	appearanceConnection: RBXScriptConnection,
}

type ServiceData = {
	_players: Players,
	_logger: Logger,
	_enableSpawnDiagnostics: boolean,
	_plotService: PlotServiceType?,
	_sessions: { [number]: PlayerSession },
	_playerAddedConnection: RBXScriptConnection?,
	_playerRemovingConnection: RBXScriptConnection?,
	_isInitialized: boolean,
	_isStarted: boolean,
	_isDestroyed: boolean,
}

local PlayerSessionService = {}
PlayerSessionService.__index = PlayerSessionService

export type Service = typeof(setmetatable({} :: ServiceData, PlayerSessionService))

local CHARACTER_ROOT_TIMEOUT_SECONDS = 10
local PLOT_FAILURE_KICK_MESSAGE = "Unable to prepare your office plot. Please rejoin."

local function formatPosition(position: Vector3?): string
	if position == nil then
		return "missing"
	end
	return string.format("%.3f,%.3f,%.3f", position.X, position.Y, position.Z)
end

function PlayerSessionService.new(players: Players, logger: Logger, enableSpawnDiagnostics: boolean): Service
	return setmetatable({
		_players = players,
		_logger = logger,
		_enableSpawnDiagnostics = enableSpawnDiagnostics,
		_plotService = nil,
		_sessions = {},
		_playerAddedConnection = nil,
		_playerRemovingConnection = nil,
		_isInitialized = false,
		_isStarted = false,
		_isDestroyed = false,
	}, PlayerSessionService)
end

function PlayerSessionService.Init(self: Service, dependencies: DependencyResolver)
	if self._isInitialized or self._isDestroyed then
		error("PlayerSessionService.Init can only run once", 2)
	end
	self._plotService = dependencies:Require("PlotService") :: PlotServiceType
	self._isInitialized = true
end

function PlayerSessionService._getSpawnContext(self: Service, player: Player, session: PlayerSession): PlotSpawnContext?
	if self._sessions[player.UserId] ~= session or session.player ~= player then
		return nil
	end

	local plotService = self._plotService
	if plotService == nil then
		return nil
	end
	local spawnContext = plotService:GetSpawnContextForUserId(player.UserId)
	if
		spawnContext == nil
		or spawnContext.plotId ~= session.plotId
		or spawnContext.userId ~= player.UserId
		or spawnContext.generationToken ~= session.generationToken
		or spawnContext.spawnLocation ~= session.spawnLocation
		or plotService:GetPlotIdForUserId(player.UserId) ~= session.plotId
		or plotService:GetOwnerUserId(session.plotId) ~= player.UserId
	then
		return nil
	end
	return spawnContext
end

function PlayerSessionService._logSpawnDiagnostic(
	self: Service,
	event: string,
	player: Player,
	character: Model,
	trigger: string,
	session: PlayerSession?,
	spawnContext: PlotSpawnContext?,
	beforePosition: Vector3?,
	afterPosition: Vector3?
)
	if not self._enableSpawnDiagnostics then
		return
	end

	local plotId = if session ~= nil then session.plotId else "none"
	local generationToken = if spawnContext ~= nil
		then spawnContext.generationToken
		elseif session ~= nil then session.generationToken
		else -1
	local expectedPosition = if spawnContext ~= nil then spawnContext.spawnCFrame.Position else nil
	local spawnClass = if spawnContext ~= nil
		then spawnContext.spawnLocation.ClassName
		elseif session ~= nil then session.spawnLocation.ClassName
		else "missing"

	self._logger:Info(event, {
		userId = player.UserId,
		assignedPlotId = plotId,
		generationToken = generationToken,
		expectedSpawnPosition = formatPosition(expectedPosition),
		actualRootPositionBefore = formatPosition(beforePosition),
		actualRootPositionAfter = formatPosition(afterPosition),
		isCurrentCharacter = player.Character == character,
		physicalSpawnClass = spawnClass,
		trigger = trigger,
	})
end

function PlayerSessionService._positionCharacter(
	self: Service,
	player: Player,
	character: Model,
	trigger: string
): boolean
	local session = self._sessions[player.UserId]
	if
		session == nil
		or session.player ~= player
		or session.pendingCharacter ~= character
		or player.Character ~= character
	then
		local spawnContext = if session ~= nil then self:_getSpawnContext(player, session) else nil
		local staleRoot = character:FindFirstChild("HumanoidRootPart")
		local stalePosition = if staleRoot ~= nil and staleRoot:IsA("BasePart") then staleRoot.Position else nil
		self:_logSpawnDiagnostic(
			"character_spawn_rejected",
			player,
			character,
			trigger,
			session,
			spawnContext,
			stalePosition,
			stalePosition
		)
		return false
	end

	local rootInstance = character:FindFirstChild("HumanoidRootPart")
	if rootInstance == nil then
		rootInstance = character:WaitForChild("HumanoidRootPart", CHARACTER_ROOT_TIMEOUT_SECONDS)
	end
	if rootInstance == nil or not rootInstance:IsA("BasePart") then
		self._logger:Warn("character_root_missing", { userId = player.UserId })
		self:_logSpawnDiagnostic(
			"character_spawn_rejected",
			player,
			character,
			trigger,
			session,
			self:_getSpawnContext(player, session),
			nil,
			nil
		)
		return false
	end

	session = self._sessions[player.UserId]
	if
		session == nil
		or session.player ~= player
		or session.pendingCharacter ~= character
		or player.Character ~= character
	then
		self:_logSpawnDiagnostic(
			"character_spawn_rejected",
			player,
			character,
			trigger,
			session,
			nil,
			rootInstance.Position,
			rootInstance.Position
		)
		return false
	end

	local spawnContext = self:_getSpawnContext(player, session)
	if spawnContext == nil then
		self._logger:Warn("character_spawn_unavailable", {
			userId = player.UserId,
			plotId = session.plotId,
		})
		self:_logSpawnDiagnostic(
			"character_spawn_rejected",
			player,
			character,
			trigger,
			session,
			nil,
			rootInstance.Position,
			rootInstance.Position
		)
		return false
	end

	local beforePosition = rootInstance.Position
	character:PivotTo(spawnContext.spawnCFrame)
	self:_logSpawnDiagnostic(
		"character_spawn_positioned",
		player,
		character,
		trigger,
		session,
		spawnContext,
		beforePosition,
		rootInstance.Position
	)
	return true
end

function PlayerSessionService._observeCharacter(self: Service, player: Player, character: Model)
	local session = self._sessions[player.UserId]
	if session == nil or session.player ~= player then
		return
	end
	session.pendingCharacter = character

	local rootInstance = character:FindFirstChild("HumanoidRootPart")
	local rootPosition = if rootInstance ~= nil and rootInstance:IsA("BasePart") then rootInstance.Position else nil
	self:_logSpawnDiagnostic(
		"character_added_observed",
		player,
		character,
		"CharacterAdded",
		session,
		self:_getSpawnContext(player, session),
		rootPosition,
		rootPosition
	)
end

function PlayerSessionService.BeginSession(self: Service, player: Player): Result<true>
	if self._isDestroyed then
		return AppTypes.failure("PlayerSessionServiceUnavailable", "Player session service is unavailable", nil)
	end

	local plotService = self._plotService
	if plotService == nil then
		return AppTypes.failure("PlayerSessionServiceUnavailable", "Plot service dependency is missing", nil)
	end

	local existingSession = self._sessions[player.UserId]
	if existingSession ~= nil then
		if existingSession.player == player then
			local spawnContext = self:_getSpawnContext(player, existingSession)
			if spawnContext == nil then
				return AppTypes.failure("PlotSpawnUnavailable", "Assigned plot spawn is unavailable", {
					plotId = existingSession.plotId,
				})
			end
			player.RespawnLocation = spawnContext.spawnLocation
			player:SetAttribute("AssignedPlotId", existingSession.plotId)
			return AppTypes.success(true)
		end
		return AppTypes.failure("DuplicatePlayerSession", "User ID already has a different active Player", {
			userId = tostring(player.UserId),
		})
	end

	local assignmentResult = plotService:AssignPlayer(player.UserId)
	if not assignmentResult.ok then
		self._logger:Error("player_plot_assignment_failed", {
			userId = player.UserId,
			code = assignmentResult.error.code,
		})
		player:Kick(PLOT_FAILURE_KICK_MESSAGE)
		return AppTypes.failure(
			assignmentResult.error.code,
			assignmentResult.error.message,
			assignmentResult.error.details
		)
	end

	local plotId = assignmentResult.value.plotId
	local spawnContext = plotService:GetSpawnContextForUserId(player.UserId)
	if spawnContext == nil or spawnContext.plotId ~= plotId then
		plotService:ReleasePlayer(player.UserId)
		self._logger:Error("player_plot_spawn_unavailable", {
			userId = player.UserId,
			plotId = plotId,
		})
		player:Kick(PLOT_FAILURE_KICK_MESSAGE)
		return AppTypes.failure("PlotSpawnUnavailable", "Assigned plot spawn is unavailable", {
			plotId = plotId,
		})
	end

	player.RespawnLocation = spawnContext.spawnLocation
	local characterConnection = player.CharacterAdded:Connect(function(character: Model)
		self:_observeCharacter(player, character)
	end)
	local appearanceConnection = player.CharacterAppearanceLoaded:Connect(function(character: Model)
		self:_positionCharacter(player, character, "CharacterAppearanceLoaded")
	end)
	self._sessions[player.UserId] = {
		player = player,
		plotId = plotId,
		generationToken = spawnContext.generationToken,
		spawnLocation = spawnContext.spawnLocation,
		pendingCharacter = nil,
		characterConnection = characterConnection,
		appearanceConnection = appearanceConnection,
	}
	player:SetAttribute("AssignedPlotId", plotId)

	local existingCharacter = player.Character
	if existingCharacter ~= nil then
		local session = self._sessions[player.UserId]
		if session ~= nil then
			session.pendingCharacter = existingCharacter
		end
		if player:HasAppearanceLoaded() then
			self:_positionCharacter(player, existingCharacter, "ExistingCharacterAppearanceLoaded")
		end
	end

	return AppTypes.success(true)
end

function PlayerSessionService.EndSession(self: Service, player: Player): Result<true>
	local session = self._sessions[player.UserId]
	local plotService = self._plotService
	local expectedSpawnLocation: SpawnLocation? = nil
	if session ~= nil and session.player == player then
		expectedSpawnLocation = session.spawnLocation
	elseif plotService ~= nil then
		local spawnContext = plotService:GetSpawnContextForUserId(player.UserId)
		if spawnContext ~= nil then
			expectedSpawnLocation = spawnContext.spawnLocation
		end
	end

	if session ~= nil and session.player == player then
		session.characterConnection:Disconnect()
		session.appearanceConnection:Disconnect()
		session.pendingCharacter = nil
		self._sessions[player.UserId] = nil
	end

	if expectedSpawnLocation ~= nil and player.RespawnLocation == expectedSpawnLocation then
		player.RespawnLocation = nil
	end
	if player:GetAttribute("AssignedPlotId") ~= nil then
		player:SetAttribute("AssignedPlotId", nil)
	end
	if plotService ~= nil then
		local releaseResult = plotService:ReleasePlayer(player.UserId)
		if not releaseResult.ok then
			return AppTypes.failure(releaseResult.error.code, releaseResult.error.message, releaseResult.error.details)
		end
	end
	return AppTypes.success(true)
end

function PlayerSessionService.Start(self: Service)
	if not self._isInitialized or self._isStarted or self._isDestroyed then
		error("PlayerSessionService.Start requires one successful Init", 2)
	end

	self._playerAddedConnection = self._players.PlayerAdded:Connect(function(player: Player)
		self:BeginSession(player)
	end)
	self._playerRemovingConnection = self._players.PlayerRemoving:Connect(function(player: Player)
		local result = self:EndSession(player)
		if not result.ok then
			self._logger:Error("player_session_cleanup_failed", {
				userId = player.UserId,
				code = result.error.code,
			})
		end
	end)

	-- Connections are installed first so a join between GetPlayers and iteration
	-- is handled by the same idempotent BeginSession path.
	for _, player in self._players:GetPlayers() do
		self:BeginSession(player)
	end
	self._isStarted = true
	self._logger:Info("player_session_service_started", nil)
end

function PlayerSessionService.Destroy(self: Service)
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true

	local playerAddedConnection = self._playerAddedConnection
	if playerAddedConnection ~= nil then
		playerAddedConnection:Disconnect()
	end
	self._playerAddedConnection = nil
	local playerRemovingConnection = self._playerRemovingConnection
	if playerRemovingConnection ~= nil then
		playerRemovingConnection:Disconnect()
	end
	self._playerRemovingConnection = nil

	local activePlayers: { Player } = {}
	for _, session in self._sessions do
		table.insert(activePlayers, session.player)
	end
	for _, player in activePlayers do
		self:EndSession(player)
	end

	self._plotService = nil
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(PlayerSessionService)
