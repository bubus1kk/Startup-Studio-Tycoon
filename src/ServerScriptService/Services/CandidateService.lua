--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local CandidateGenerator = require(ServerScriptService.Domain.CandidateGenerator)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)

type Candidate = EmployeeTypes.Candidate
type CandidateSnapshot = EmployeeTypes.CandidateSnapshot
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type EmployeeRoleId = EmployeeTypes.EmployeeRoleId
type Generator = CandidateGenerator.Generator
type Result<T> = AppTypes.Result<T>

export type Clock = () -> number
export type GenerationContext = {
	officeTierId: string,
	availableRoles: { EmployeeRoleId },
	cash: number,
}
export type ContextProvider = (userId: number) -> GenerationContext?

type Board = {
	userId: number,
	generation: number,
	candidates: { Candidate },
	nextRefreshAt: number,
	consumedIds: { [string]: boolean },
	consumedOrder: { string },
	expiredIds: { [string]: boolean },
	expiredOrder: { string },
}

type ServiceData = {
	_config: EmployeeConfig,
	_generator: Generator,
	_clock: Clock,
	_contextProvider: ContextProvider,
	_boards: { [number]: Board },
}

local CandidateService = {}
CandidateService.__index = CandidateService
export type Service = typeof(setmetatable({} :: ServiceData, CandidateService))

local HISTORY_LIMIT = 32

local function remember(ids: { [string]: boolean }, order: { string }, candidateId: string)
	if ids[candidateId] then
		return
	end
	ids[candidateId] = true
	table.insert(order, candidateId)
	if #order > HISTORY_LIMIT then
		local removedId = table.remove(order, 1)
		if removedId ~= nil then
			ids[removedId] = nil
		end
	end
end

function CandidateService.new(
	config: EmployeeConfig,
	generator: Generator,
	clock: Clock,
	contextProvider: ContextProvider
): Service
	return setmetatable({
		_config = config,
		_generator = generator,
		_clock = clock,
		_contextProvider = contextProvider,
		_boards = {},
	}, CandidateService)
end

function CandidateService._generateSlot(self: Service, board: Board, slotIndex: number, guaranteed: boolean): Candidate
	local context = assert(self._contextProvider(board.userId), "Candidate context unavailable")
	local roles = context.availableRoles
	if #roles == 0 then
		roles = {}
		for _, role in self._config.roles do
			table.insert(roles, role.id)
		end
	end
	board.generation += 1
	return self._generator:Generate({
		ownerUserId = board.userId,
		slotIndex = slotIndex,
		generation = board.generation,
		officeTierId = context.officeTierId,
		availableRoles = roles,
		now = self._clock(),
		forcedRoleId = if guaranteed and context.availableRoles[1] ~= nil then context.availableRoles[1] else nil,
		forcedGrade = if guaranteed then "Trainee" else nil,
		forcedMinimumStats = guaranteed,
		forcedTraitId = if guaranteed then "Efficient" else nil,
	})
end

function CandidateService._replaceAll(self: Service, board: Board)
	table.clear(board.candidates)
	local context = assert(self._contextProvider(board.userId), "Candidate context unavailable")
	local guarantee = #context.availableRoles > 0 and context.cash >= self._config.grades[1].baseHiringCost
	for slotIndex = 1, self._config.candidate.poolSize do
		local candidate = self:_generateSlot(board, slotIndex, guarantee and slotIndex == 1)
		table.insert(board.candidates, candidate)
	end
end

function CandidateService._ensureHireable(self: Service, board: Board)
	local context = self._contextProvider(board.userId)
	if context == nil or #context.availableRoles == 0 or context.cash < self._config.grades[1].baseHiringCost then
		return
	end
	local available = {} :: { [EmployeeRoleId]: boolean }
	for _, roleId in context.availableRoles do
		available[roleId] = true
	end
	for _, candidate in board.candidates do
		if
			available[candidate.roleId]
			and candidate.hiringCost <= context.cash
			and candidate.expiresAt > self._clock()
		then
			return
		end
	end
	board.candidates[1] = self:_generateSlot(board, 1, true)
end

function CandidateService.PrepareSession(
	self: Service,
	userId: number,
	restoredCandidates: { CandidateSnapshot }?,
	refreshRemainingSeconds: number?
): Result<true>
	if self._boards[userId] ~= nil then
		return AppTypes.failure("CandidateSessionAlreadyOpen", "Candidate board is already open", nil)
	end
	if self._contextProvider(userId) == nil then
		return AppTypes.failure("CandidateContextUnavailable", "Candidate context is unavailable", nil)
	end
	local now = self._clock()
	local board: Board = {
		userId = userId,
		generation = 0,
		candidates = {},
		nextRefreshAt = now + math.max(0, refreshRemainingSeconds or 0),
		consumedIds = {},
		consumedOrder = {},
		expiredIds = {},
		expiredOrder = {},
	}
	self._boards[userId] = board
	if restoredCandidates ~= nil and #restoredCandidates == self._config.candidate.poolSize then
		local valid = true
		for slotIndex, entry in restoredCandidates do
			local candidate = table.clone(entry.candidate)
			if candidate.ownerUserId ~= userId or candidate.slotIndex ~= slotIndex or entry.remainingTtl <= 0 then
				valid = false
				break
			end
			candidate.createdAt = now
			candidate.expiresAt = now + math.min(entry.remainingTtl, self._config.candidate.ttlSeconds)
			board.generation = math.max(board.generation, candidate.generation)
			table.insert(board.candidates, candidate)
		end
		if not valid then
			table.clear(board.candidates)
		end
	end
	if #board.candidates ~= self._config.candidate.poolSize then
		self:_replaceAll(board)
	end
	self:_ensureHireable(board)
	return AppTypes.success(true)
