--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local LoggerTypes = require(ReplicatedStorage.Shared.Types.LoggerTypes)
local RemoteDefinitionValidator = require(ReplicatedStorage.Shared.Remotes.RemoteDefinitionValidator)
local RemoteTypes = require(ReplicatedStorage.Shared.Remotes.RemoteTypes)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type Logger = LoggerTypes.Logger
type RemoteDefinition = RemoteTypes.RemoteDefinition
type Result<T> = AppTypes.Result<T>

type RegistryData = {
	_parent: Instance,
	_folderName: string,
	_definitions: { RemoteDefinition },
	_byName: { [string]: RemoteDefinition },
	_instances: { [string]: RemoteEvent | RemoteFunction },
	_connections: { RBXScriptConnection },
	_boundFunctions: { RemoteFunction },
	_boundNames: { [string]: boolean },
	_folder: Folder?,
	_ownsFolder: boolean,
	_logger: Logger,
	_isInitialized: boolean,
	_isStarted: boolean,
}

local ServerRemoteRegistry = {}
ServerRemoteRegistry.__index = ServerRemoteRegistry

export type Registry = typeof(setmetatable({} :: RegistryData, ServerRemoteRegistry))
export type EventHandler = (player: Player, payload: unknown) -> ()
export type FunctionHandler = (player: Player, payload: unknown) -> unknown

local function safeRemoteFailure(code: string): { ok: false, error: { code: string, message: string } }
	return {
		ok = false,
		error = {
			code = code,
			message = "Request rejected",
		},
	}
end

function ServerRemoteRegistry.new(
	parent: Instance,
	folderName: string,
	definitions: { RemoteDefinition },
	logger: Logger
): Registry
	return setmetatable({
		_parent = parent,
		_folderName = folderName,
		_definitions = definitions,
		_byName = {},
		_instances = {},
		_connections = {},
		_boundFunctions = {},
		_boundNames = {},
		_folder = nil,
		_ownsFolder = false,
		_logger = logger,
		_isInitialized = false,
		_isStarted = false,
	}, ServerRemoteRegistry)
end

function ServerRemoteRegistry.Init(self: Registry, _dependencies: DependencyResolver)
	if self._isInitialized then
		error("ServerRemoteRegistry.Init can only run once", 2)
	end

	local validationResult = RemoteDefinitionValidator.validate(self._definitions)
	if not validationResult.ok then
		error(`Remote definitions are invalid: {validationResult.error.code}`, 2)
	end

	self._byName = validationResult.value
	self._isInitialized = true
end

function ServerRemoteRegistry.Start(self: Registry)
	if not self._isInitialized or self._isStarted then
		error("ServerRemoteRegistry.Start requires one successful Init", 2)
	end

	local existingFolder = self._parent:FindFirstChild(self._folderName)
	if existingFolder ~= nil and not existingFolder:IsA("Folder") then
		error(`Remote container {self._folderName} exists with class {existingFolder.ClassName}`, 2)
	end

	local folder: Folder
	if existingFolder == nil then
		folder = Instance.new("Folder")
		folder.Name = self._folderName
		folder.Parent = self._parent
		self._ownsFolder = true
	else
		folder = existingFolder
	end
	self._folder = folder

	for _, definition in self._definitions do
		if folder:FindFirstChild(definition.name) ~= nil then
			error(`Remote instance {definition.name} already exists`, 2)
		end

		local remote: RemoteEvent | RemoteFunction
		if definition.kind == "Event" then
			remote = Instance.new("RemoteEvent")
		else
			remote = Instance.new("RemoteFunction")
		end
		remote.Name = definition.name
		remote.Parent = folder
		self._instances[definition.name] = remote
	end

	self._isStarted = true
	self._logger:Info("remote_registry_started", {
		remoteCount = #self._definitions,
	})
end

function ServerRemoteRegistry.GetEvent(self: Registry, name: string): RemoteEvent?
	local instance = self._instances[name]
	return if instance ~= nil and instance:IsA("RemoteEvent") then instance else nil
end

