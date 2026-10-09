--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local LoggerTypes = require(ReplicatedStorage.Shared.Types.LoggerTypes)
local EmployeeRemoteTypes = require(ReplicatedStorage.Shared.Types.EmployeeRemoteTypes)
local CandidateGenerator = require(ServerScriptService.Domain.CandidateGenerator)
local EmployeeProgression = require(ServerScriptService.Domain.EmployeeProgression)
local EmployeeSnapshotSerializer = require(ServerScriptService.Domain.EmployeeSnapshotSerializer)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local RequestRateLimiter = require(ServerScriptService.Security.RequestRateLimiter)
local ServerRemoteRegistry = require(ServerScriptService.Infrastructure.ServerRemoteRegistry)
local CandidateService = require(ServerScriptService.Services.CandidateService)
local EmployeeMovementService = require(ServerScriptService.Services.EmployeeMovementService)
local EmployeePayrollService = require(ServerScriptService.Services.EmployeePayrollService)
local EmployeeProductivityService = require(ServerScriptService.Services.EmployeeProductivityService)
local SessionCurrencyService = require(ServerScriptService.Services.SessionCurrencyService)
local WorkstationService = require(ServerScriptService.Services.WorkstationService)

type Candidate = EmployeeTypes.Candidate
type CandidateBoardService = CandidateService.Service
type Clock = () -> number
type CurrencyService = SessionCurrencyService.Service
type DependencyResolver = LifecycleRegistry.DependencyResolver
type Employee = EmployeeTypes.Employee
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type EmployeeMutationResponse = EmployeeRemoteTypes.EmployeeMutationResponse
type EmployeeOverview = EmployeeRemoteTypes.EmployeeOverview
type EmployeeOverviewRequest = EmployeeRemoteTypes.EmployeeOverviewRequest
type EmployeeOverviewResponse = EmployeeRemoteTypes.EmployeeOverviewResponse
type EmployeeSessionSnapshot = EmployeeTypes.EmployeeSessionSnapshot
type Logger = LoggerTypes.Logger
type MovementService = EmployeeMovementService.Service
type RandomSource = CandidateGenerator.RandomSource
type RemoteRegistry = ServerRemoteRegistry.Registry
type Result<T> = AppTypes.Result<T>
type RoleWorkLedger = EmployeeTypes.RoleWorkLedger
type TeamProfile = EmployeeProductivityService.TeamProfile
type Workstations = WorkstationService.Service

type CachedResponse = { signature: string, response: EmployeeMutationResponse }
type Session = {
	userId: number,
	runtimeSessionId: string,
	runtimeGeneration: number,
	employeesById: { [string]: Employee },
	ledger: RoleWorkLedger,
	nextEmployeeSequence: number,
	payrollAt: number,
	payrollCycle: number,
	lastProductivityAt: number,
	lastCandidateStepAt: number,
	teamProfiles: { TeamProfile },
	activeRequestId: string?,
	recentResponses: { [string]: CachedResponse },
	recentOrder: { string },
	dismissedIds: { [string]: boolean },
	dismissedOrder: { string },
	isAcceptingMutations: boolean,
}

type ServiceData = {
	_config: EmployeeConfig,
	_limiter: RequestRateLimiter.Limiter,
	_logger: Logger,
	_clock: Clock,
	_random: RandomSource,
	_currency: CurrencyService?,
	_workstations: Workstations?,
	_movement: MovementService?,
	_remotes: RemoteRegistry?,
	_candidates: CandidateBoardService?,
	_sessions: { [number]: Session },
	_nextRuntimeSessionId: number,
	_unsubscribeWorkstations: (() -> ())?,
	_heartbeat: RBXScriptConnection?,
	_isInitialized: boolean,
	_isStarted: boolean,
	_isDestroyed: boolean,
}

local EmployeeService = {}
EmployeeService.__index = EmployeeService
export type Service = typeof(setmetatable({} :: ServiceData, EmployeeService))

local MAX_RECENT_RESPONSES = 64
local MAX_DISMISSED_IDS = 32

