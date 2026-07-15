--!strict

local AppTypes = require(script.Parent.Parent.Types.AppTypes)
local RemoteTypes = require(script.Parent.RemoteTypes)

type Result<T> = AppTypes.Result<T>
type RemoteDefinition = RemoteTypes.RemoteDefinition

local RemoteDefinitionValidator = {}

function RemoteDefinitionValidator.validate(definitions: { RemoteDefinition }): Result<{ [string]: RemoteDefinition }>
	local byName: { [string]: RemoteDefinition } = {}
	for _, definition in definitions do
		if string.match(definition.name, "^[A-Z][A-Za-z0-9]*$") == nil then
			return AppTypes.failure("InvalidRemoteName", "Remote name must be a stable PascalCase identifier", {
				name = definition.name,
			})
		end
		if byName[definition.name] ~= nil then
			return AppTypes.failure("DuplicateRemoteDefinition", "Remote is defined more than once", {
				name = definition.name,
			})
		end
		if definition.kind ~= "Event" and definition.kind ~= "Function" then
			return AppTypes.failure("InvalidRemoteKind", "Remote kind is unsupported", {
				name = definition.name,
			})
		end
		if definition.direction ~= "ClientToServer" and definition.direction ~= "ServerToClient" then
			return AppTypes.failure("InvalidRemoteDirection", "Remote direction is unsupported", {
				name = definition.name,
			})
		end
		if definition.direction == "ClientToServer" and definition.requestValidator == nil then
			return AppTypes.failure("MissingRemoteValidator", "Client-to-server remote requires a request validator", {
				name = definition.name,
			})
		end
		if definition.kind == "Function" and definition.direction ~= "ClientToServer" then
			return AppTypes.failure("InvalidRemoteDirection", "RemoteFunction must be client-to-server", {
				name = definition.name,
			})
		end
		if definition.kind == "Function" and definition.responseValidator == nil then
			return AppTypes.failure("MissingRemoteValidator", "RemoteFunction requires a response validator", {
				name = definition.name,
			})
		end

		byName[definition.name] = definition
	end

	return AppTypes.success(byName)
end

return table.freeze(RemoteDefinitionValidator)
