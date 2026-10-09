--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local EmployeePayrollService = require(ServerScriptService.Services.EmployeePayrollService)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local SessionCurrencyService = require(ServerScriptService.Services.SessionCurrencyService)
local TestHarness = require(script.Parent.Parent.TestHarness)
local EmployeeTestUtils = require(script.Parent.Parent.ServerFixtures.EmployeeTestUtils)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type Employee = EmployeeTypes.Employee
type TestCase = TestHarness.TestCase
local EmployeePayrollSpec = {}

local resolver: DependencyResolver = {
	Get = function(_self: DependencyResolver, _name: string): unknown
		return nil
	end,
	Require = function(_self: DependencyResolver, name: string): unknown
		error(`Unexpected dependency {name}`)
	end,
}

local function employee(): Employee
	return {
		employeeId = "employee-1-1",
		ownerUserId = 1,
		displayName = "Alex",
		roleId = "Developer",
		grade = "Trainee",
		level = 1,
		xp = 0,
		speed = 5,
		quality = 5,
		reliability = 5,
		traitId = "Efficient",
		hiringCost = 250,
		salaryPerCycle = 10,
		morale = 80,
		status = "Active",
		missedPayrollCount = 0,
		assignedWorkstationId = "workstation:Developer:1",
		runtimeGeneration = 1,
		createdSequence = 1,
	}
end

local function atomicSuccessFailureRecoveryTest()
	local config = EmployeeTestUtils.validatedConfig()
	local currency = SessionCurrencyService.new(10)
	currency:Init(resolver)
	currency:Start()
	currency:OpenSession(1)
	local value = employee()
	local employees = { [value.employeeId] = value }
	local success = EmployeePayrollService.RunCycle(config, currency, 1, "a", 1, employees)
	TestHarness.assertTrue(success.ok and success.value.paid)
	local balance = currency:GetBalance(1, "Cash")
	TestHarness.assertTrue(balance.ok and balance.value == 0)
	local duplicate = EmployeePayrollService.RunCycle(config, currency, 1, "a", 1, employees)
	local duplicateBalance = currency:GetBalance(1, "Cash")
	TestHarness.assertTrue(duplicate.ok and duplicate.value.paid)
	TestHarness.assertTrue(duplicateBalance.ok and duplicateBalance.value == 0, "Duplicate payroll cycle debited twice")
	local firstMiss = EmployeePayrollService.RunCycle(config, currency, 1, "a", 2, employees)
	TestHarness.assertTrue(firstMiss.ok and not firstMiss.value.paid)
	TestHarness.assertEqual(value.status, "Unpaid")
	TestHarness.assertEqual(value.morale, 65)
	local secondMiss = EmployeePayrollService.RunCycle(config, currency, 1, "a", 3, employees)
	TestHarness.assertTrue(secondMiss.ok and not secondMiss.value.paid)
	TestHarness.assertEqual(value.status, "Inactive")
	TestHarness.assertEqual(value.morale, 55)
	currency:Destroy()
	local recoveryCurrency = SessionCurrencyService.new(10)
	recoveryCurrency:Init(resolver)
	recoveryCurrency:Start()
	recoveryCurrency:OpenSession(1)
	local recovery = EmployeePayrollService.RunCycle(config, recoveryCurrency, 1, "b", 1, employees)
	TestHarness.assertTrue(recovery.ok and recovery.value.paid)
	TestHarness.assertEqual(value.status, "Active")
	TestHarness.assertEqual(value.morale, 65)
	recoveryCurrency:Destroy()
end

function EmployeePayrollSpec.tests(): { TestCase }
	return {
		{
			name = "payroll is atomic and applies unpaid inactive recovery transitions",
			run = atomicSuccessFailureRecoveryTest,
		},
	}
end

return table.freeze(EmployeePayrollSpec)
