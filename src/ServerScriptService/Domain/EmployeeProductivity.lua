--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)

type Employee = EmployeeTypes.Employee
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type TraitDefinition = EmployeeTypes.TraitDefinition

export type Context = {
	equipmentLevel: number,
	teamOutputBonus: number,
	teamXpBonus: number,
	deltaSeconds: number,
}
export type ProductivityResult = { points: number, xp: number, pointsPerMinute: number }

local EmployeeProductivity = {}

local function moraleMultiplier(config: EmployeeConfig, morale: number): number
	for _, band in config.morale.bands do
		if morale >= band.minimum then
			return band.multiplier
		end
	end
	return config.morale.bands[#config.morale.bands].multiplier
end

function EmployeeProductivity.Calculate(
	config: EmployeeConfig,
	employee: Employee,
	traitDefinition: TraitDefinition,
	context: Context
): ProductivityResult
	local delta = math.clamp(context.deltaSeconds, 0, config.productivity.maximumDeltaSeconds)
	if employee.status == "Inactive" or employee.status == "Dismissed" or delta <= 0 then
		return { points = 0, xp = 0, pointsPerMinute = 0 }
	end
	local speed = employee.speed * traitDefinition.speedMultiplier
	local quality = employee.quality * traitDefinition.qualityMultiplier
	local reliability = employee.reliability * traitDefinition.reliabilityMultiplier
	local basePower = speed * config.productivity.speedWeight
		+ quality * config.productivity.qualityWeight
		+ reliability * config.productivity.reliabilityWeight
	local personalOutput = traitDefinition.outputMultiplier
	if traitDefinition.focusedMoraleMinimum ~= nil and employee.morale < traitDefinition.focusedMoraleMinimum then
		personalOutput = 1
	end
	local teamOutput = if traitDefinition.ignoresTeamBonuses
		then 1
		else 1 + math.min(context.teamOutputBonus, config.productivity.teamPlayerStackCap)
	local levelMultiplier = 1 + (employee.level - 1) * config.productivity.levelBonusPerLevel
	local pointsPerMinute = basePower
		* levelMultiplier
		* (config.productivity.equipmentMultipliers[context.equipmentLevel] or 1)
		* moraleMultiplier(config, employee.morale)
		* (config.productivity.employmentMultipliers[employee.status] or 0)
		* personalOutput
		* teamOutput
	local points = math.max(0, pointsPerMinute * delta / 60)
	local xpTeam = if traitDefinition.ignoresTeamBonuses
		then 1
		else 1 + math.min(context.teamXpBonus, config.productivity.mentorStackCap)
	local xp = points * config.progression.xpPerWorkPoint * traitDefinition.xpMultiplier * xpTeam
	if points ~= points or math.abs(points) == math.huge or xp ~= xp or math.abs(xp) == math.huge then
		return { points = 0, xp = 0, pointsPerMinute = 0 }
	end
	return { points = points, xp = xp, pointsPerMinute = pointsPerMinute }
end

return table.freeze(EmployeeProductivity)
