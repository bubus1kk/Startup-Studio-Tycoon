--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local SessionCurrencyService = require(ServerScriptService.Services.SessionCurrencyService)

type CurrencyService = SessionCurrencyService.Service
type Employee = EmployeeTypes.Employee
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type Result<T> = AppTypes.Result<T>

export type PayrollResult = { paid: boolean, totalSalary: number, cash: number? }

local EmployeePayrollService = {}

local function activeEmployees(employeesById: { [string]: Employee }): { Employee }
	local employees = {}
	for _, employee in employeesById do
		if employee.status ~= "Dismissed" then
			table.insert(employees, employee)
		end
	end
	table.sort(employees, function(a: Employee, b: Employee): boolean
		if a.createdSequence == b.createdSequence then
			return a.employeeId < b.employeeId
		end
		return a.createdSequence < b.createdSequence
	end)
	return employees
end

function EmployeePayrollService.RunCycle(
	config: EmployeeConfig,
	currency: CurrencyService,
	userId: number,
	runtimeSessionId: string,
	cycle: number,
	employeesById: { [string]: Employee }
): Result<PayrollResult>
	local employees = activeEmployees(employeesById)
	local totalSalary = 0
	for _, employee in employees do
		totalSalary += employee.salaryPerCycle
	end
	if totalSalary == 0 then
		return AppTypes.success({ paid = true, totalSalary = 0 })
	end
	local transactionId = `employee-payroll:{userId}:{runtimeSessionId}:{cycle}`
	local reserve = currency:ReserveDebit(userId, "Cash", totalSalary, "EmployeePayroll", transactionId)
	if not reserve.ok then
		if reserve.error.code ~= "InsufficientFunds" then
			return AppTypes.failure(reserve.error.code, reserve.error.message, reserve.error.details)
		end
		for _, employee in employees do
			employee.missedPayrollCount += 1
			if employee.missedPayrollCount == 1 then
				employee.status = "Unpaid"
				employee.morale = math.max(config.morale.minimum, employee.morale + config.payroll.firstMissMorale)
			else
				employee.status = "Inactive"
				employee.morale = math.max(config.morale.minimum, employee.morale + config.payroll.laterMissMorale)
			end
		end
		return AppTypes.success({ paid = false, totalSalary = totalSalary })
	end
	local commit = currency:CommitDebit(reserve.value.reservationId)
	if not commit.ok then
		currency:ReleaseDebit(reserve.value.reservationId)
		return AppTypes.failure("TransactionFailed", "Payroll transaction could not be committed", nil)
	end
	for _, employee in employees do
		if employee.missedPayrollCount > 0 then
			employee.status = "Active"
			employee.morale = math.min(config.morale.maximum, employee.morale + config.payroll.recoveryMorale)
		end
		employee.missedPayrollCount = 0
	end
	return AppTypes.success({ paid = true, totalSalary = totalSalary, cash = commit.value.balances.Cash })
end

return table.freeze(EmployeePayrollService)
