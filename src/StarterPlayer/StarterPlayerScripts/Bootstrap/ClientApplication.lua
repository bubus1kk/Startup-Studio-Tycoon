--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local ClientDependencyResolver = require(ReplicatedStorage.Shared.Infrastructure.ClientDependencyResolver)
local ConfigLoader = require(ReplicatedStorage.Shared.Config.ConfigLoader)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local PublicFeatureFlags = require(ReplicatedStorage.Shared.Config.PublicFeatureFlags)
local RemoteDefinitions = require(ReplicatedStorage.Shared.Remotes.RemoteDefinitions)

local CLIENT_DEPENDENCY_TIMEOUT_SECONDS = 10
local playerScripts = script.Parent.Parent
local clientDependenciesResult =
	ClientDependencyResolver.resolvePlayerScripts(playerScripts, CLIENT_DEPENDENCY_TIMEOUT_SECONDS)
if not clientDependenciesResult.ok then
	error(ClientDependencyResolver.formatStartupError(clientDependenciesResult.error), 0)
end

-- The bounded resolver above proves that these runtime-copied siblings exist
-- with the required classes before the static requires preserve their types.
local ControllerRegistry = require(playerScripts.Infrastructure.ControllerRegistry)
local RemoteClient = require(playerScripts.Infrastructure.RemoteClient)
local BuildMenuController = require(playerScripts.Controllers.BuildMenuController)

type AppError = AppTypes.AppError
type Result<T> = AppTypes.Result<T>
type Registry = LifecycleRegistry.Registry
type RootLogger = Logger.Logger
type RemoteClientType = RemoteClient.Client
type PublicFlags = PublicFeatureFlags.PublicFeatureFlags

type ApplicationData = {
	_registry: Registry,
	_remoteClient: RemoteClientType,
	_logger: RootLogger,
	_publicFeatureFlags: PublicFlags,
}

local ClientApplication = {}
ClientApplication.__index = ClientApplication

export type Application = typeof(setmetatable({} :: ApplicationData, ClientApplication))

local function errorMetadata(errorValue: AppError): { [string]: string }
	local metadata = table.clone(errorValue.details or {})
	metadata.code = errorValue.code
	return metadata
end

function ClientApplication.new(): Result<Application>
	local publicFlagsResult =
		ConfigLoader.validateAndFreeze("PublicFeatureFlags", PublicFeatureFlags.defaults(), PublicFeatureFlags.validate)
	if not publicFlagsResult.ok then
		return AppTypes.failure(
			publicFlagsResult.error.code,
			publicFlagsResult.error.message,
			publicFlagsResult.error.details
		)
	end

	local publicFlags = publicFlagsResult.value
	local environment = if RunService:IsStudio() then "Studio" else "Production"
	local logger = Logger.new(environment, "client", "ClientApplication", publicFlags.enableClientDebugLogging)
	local registry = ControllerRegistry.new(function(cleanupError: AppError)
		logger:Error("lifecycle_cleanup_failed", errorMetadata(cleanupError))
	end)
	local remoteClient =
		RemoteClient.new(ReplicatedStorage, RemoteDefinitions.folderName, RemoteDefinitions.definitions)
	local buildMenuController = BuildMenuController.new(game:GetService("Players").LocalPlayer)

	local registrationResult = registry:Register({
		name = "RemoteClient",
		dependencies = {},
		value = remoteClient,
		hooks = {
			Init = function(dependencies)
				remoteClient:Init(dependencies)
			end,
			Start = function()
				remoteClient:Start()
			end,
			Destroy = function()
				remoteClient:Destroy()
			end,
		},
	})
	if not registrationResult.ok then
		return AppTypes.failure(
			registrationResult.error.code,
			registrationResult.error.message,
			registrationResult.error.details
		)
	end

	local buildMenuRegistrationResult = registry:Register({
		name = "BuildMenuController",
		dependencies = { "RemoteClient" },
		value = buildMenuController,
		hooks = {
			Init = function(dependencies)
				buildMenuController:Init(dependencies)
			end,
			Start = function()
				buildMenuController:Start()
			end,
			Destroy = function()
				buildMenuController:Destroy()
			end,
		},
	})
	if not buildMenuRegistrationResult.ok then
		return AppTypes.failure(
			buildMenuRegistrationResult.error.code,
			buildMenuRegistrationResult.error.message,
			buildMenuRegistrationResult.error.details
		)
	end

	return AppTypes.success(setmetatable({
		_registry = registry,
		_remoteClient = remoteClient,
		_logger = logger,
		_publicFeatureFlags = publicFlags,
	}, ClientApplication))
end

function ClientApplication.Start(self: Application): Result<true>
	local orderResult = self._registry:ResolveStartupOrder()
	if not orderResult.ok then
		self._logger:Error("startup_order_failed", errorMetadata(orderResult.error))
		return orderResult
	end

	local initResult = self._registry:InitAll()
	if not initResult.ok then
		self._logger:Error("application_init_failed", errorMetadata(initResult.error))
		return initResult
	end

	local startResult = self._registry:StartAll()
	if not startResult.ok then
		self._logger:Error("application_start_failed", errorMetadata(startResult.error))
		return startResult
	end

	self._logger:Info("client_bootstrap_ready", {
		order = table.concat(orderResult.value, ","),
	})
	return AppTypes.success(true)
end

function ClientApplication.Destroy(self: Application): Result<true>
	local destroyResult = self._registry:DestroyAll()
	self._logger:Info("client_application_destroyed", nil)
	return destroyResult
end

function ClientApplication.GetRemoteClient(self: Application): RemoteClientType
	return self._remoteClient
end

function ClientApplication.GetPublicFeatureFlags(self: Application): PublicFlags
	return self._publicFeatureFlags
end

return table.freeze(ClientApplication)
