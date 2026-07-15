--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local ConfigLoader = require(ReplicatedStorage.Shared.Config.ConfigLoader)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local PublicFeatureFlags = require(ReplicatedStorage.Shared.Config.PublicFeatureFlags)
local RemoteDefinitions = require(ReplicatedStorage.Shared.Remotes.RemoteDefinitions)
local RuntimeEnvironment = require(ServerScriptService.Infrastructure.RuntimeEnvironment)
local ServerConfig = require(ServerStorage.Config.ServerConfig)
local ServerConfigValidator = require(ServerScriptService.Config.ServerConfigValidator)
local ServerRemoteRegistry = require(ServerScriptService.Infrastructure.ServerRemoteRegistry)
local ServiceRegistry = require(ServerScriptService.Infrastructure.ServiceRegistry)

type AppError = AppTypes.AppError
type Result<T> = AppTypes.Result<T>
type Registry = LifecycleRegistry.Registry
type RootLogger = Logger.Logger
type RemoteRegistry = ServerRemoteRegistry.Registry
type ServerConfigType = ServerConfigValidator.ServerConfig
type PublicFlags = PublicFeatureFlags.PublicFeatureFlags

type ApplicationData = {
	_registry: Registry,
	_remoteRegistry: RemoteRegistry,
	_logger: RootLogger,
	_serverConfig: ServerConfigType,
	_publicFeatureFlags: PublicFlags,
}

local ServerApplication = {}
ServerApplication.__index = ServerApplication

export type Application = typeof(setmetatable({} :: ApplicationData, ServerApplication))

local function errorMetadata(errorValue: AppError): { [string]: string }
	local metadata = table.clone(errorValue.details or {})
	metadata.code = errorValue.code
	return metadata
end

function ServerApplication.new(): Result<Application>
	local serverConfigResult =
		ConfigLoader.validateAndFreeze("ServerConfig", ServerConfig, ServerConfigValidator.validate)
	if not serverConfigResult.ok then
		return AppTypes.failure(
			serverConfigResult.error.code,
			serverConfigResult.error.message,
			serverConfigResult.error.details
		)
	end

	local publicFlagsResult =
		ConfigLoader.validateAndFreeze("PublicFeatureFlags", PublicFeatureFlags.defaults(), PublicFeatureFlags.validate)
	if not publicFlagsResult.ok then
		return AppTypes.failure(
			publicFlagsResult.error.code,
			publicFlagsResult.error.message,
			publicFlagsResult.error.details
		)
	end

	local serverConfig = serverConfigResult.value
	local environment = RuntimeEnvironment.detect(serverConfig.environment)
	local logger =
		Logger.new(environment, game.JobId, "ServerApplication", serverConfig.featureFlags.enableServerDebugLogging)
	local registry = ServiceRegistry.new(function(cleanupError: AppError)
		logger:Error("lifecycle_cleanup_failed", errorMetadata(cleanupError))
	end)
	local remoteRegistry =
		ServerRemoteRegistry.new(ReplicatedStorage, RemoteDefinitions.folderName, RemoteDefinitions.definitions, logger)

	local registrationResult = registry:Register({
		name = "ServerRemoteRegistry",
		dependencies = {},
		value = remoteRegistry,
		hooks = {
			Init = function(dependencies)
				remoteRegistry:Init(dependencies)
			end,
			Start = function()
				remoteRegistry:Start()
			end,
			Destroy = function()
				remoteRegistry:Destroy()
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

	return AppTypes.success(setmetatable({
		_registry = registry,
		_remoteRegistry = remoteRegistry,
		_logger = logger,
		_serverConfig = serverConfig,
		_publicFeatureFlags = publicFlagsResult.value,
	}, ServerApplication))
end

function ServerApplication.Start(self: Application): Result<true>
	local orderResult = self._registry:ResolveStartupOrder()
	if not orderResult.ok then
		self._logger:Error("startup_order_failed", errorMetadata(orderResult.error))
		return orderResult
	end

	self._logger:Info("startup_order_resolved", {
		order = table.concat(orderResult.value, ","),
	})

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

	self._logger:Info("server_bootstrap_ready", nil)
	return AppTypes.success(true)
end

function ServerApplication.Destroy(self: Application): Result<true>
	local destroyResult = self._registry:DestroyAll()
	self._logger:Info("server_application_destroyed", nil)
	return destroyResult
end

function ServerApplication.GetRemoteRegistry(self: Application): RemoteRegistry
	return self._remoteRegistry
end

function ServerApplication.GetServerConfig(self: Application): ServerConfigType
	return self._serverConfig
end

function ServerApplication.GetPublicFeatureFlags(self: Application): PublicFlags
	return self._publicFeatureFlags
end

return table.freeze(ServerApplication)
