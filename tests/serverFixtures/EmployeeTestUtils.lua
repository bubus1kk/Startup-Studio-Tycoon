--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local ConfigLoader = require(ReplicatedStorage.Shared.Config.ConfigLoader)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local EmployeeConfigValidator = require(ServerScriptService.Config.EmployeeConfigValidator)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local RequestRateLimiter = require(ServerScriptService.Security.RequestRateLimiter)
local EmployeeMovementService = require(ServerScriptService.Services.EmployeeMovementService)
local EmployeeService = require(ServerScriptService.Services.EmployeeService)
local WorkstationService = require(ServerScriptService.Services.WorkstationService)
local EmployeeDefinitions = require(ServerStorage.Config.EmployeeDefinitions)
local OfficeTestUtils = require(script.Parent.OfficeTestUtils)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type EmployeeConfig = EmployeeTypes.EmployeeConfig

export type Fixture = {
	userId: number,
	config: EmployeeConfig,
	officeFixture: OfficeTestUtils.Fixture,
	workstations: WorkstationService.Service,
	movement: EmployeeMovementService.Service,
	employees: EmployeeService.Service,
	requestSequence: number,
	HireAny: (self: Fixture) -> EmployeeRemoteResult,
	Destroy: (self: Fixture) -> (),
}

export type EmployeeRemoteResult = {
	ok: boolean,
	requestId: string,
	overview: unknown?,
	error: { code: string, message: string }?,
}

local EmployeeTestUtils = {}

function EmployeeTestUtils.validatedConfig(): EmployeeConfig
	local officeConfig = OfficeTestUtils.validatedConfig()
	local result = ConfigLoader.validateAndFreeze("EmployeeDefinitions", EmployeeDefinitions, function(value: unknown)
		return EmployeeConfigValidator.validate(value, officeConfig)
	end)
	if not result.ok then
		error(`Employee config validation failed: {result.error.code}`)
	end
	return result.value
end

function EmployeeTestUtils.createFixture(
	userId: number,
	fullOffice: boolean?,
	initialCash: number?,
	deferredItemId: string?,
	clock: (() -> number)?
): Fixture
	local officeFixture = OfficeTestUtils.createFixture(userId, nil, initialCash)
	local order = if fullOffice
		then OfficeTestUtils.fullProgressionOrder(officeFixture.config)
		else {
			"room_development",
			"equipment_dev_workstation",
		}
	for _, itemId in order do
		if itemId ~= deferredItemId then
			local response = officeFixture:Purchase(itemId)
			if not response.ok then
				error(`Employee fixture office purchase failed: {OfficeTestUtils.purchaseDiagnostic(itemId, response)}`)
			end
		end
	end
	local config = EmployeeTestUtils.validatedConfig()
	local logger = Logger.new("Test", "employee-fixture", "EmployeeFixture", true)
	local workstations = WorkstationService.new(config)
	local movement = EmployeeMovementService.new(config, logger)
	local limiterClock = 0
	local limiter = RequestRateLimiter.new(function(): number
		limiterClock += 0.5
		return limiterClock
	end)
	local randomCursor = 0
	local employees = EmployeeService.new(
		config,
		limiter,
		logger,
		clock or os.clock,
		function(minimum: number, maximum: number): number
			randomCursor += 1
			return minimum + (randomCursor - 1) % (maximum - minimum + 1)
		end
	)
	local fakeRemotes = {}
	function fakeRemotes:BindFunction(_name: string, _handler: (Player, unknown) -> unknown)
		return AppTypes.success(true)
	end
	local function dependency(name: string): unknown
		if name == "OfficeBuildingService" then
			return officeFixture.office
		elseif name == "PlotService" then
			return officeFixture.plot.service
		elseif name == "SessionCurrencyService" then
			return officeFixture.currency
		elseif name == "WorkstationService" then
			return workstations
		elseif name == "EmployeeMovementService" then
			return movement
		elseif name == "ServerRemoteRegistry" then
			return fakeRemotes
		end
		return nil
	end
	local resolver: DependencyResolver = {
		Get = function(_self: DependencyResolver, name: string): unknown
			return dependency(name)
		end,
		Require = function(_self: DependencyResolver, name: string): unknown
			local value = dependency(name)
			if value == nil then
				error(`Missing employee fixture dependency {name}`)
			end
			return value
		end,
	}
	workstations:Init(resolver)
	workstations:Start()
	movement:Init(resolver)
	movement:Start()
	employees:Init(resolver)
	employees:Start()
	local workstationPrepare = workstations:PrepareSession(userId)
	if not workstationPrepare.ok then
		error(`Workstation prepare failed: {workstationPrepare.error.code}`)
	end
	local employeePrepare = employees:PrepareSession(userId, nil)
	if not employeePrepare.ok then
		error(`Employee prepare failed: {employeePrepare.error.code}`)
	end
	local fixture: Fixture
	fixture = {
		userId = userId,
		config = config,
		officeFixture = officeFixture,
		workstations = workstations,
		movement = movement,
		employees = employees,
		requestSequence = 0,
		HireAny = function(self: Fixture): EmployeeRemoteResult
			local overview = self.employees:HandleOverview(self.userId, { rosterPage = 1 })
			if not overview.ok then
				error("Employee fixture overview failed")
			end
			local lastResponse: EmployeeRemoteResult? = nil
			for _, candidate in overview.candidates do
				self.requestSequence += 1
				local response = self.employees:Hire(self.userId, {
					requestId = `employee-fixture-{self.requestSequence}`,
					candidateId = candidate.candidateId,
				})
				lastResponse = response :: EmployeeRemoteResult
				if response.ok then
					return response :: EmployeeRemoteResult
				end
			end
			return assert(lastResponse, "Candidate board was empty")
		end,
		Destroy = function(self: Fixture)
			self.employees:Destroy()
			self.movement:Destroy()
			self.workstations:Destroy()
			self.officeFixture:Destroy()
		end,
	}
	return fixture
end

return table.freeze(EmployeeTestUtils)
