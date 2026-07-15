--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PayloadValidator = require(ReplicatedStorage.Shared.Validation.PayloadValidator)
local RemoteTypes = require(ReplicatedStorage.Shared.Remotes.RemoteTypes)
local DeepFreeze = require(ReplicatedStorage.Shared.Utils.DeepFreeze)

type RemoteDefinition = RemoteTypes.RemoteDefinition

local requestValidator = PayloadValidator.compile(PayloadValidator.record({
	requestId = {
		rule = PayloadValidator.string({
			minLength = 1,
			maxLength = 32,
			pattern = "^[A-Za-z0-9_-]+$",
		}),
	},
}))

local responseValidator = PayloadValidator.compile(PayloadValidator.record({
	ok = {
		rule = PayloadValidator.boolean(),
	},
}))

local definitions: { RemoteDefinition } = {
	{
		name = "TestRequest",
		kind = "Event",
		direction = "ClientToServer",
		requestValidator = requestValidator,
	},
	{
		name = "TestFunction",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = requestValidator,
		responseValidator = responseValidator,
	},
}

return table.freeze({
	folderName = "TestRemotes",
	definitions = DeepFreeze.copy(definitions),
})
