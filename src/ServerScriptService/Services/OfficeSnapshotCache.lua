--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)
local SessionCurrencyService = require(ServerScriptService.Services.SessionCurrencyService)

type CurrencySnapshot = SessionCurrencyService.CurrencySnapshot
type OfficeLayoutState = OfficeTypes.OfficeLayoutState

export type SessionSnapshot = {
	userId: number,
	createdAt: number,
	expiresAt: number,
	layout: OfficeLayoutState,
	currency: CurrencySnapshot,
}

export type Clock = () -> number

type CacheData = {
	_clock: Clock,
	_ttlSeconds: number,
	_capacity: number,
	_byUserId: { [number]: SessionSnapshot },
}

local OfficeSnapshotCache = {}
OfficeSnapshotCache.__index = OfficeSnapshotCache
export type Cache = typeof(setmetatable({} :: CacheData, OfficeSnapshotCache))

function OfficeSnapshotCache.new(clock: Clock, ttlSeconds: number, capacity: number): Cache
	assert(ttlSeconds > 0, "ttlSeconds must be positive")
	assert(capacity > 0 and capacity % 1 == 0, "capacity must be a positive integer")
	return setmetatable({
		_clock = clock,
		_ttlSeconds = ttlSeconds,
		_capacity = capacity,
		_byUserId = {},
	}, OfficeSnapshotCache)
end

function OfficeSnapshotCache.EvictExpired(self: Cache): number
	local now = self._clock()
	local removed = 0
	for userId, snapshot in self._byUserId do
		if snapshot.expiresAt <= now then
			self._byUserId[userId] = nil
			removed += 1
		end
	end
	return removed
end

function OfficeSnapshotCache.Put(
	self: Cache,
	userId: number,
	layout: OfficeLayoutState,
	currency: CurrencySnapshot
): SessionSnapshot
	self:EvictExpired()
	local now = self._clock()
	if self._byUserId[userId] == nil then
		local count = 0
		local oldestUserId: number? = nil
		local oldestTime = math.huge
		for existingUserId, snapshot in self._byUserId do
			count += 1
			if
				snapshot.createdAt < oldestTime
				or snapshot.createdAt == oldestTime and (oldestUserId == nil or existingUserId < oldestUserId)
			then
				oldestTime = snapshot.createdAt
				oldestUserId = existingUserId
			end
		end
		if count >= self._capacity and oldestUserId ~= nil then
			self._byUserId[oldestUserId] = nil
		end
	end
	local snapshot = {
		userId = userId,
		createdAt = now,
		expiresAt = now + self._ttlSeconds,
		layout = layout,
		currency = currency,
	}
	self._byUserId[userId] = snapshot
	return snapshot
end

function OfficeSnapshotCache.Peek(self: Cache, userId: number): SessionSnapshot?
	self:EvictExpired()
	return self._byUserId[userId]
end

function OfficeSnapshotCache.Consume(self: Cache, userId: number): SessionSnapshot?
	local snapshot = self:Peek(userId)
	if snapshot ~= nil then
		self._byUserId[userId] = nil
	end
	return snapshot
end

function OfficeSnapshotCache.Remove(self: Cache, userId: number): boolean
	local existed = self._byUserId[userId] ~= nil
	self._byUserId[userId] = nil
	return existed
end

function OfficeSnapshotCache.GetCount(self: Cache): number
	self:EvictExpired()
	local count = 0
	for _ in self._byUserId do
		count += 1
	end
	return count
end

function OfficeSnapshotCache.Destroy(self: Cache)
	table.clear(self._byUserId)
end

return table.freeze(OfficeSnapshotCache)