local SAFE_MESSAGES: { [string]: string } = {
	InvalidPayload = "The request was invalid.",
	RateLimited = "Please wait before trying again.",
	RequestIdConflict = "The request identifier was already used.",
	EmployeeMutationInProgress = "Another employee change is still processing.",
	EmployeeSessionNotReady = "Your employee session is not ready yet.",
	CandidateNotFound = "That candidate is no longer available.",
	CandidateExpired = "That candidate has expired.",
	CandidateAlreadyConsumed = "That candidate was already hired.",
	CandidateRefreshCooldown = "Candidate refresh is cooling down.",
	EmployeeCapacityReached = "Your office employee capacity is full.",
	NoCompatibleWorkstation = "Build or upgrade compatible equipment.",
	InsufficientFunds = "You do not have enough Cash.",
	EmployeeNotFound = "That employee was not found.",
	EmployeeDismissed = "That employee was dismissed.",
	WorkstationNotFound = "That workstation was not found.",
	WorkstationOccupied = "That workstation is occupied.",
	WorkstationIncompatible = "That workstation is incompatible.",
	EmployeeAlreadyAssigned = "The employee already has that assignment.",
	ForeignEmployee = "That employee belongs to another player.",
	ForeignWorkstation = "That workstation belongs to another player.",
	TransactionFailed = "The employee transaction could not be completed.",
	InternalError = "The employee request could not be completed.",
}

local function safeError(code: string): EmployeeRemoteTypes.EmployeeRemoteError
	local safeCode = if SAFE_MESSAGES[code] ~= nil then code else "InternalError"
	return {
		code = safeCode :: EmployeeRemoteTypes.EmployeeRemoteErrorCode,
		message = SAFE_MESSAGES[safeCode],
	}
end

local function defaultLedger(config: EmployeeConfig): RoleWorkLedger
	local ledger = {} :: RoleWorkLedger
	for _, role in config.roles do
		ledger[role.id] = 0
	end
	return ledger
end

local function orderedEmployees(session: Session): { Employee }
	local result = {}
	for _, employee in session.employeesById do
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

local function remember(session: Session, requestId: string, signature: string, response: EmployeeMutationResponse)
	if session.recentResponses[requestId] == nil then
		table.insert(session.recentOrder, requestId)
	end
	session.recentResponses[requestId] = { signature = signature, response = response }
	while #session.recentOrder > MAX_RECENT_RESPONSES do
		local id = table.remove(session.recentOrder, 1)
		session.recentResponses[id] = nil
	end
end

local function rememberDismissed(session: Session, employeeId: string)
	if session.dismissedIds[employeeId] then
		return
	end
	session.dismissedIds[employeeId] = true
	table.insert(session.dismissedOrder, employeeId)
	while #session.dismissedOrder > MAX_DISMISSED_IDS do
		local removedId = table.remove(session.dismissedOrder, 1)
		session.dismissedIds[removedId] = nil
	end
end

function EmployeeService.new(
	config: EmployeeConfig,
	limiter: RequestRateLimiter.Limiter,
	logger: Logger,
	clock: Clock,
	randomSource: RandomSource
): Service
	return setmetatable({
		_config = config,
		_limiter = limiter,
		_logger = logger,
		_clock = clock,
		_random = randomSource,
		_currency = nil,
		_workstations = nil,
		_movement = nil,
		_remotes = nil,
		_candidates = nil,
		_sessions = {},
		_nextRuntimeSessionId = 0,
		_unsubscribeWorkstations = nil,
		_heartbeat = nil,
		_isInitialized = false,
		_isStarted = false,
		_isDestroyed = false,
	}, EmployeeService)
end

function EmployeeService.Init(self: Service, dependencies: DependencyResolver)
	self._currency = dependencies:Require("SessionCurrencyService") :: CurrencyService
	self._workstations = dependencies:Require("WorkstationService") :: Workstations
	self._movement = dependencies:Require("EmployeeMovementService") :: MovementService
	self._remotes = dependencies:Require("ServerRemoteRegistry") :: RemoteRegistry
	local generator = CandidateGenerator.new(self._config, self._random, nil)
	self._candidates = CandidateService.new(self._config, generator, self._clock, function(userId: number)
		local tierId = (self._workstations :: Workstations):GetTierId(userId)
		local balance = (self._currency :: CurrencyService):GetBalance(userId, "Cash")
		if tierId == nil or not balance.ok then
			return nil
		end
		return {
			officeTierId = tierId,
			availableRoles = (self._workstations :: Workstations):GetAvailableRoles(userId),
			cash = balance.value,
		}
	end)
	self._isInitialized = true
