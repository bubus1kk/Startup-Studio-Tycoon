--!strict

export type Clock = () -> number

type Bucket = {
	tokens: number,
	updatedAt: number,
}

type LimiterData = {
	_clock: Clock,
	_buckets: { [number]: { [string]: Bucket } },
}

local RequestRateLimiter = {}
RequestRateLimiter.__index = RequestRateLimiter
export type Limiter = typeof(setmetatable({} :: LimiterData, RequestRateLimiter))

function RequestRateLimiter.new(clock: Clock): Limiter
	return setmetatable({ _clock = clock, _buckets = {} }, RequestRateLimiter)
end

function RequestRateLimiter.Allow(
	self: Limiter,
	userId: number,
	key: string,
	capacity: number,
	refillPerSecond: number
): boolean
	local now = self._clock()
	local playerBuckets = self._buckets[userId]
	if playerBuckets == nil then
		playerBuckets = {}
		self._buckets[userId] = playerBuckets
	end
	local bucket = playerBuckets[key]
	if bucket == nil then
		bucket = { tokens = capacity, updatedAt = now }
		playerBuckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.tokens = math.min(capacity, bucket.tokens + elapsed * refillPerSecond)
	bucket.updatedAt = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function RequestRateLimiter.ClearPlayer(self: Limiter, userId: number)
	self._buckets[userId] = nil
end

function RequestRateLimiter.Destroy(self: Limiter)
	table.clear(self._buckets)
end

return table.freeze(RequestRateLimiter)
