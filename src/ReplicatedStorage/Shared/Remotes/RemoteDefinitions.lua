--!strict

local RemoteTypes = require(script.Parent.RemoteTypes)
local DeepFreeze = require(script.Parent.Parent.Utils.DeepFreeze)

type RemoteDefinition = RemoteTypes.RemoteDefinition

local definitions: { RemoteDefinition } = {}

return table.freeze({
	folderName = "Remotes",
	definitions = DeepFreeze.copy(definitions),
})