end

function EmployeeService._findForeignEmployee(self: Service, userId: number, employeeId: string): boolean
	for otherUserId, session in self._sessions do
		if
			otherUserId ~= userId
			and (session.employeesById[employeeId] ~= nil or session.dismissedIds[employeeId] == true)
		then
			return true
		end
	end
	return false
end

function EmployeeService._overview(self: Service, userId: number, rosterPage: number): Result<EmployeeOverview>
	local session = self._sessions[userId]
	if session == nil then
		return AppTypes.failure("EmployeeSessionNotReady", "Employee session is not open", nil)
	end
	local candidatesResult = (self._candidates :: CandidateBoardService):EnsureFresh(userId)
	local balance = (self._currency :: CurrencyService):GetBalance(userId, "Cash")
	if not candidatesResult.ok or not balance.ok then
		return AppTypes.failure("EmployeeSessionNotReady", "Employee overview is unavailable", nil)
	end
	local now = self._clock()
	local candidateViews = {}
	for _, candidate in candidatesResult.value do
		table.insert(candidateViews, {
			candidateId = candidate.candidateId,
			displayName = candidate.displayName,
			roleId = candidate.roleId,
			grade = candidate.grade,
			speed = candidate.speed,
			quality = candidate.quality,
			reliability = candidate.reliability,
			traitId = candidate.traitId,
			hiringCost = candidate.hiringCost,
			salaryPerCycle = candidate.salaryPerCycle,
			expiresInSeconds = math.max(0, candidate.expiresAt - now),
		})
	end
	local employees = orderedEmployees(session)
	local pageSize = self._config.ui.rosterPageSize
	local pageCount = math.ceil(#employees / pageSize)
	local page = math.max(1, math.min(rosterPage, math.max(1, pageCount)))
	local roster = {}
	local first = (page - 1) * pageSize + 1
	for index = first, math.min(#employees, first + pageSize - 1) do
		local employee = employees[index]
		table.insert(roster, {
			employeeId = employee.employeeId,
			displayName = employee.displayName,
			roleId = employee.roleId,
			grade = employee.grade,
			level = employee.level,
			xp = employee.xp,
			requiredXp = EmployeeProgression.RequiredXp(self._config, employee.level),
			speed = employee.speed,
			quality = employee.quality,
			reliability = employee.reliability,
			traitId = employee.traitId,
			salaryPerCycle = employee.salaryPerCycle,
			morale = employee.morale,
			status = employee.status,
			assignedWorkstationId = employee.assignedWorkstationId,
		})
	end
	local tierId = (self._workstations :: Workstations):GetTierId(userId)
	local roleWorkSummary = {}
	for _, role in self._config.roles do
		table.insert(roleWorkSummary, { roleId = role.id, workPoints = session.ledger[role.id] or 0 })
	end
	return AppTypes.success({
		candidates = candidateViews,
		roster = roster,
		rosterPage = page,
		rosterPageCount = pageCount,
		rosterTotal = #employees,
		tierEmployeeCap = if tierId ~= nil then self._config.tierEmployeeCaps[tierId] else 0,
		workstationCapacity = (self._workstations :: Workstations):GetCapacity(userId),
		occupiedWorkstations = (self._workstations :: Workstations):GetOccupiedCount(userId),
		payrollRemainingSeconds = math.max(0, session.payrollAt - now),
		refreshRemainingSeconds = (self._candidates :: CandidateBoardService):GetRefreshRemaining(userId),
		roleWorkSummary = roleWorkSummary,
		cash = balance.value,
	})
end

function EmployeeService.HandleOverview(
	self: Service,
	userId: number,
	request: EmployeeOverviewRequest
): EmployeeOverviewResponse
	local result = self:_overview(userId, request.rosterPage)
	if not result.ok then
		return {
			ok = false,
			candidates = {},
			roster = {},
			rosterPage = request.rosterPage,
			rosterPageCount = 0,
			rosterTotal = 0,
			tierEmployeeCap = 0,
			workstationCapacity = 0,
			occupiedWorkstations = 0,
			payrollRemainingSeconds = 0,
			refreshRemainingSeconds = 0,
			roleWorkSummary = {},
			cash = 0,
			error = safeError(result.error.code),
		}
	end
	local response = result.value :: EmployeeOverviewResponse
	response.ok = true
	return response
end

function EmployeeService._failureResponse(requestId: string, code: string): EmployeeMutationResponse
	return { ok = false, requestId = requestId, error = safeError(code) }
end

function EmployeeService._beginMutation(
	self: Service,
	userId: number,
	requestId: string,
	signature: string
): (Session?, EmployeeMutationResponse?)
	local session = self._sessions[userId]
	if session == nil or not session.isAcceptingMutations then
		return nil, self._failureResponse(requestId, "EmployeeSessionNotReady")
	end
	local cached = session.recentResponses[requestId]
	if cached ~= nil then
		if cached.signature ~= signature then
			return nil, self._failureResponse(requestId, "RequestIdConflict")
		end
		return nil, cached.response
	end
	if not self._limiter:Allow(userId, "employeeMutation", 8, 3) then
		return nil, self._failureResponse(requestId, "RateLimited")
	end
	if session.activeRequestId ~= nil then
		return nil, self._failureResponse(requestId, "EmployeeMutationInProgress")
	end
	session.activeRequestId = requestId
	return session, nil
end

function EmployeeService._finishMutation(
	_self: Service,
	session: Session,
	requestId: string,
	signature: string,
	response: EmployeeMutationResponse
): EmployeeMutationResponse
	session.activeRequestId = nil
	remember(session, requestId, signature, response)
	return response
end

function EmployeeService._successMutation(self: Service, session: Session, requestId: string): EmployeeMutationResponse
	local overview = self:_overview(session.userId, 1)
	if not overview.ok then
		return self._failureResponse(requestId, "InternalError")
	end
	return { ok = true, requestId = requestId, overview = overview.value }
end

function EmployeeService.Hire(
	self: Service,
	userId: number,
	request: EmployeeRemoteTypes.EmployeeHireRequest
): EmployeeMutationResponse
	local signature = `Hire:{request.candidateId}`
	local session, early = self:_beginMutation(userId, request.requestId, signature)
	if early ~= nil then
		return early
	end
	local runtime = session :: Session
	local currency = self._currency :: CurrencyService
	local workstations = self._workstations :: Workstations
	local movement = self._movement :: MovementService
	local candidates = self._candidates :: CandidateBoardService
	local candidateResult = candidates:Find(userId, request.candidateId)
	if not candidateResult.ok then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, candidateResult.error.code)
		)
	end
	local candidate = candidateResult.value
	local tierId = workstations:GetTierId(userId)
	local capacity =
		math.min(if tierId ~= nil then self._config.tierEmployeeCaps[tierId] else 0, workstations:GetCapacity(userId))
	if #orderedEmployees(runtime) >= capacity then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, "EmployeeCapacityReached")
		)
	end
	local workstation = workstations:FindFirstFree(userId, candidate.roleId)
	if workstation == nil then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, "NoCompatibleWorkstation")
		)
	end
	local transactionId = `employee-hire:{userId}:{runtime.runtimeSessionId}:{request.requestId}`
	local reserve = currency:ReserveDebit(
		userId,
		"Cash",
		candidate.hiringCost,
		`EmployeeHire:{candidate.candidateId}`,
		transactionId
	)
	if not reserve.ok then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, reserve.error.code)
		)
	end
	local previousSequence = runtime.nextEmployeeSequence
	runtime.nextEmployeeSequence += 1
	local employeeId = `employee-{userId}-{runtime.nextEmployeeSequence}`
	local employee: Employee = {
		employeeId = employeeId,
		ownerUserId = userId,
		displayName = candidate.displayName,
		roleId = candidate.roleId,
		grade = candidate.grade,
		level = 1,
		xp = 0,
		speed = candidate.speed,
		quality = candidate.quality,
		reliability = candidate.reliability,
		traitId = candidate.traitId,
		hiringCost = candidate.hiringCost,
		salaryPerCycle = candidate.salaryPerCycle,
		morale = self._config.morale.initial,
		status = "Active",
		missedPayrollCount = 0,
		assignedWorkstationId = workstation.workstationId,
		runtimeGeneration = workstation.runtimeGeneration,
		createdSequence = runtime.nextEmployeeSequence,
	}
	runtime.employeesById[employeeId] = employee
	local assign = workstations:Assign(userId, employeeId, employee.roleId, workstation.workstationId)
	if not assign.ok then
		runtime.employeesById[employeeId] = nil
		runtime.nextEmployeeSequence = previousSequence
		currency:ReleaseDebit(reserve.value.reservationId)
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, assign.error.code)
		)
	end
	local visual = movement:Spawn(employee, assign.value)
	if not visual.ok then
		self._logger:Warn(
			"employee_npc_spawn_failed",
			{ userId = userId, employeeId = employeeId, code = visual.error.code }
		)
	end
	local commit = currency:CommitDebit(reserve.value.reservationId)
	if not commit.ok then
		movement:Remove(userId, employeeId)
		workstations:ReleaseEmployee(userId, employeeId)
		runtime.employeesById[employeeId] = nil
		runtime.nextEmployeeSequence = previousSequence
		currency:ReleaseDebit(reserve.value.reservationId)
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, "TransactionFailed")
		)
	end
	local consume = candidates:Consume(userId, request.candidateId)
	if not consume.ok then
		currency:RollbackCommittedDebit(reserve.value.reservationId)
		movement:Remove(userId, employeeId)
		workstations:ReleaseEmployee(userId, employeeId)
		runtime.employeesById[employeeId] = nil
		runtime.nextEmployeeSequence = previousSequence
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, "TransactionFailed")
		)
	end
	return self:_finishMutation(
		runtime,
		request.requestId,
		signature,
		self:_successMutation(runtime, request.requestId)
	)
