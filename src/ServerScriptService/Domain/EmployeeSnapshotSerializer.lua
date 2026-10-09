--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)

type EmployeeConfig = EmployeeTypes.EmployeeConfig
type EmployeeSessionSnapshot = EmployeeTypes.EmployeeSessionSnapshot
type Result<T> = AppTypes.Result<T>

local EmployeeSnapshotSerializer = {}

type DataBudget = { nodes: number, seen: { [{ [unknown]: unknown }]: boolean } }

local function dataOnly(value: unknown, depth: number, budget: DataBudget): boolean
	local valueType = typeof(value)
	if valueType == "number" then
		return value == value and math.abs(value) ~= math.huge
	elseif valueType == "string" or valueType == "boolean" then
		return true
	elseif valueType ~= "table" or depth > 8 then
		return false
	end
	budget.nodes += 1
	if budget.nodes > 1024 then
		return false
	end
	local current = value :: { [unknown]: unknown }
	if budget.seen[current] then
		return false
	end
	budget.seen[current] = true
	for key, nested in current do
		if (typeof(key) ~= "string" and typeof(key) ~= "number") or not dataOnly(nested, depth + 1, budget) then
			return false
		end
	end
	budget.seen[current] = nil
	return true
end

local function copyEmployee(employee: EmployeeTypes.Employee): EmployeeTypes.Employee
	return table.clone(employee)
end

function EmployeeSnapshotSerializer.Copy(snapshot: EmployeeSessionSnapshot): EmployeeSessionSnapshot
	local employees = {}
	for _, employee in snapshot.employees do
		table.insert(employees, copyEmployee(employee))
	end
	local candidates = {}
	for _, entry in snapshot.candidates do
		table.insert(candidates, { candidate = table.clone(entry.candidate), remainingTtl = entry.remainingTtl })
	end
	return {
		schemaVersion = snapshot.schemaVersion,
		employees = employees,
		assignments = table.clone(snapshot.assignments),
		roleWorkLedger = table.clone(snapshot.roleWorkLedger),
		candidates = candidates,
		refreshRemainingSeconds = snapshot.refreshRemainingSeconds,
		payrollRemainingSeconds = snapshot.payrollRemainingSeconds,
		nextEmployeeSequence = snapshot.nextEmployeeSequence,
	}
end

