--!strict

local AppTypes = require(script.Parent.Parent.Types.AppTypes)
local DeepFreeze = require(script.Parent.Parent.Utils.DeepFreeze)

type AppError = AppTypes.AppError
type Result<T> = AppTypes.Result<T>

export type Validator<T> = (value: unknown) -> Result<T>

local ConfigLoader = {}

function ConfigLoader.validateAndFreeze<T>(name: string, rawConfig: unknown, validator: Validator<T>): Result<T>
	local validationResult = validator(rawConfig)
	if not validationResult.ok then
		local validationError: AppError = validationResult.error
		local details = table.clone(validationError.details or {})
		details.config = name
		return AppTypes.failure(validationError.code, validationError.message, details)
	end

	return AppTypes.success(DeepFreeze.copy(validationResult.value))
end

return table.freeze(ConfigLoader)