end

function EmployeeService.Assign(
	self: Service,
	userId: number,
	request: EmployeeRemoteTypes.EmployeeAssignmentRequest
): EmployeeMutationResponse
	local signature = `Assign:{request.employeeId}:{request.workstationId}`
	local session, early = self:_beginMutation(userId, request.requestId, signature)
	if early ~= nil then
		return early
	end
	local runtime = session :: Session
	local employee = runtime.employeesById[request.employeeId]
	if employee == nil then
		local code = if runtime.dismissedIds[request.employeeId]
			then "EmployeeDismissed"
			elseif self:_findForeignEmployee(userId, request.employeeId) then "ForeignEmployee"
			else "EmployeeNotFound"
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, code)
		)
	end
	if employee.status == "Dismissed" then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, "EmployeeDismissed")
		)
	end
	if employee.assignedWorkstationId == request.workstationId then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, "EmployeeAlreadyAssigned")
		)
	end
	local workstation = (self._workstations :: Workstations):GetSlot(userId, request.workstationId)
	if workstation == nil then
		local owner = (self._workstations :: Workstations):FindOwner(request.workstationId)
		local code = if owner ~= nil and owner ~= userId then "ForeignWorkstation" else "WorkstationNotFound"
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, code)
		)
	end
	local assign = (self._workstations :: Workstations):Assign(
		userId,
		employee.employeeId,
		employee.roleId,
		request.workstationId
	)
	if not assign.ok then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, assign.error.code)
		)
	end
	employee.assignedWorkstationId = request.workstationId
	employee.runtimeGeneration = assign.value.runtimeGeneration
	local movementService = self._movement :: MovementService
	local movementResult = movementService:MoveToWorkstation(userId, employee.employeeId, assign.value)
	if not movementResult.ok and movementResult.error.code == "EmployeeNpcNotFound" then
		movementResult = movementService:Spawn(employee, assign.value)
	end
	if not movementResult.ok then
		self._logger:Warn(
			"employee_npc_reassign_failed",
			{ userId = userId, employeeId = employee.employeeId, code = movementResult.error.code }
		)
	end
	return self:_finishMutation(
		runtime,
		request.requestId,
		signature,
		self:_successMutation(runtime, request.requestId)
	)
