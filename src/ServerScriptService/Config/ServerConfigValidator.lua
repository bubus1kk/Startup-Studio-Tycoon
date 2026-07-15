--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local ConfigValidator = require(ReplicatedStorage.Shared.Config.ConfigValidator)

type Result<T> = AppTypes.Result<T>

export type ServerConfig = {
	environment: "Auto" | "Test" | "Production",
	featureFlags: {
		enableServerDebugLogging: boolean,
	},
}

local ServerConfigValidator = {}

function ServerConfigValidator.validate(value: unknown): Result<ServerConfig>
	local rootResult = ConfigValidator.expectObject(value, "ServerConfig")
	if not rootResult.ok then
		return rootResult
	end
	local root = rootResult.value

	local rootKeysResult = ConfigValidator.rejectUnknownKeys(root, {
		environment = true,
		featureFlags = true,
	}, "ServerConfig")
	if not rootKeysResult.ok then
		return rootKeysResult
	end

	local environmentResult = ConfigValidator.stringEnumField(root, "environment", {
		Auto = true,
		Test = true,
		Production = true,
	}, "ServerConfig")
	if not environmentResult.ok then
		return environmentResult
	end

	local flagsResult = ConfigValidator.expectObject(root.featureFlags, "ServerConfig.featureFlags")
	if not flagsResult.ok then
		return flagsResult
	end
	local flags = flagsResult.value

	local flagKeysResult = ConfigValidator.rejectUnknownKeys(flags, {
		enableServerDebugLogging = true,
	}, "ServerConfig.featureFlags")
	if not flagKeysResult.ok then
		return flagKeysResult
	end

	local debugResult = ConfigValidator.booleanField(flags, "enableServerDebugLogging", "ServerConfig.featureFlags")
	if not debugResult.ok then
		return debugResult
	end

	return AppTypes.success({
		environment = environmentResult.value :: "Auto" | "Test" | "Production",
		featureFlags = {
			enableServerDebugLogging = debugResult.value,
		},
	})
end

return table.freeze(ServerConfigValidator)
