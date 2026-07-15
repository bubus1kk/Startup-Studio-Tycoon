--!strict

local AppTypes = require(script.Parent.Parent.Types.AppTypes)

type Result<T> = AppTypes.Result<T>
type StringMap = { [string]: unknown }

local ConfigValidator = {}

function ConfigValidator.expectObject(value: unknown, path: string): Result<StringMap>
	if typeof(value) ~= "table" then
		return AppTypes.failure("ConfigTypeMismatch", "Expected a configuration object", {
			path = path,
			expected = "table",
			actual = typeof(value),
		})
	end

	for key in value :: { [string | number]: unknown } do
		if typeof(key) ~= "string" then
			return AppTypes.failure("ConfigKeyTypeMismatch", "Configuration keys must be strings", {
				path = path,
				actual = typeof(key),
			})
		end
	end

	return AppTypes.success(value :: StringMap)
end

function ConfigValidator.rejectUnknownKeys(
	value: StringMap,
	allowedKeys: { [string]: boolean },
	path: string
): Result<true>
	for key in value do
		if not allowedKeys[key] then
			return AppTypes.failure("ConfigUnknownKey", "Configuration contains an unknown key", {
				path = `{path}.{key}`,
			})
		end
	end

	return AppTypes.success(true)
end

function ConfigValidator.booleanField(value: StringMap, key: string, path: string): Result<boolean>
	local fieldValue = value[key]
	if typeof(fieldValue) ~= "boolean" then
		return AppTypes.failure("ConfigTypeMismatch", "Expected a boolean configuration field", {
			path = `{path}.{key}`,
			expected = "boolean",
			actual = typeof(fieldValue),
		})
	end

	return AppTypes.success(fieldValue)
end

function ConfigValidator.stringEnumField(
	value: StringMap,
	key: string,
	allowedValues: { [string]: boolean },
	path: string
): Result<string>
	local fieldValue = value[key]
	if typeof(fieldValue) ~= "string" or not allowedValues[fieldValue] then
		return AppTypes.failure("ConfigInvalidEnum", "Configuration field has an unsupported value", {
			path = `{path}.{key}`,
			actual = tostring(fieldValue),
		})
	end

	return AppTypes.success(fieldValue)
end

return table.freeze(ConfigValidator)