function ServerRemoteRegistry.GetFunction(self: Registry, name: string): RemoteFunction?
	local instance = self._instances[name]
	return if instance ~= nil and instance:IsA("RemoteFunction") then instance else nil
end

function ServerRemoteRegistry.BindEvent(
	self: Registry,
	name: string,
	handler: EventHandler
): Result<RBXScriptConnection>
	if self._boundNames[name] then
		return AppTypes.failure("DuplicateRemoteBinding", "Remote already has a server binding", {
			name = name,
		})
	end

	local definition = self._byName[name]
	local remote = self:GetEvent(name)
	if definition == nil or remote == nil or definition.direction ~= "ClientToServer" then
		return AppTypes.failure("RemoteBindingRejected", "RemoteEvent is missing or has incompatible direction", {
			name = name,
		})
	end

	local validator = definition.requestValidator
	if validator == nil then
		return AppTypes.failure("RemoteBindingRejected", "RemoteEvent has no request validator", {
			name = name,
		})
	end

	local connection = remote.OnServerEvent:Connect(function(player: Player, payload: unknown, ...: unknown)
		if select("#", ...) ~= 0 then
			self._logger:Security("remote_payload_rejected", {
				remote = name,
				reason = "unexpected_argument_count",
				userId = player.UserId,
			})
			return
		end

		local validationResult = validator(payload)
		if not validationResult.ok then
			self._logger:Security("remote_payload_rejected", {
				remote = name,
				reason = validationResult.error.code,
				userId = player.UserId,
			})
			return
		end

		handler(player, payload)
	end)
	table.insert(self._connections, connection)
	self._boundNames[name] = true
	return AppTypes.success(connection)
end

function ServerRemoteRegistry.BindFunction(self: Registry, name: string, handler: FunctionHandler): Result<true>
	if self._boundNames[name] then
		return AppTypes.failure("DuplicateRemoteBinding", "Remote already has a server binding", {
			name = name,
		})
	end

	local definition = self._byName[name]
	local remote = self:GetFunction(name)
	if definition == nil or remote == nil or definition.direction ~= "ClientToServer" then
		return AppTypes.failure("RemoteBindingRejected", "RemoteFunction is missing or has incompatible direction", {
			name = name,
		})
	end

	local requestValidator = definition.requestValidator
	if requestValidator == nil then
		return AppTypes.failure("RemoteBindingRejected", "RemoteFunction has no request validator", {
			name = name,
		})
	end

	remote.OnServerInvoke = function(player: Player, payload: unknown, ...: unknown): unknown
		if select("#", ...) ~= 0 then
			self._logger:Security("remote_payload_rejected", {
				remote = name,
				reason = "unexpected_argument_count",
				userId = player.UserId,
			})
			return safeRemoteFailure("InvalidPayload")
		end

		local requestResult = requestValidator(payload)
		if not requestResult.ok then
			self._logger:Security("remote_payload_rejected", {
				remote = name,
				reason = requestResult.error.code,
				userId = player.UserId,
			})
			return safeRemoteFailure("InvalidPayload")
		end

		local response = handler(player, payload)
		local responseValidator = definition.responseValidator
		if responseValidator ~= nil then
			local responseResult = responseValidator(response)
			if not responseResult.ok then
				self._logger:Error("remote_response_contract_failed", {
					remote = name,
				})
				return safeRemoteFailure("InternalError")
			end
		end

		return response
	end
	table.insert(self._boundFunctions, remote)
	self._boundNames[name] = true
	return AppTypes.success(true)
end

function ServerRemoteRegistry.Destroy(self: Registry)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)

	for _, remoteFunction in self._boundFunctions do
		remoteFunction.OnServerInvoke = nil
	end
	table.clear(self._boundFunctions)
	table.clear(self._boundNames)

	for _, remote in self._instances do
		remote:Destroy()
	end
	table.clear(self._instances)

	if self._ownsFolder and self._folder ~= nil then
		self._folder:Destroy()
	end
	self._folder = nil
	self._ownsFolder = false
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(ServerRemoteRegistry)