end

function EmployeeService.Dismiss(
	self: Service,
	userId: number,
	request: EmployeeRemoteTypes.EmployeeDismissRequest
): EmployeeMutationResponse
	local signature = `Dismiss:{request.employeeId}`
	local session, early = self:_beginMutation(userId, request.requestId, signature)
	if early ~= nil then
		return early
	end
	local runtime = session :: Session
	local employee = runtime.employeesById[request.employeeId]
	if employee == nil then
		local code = if runtime.dismissedIds[request.employeeId]
			then "EmployeeDismissed"
			elseif self:_findForeignEmployee(userId, request.employeeId) then "ForeignEmployee"
			else "EmployeeNotFound"
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, code)
		)
	end
	if employee.status == "Dismissed" then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, "EmployeeDismissed")
		)
	end
	local workstations = self._workstations :: Workstations
	local movement = self._movement :: MovementService
	workstations:ReleaseEmployee(userId, employee.employeeId)
	movement:Remove(userId, employee.employeeId)
	runtime.employeesById[employee.employeeId] = nil
	rememberDismissed(runtime, employee.employeeId)
	return self:_finishMutation(
		runtime,
		request.requestId,
		signature,
		self:_successMutation(runtime, request.requestId)
	)
end

function EmployeeService.RefreshCandidates(
	self: Service,
	userId: number,
	request: EmployeeRemoteTypes.CandidateRefreshRequest
): EmployeeMutationResponse
	local signature = "RefreshCandidates"
	local session, early = self:_beginMutation(userId, request.requestId, signature)
	if early ~= nil then
		return early
	end
	local runtime = session :: Session
	local result = (self._candidates :: CandidateBoardService):Refresh(userId)
	if not result.ok then
		return self:_finishMutation(
			runtime,
			request.requestId,
			signature,
			self._failureResponse(request.requestId, result.error.code)
		)
	end
	return self:_finishMutation(
		runtime,
		request.requestId,
		signature,
		self:_successMutation(runtime, request.requestId)
	)
