--!strict

export type ErrorDetail = {
	message: string,
	traceback: string,
}

type GuardData = {
	_running: boolean,
	_setEnabled: (boolean) -> (),
}

local AcceptanceRunGuard = {}
AcceptanceRunGuard.__index = AcceptanceRunGuard
export type Guard = typeof(setmetatable({} :: GuardData, AcceptanceRunGuard))

function AcceptanceRunGuard.new(setEnabled: (boolean) -> ()): Guard
	return setmetatable({
		_running = false,
		_setEnabled = setEnabled,
	}, AcceptanceRunGuard)
end

function AcceptanceRunGuard.Begin(self: Guard): boolean
	if self._running then
		return false
	end
	self._running = true
	self._setEnabled(false)
	return true
end

function AcceptanceRunGuard.Finish(self: Guard)
	self._running = false
	self._setEnabled(true)
end

function AcceptanceRunGuard.RunActive(self: Guard, callback: () -> unknown): (boolean, unknown)
	local ok, value = xpcall(callback, function(errorValue: unknown): ErrorDetail
		return {
			message = tostring(errorValue),
			traceback = debug.traceback(tostring(errorValue), 2),
		}
	end)
	self:Finish()
	return ok, value
end

function AcceptanceRunGuard.IsRunning(self: Guard): boolean
	return self._running
end

return table.freeze(AcceptanceRunGuard)
