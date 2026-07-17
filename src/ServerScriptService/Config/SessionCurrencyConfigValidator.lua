--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)

type Result<T> = AppTypes.Result<T>

export type SessionCurrencyConfig = {
	initialCashByEnvironment: {
		Development: number,
		Test: number,
		Production: number,
	},
	snapshotTtlSeconds: number,
	snapshotCapacity: number,
}

local SessionCurrencyConfigValidator = {}

local function integer(value: unknown, minimum: number): boolean
	return typeof(value) == "number" and value >= minimum and value % 1 == 0
end

function SessionCurrencyConfigValidator.validate(value: unknown): Result<SessionCurrencyConfig>
	if typeof(value) ~= "table" then
		return AppTypes.failure("SessionCurrencyConfigInvalid", "Session currency config must be a table", nil)
	end
	local config = value :: SessionCurrencyConfig
	local balances = config.initialCashByEnvironment
	if
		typeof(balances) ~= "table"
		or not integer(balances.Development, 1)
		or not integer(balances.Test, 1)
		or not integer(balances.Production, 1)
	then
		return AppTypes.failure(
			"SessionCurrencyConfigInvalid",
			"Every environment requires explicit positive funding",
			nil
		)
	end
	if not integer(config.snapshotTtlSeconds, 1) or not integer(config.snapshotCapacity, 1) then
		return AppTypes.failure("SessionCurrencyConfigInvalid", "Snapshot limits must be positive integers", nil)
	end
	return AppTypes.success(config)
end

return table.freeze(SessionCurrencyConfigValidator)