function EmployeeSnapshotSerializer.Validate(config: EmployeeConfig, value: unknown): Result<EmployeeSessionSnapshot>
	if typeof(value) ~= "table" then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Snapshot is not a table", nil)
	end
	if not dataOnly(value, 0, { nodes = 0, seen = {} }) then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Snapshot contains unsafe or unbounded data", nil)
	end
	local snapshot = value :: EmployeeSessionSnapshot
	if
		snapshot.schemaVersion ~= config.schemaVersion
		or typeof(snapshot.employees) ~= "table"
		or #snapshot.employees > 30
	then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Snapshot header is invalid", nil)
	end
	if
		typeof(snapshot.assignments) ~= "table"
		or typeof(snapshot.roleWorkLedger) ~= "table"
		or typeof(snapshot.candidates) ~= "table"
	then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Snapshot collections are invalid", nil)
	end
	if #snapshot.candidates ~= config.candidate.poolSize then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Candidate snapshot size is invalid", nil)
	end
	local roleIds = {}
	local gradeById = {}
	local traitIds = {}
	for _, definition in config.roles do
		roleIds[definition.id] = true
	end
	for _, definition in config.grades do
		gradeById[definition.id] = definition
	end
	for _, definition in config.traits do
		traitIds[definition.id] = true
	end
	local function finite(numberValue: unknown): boolean
		return typeof(numberValue) == "number" and numberValue == numberValue and math.abs(numberValue) ~= math.huge
	end
	local function integer(numberValue: unknown, minimum: number): boolean
		return finite(numberValue) and numberValue >= minimum and numberValue % 1 == 0
	end
	local employeeIds: { [string]: boolean } = {}
	local createdSequences: { [number]: boolean } = {}
	local maximumSequence = 0
	local employeeEntryCount = 0
	for employeeIndex, employee in snapshot.employees do
		employeeEntryCount += 1
		if
			typeof(employeeIndex) ~= "number"
			or employeeIndex % 1 ~= 0
			or employeeIndex < 1
			or employeeIndex > #snapshot.employees
		then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Employee array is invalid", nil)
		end
		if typeof(employee) ~= "table" then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Employee entry is invalid", nil)
		end
		local grade = gradeById[employee.grade]
		if
			typeof(employee.employeeId) ~= "string"
			or #employee.employeeId < 1
			or #employee.employeeId > 72
			or employeeIds[employee.employeeId]
			or not integer(employee.ownerUserId, 1)
			or typeof(employee.displayName) ~= "string"
			or #employee.displayName < 1
			or #employee.displayName > 48
			or roleIds[employee.roleId] ~= true
			or grade == nil
			or not integer(employee.level, 1)
			or employee.level > grade.maxLevel
			or not finite(employee.xp)
			or employee.xp < 0
			or employee.xp > 1000000000
			or not integer(employee.speed, config.statClamp.minimum)
			or employee.speed > config.statClamp.maximum
			or not integer(employee.quality, config.statClamp.minimum)
			or employee.quality > config.statClamp.maximum
			or not integer(employee.reliability, config.statClamp.minimum)
			or employee.reliability > config.statClamp.maximum
			or traitIds[employee.traitId] ~= true
			or not integer(employee.hiringCost, 0)
			or employee.hiringCost > 1000000000
			or not integer(employee.salaryPerCycle, 0)
			or employee.salaryPerCycle > 1000000000
			or not finite(employee.morale)
			or employee.morale < config.morale.minimum
			or employee.morale > config.morale.maximum
			or (employee.status ~= "Active" and employee.status ~= "Unpaid" and employee.status ~= "Inactive")
			or not integer(employee.missedPayrollCount, 0)
			or (employee.assignedWorkstationId ~= nil and typeof(employee.assignedWorkstationId) ~= "string")
			or not integer(employee.runtimeGeneration, 0)
			or not integer(employee.createdSequence, 1)
			or createdSequences[employee.createdSequence]
			or employee.status == "Dismissed"
		then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Employee record is invalid", nil)
		end
		employeeIds[employee.employeeId] = true
		createdSequences[employee.createdSequence] = true
		maximumSequence = math.max(maximumSequence, employee.createdSequence)
	end
	if employeeEntryCount ~= #snapshot.employees then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Employee array contains holes", nil)
	end
	local workstationIds: { [string]: boolean } = {}
	for employeeId, workstationId in snapshot.assignments do
		if
			typeof(employeeId) ~= "string"
			or not employeeIds[employeeId]
			or typeof(workstationId) ~= "string"
			or #workstationId < 1
			or #workstationId > 72
			or workstationIds[workstationId]
		then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Assignment record is invalid", nil)
		end
		workstationIds[workstationId] = true
	end
	local ledgerCount = 0
	for roleId, points in snapshot.roleWorkLedger do
		ledgerCount += 1
		if roleIds[roleId] ~= true or not finite(points) or points < 0 or points > 1000000000000 then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Role ledger is invalid", nil)
		end
	end
	if ledgerCount ~= #config.roles then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Role ledger size is invalid", nil)
	end
	for _, role in config.roles do
		local points = snapshot.roleWorkLedger[role.id]
		if not finite(points) or points < 0 or points > 1000000000000 then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Role ledger is invalid", nil)
		end
	end
	local candidateIds: { [string]: boolean } = {}
	local candidateEntryCount = 0
	for slotIndex, entry in snapshot.candidates do
		candidateEntryCount += 1
		if
			typeof(slotIndex) ~= "number"
			or slotIndex % 1 ~= 0
			or slotIndex < 1
			or slotIndex > config.candidate.poolSize
		then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Candidate array is invalid", nil)
		end
		if typeof(entry) ~= "table" or typeof(entry.candidate) ~= "table" then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Candidate entry is invalid", nil)
		end
		local candidate = entry.candidate
		if
			typeof(candidate.candidateId) ~= "string"
			or #candidate.candidateId < 1
			or #candidate.candidateId > 72
			or candidateIds[candidate.candidateId]
			or not integer(candidate.ownerUserId, 1)
			or candidate.slotIndex ~= slotIndex
			or not integer(candidate.generation, 1)
			or typeof(candidate.displayName) ~= "string"
			or #candidate.displayName < 1
			or #candidate.displayName > 48
			or roleIds[candidate.roleId] ~= true
			or gradeById[candidate.grade] == nil
			or not integer(candidate.speed, config.statClamp.minimum)
			or candidate.speed > config.statClamp.maximum
			or not integer(candidate.quality, config.statClamp.minimum)
			or candidate.quality > config.statClamp.maximum
			or not integer(candidate.reliability, config.statClamp.minimum)
			or candidate.reliability > config.statClamp.maximum
			or traitIds[candidate.traitId] ~= true
			or not integer(candidate.hiringCost, 0)
			or candidate.hiringCost > 1000000000
			or not integer(candidate.salaryPerCycle, 0)
			or candidate.salaryPerCycle > 1000000000
			or not finite(candidate.createdAt)
			or not finite(candidate.expiresAt)
			or candidate.expiresAt <= candidate.createdAt
			or not finite(entry.remainingTtl)
			or entry.remainingTtl <= 0
			or entry.remainingTtl > config.candidate.ttlSeconds
		then
			return AppTypes.failure("EmployeeSnapshotInvalid", "Candidate record is invalid", nil)
		end
		candidateIds[candidate.candidateId] = true
	end
	if candidateEntryCount ~= config.candidate.poolSize then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Candidate array contains holes", nil)
	end
	if
		not finite(snapshot.refreshRemainingSeconds)
		or snapshot.refreshRemainingSeconds < 0
		or snapshot.refreshRemainingSeconds > config.candidate.refreshCooldownSeconds
		or not finite(snapshot.payrollRemainingSeconds)
		or snapshot.payrollRemainingSeconds < 0
		or snapshot.payrollRemainingSeconds > config.payroll.intervalSeconds
		or not integer(snapshot.nextEmployeeSequence, 0)
		or snapshot.nextEmployeeSequence < maximumSequence
	then
		return AppTypes.failure("EmployeeSnapshotInvalid", "Snapshot timers are invalid", nil)
	end
	return AppTypes.success(EmployeeSnapshotSerializer.Copy(snapshot))
end

return table.freeze(EmployeeSnapshotSerializer)
