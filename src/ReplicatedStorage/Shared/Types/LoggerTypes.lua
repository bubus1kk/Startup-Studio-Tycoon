--!strict

export type MetadataValue = boolean | number | string
export type Metadata = { [string]: MetadataValue }

export type Logger = {
	Debug: (self: Logger, event: string, metadata: Metadata?) -> (),
	Info: (self: Logger, event: string, metadata: Metadata?) -> (),
	Warn: (self: Logger, event: string, metadata: Metadata?) -> (),
	Error: (self: Logger, event: string, metadata: Metadata?) -> (),
	Security: (self: Logger, event: string, metadata: Metadata?) -> (),
}

return table.freeze({})
