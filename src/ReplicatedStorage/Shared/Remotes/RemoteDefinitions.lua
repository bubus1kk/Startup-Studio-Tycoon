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

local employeeIdRule = PayloadValidator.string({ minLength = 1, maxLength = 72, pattern = "^[A-Za-z0-9_:-]+$" })
local employeeEnumRule = PayloadValidator.string({ minLength = 3, maxLength = 32, pattern = "^[A-Za-z]+$" })
local employeeOverviewRequestValidator = PayloadValidator.compile(PayloadValidator.record({
	rosterPage = { rule = PayloadValidator.number({ min = 1, max = 100, integer = true }) },
}, { maxItems = 1 }))
local employeeHireRequestValidator = PayloadValidator.compile(PayloadValidator.record({
	requestId = { rule = requestIdRule },
	candidateId = { rule = employeeIdRule },
}, { maxItems = 2 }))
local employeeAssignmentRequestValidator = PayloadValidator.compile(PayloadValidator.record({
	requestId = { rule = requestIdRule },
	employeeId = { rule = employeeIdRule },
	workstationId = { rule = employeeIdRule },
}, { maxItems = 3 }))
local employeeDismissRequestValidator = PayloadValidator.compile(PayloadValidator.record({
	requestId = { rule = requestIdRule },
	employeeId = { rule = employeeIdRule },
}, { maxItems = 2 }))
local candidateRefreshRequestValidator = PayloadValidator.compile(PayloadValidator.record({
	requestId = { rule = requestIdRule },
}, { maxItems = 1 }))

local candidateViewRule = PayloadValidator.record({
	candidateId = { rule = employeeIdRule },
	displayName = { rule = PayloadValidator.string({ minLength = 1, maxLength = 48 }) },
	roleId = { rule = employeeEnumRule },
	grade = { rule = employeeEnumRule },
	speed = { rule = PayloadValidator.number({ min = 0, max = 100, integer = true }) },
	quality = { rule = PayloadValidator.number({ min = 0, max = 100, integer = true }) },
	reliability = { rule = PayloadValidator.number({ min = 0, max = 100, integer = true }) },
	traitId = { rule = employeeEnumRule },
	hiringCost = { rule = PayloadValidator.number({ min = 0, max = 1000000000, integer = true }) },
	salaryPerCycle = { rule = PayloadValidator.number({ min = 0, max = 1000000000, integer = true }) },
	expiresInSeconds = { rule = PayloadValidator.number({ min = 0, max = 300 }) },
}, { maxItems = 11 })
local employeeViewRule = PayloadValidator.record({
	employeeId = { rule = employeeIdRule },
	displayName = { rule = PayloadValidator.string({ minLength = 1, maxLength = 48 }) },
	roleId = { rule = employeeEnumRule },
	grade = { rule = employeeEnumRule },
	level = { rule = PayloadValidator.number({ min = 1, max = 20, integer = true }) },
	xp = { rule = PayloadValidator.number({ min = 0, max = 1000000000 }) },
	requiredXp = { rule = PayloadValidator.number({ min = 0, max = 1000000000 }) },
	speed = { rule = PayloadValidator.number({ min = 0, max = 100, integer = true }) },
	quality = { rule = PayloadValidator.number({ min = 0, max = 100, integer = true }) },
	reliability = { rule = PayloadValidator.number({ min = 0, max = 100, integer = true }) },
	traitId = { rule = employeeEnumRule },
	salaryPerCycle = { rule = PayloadValidator.number({ min = 0, max = 1000000000, integer = true }) },
	morale = { rule = PayloadValidator.number({ min = 0, max = 100 }) },
	status = { rule = employeeEnumRule },
	assignedWorkstationId = { rule = employeeIdRule, optional = true },
}, { maxItems = 15 })
local roleWorkRule = PayloadValidator.record({
	roleId = { rule = employeeEnumRule },
	workPoints = { rule = PayloadValidator.number({ min = 0, max = 1000000000000 }) },
}, { maxItems = 2 })
local employeeOverviewFields = {
	candidates = { rule = PayloadValidator.array(candidateViewRule, { maxItems = 3 }) },
	roster = { rule = PayloadValidator.array(employeeViewRule, { maxItems = 5 }) },
	rosterPage = { rule = PayloadValidator.number({ min = 1, max = 100, integer = true }) },
	rosterPageCount = { rule = PayloadValidator.number({ min = 0, max = 100, integer = true }) },
	rosterTotal = { rule = PayloadValidator.number({ min = 0, max = 30, integer = true }) },
	tierEmployeeCap = { rule = PayloadValidator.number({ min = 0, max = 30, integer = true }) },
	workstationCapacity = { rule = PayloadValidator.number({ min = 0, max = 30, integer = true }) },
	occupiedWorkstations = { rule = PayloadValidator.number({ min = 0, max = 30, integer = true }) },
	payrollRemainingSeconds = { rule = PayloadValidator.number({ min = 0, max = 60 }) },
	refreshRemainingSeconds = { rule = PayloadValidator.number({ min = 0, max = 120 }) },
	roleWorkSummary = { rule = PayloadValidator.array(roleWorkRule, { maxItems = 9 }) },
	cash = { rule = PayloadValidator.number({ min = 0, max = 1000000000, integer = true }) },
}
local overviewResponseFields = table.clone(employeeOverviewFields)
overviewResponseFields.ok = { rule = PayloadValidator.boolean() }
overviewResponseFields.error = { rule = remoteErrorRule, optional = true }
local employeeOverviewResponseValidator =
	PayloadValidator.compile(PayloadValidator.record(overviewResponseFields, { maxItems = 14 }), { maxNodes = 256 })
local employeeOverviewRule = PayloadValidator.record(employeeOverviewFields, { maxItems = 12 })
local mutationResponseValidator = PayloadValidator.compile(
	PayloadValidator.record({
		ok = { rule = PayloadValidator.boolean() },
		requestId = { rule = requestIdRule },
		overview = { rule = employeeOverviewRule, optional = true },
		error = { rule = remoteErrorRule, optional = true },
	}, { maxItems = 4 }),
	{ maxNodes = 256 }
)

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
	{
		name = "RequestEmployeeOverview",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = employeeOverviewRequestValidator,
		responseValidator = employeeOverviewResponseValidator,
	},
	{
		name = "RequestEmployeeHire",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = employeeHireRequestValidator,
		responseValidator = mutationResponseValidator,
	},
	{
		name = "RequestEmployeeAssignment",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = employeeAssignmentRequestValidator,
		responseValidator = mutationResponseValidator,
	},
	{
		name = "RequestEmployeeDismiss",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = employeeDismissRequestValidator,
		responseValidator = mutationResponseValidator,
	},
	{
		name = "RequestCandidateRefresh",
		kind = "Function",
		direction = "ClientToServer",
		requestValidator = candidateRefreshRequestValidator,
		responseValidator = mutationResponseValidator,
	},
}

return table.freeze({
	folderName = "Remotes",
	definitions = DeepFreeze.copy(definitions),
})
