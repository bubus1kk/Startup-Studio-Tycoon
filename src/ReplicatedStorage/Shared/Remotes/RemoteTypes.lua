--!strict

local AppTypes = require(script.Parent.Parent.Types.AppTypes)

export type Validator = (value: unknown) -> AppTypes.Result<true>
export type RemoteKind = "Event" | "Function"
export type RemoteDirection = "ClientToServer" | "ServerToClient"

export type RemoteDefinition = {
	name: string,
	kind: RemoteKind,
	direction: RemoteDirection,
	requestValidator: Validator?,
	responseValidator: Validator?,
}

return table.freeze({
	Kind = table.freeze({
		Event = "Event",
		Function = "Function",
	}),
	Direction = table.freeze({
		ClientToServer = "ClientToServer",
		ServerToClient = "ServerToClient",
	}),
})
