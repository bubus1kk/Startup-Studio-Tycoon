--!strict

local AppTypes = require(script.Parent.Parent.Types.AppTypes)

type Result<T> = AppTypes.Result<T>
type Budget = { nodes: number }

export type Rule = (value: unknown, path: string, depth: number, budget: Budget) -> Result<true>
export type Validator = (value: unknown) -> Result<true>

export type StringOptions = {
	minLength: number?,
	maxLength: number?,
	pattern: string?,
}

export type NumberOptions = {
	min: number?,
	max: number?,
	integer: boolean?,
}

export type Field = {
	rule: Rule,
	optional: boolean?,
}

export type CollectionOptions = {
	maxItems: number?,
}

local DEFAULT_MAX_DEPTH = 8
local DEFAULT_MAX_NODES = 128

local PayloadValidator = {}

local function invalid(path: string, reason: string, actual: string?): AppTypes.Failure
	return AppTypes.failure("InvalidPayload", "Remote payload validation failed", {
		path = path,
		reason = reason,
		actual = actual or "unknown",
	})
end

local function consumeNode(path: string, depth: number, budget: Budget): Result<true>
	if depth > DEFAULT_MAX_DEPTH then
		return invalid(path, "maximum depth exceeded", tostring(depth))
	end

	budget.nodes += 1
	if budget.nodes > DEFAULT_MAX_NODES then
		return invalid(path, "maximum node count exceeded", tostring(budget.nodes))
	end

	return AppTypes.success(true)
end

function PayloadValidator.string(options: StringOptions?): Rule
	local settings = options or {}
	return function(value: unknown, path: string, depth: number, budget: Budget): Result<true>
		local budgetResult = consumeNode(path, depth, budget)
		if not budgetResult.ok then
			return budgetResult
		end

		if typeof(value) ~= "string" then
			return invalid(path, "expected string", typeof(value))
		end

		local length = #value
		if settings.minLength ~= nil and length < settings.minLength then
			return invalid(path, "string shorter than minimum", tostring(length))
		end
		if settings.maxLength ~= nil and length > settings.maxLength then
			return invalid(path, "string longer than maximum", tostring(length))
		end
		if settings.pattern ~= nil and string.match(value, settings.pattern) == nil then
			return invalid(path, "string does not match required pattern", "string")
		end

		return AppTypes.success(true)
	end
end

function PayloadValidator.number(options: NumberOptions?): Rule
	local settings = options or {}
	return function(value: unknown, path: string, depth: number, budget: Budget): Result<true>
		local budgetResult = consumeNode(path, depth, budget)
		if not budgetResult.ok then
			return budgetResult
		end

		if typeof(value) ~= "number" then
			return invalid(path, "expected number", typeof(value))
		end
		if value ~= value or math.abs(value) == math.huge then
			return invalid(path, "number must be finite", tostring(value))
		end
		if settings.integer and value % 1 ~= 0 then
			return invalid(path, "expected integer", tostring(value))
		end
		if settings.min ~= nil and value < settings.min then
			return invalid(path, "number below minimum", tostring(value))
		end
		if settings.max ~= nil and value > settings.max then
			return invalid(path, "number above maximum", tostring(value))
		end

		return AppTypes.success(true)
	end
end

function PayloadValidator.boolean(): Rule
	return function(value: unknown, path: string, depth: number, budget: Budget): Result<true>
		local budgetResult = consumeNode(path, depth, budget)
		if not budgetResult.ok then
			return budgetResult
		end

		if typeof(value) ~= "boolean" then
			return invalid(path, "expected boolean", typeof(value))
		end

		return AppTypes.success(true)
	end
end

function PayloadValidator.record(fields: { [string]: Field }, options: CollectionOptions?): Rule
	local maxItems = if options == nil or options.maxItems == nil then 32 else options.maxItems
	return function(value: unknown, path: string, depth: number, budget: Budget): Result<true>
		local budgetResult = consumeNode(path, depth, budget)
		if not budgetResult.ok then
			return budgetResult
		end
		if typeof(value) ~= "table" then
			return invalid(path, "expected object", typeof(value))
		end

		local object = value :: { [string | number]: unknown }
		local itemCount = 0
		for key in object do
			itemCount += 1
			if itemCount > maxItems then
				return invalid(path, "object has too many fields", tostring(itemCount))
			end
			if typeof(key) ~= "string" or fields[key] == nil then
				return invalid(path, "object contains an unknown field", tostring(key))
			end
		end

		for fieldName, field in fields do
			local fieldValue = object[fieldName]
			if fieldValue == nil then
				if not field.optional then
					return invalid(`{path}.{fieldName}`, "required field is missing", "nil")
				end
			else
				local fieldResult = field.rule(fieldValue, `{path}.{fieldName}`, depth + 1, budget)
				if not fieldResult.ok then
					return fieldResult
				end
			end
		end

		return AppTypes.success(true)
	end
end

function PayloadValidator.array(itemRule: Rule, options: CollectionOptions?): Rule
	local maxItems = if options == nil or options.maxItems == nil then 32 else options.maxItems
	return function(value: unknown, path: string, depth: number, budget: Budget): Result<true>
		local budgetResult = consumeNode(path, depth, budget)
		if not budgetResult.ok then
			return budgetResult
		end
		if typeof(value) ~= "table" then
			return invalid(path, "expected array", typeof(value))
		end

		local arrayValue = value :: { [string | number]: unknown }
		local length = #arrayValue
		if length > maxItems then
			return invalid(path, "array has too many items", tostring(length))
		end

		local keyCount = 0
		for key in arrayValue do
			keyCount += 1
			if typeof(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
				return invalid(path, "array contains a non-sequential key", tostring(key))
			end
		end
		if keyCount ~= length then
			return invalid(path, "array contains holes", tostring(keyCount))
		end

		for index = 1, length do
			local itemResult = itemRule(arrayValue[index], `{path}[{index}]`, depth + 1, budget)
			if not itemResult.ok then
				return itemResult
			end
		end

		return AppTypes.success(true)
	end
end

function PayloadValidator.compile(rule: Rule): Validator
	return function(value: unknown): Result<true>
		return rule(value, "$", 0, { nodes = 0 })
	end
end

return table.freeze(PayloadValidator)
