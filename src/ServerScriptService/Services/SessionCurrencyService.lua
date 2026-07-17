--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type Result<T> = AppTypes.Result<T>

export type CurrencySnapshot = {
	balances: { Cash: number },
}

export type DebitReservation = {
	reservationId: string,
	transactionId: string,
	userId: number,
	currency: "Cash",
	amount: number,
	reason: string,
	state: "Reserved" | "Committed" | "Released" | "RolledBack",
}

type CurrencySession = {
	balances: { Cash: number },
	reservationsById: { [string]: DebitReservation },
	reservationIdByTransaction: { [string]: string },
}

type ServiceData = {
	_initialCash: number,
	_sessions: { [number]: CurrencySession },
	_nextReservationId: number,
	_isInitialized: boolean,
	_isStarted: boolean,
	_isDestroyed: boolean,
}

local SessionCurrencyService = {}
SessionCurrencyService.__index = SessionCurrencyService
export type Service = typeof(setmetatable({} :: ServiceData, SessionCurrencyService))

function SessionCurrencyService.new(initialCash: number): Service
	assert(initialCash >= 0 and initialCash % 1 == 0, "initialCash must be a non-negative integer")
	return setmetatable({
		_initialCash = initialCash,
		_sessions = {},
		_nextReservationId = 0,
		_isInitialized = false,
		_isStarted = false,
		_isDestroyed = false,
	}, SessionCurrencyService)
end

function SessionCurrencyService.Init(self: Service, _dependencies: DependencyResolver)
	if self._isInitialized or self._isDestroyed then
		error("SessionCurrencyService.Init can only run once", 2)
	end
	self._isInitialized = true
end

function SessionCurrencyService.Start(self: Service)
	if not self._isInitialized or self._isStarted or self._isDestroyed then
		error("SessionCurrencyService.Start requires one successful Init", 2)
	end
	self._isStarted = true
end

function SessionCurrencyService.OpenSession(self: Service, userId: number): Result<CurrencySnapshot>
	if self._sessions[userId] ~= nil then
		return AppTypes.failure("CurrencySessionAlreadyOpen", "Currency session is already open", nil)
	end
	local session: CurrencySession = {
		balances = { Cash = self._initialCash },
		reservationsById = {},
		reservationIdByTransaction = {},
	}
	self._sessions[userId] = session
	return AppTypes.success({ balances = { Cash = session.balances.Cash } })
end

function SessionCurrencyService.RestoreSession(
	self: Service,
	userId: number,
	snapshot: CurrencySnapshot
): Result<CurrencySnapshot>
	if self._sessions[userId] ~= nil then
		return AppTypes.failure("CurrencySessionAlreadyOpen", "Currency session is already open", nil)
	end
	local cash = snapshot.balances.Cash
	if typeof(cash) ~= "number" or cash < 0 or cash % 1 ~= 0 then
		return AppTypes.failure("SnapshotInvalid", "Currency snapshot balance is invalid", nil)
	end
	self._sessions[userId] = {
		balances = { Cash = cash },
		reservationsById = {},
		reservationIdByTransaction = {},
	}
	return AppTypes.success({ balances = { Cash = cash } })
end

function SessionCurrencyService.GetBalance(self: Service, userId: number, currency: "Cash"): Result<number>
	local session = self._sessions[userId]
	if session == nil then
		return AppTypes.failure("CurrencySessionNotOpen", "Currency session is not open", nil)
	end
	return AppTypes.success(session.balances[currency])
end