end

function EmployeeService._step(self: Service)
	local now = self._clock()
	for userId, session in self._sessions do
		if session.isAcceptingMutations then
			local delta = now - session.lastProductivityAt
			if delta >= self._config.scheduler.productivitySeconds then
				session.lastProductivityAt = now
				session.teamProfiles = EmployeeProductivityService.Step(
					self._config,
					self._workstations :: Workstations,
					userId,
					session.employeesById,
					session.ledger,
					delta
				)
			end
			if now - session.lastCandidateStepAt >= self._config.scheduler.candidateSeconds then
				session.lastCandidateStepAt = now
				local candidates = self._candidates :: CandidateBoardService
				candidates:EnsureFresh(userId)
			end
			if now >= session.payrollAt and session.activeRequestId == nil then
				session.payrollCycle += 1
				local payroll = EmployeePayrollService.RunCycle(
					self._config,
					self._currency :: CurrencyService,
					userId,
					session.runtimeSessionId,
					session.payrollCycle,
					session.employeesById
				)
				if not payroll.ok then
					self._logger:Error("employee_payroll_failed", { userId = userId, code = payroll.error.code })
				end
				session.payrollAt = now + self._config.payroll.intervalSeconds
			end
		end
	end
end

function EmployeeService.Start(self: Service)
	if not self._isInitialized or self._isStarted or self._isDestroyed then
		error("EmployeeService.Start requires one successful Init", 2)
	end
	local remotes = self._remotes :: RemoteRegistry
	local bindings = {
		{
			"RequestEmployeeOverview",
			function(userId: number, payload: unknown): unknown
				return self:HandleOverview(userId, payload :: EmployeeOverviewRequest)
			end,
		},
		{
			"RequestEmployeeHire",
			function(userId: number, payload: unknown): unknown
				return self:Hire(userId, payload :: EmployeeRemoteTypes.EmployeeHireRequest)
			end,
		},
		{
			"RequestEmployeeAssignment",
			function(userId: number, payload: unknown): unknown
				return self:Assign(userId, payload :: EmployeeRemoteTypes.EmployeeAssignmentRequest)
			end,
		},
		{
			"RequestEmployeeDismiss",
			function(userId: number, payload: unknown): unknown
				return self:Dismiss(userId, payload :: EmployeeRemoteTypes.EmployeeDismissRequest)
			end,
		},
		{
			"RequestCandidateRefresh",
			function(userId: number, payload: unknown): unknown
				return self:RefreshCandidates(userId, payload :: EmployeeRemoteTypes.CandidateRefreshRequest)
			end,
		},
	}
	for _, definition in bindings do
		local name = definition[1] :: string
		local handler = definition[2] :: (number, unknown) -> unknown
		local result = remotes:BindFunction(name, function(player: Player, payload: unknown): unknown
			return handler(player.UserId, payload)
		end)
		if not result.ok then
			error(`Could not bind {name}: {result.error.code}`, 2)
		end
	end
	local workstations = self._workstations :: Workstations
	local movement = self._movement :: MovementService
	self._unsubscribeWorkstations = workstations:SubscribeChanged(function(context)
		local session = self._sessions[context.userId]
		if session == nil then
			return
		end
		for _, employeeId in context.releasedEmployeeIds do
			local employee = session.employeesById[employeeId]
			if employee ~= nil then
				employee.assignedWorkstationId = nil
				movement:Remove(context.userId, employeeId)
			end
		end
		for _, employee in session.employeesById do
			if employee.assignedWorkstationId ~= nil then
				local slot = workstations:GetSlot(context.userId, employee.assignedWorkstationId)
				if slot ~= nil then
					employee.runtimeGeneration = context.runtimeGeneration
					movement:MoveToWorkstation(context.userId, employee.employeeId, slot)
				end
			end
		end
	end)
	self._heartbeat = RunService.Heartbeat:Connect(function()
		self:_step()
	end)
	self._isStarted = true