end

function CandidateService.EnsureFresh(self: Service, userId: number): Result<{ Candidate }>
	local board = self._boards[userId]
	if board == nil then
		return AppTypes.failure("EmployeeSessionNotReady", "Candidate board is not open", nil)
	end
	local now = self._clock()
	for slotIndex, candidate in board.candidates do
		if candidate.expiresAt <= now then
			remember(board.expiredIds, board.expiredOrder, candidate.candidateId)
			board.candidates[slotIndex] = self:_generateSlot(board, slotIndex, false)
		end
	end
	self:_ensureHireable(board)
	local copy = {}
	for _, candidate in board.candidates do
		table.insert(copy, table.clone(candidate))
	end
	return AppTypes.success(copy)
end

function CandidateService.Find(self: Service, userId: number, candidateId: string): Result<Candidate>
	local board = self._boards[userId]
	if board == nil then
		return AppTypes.failure("EmployeeSessionNotReady", "Candidate board is not open", nil)
	end
	for slotIndex, candidate in board.candidates do
		if candidate.candidateId == candidateId then
			if candidate.ownerUserId ~= userId then
				return AppTypes.failure("ForeignEmployee", "Candidate belongs to another player", nil)
			end
			if candidate.expiresAt <= self._clock() then
				remember(board.expiredIds, board.expiredOrder, candidate.candidateId)
				board.candidates[slotIndex] = self:_generateSlot(board, slotIndex, false)
				self:_ensureHireable(board)
				return AppTypes.failure("CandidateExpired", "Candidate has expired", nil)
			end
			return AppTypes.success(table.clone(candidate))
		end
	end
	if board.consumedIds[candidateId] then
		return AppTypes.failure("CandidateAlreadyConsumed", "Candidate is no longer available", nil)
	end
	if board.expiredIds[candidateId] then
		return AppTypes.failure("CandidateExpired", "Candidate has expired", nil)
	end
	return AppTypes.failure("CandidateNotFound", "Candidate does not exist", nil)
end

function CandidateService.Consume(self: Service, userId: number, candidateId: string): Result<Candidate>
	local board = self._boards[userId]
	if board == nil then
		return AppTypes.failure("EmployeeSessionNotReady", "Candidate board is not open", nil)
	end
	for slotIndex, candidate in board.candidates do
		if candidate.candidateId == candidateId then
			if candidate.expiresAt <= self._clock() then
				remember(board.expiredIds, board.expiredOrder, candidate.candidateId)
				board.candidates[slotIndex] = self:_generateSlot(board, slotIndex, false)
				self:_ensureHireable(board)
				return AppTypes.failure("CandidateExpired", "Candidate has expired", nil)
			end
			remember(board.consumedIds, board.consumedOrder, candidate.candidateId)
			board.candidates[slotIndex] = self:_generateSlot(board, slotIndex, false)
			self:_ensureHireable(board)
			return AppTypes.success(table.clone(candidate))
		end
	end
	if board.expiredIds[candidateId] then
		return AppTypes.failure("CandidateExpired", "Candidate has expired", nil)
	end
	return AppTypes.failure("CandidateAlreadyConsumed", "Candidate is no longer available", nil)
end

function CandidateService.Refresh(self: Service, userId: number): Result<true>
	local board = self._boards[userId]
	if board == nil then
		return AppTypes.failure("EmployeeSessionNotReady", "Candidate board is not open", nil)
	end
	local now = self._clock()
	if now < board.nextRefreshAt then
		return AppTypes.failure("CandidateRefreshCooldown", "Candidate refresh is cooling down", nil)
	end
	self:_replaceAll(board)
	self:_ensureHireable(board)
	board.nextRefreshAt = now + self._config.candidate.refreshCooldownSeconds
	return AppTypes.success(true)
end

function CandidateService.GetRefreshRemaining(self: Service, userId: number): number
	local board = self._boards[userId]
	return if board ~= nil then math.max(0, board.nextRefreshAt - self._clock()) else 0
end

function CandidateService.Export(self: Service, userId: number): ({ CandidateSnapshot }, number)
	local board = self._boards[userId]
	if board == nil then
		return {}, 0
	end
	self:EnsureFresh(userId)
	local now = self._clock()
	local result = {}
	for _, candidate in board.candidates do
		table.insert(result, {
			candidate = table.clone(candidate),
			remainingTtl = math.max(0, candidate.expiresAt - now),
		})
	end
	return result, math.max(0, board.nextRefreshAt - now)
end

function CandidateService.CloseSession(self: Service, userId: number)
	self._boards[userId] = nil
end

function CandidateService.Destroy(self: Service)
	table.clear(self._boards)
end

return table.freeze(CandidateService)
