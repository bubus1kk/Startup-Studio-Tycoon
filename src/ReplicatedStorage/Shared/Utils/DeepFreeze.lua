--!strict

type ConfigKey = string | number
type UnknownTable = { [ConfigKey]: unknown }

local DeepFreeze = {}

local function copyValue(value: unknown, copies: { [UnknownTable]: UnknownTable }): unknown
	if typeof(value) ~= "table" then
		return value
	end

	local source = value :: UnknownTable
	local existing = copies[source]
	if existing ~= nil then
		return existing
	end

	local copy: UnknownTable = {}
	copies[source] = copy

	for key, nestedValue in source do
		copy[key] = copyValue(nestedValue, copies)
	end

	return table.freeze(copy)
end

function DeepFreeze.copy<T>(value: T): T
	return copyValue(value, {}) :: T
end

function DeepFreeze.isFrozenRecursive(value: unknown, visited: { [UnknownTable]: boolean }?): boolean
	if typeof(value) ~= "table" then
		return true
	end

	local source = value :: UnknownTable
	local seen = visited or {}
	if seen[source] then
		return true
	end
	seen[source] = true

	if not table.isfrozen(source) then
		return false
	end

	for _, nestedValue in source do
		if not DeepFreeze.isFrozenRecursive(nestedValue, seen) then
			return false
		end
	end

	return true
end

return table.freeze(DeepFreeze)
