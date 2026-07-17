--!strict

local RemoteTypes = require(script.Parent.RemoteTypes)
local AppTypes = require(script.Parent.Parent.Types.AppTypes)
local DeepFreeze = require(script.Parent.Parent.Utils.DeepFreeze)
local PayloadValidator = require(script.Parent.Parent.Validation.PayloadValidator)

type RemoteDefinition = RemoteTypes.RemoteDefinition

local idRule = PayloadValidator.string({ minLength = 1, maxLength = 64, pattern = "^[A-Za-z0-9_-]+$" })
local requestIdRule = PayloadValidator.string({ minLength = 1, maxLength = 36, pattern = "^[A-Za-z0-9_-]+$" })
local categoryRule = PayloadValidator.string({ minLength = 5, maxLength = 9, pattern = "^[A-Za-z]+$" })
local stateRule = PayloadValidator.string({ minLength = 6, maxLength = 10, pattern = "^[A-Za-z]+$" })

local catalogRequestShape = PayloadValidator.compile(PayloadValidator.record({
	requestId = { rule = requestIdRule },
	categoryId = { rule = categoryRule },
	page = { rule = PayloadValidator.number({ min = 1, max = 100, integer = true }) },
}, { maxItems = 3 }))

local function catalogRequestValidator(value: unknown)
	local result = catalogRequestShape(value)
	if not result.ok then
		return result
	end
	local categoryId = (value :: { [string]: unknown }).categoryId
	if
		categoryId ~= "Tiers"
		and categoryId ~= "Rooms"
		and categoryId ~= "Equipment"
		and categoryId ~= "Furniture"
		and categoryId ~= "Upgrades"
	then
		return AppTypes.failure("InvalidPayload", "Remote payload validation failed", {
			path = "$.categoryId",
			reason = "unsupported office category",
		})
	end
	return result
end

local remoteErrorRule = PayloadValidator.record({
	code = { rule = PayloadValidator.string({ minLength = 1, maxLength = 64 }) },
	message = { rule = PayloadValidator.string({ minLength = 1, maxLength = 160 }) },
}, { maxItems = 2 })

local catalogItemRule = PayloadValidator.record({
	itemId = { rule = idRule },
	displayName = { rule = PayloadValidator.string({ minLength = 1, maxLength = 48 }) },
	description = { rule = PayloadValidator.string({ minLength = 1, maxLength = 160 }) },
	categoryId = { rule = categoryRule },
	price = { rule = PayloadValidator.number({ min = 0, max = 1000000000, integer = true }) },
	state = { rule = stateRule },
	lockCode = { rule = PayloadValidator.string({ minLength = 1, maxLength = 64 }), optional = true },
	lockText = { rule = PayloadValidator.string({ minLength = 1, maxLength = 120 }), optional = true },
	requiredTierId = { rule = idRule, optional = true },
	requiredRoomId = { rule = idRule, optional = true },
	prerequisiteIds = { rule = PayloadValidator.array(idRule, { maxItems = 4 }) },
	slotId = { rule = PayloadValidator.string({ minLength = 1, maxLength = 64 }), optional = true },
	currentLevel = { rule = PayloadValidator.number({ min = 0, max = 3, integer = true }), optional = true },
	maxLevel = { rule = PayloadValidator.number({ min = 1, max = 3, integer = true }), optional = true },
}, { maxItems = 14 })

local catalogResponseValidator = PayloadValidator.compile(PayloadValidator.record({
	ok = { rule = PayloadValidator.boolean() },
	requestId = { rule = requestIdRule },
	categoryId = { rule = categoryRule },
	page = { rule = PayloadValidator.number({ min = 1, max = 100, integer = true }) },
	pageCount = { rule = PayloadValidator.number({ min = 0, max = 100, integer = true }) },
	totalItems = { rule = PayloadValidator.number({ min = 0, max = 41, integer = true }) },
	revision = { rule = PayloadValidator.number({ min = 0, integer = true }) },
	currentTierId = { rule = idRule },
	cash = { rule = PayloadValidator.number({ min = 0, max = 1000000000, integer = true }) },
	items = { rule = PayloadValidator.array(catalogItemRule, { maxItems = 5 }) },
	error = { rule = remoteErrorRule, optional = true },
}, { maxItems = 11 }))

local purchaseRequestValidator = PayloadValidator.compile(PayloadValidator.record({
	requestId = { rule = requestIdRule },
	itemId = { rule = idRule },
}, { maxItems = 2 }))

local purchaseResponseValidator = PayloadValidator.compile(PayloadValidator.record({
	ok = { rule = PayloadValidator.boolean() },
	requestId = { rule = requestIdRule },
	itemId = { rule = idRule },
	revision = { rule = PayloadValidator.number({ min = 0, integer = true }) },
	currentTierId = { rule = idRule },
	cash = { rule = PayloadValidator.number({ min = 0, max = 1000000000, integer = true }) },
	state = { rule = stateRule },
	currentLevel = { rule = PayloadValidator.number({ min = 0, max = 3, integer = true }), optional = true },
	error = { rule = remoteErrorRule, optional = true },
}, { maxItems = 9 }))

local definitions: { RemoteDefinition } = {
	{
		name = "RequestOfficeCatalog",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = catalogRequestValidator,
		responseValidator = catalogResponseValidator,
	},
	{
		name = "RequestOfficePurchase",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = purchaseRequestValidator,
		responseValidator = purchaseResponseValidator,
	},
}

return table.freeze({
	folderName = "Remotes",
	definitions = DeepFreeze.copy(definitions),
})
