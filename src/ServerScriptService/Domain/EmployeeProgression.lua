--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)

type Employee = EmployeeTypes.Employee
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type GradeDefinition = EmployeeTypes.GradeDefinition

local EmployeeProgression = {}

function EmployeeProgression.RequiredXp(config: EmployeeConfig, currentLevel: number): number
	return config.progression.baseRequiredXp + (currentLevel - 1) * config.progression.requiredXpPerLevel
end

function EmployeeProgression.ApplyXp(config: EmployeeConfig, employee: Employee, xpGain: number): number
	if xpGain <= 0 or xpGain ~= xpGain or math.abs(xpGain) == math.huge then
		return 0
	end
	local grade: GradeDefinition? = nil
	for _, candidate in config.grades do
		if candidate.id == employee.grade then
			grade = candidate
			break
		end
	end
	assert(grade ~= nil, `Unknown employee grade {employee.grade}`)
	local maximumLevel = (grade :: GradeDefinition).maxLevel
	if employee.level >= maximumLevel then
		if not config.progression.retainXpAtMaxLevel then
			employee.xp = 0
		end
		return 0
	end
	employee.xp += xpGain
	local levels = 0
	while employee.level < maximumLevel do
		local required = EmployeeProgression.RequiredXp(config, employee.level)
		if employee.xp < required then
			break
		end
		employee.xp -= required
		employee.level += 1
		levels += 1
		employee.speed = math.min(config.statClamp.maximum, employee.speed + 1)
		if employee.level % 2 == 0 then
			employee.quality = math.min(config.statClamp.maximum, employee.quality + 1)
		end
		if employee.level % 3 == 0 then
			employee.reliability = math.min(config.statClamp.maximum, employee.reliability + 1)
		end
		employee.morale = math.min(config.morale.maximum, employee.morale + config.progression.levelUpMorale)
	end
	if employee.level >= maximumLevel and not config.progression.retainXpAtMaxLevel then
		employee.xp = 0
	end
	return levels
end

return table.freeze(EmployeeProgression)