end

function EmployeeService.PrepareSession(
	self: Service,
	userId: number,
	restoredSnapshot: EmployeeSessionSnapshot?
): Result<true>
	if self._sessions[userId] ~= nil then
		return AppTypes.failure("EmployeeSessionAlreadyOpen", "Employee session is already open", nil)
	end
	self._nextRuntimeSessionId += 1
	local now = self._clock()
	local session: Session = {
		userId = userId,
		runtimeSessionId = tostring(self._nextRuntimeSessionId),
		runtimeGeneration = 1,
		employeesById = {},
		ledger = defaultLedger(self._config),
		nextEmployeeSequence = 0,
		payrollAt = now + self._config.payroll.intervalSeconds,
		payrollCycle = 0,
		lastProductivityAt = now,
		lastCandidateStepAt = now,
		teamProfiles = {},
		activeRequestId = nil,
		recentResponses = {},
		recentOrder = {},
		dismissedIds = {},
		dismissedOrder = {},
		isAcceptingMutations = true,
	}
	local snapshot: EmployeeSessionSnapshot? = nil
	if restoredSnapshot ~= nil then
		local validation = EmployeeSnapshotSerializer.Validate(self._config, restoredSnapshot)
		if validation.ok then
			local ownerValid = true
			for _, employee in validation.value.employees do
				if employee.ownerUserId ~= userId then
					ownerValid = false
					break
				end
			end
			for _, entry in validation.value.candidates do
				if entry.candidate.ownerUserId ~= userId then
					ownerValid = false
					break
				end
			end
			if ownerValid then
				snapshot = validation.value
			else
				self._logger:Warn("employee_snapshot_rejected", { userId = userId, code = "SnapshotOwnerMismatch" })
			end
		else
			self._logger:Warn("employee_snapshot_rejected", { userId = userId, code = validation.error.code })
		end
	end
	if snapshot ~= nil then
		session.ledger = table.clone(snapshot.roleWorkLedger)
		session.nextEmployeeSequence = snapshot.nextEmployeeSequence
		session.payrollAt = now + math.min(snapshot.payrollRemainingSeconds, self._config.payroll.intervalSeconds)
		for _, source in snapshot.employees do
			if source.ownerUserId == userId then
				local employee = table.clone(source)
				employee.assignedWorkstationId = nil
				session.employeesById[employee.employeeId] = employee
			end
		end
	end
	self._sessions[userId] = session
	local movement = (self._movement :: MovementService):PrepareSession(userId)
	if not movement.ok then
		self._sessions[userId] = nil
		return movement
	end
	local candidates = (self._candidates :: CandidateBoardService):PrepareSession(
		userId,
		if snapshot ~= nil then snapshot.candidates else nil,
		if snapshot ~= nil then snapshot.refreshRemainingSeconds else nil
	)
	if not candidates.ok then
		(self._movement :: MovementService):AbortSession(userId)
		self._sessions[userId] = nil
		return candidates
	end
	if snapshot ~= nil then
		(self._workstations :: Workstations):RestoreAssignments(userId, session.employeesById, snapshot.assignments)
	end
	for _, employee in orderedEmployees(session) do
		local slot = if employee.assignedWorkstationId ~= nil
			then (self._workstations :: Workstations):GetSlot(userId, employee.assignedWorkstationId)
			else nil
		local visual = (self._movement :: MovementService):Spawn(employee, slot)
		if not visual.ok then
			self._logger:Warn(
				"employee_npc_restore_failed",
				{ userId = userId, employeeId = employee.employeeId, code = visual.error.code }
			)
		end
	end
	return AppTypes.success(true)
