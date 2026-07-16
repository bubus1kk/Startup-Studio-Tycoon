--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DeepFreeze = require(ReplicatedStorage.Shared.Utils.DeepFreeze)
local PayloadValidator = require(ReplicatedStorage.Shared.Validation.PayloadValidator)
local RemoteTypes = require(ReplicatedStorage.Shared.Remotes.RemoteTypes)

type RemoteDefinition = RemoteTypes.RemoteDefinition

local requestValidator = PayloadValidator.compile(PayloadValidator.record({
	plotId = {
		rule = PayloadValidator.string({ minLength = 7, maxLength = 7, pattern = "^plot_%d%d$" }),
	},
}))

local responseValidator = PayloadValidator.compile(PayloadValidator.record({
	ok = { rule = PayloadValidator.boolean() },
	code = { rule = PayloadValidator.string({ maxLength = 64 }) },
	mutationCount = { rule = PayloadValidator.number({ min = 0, integer = true }) },
	mutationUnchanged = { rule = PayloadValidator.boolean() },
}))

local definitions: { RemoteDefinition } = {
	{
		name = "TestPlotMutation",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = requestValidator,
		responseValidator = responseValidator,
	},
}

return table.freeze({
	folderName = "Stage3TestRemotes",
	definitions = DeepFreeze.copy(definitions),
})
