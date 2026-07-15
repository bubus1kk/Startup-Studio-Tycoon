--!strict

export type ErrorDetails = { [string]: string }

export type AppError = {
	code: string,
	message: string,
	details: ErrorDetails?,
}

export type Success<T> = {
	ok: true,
	value: T,
}

export type Failure = {
	ok: false,
	error: AppError,
}

export type Result<T> = Success<T> | Failure

local AppTypes = {}

function AppTypes.success<T>(value: T): Result<T>
	return {
		ok = true,
		value = value,
	}
end

function AppTypes.failure(code: string, message: string, details: ErrorDetails?): Failure
	return {
		ok = false,
		error = {
			code = code,
			message = message,
			details = details,
		},
	}
end

return table.freeze(AppTypes)