end

function EmployeeService.StopMutations(self: Service, userId: number): Result<true>
	local session = self._sessions[userId]
	if session == nil or session.activeRequestId ~= nil then
		return AppTypes.failure("EmployeeSessionNotReady", "Employee session cannot stop during a mutation", nil)
	end
	session.isAcceptingMutations = false
	return AppTypes.success(true)
end

function EmployeeService.ExportSession(self: Service, userId: number): Result<EmployeeSessionSnapshot>
	local session = self._sessions[userId]
	if session == nil or session.activeRequestId ~= nil then
		return AppTypes.failure("EmployeeSessionNotReady", "Employee session cannot be exported", nil)
	end
	local candidates, refreshRemaining = (self._candidates :: CandidateBoardService):Export(userId)
	local snapshot: EmployeeSessionSnapshot = {
		schemaVersion = self._config.schemaVersion,
		employees = {},
		assignments = (self._workstations :: Workstations):ExportAssignments(userId),
		roleWorkLedger = table.clone(session.ledger),
		candidates = candidates,
		refreshRemainingSeconds = refreshRemaining,
		payrollRemainingSeconds = math.max(0, session.payrollAt - self._clock()),
		nextEmployeeSequence = session.nextEmployeeSequence,
	}
	for _, employee in orderedEmployees(session) do
		table.insert(snapshot.employees, table.clone(employee))
	end
	return EmployeeSnapshotSerializer.Validate(self._config, snapshot)
end

function EmployeeService.GetRoleWorkLedger(self: Service, userId: number): RoleWorkLedger?
	local session = self._sessions[userId]
	return if session ~= nil then table.clone(session.ledger) else nil
end

function EmployeeService.GetTeamProductivityProfile(self: Service, userId: number): { TeamProfile }?
	local session = self._sessions[userId]
	if session == nil then
		return nil
	end
	local result = {}
	for _, profile in session.teamProfiles do
		table.insert(result, table.clone(profile))
	end
	return result
end

function EmployeeService.CloseSession(self: Service, userId: number): Result<boolean>
	local session = self._sessions[userId]
	if session == nil then
		return AppTypes.success(false)
	end
	session.isAcceptingMutations = false
	self._sessions[userId] = nil
	local candidates = self._candidates :: CandidateBoardService
	local movement = self._movement :: MovementService
	candidates:CloseSession(userId)
	movement:CloseSession(userId)
	self._limiter:ClearPlayer(userId)
	return AppTypes.success(true)
end

function EmployeeService.AbortSession(self: Service, userId: number): Result<boolean>
	return self:CloseSession(userId)
end

function EmployeeService.Destroy(self: Service)
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true
	if self._heartbeat ~= nil then
		self._heartbeat:Disconnect()
	end
	self._heartbeat = nil
	if self._unsubscribeWorkstations ~= nil then
		self._unsubscribeWorkstations()
	end
	self._unsubscribeWorkstations = nil
	local userIds = {}
	for userId in self._sessions do
		table.insert(userIds, userId)
	end
	for _, userId in userIds do
		self:CloseSession(userId)
	end
	if self._candidates ~= nil then
		self._candidates:Destroy()
	end
	self._limiter:Destroy()
	self._currency = nil
	self._workstations = nil
	self._movement = nil
	self._remotes = nil
	self._candidates = nil
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(EmployeeService)
