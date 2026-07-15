--!strict

local LoggerTypes = require(script.Parent.Parent.Types.LoggerTypes)

type Metadata = LoggerTypes.Metadata
type MetadataValue = LoggerTypes.MetadataValue
type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR" | "SECURITY"

type LoggerData = {
	_environment: string,
	_jobId: string,
	_subsystem: string,
	_minimumRank: number,
}

local LEVEL_RANK: { [LogLevel]: number } = {
	DEBUG = 10,
	INFO = 20,
	WARN = 30,
	ERROR = 40,
	SECURITY = 50,
}

local Logger = {}
Logger.__index = Logger

export type Logger = typeof(setmetatable({} :: LoggerData, Logger))

local function sanitizeValue(value: MetadataValue): string
	if typeof(value) == "number" and (value ~= value or math.abs(value) == math.huge) then
		return "<non-finite-number>"
	end
	return tostring(value)
end

local function formatMetadata(metadata: Metadata?): string
	if metadata == nil then
		return ""
	end

	local keys: { string } = {}
	for key in metadata do
		table.insert(keys, key)
	end
	table.sort(keys)

	local fields: { string } = {}
	for _, key in keys do
		table.insert(fields, `{key}={sanitizeValue(metadata[key])}`)
	end

	return if #fields == 0 then "" else ` {table.concat(fields, " ")}`
end

function Logger.new(environment: string, jobId: string, subsystem: string, enableDebug: boolean): Logger
	return setmetatable({
		_environment = environment,
		_jobId = jobId,
		_subsystem = subsystem,
		_minimumRank = if enableDebug then LEVEL_RANK.DEBUG else LEVEL_RANK.INFO,
	}, Logger)
end

function Logger._emit(self: Logger, level: LogLevel, event: string, metadata: Metadata?)
	if LEVEL_RANK[level] < self._minimumRank then
		return
	end

	local timestamp = DateTime.now().UnixTimestampMillis
	local line =
		`[{timestamp}] [{level}] [{self._environment}] [{self._jobId}] [{self._subsystem}] {event}{formatMetadata(
			metadata
		)}`
	if level == "WARN" or level == "ERROR" or level == "SECURITY" then
		warn(line)
	else
		print(line)
	end
end

function Logger.Debug(self: Logger, event: string, metadata: Metadata?)
	self:_emit("DEBUG", event, metadata)
end

function Logger.Info(self: Logger, event: string, metadata: Metadata?)
	self:_emit("INFO", event, metadata)
end

function Logger.Warn(self: Logger, event: string, metadata: Metadata?)
	self:_emit("WARN", event, metadata)
end

function Logger.Error(self: Logger, event: string, metadata: Metadata?)
	self:_emit("ERROR", event, metadata)
end

function Logger.Security(self: Logger, event: string, metadata: Metadata?)
	self:_emit("SECURITY", event, metadata)
end

return table.freeze(Logger)