function SessionCurrencyService.ReserveDebit(
	self: Service,
	userId: number,
	currency: "Cash",
	amount: number,
	reason: string,
	transactionId: string
): Result<DebitReservation>
	local session = self._sessions[userId]
	if session == nil then
		return AppTypes.failure("CurrencySessionNotOpen", "Currency session is not open", nil)
	end
	if amount <= 0 or amount % 1 ~= 0 then
		return AppTypes.failure("InvalidDebitAmount", "Debit amount must be a positive integer", nil)
	end
	local existingId = session.reservationIdByTransaction[transactionId]
	if existingId ~= nil then
		local existing = session.reservationsById[existingId]
		if
			existing.userId == userId
			and existing.currency == currency
			and existing.amount == amount
			and existing.reason == reason
		then
			return AppTypes.success(existing)
		end
		return AppTypes.failure("TransactionIdConflict", "Transaction ID was reused with different parameters", nil)
	end
	if session.balances[currency] < amount then
		return AppTypes.failure("InsufficientFunds", "Available Cash is insufficient", nil)
	end
	self._nextReservationId += 1
	local reservationId = `currency-reservation-{self._nextReservationId}`
	local reservation: DebitReservation = {
		reservationId = reservationId,
		transactionId = transactionId,
		userId = userId,
		currency = currency,
		amount = amount,
		reason = reason,
		state = "Reserved",
	}
	session.balances[currency] -= amount
	session.reservationsById[reservationId] = reservation
	session.reservationIdByTransaction[transactionId] = reservationId
	return AppTypes.success(reservation)
end

function SessionCurrencyService.CommitDebit(self: Service, reservationId: string): Result<CurrencySnapshot>
	for _, session in self._sessions do
		local reservation = session.reservationsById[reservationId]
		if reservation ~= nil then
			if reservation.state == "Released" or reservation.state == "RolledBack" then
				return AppTypes.failure("TransactionAlreadyReleased", "Released reservation cannot be committed", nil)
			end
			reservation.state = "Committed"
			return AppTypes.success({ balances = { Cash = session.balances.Cash } })
		end
	end
	return AppTypes.failure("UnknownReservation", "Debit reservation does not exist", nil)
end

function SessionCurrencyService.RollbackCommittedDebit(self: Service, reservationId: string): Result<CurrencySnapshot>
	for _, session in self._sessions do
		local reservation = session.reservationsById[reservationId]
		if reservation ~= nil then
			if reservation.state == "Reserved" then
				return AppTypes.failure("TransactionNotCommitted", "Reserved debit must be released instead", nil)
			end
			if reservation.state == "Committed" then
				session.balances[reservation.currency] += reservation.amount
				reservation.state = "RolledBack"
			end
			return AppTypes.success({ balances = { Cash = session.balances.Cash } })
		end
	end
	return AppTypes.failure("UnknownReservation", "Debit reservation does not exist", nil)
end

function SessionCurrencyService.ReleaseDebit(self: Service, reservationId: string): Result<CurrencySnapshot>
	for _, session in self._sessions do
		local reservation = session.reservationsById[reservationId]
		if reservation ~= nil then
			if reservation.state == "Committed" then
				return AppTypes.failure("TransactionAlreadyCommitted", "Committed reservation cannot be released", nil)
			end
			if reservation.state == "Reserved" then
				session.balances[reservation.currency] += reservation.amount
				reservation.state = "Released"
			end
			return AppTypes.success({ balances = { Cash = session.balances.Cash } })
		end
	end
	return AppTypes.failure("UnknownReservation", "Debit reservation does not exist", nil)
end

function SessionCurrencyService.ExportSession(self: Service, userId: number): Result<CurrencySnapshot>
	local session = self._sessions[userId]
	if session == nil then
		return AppTypes.failure("CurrencySessionNotOpen", "Currency session is not open", nil)
	end
	for _, reservation in session.reservationsById do
		if reservation.state == "Reserved" then
			return AppTypes.failure("CurrencyReservationActive", "Currency session has an active reservation", nil)
		end
	end
	return AppTypes.success({ balances = { Cash = session.balances.Cash } })
end

function SessionCurrencyService.CloseSession(self: Service, userId: number): Result<boolean>
	local session = self._sessions[userId]
	if session == nil then
		return AppTypes.success(false)
	end
	for _, reservation in session.reservationsById do
		if reservation.state == "Reserved" then
			session.balances[reservation.currency] += reservation.amount
			reservation.state = "Released"
		end
	end
	self._sessions[userId] = nil
	return AppTypes.success(true)
end

function SessionCurrencyService.AbortSession(self: Service, userId: number): Result<boolean>
	return self:CloseSession(userId)
end

function SessionCurrencyService.Destroy(self: Service)
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true
	local userIds = {}
	for userId in self._sessions do
		table.insert(userIds, userId)
	end
	for _, userId in userIds do
		self:CloseSession(userId)
	end
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(SessionCurrencyService)
