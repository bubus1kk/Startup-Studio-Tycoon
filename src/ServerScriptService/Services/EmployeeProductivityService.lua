--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local EmployeeProductivity = require(ServerScriptService.Domain.EmployeeProductivity)
local EmployeeProgression = require(ServerScriptService.Domain.EmployeeProgression)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local WorkstationService = require(ServerScriptService.Services.WorkstationService)

type Employee = EmployeeTypes.Employee
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type EmployeeGrade = EmployeeTypes.EmployeeGrade
type EmployeeRoleId = EmployeeTypes.EmployeeRoleId
type RoleWorkLedger = EmployeeTypes.RoleWorkLedger
type TraitDefinition = EmployeeTypes.TraitDefinition
type Workstations = WorkstationService.Service

export type TeamProfile = {
	roleId: EmployeeRoleId,
	activeEmployees: number,
	pointsPerMinute: number,
	averageQuality: number,
	averageReliability: number,
	accumulatedWorkPoints: number,
}

local EmployeeProductivityService = {}

local function orderedEmployees(employeesById: { [string]: Employee }): { Employee }
	local result = {}
	for _, employee in employeesById do
		if employee.status ~= "Dismissed" then
			table.insert(result, employee)
		end
	end
	table.sort(result, function(a: Employee, b: Employee): boolean
		if a.createdSequence == b.createdSequence then
			return a.employeeId < b.employeeId
		end
		return a.createdSequence < b.createdSequence
	end)
	return result
end

function EmployeeProductivityService.Step(
	config: EmployeeConfig,
	workstations: Workstations,
	userId: number,
	employeesById: { [string]: Employee },
	ledger: RoleWorkLedger,
	deltaSeconds: number
): { TeamProfile }
	local traitById = {} :: { [EmployeeTypes.EmployeeTraitId]: TraitDefinition }
	local gradeOrder = {} :: { [EmployeeGrade]: number }
	for _, definition in config.traits do
		traitById[definition.id] = definition
	end
	for _, definition in config.grades do
		gradeOrder[definition.id] = definition.order
	end
	local employees = orderedEmployees(employeesById)
	local teamPlayersByRole = {} :: { [EmployeeRoleId]: number }
	local mentorsByRoleAndGrade = {} :: { [EmployeeRoleId]: { [number]: number } }
	local teamPlayerBonus = assert(traitById.TeamPlayer, "TeamPlayer trait is missing").teamOutputBonus
	local mentorXpBonus = assert(traitById.Mentor, "Mentor trait is missing").mentorXpBonus
	local activeHr = 0
	for _, employee in employees do
		if workstations:IsAssignmentValid(userId, employee.employeeId) and employee.status ~= "Inactive" then
			if employee.traitId == "TeamPlayer" then
				teamPlayersByRole[employee.roleId] = (teamPlayersByRole[employee.roleId] or 0) + 1
			end
			if employee.traitId == "Mentor" then
				local byGrade = mentorsByRoleAndGrade[employee.roleId]
				if byGrade == nil then
					byGrade = {}
					mentorsByRoleAndGrade[employee.roleId] = byGrade
				end
				local order = gradeOrder[employee.grade]
				byGrade[order] = (byGrade[order] or 0) + 1
			end
			if employee.roleId == "HRSpecialist" and employee.status == "Active" then
				activeHr += 1
			end
		end
	end

	local totals = {} :: { [EmployeeRoleId]: { count: number, ppm: number, quality: number, reliability: number } }
	for _, role in config.roles do
		totals[role.id] = { count = 0, ppm = 0, quality = 0, reliability = 0 }
	end
	for _, employee in employees do
		local workstationId = employee.assignedWorkstationId
		local slot = if workstationId ~= nil then workstations:GetSlot(userId, workstationId) else nil
		if slot ~= nil and workstations:IsAssignmentValid(userId, employee.employeeId) then
			local teamCount = teamPlayersByRole[employee.roleId] or 0
			if employee.traitId == "TeamPlayer" then
				teamCount = math.max(0, teamCount - 1)
			end
			local mentorCount = 0
			local byGrade = mentorsByRoleAndGrade[employee.roleId]
			if byGrade ~= nil then
				for order, count in byGrade do
					if order > gradeOrder[employee.grade] then
						mentorCount += count
					end
				end
			end
			local traitDefinition = assert(traitById[employee.traitId], `Unknown employee trait {employee.traitId}`)
			local result = EmployeeProductivity.Calculate(config, employee, traitDefinition, {
				equipmentLevel = slot.equipmentLevel,
				teamOutputBonus = teamCount * teamPlayerBonus,
				teamXpBonus = mentorCount * mentorXpBonus,
				deltaSeconds = deltaSeconds,
			})
			ledger[employee.roleId] = math.max(0, (ledger[employee.roleId] or 0) + result.points)
			EmployeeProgression.ApplyXp(config, employee, result.xp)
			local total = totals[employee.roleId]
			if result.pointsPerMinute > 0 then
				total.count += 1
				total.ppm += result.pointsPerMinute
				total.quality += employee.quality
				total.reliability += employee.reliability
			end
		end
	end

	local recreationRecovery = if workstations:HasRecreationLounge(userId)
		then config.morale.recreationRecoveryPerMinute
		else 0
	if activeHr > 0 or recreationRecovery > 0 then
		local recoveryPerSecond = math.min(
			activeHr * config.morale.hrRecoveryPerMinute + recreationRecovery,
			config.morale.teamRecoveryCapPerMinute
		) / 60
		for _, employee in employees do
			if employee.status == "Active" then
				local traitDefinition = assert(traitById[employee.traitId], `Unknown employee trait {employee.traitId}`)
				employee.morale = math.min(
					config.morale.maximum,
					employee.morale + recoveryPerSecond * deltaSeconds * traitDefinition.positiveMoraleMultiplier
				)
			end
		end
	end

	local profiles = {}
	for _, role in config.roles do
		local total = totals[role.id]
		table.insert(profiles, {
			roleId = role.id,
			activeEmployees = total.count,
			pointsPerMinute = total.ppm,
			averageQuality = if total.count > 0 then total.quality / total.count else 0,
			averageReliability = if total.count > 0 then total.reliability / total.count else 0,
			accumulatedWorkPoints = ledger[role.id] or 0,
		})
	end
	return profiles
end

return table.freeze(EmployeeProductivityService)
