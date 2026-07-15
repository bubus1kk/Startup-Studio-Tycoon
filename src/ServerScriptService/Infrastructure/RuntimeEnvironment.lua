--!strict

local RunService = game:GetService("RunService")

export type RuntimeEnvironment = "Studio" | "Test" | "Production"
export type EnvironmentSetting = "Auto" | "Test" | "Production"

local RuntimeEnvironment = {}

function RuntimeEnvironment.resolve(isStudio: boolean, setting: EnvironmentSetting): RuntimeEnvironment
	if setting == "Test" then
		return "Test"
	end
	if setting == "Production" then
		return "Production"
	end
	return if isStudio then "Studio" else "Production"
end

function RuntimeEnvironment.detect(setting: EnvironmentSetting): RuntimeEnvironment
	return RuntimeEnvironment.resolve(RunService:IsStudio(), setting)
end

return table.freeze(RuntimeEnvironment)
