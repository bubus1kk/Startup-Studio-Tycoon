--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local RemoteDefinitionValidator = require(ReplicatedStorage.Shared.Remotes.RemoteDefinitionValidator)
local RemoteTypes = require(ReplicatedStorage.Shared.Remotes.RemoteTypes)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type RemoteDefinition = RemoteTypes.RemoteDefinition

type ClientData = {
	_parent: Instance,
	_folderName: string,
	_definitions: { RemoteDefinition },
	_instances: { [string]: RemoteEvent | RemoteFunction },
	_isInitialized: boolean,
}

local RemoteClient = {}
RemoteClient.__index = RemoteClient

export type Client = typeof(setmetatable({} :: ClientData, RemoteClient))

function RemoteClient.new(parent: Instance, folderName: string, definitions: { RemoteDefinition }): Client
	return setmetatable({
		_parent = parent,
		_folderName = folderName,
		_definitions = definitions,
		_instances = {},
		_isInitialized = false,
	}, RemoteClient)
end

function RemoteClient.Init(self: Client, _dependencies: DependencyResolver)
	local validationResult = RemoteDefinitionValidator.validate(self._definitions)
	if not validationResult.ok then
		error(`Remote definitions are invalid: {validationResult.error.code}`, 2)
	end
	self._isInitialized = true
end

function RemoteClient.Start(self: Client)
	if not self._isInitialized then
		error("RemoteClient.Start requires a successful Init", 2)
	end

	local folderInstance = self._parent:WaitForChild(self._folderName, 10)
	if folderInstance == nil or not folderInstance:IsA("Folder") then
		error(`Remote folder {self._folderName} was not replicated`, 2)
	end

	for _, definition in self._definitions do
		local remote = folderInstance:WaitForChild(definition.name, 10)
		if remote == nil then
			error(`Remote {definition.name} was not replicated`, 2)
		end
		if definition.kind == "Event" then
			if not remote:IsA("RemoteEvent") then
				error(`Remote {definition.name} must be a RemoteEvent`, 2)
			end
			self._instances[definition.name] = remote
		else
			if not remote:IsA("RemoteFunction") then
				error(`Remote {definition.name} must be a RemoteFunction`, 2)
			end
			self._instances[definition.name] = remote
		end
	end
end

function RemoteClient.GetEvent(self: Client, name: string): RemoteEvent?
	local remote = self._instances[name]
	return if remote ~= nil and remote:IsA("RemoteEvent") then remote else nil
end

function RemoteClient.GetFunction(self: Client, name: string): RemoteFunction?
	local remote = self._instances[name]
	return if remote ~= nil and remote:IsA("RemoteFunction") then remote else nil
end

function RemoteClient.Destroy(self: Client)
	-- The client never owns or destroys server-created remote instances.
	table.clear(self._instances)
	self._isInitialized = false
end

return table.freeze(RemoteClient)
