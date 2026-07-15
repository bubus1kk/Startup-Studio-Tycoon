--!strict

local AppTypes = require(script.Parent.Parent.Types.AppTypes)
local ConfigValidator = require(script.Parent.ConfigValidator)

type Result<T> = AppTypes.Result<T>

export type PublicFeatureFlags = {
	enableClientDebugLogging: boolean,
}

local DEFAULTS: PublicFeatureFlags = {
	enableClientDebugLogging = false,
}

local PublicFeatureFlags = {}

function PublicFeatureFlags.defaults(): PublicFeatureFlags
	return table.clone(DEFAULTS)
end

function PublicFeatureFlags.validate(value: unknown): Result<PublicFeatureFlags>
	local objectResult = ConfigValidator.expectObject(value, "PublicFeatureFlags")
	if not objectResult.ok then
		return objectResult
	end

	local object = objectResult.value
	local keysResult = ConfigValidator.rejectUnknownKeys(object, {
		enableClientDebugLogging = true,
	}, "PublicFeatureFlags")
	if not keysResult.ok then
		return keysResult
	end

	local debugResult = ConfigValidator.booleanField(object, "enableClientDebugLogging", "PublicFeatureFlags")
	if not debugResult.ok then
		return debugResult
	end

	return AppTypes.success({
		enableClientDebugLogging = debugResult.value,
	})
end

return table.freeze(PublicFeatureFlags)
