--!strict

local AppTypes = require(script.Parent.Parent.Types.AppTypes)

type AppError = AppTypes.AppError
type Result<T> = AppTypes.Result<T>

export type DependencyResolver = {
	Get: (self: DependencyResolver, name: string) -> unknown,
	Require: (self: DependencyResolver, name: string) -> unknown,
}

export type LifecycleHooks = {
	Init: (dependencies: DependencyResolver) -> (),
	Start: () -> (),
	Destroy: () -> (),
}

export type Definition = {
	name: string,
	dependencies: { string },
	value: unknown,
	hooks: LifecycleHooks,
}

export type DiagnosticSink = (error: AppError) -> ()

type RegistryState = "Registering" | "Initializing" | "Initialized" | "Starting" | "Started" | "Destroyed"

type RegistryData = {
	_definitions: { [string]: Definition },
	_order: { string }?,
	_initialized: { string },
	_state: RegistryState,
	_isSealed: boolean,
	_diagnosticSink: DiagnosticSink?,
}

type ResolverData = {
	_registry: Registry,
	_ownerName: string,
	_allowed: { [string]: boolean },
}

local DependencyResolver = {}
DependencyResolver.__index = DependencyResolver

local LifecycleRegistry = {}
LifecycleRegistry.__index = LifecycleRegistry

export type Registry = typeof(setmetatable({} :: RegistryData, LifecycleRegistry))
type Resolver = typeof(setmetatable({} :: ResolverData, DependencyResolver))

local function failure(code: string, message: string, details: { [string]: string }?): AppTypes.Failure
	return AppTypes.failure(code, message, details)
end

local function tracebackError(errorValue: unknown): string
	return debug.traceback(tostring(errorValue), 2)
end

function DependencyResolver.Get(self: Resolver, name: string): unknown
	if not self._allowed[name] then
		return nil
	end

	local definition = self._registry._definitions[name]
	if definition == nil then
		return nil
	end

	return definition.value
end

function DependencyResolver.Require(self: Resolver, name: string): unknown
	local dependency = self:Get(name)
	if dependency == nil then
		error(`{self._ownerName} requested undeclared or missing dependency {name}`, 2)
	end

	return dependency
end

function LifecycleRegistry.new(diagnosticSink: DiagnosticSink?): Registry
	return setmetatable({
		_definitions = {},
		_order = nil,
		_initialized = {},
		_state = "Registering",
		_isSealed = false,
		_diagnosticSink = diagnosticSink,
	}, LifecycleRegistry)
end

function LifecycleRegistry.Register(self: Registry, definition: Definition): Result<true>
	if self._state ~= "Registering" or self._isSealed then
		return failure("LifecycleRegistrySealed", "Lifecycle registrations are closed", {
			name = definition.name,
		})
	end

	if definition.name == "" then
		return failure("InvalidLifecycleName", "Lifecycle object name cannot be empty", nil)
	end

	if self._definitions[definition.name] ~= nil then
		return failure("DuplicateLifecycleObject", "Lifecycle object is already registered", {
			name = definition.name,
		})
	end

	local seenDependencies: { [string]: boolean } = {}
	local dependencies = table.clone(definition.dependencies)
	for _, dependencyName in dependencies do
		if dependencyName == definition.name then
			return failure("LifecycleSelfDependency", "Lifecycle object cannot depend on itself", {
				name = definition.name,
			})
		end
		if seenDependencies[dependencyName] then
			return failure("DuplicateLifecycleDependency", "Dependency is declared more than once", {
				name = definition.name,
				dependency = dependencyName,
			})
		end
		seenDependencies[dependencyName] = true
	end

	self._definitions[definition.name] = {
		name = definition.name,
		dependencies = dependencies,
		value = definition.value,
		hooks = definition.hooks,
	}

	return AppTypes.success(true)
end

function LifecycleRegistry.ResolveStartupOrder(self: Registry): Result<{ string }>
	if self._order ~= nil then
		return AppTypes.success(table.clone(self._order))
	end

	if self._state ~= "Registering" then
		return failure("InvalidLifecycleState", "Startup order cannot be resolved in the current state", {
			state = self._state,
		})
	end

	local names: { string } = {}
	for name in self._definitions do
		table.insert(names, name)
	end
	table.sort(names)

	local inDegree: { [string]: number } = {}
	local dependents: { [string]: { string } } = {}
	for _, name in names do
		inDegree[name] = 0
		dependents[name] = {}
	end

	for _, name in names do
		local definition = self._definitions[name]
		for _, dependencyName in definition.dependencies do
			if self._definitions[dependencyName] == nil then
				return failure("MissingLifecycleDependency", "A declared dependency is not registered", {
					name = name,
					dependency = dependencyName,
				})
			end

			inDegree[name] += 1
			table.insert(dependents[dependencyName], name)
		end
	end

	for _, dependentNames in dependents do
		table.sort(dependentNames)
	end

	local ready: { string } = {}
	for _, name in names do
		if inDegree[name] == 0 then
			table.insert(ready, name)
		end
	end

	local order: { string } = {}
	while #ready > 0 do
		local name = table.remove(ready, 1)
		table.insert(order, name)

		for _, dependentName in dependents[name] do
			inDegree[dependentName] -= 1
			if inDegree[dependentName] == 0 then
				table.insert(ready, dependentName)
				table.sort(ready)
			end
		end
	end

	if #order ~= #names then
		local cycleMembers: { string } = {}
		for _, name in names do
			if inDegree[name] > 0 then
				table.insert(cycleMembers, name)
			end
		end

		return failure("LifecycleDependencyCycle", "Lifecycle dependency graph contains a cycle", {
			members = table.concat(cycleMembers, ","),
		})
	end

	self._order = order
	self._isSealed = true
	return AppTypes.success(table.clone(order))
end

function LifecycleRegistry._resolverFor(self: Registry, definition: Definition): DependencyResolver
	local allowed: { [string]: boolean } = {}
	for _, dependencyName in definition.dependencies do
		allowed[dependencyName] = true
	end

	return setmetatable({
		_registry = self,
		_ownerName = definition.name,
		_allowed = allowed,
	}, DependencyResolver) :: Resolver
end

function LifecycleRegistry._reportCleanupFailure(self: Registry, name: string, cause: string)
	local sink = self._diagnosticSink
	if sink ~= nil then
		sink({
			code = "LifecycleCleanupFailed",
			message = "Lifecycle cleanup failed",
			details = {
				name = name,
				cause = cause,
			},
		})
	end
end

function LifecycleRegistry._destroyInitialized(self: Registry)
	for index = #self._initialized, 1, -1 do
		local name = self._initialized[index]
		local definition = self._definitions[name]
		local ok, cause = xpcall(function()
			definition.hooks.Destroy()
		end, tracebackError)

		if not ok then
			self:_reportCleanupFailure(name, cause)
		end
	end

	table.clear(self._initialized)
end

function LifecycleRegistry.InitAll(self: Registry): Result<true>
	if self._state ~= "Registering" then
		return failure("InvalidLifecycleState", "InitAll can only run once after registration", {
			state = self._state,
		})
	end

	local orderResult = self:ResolveStartupOrder()
	if not orderResult.ok then
		return orderResult
	end

	self._state = "Initializing"
	for _, name in orderResult.value do
		local definition = self._definitions[name]
		local resolver = self:_resolverFor(definition)
		local ok, cause = xpcall(function()
			definition.hooks.Init(resolver)
		end, tracebackError)

		if not ok then
			self:_destroyInitialized()
			self._state = "Destroyed"
			return failure("LifecycleInitFailed", "Lifecycle Init failed", {
				name = name,
				cause = cause,
			})
		end

		table.insert(self._initialized, name)
	end

	self._state = "Initialized"
	return AppTypes.success(true)
end

function LifecycleRegistry.StartAll(self: Registry): Result<true>
	if self._state ~= "Initialized" then
		return failure("InvalidLifecycleState", "StartAll requires a successful InitAll", {
			state = self._state,
		})
	end

	local order = self._order
	if order == nil then
		return failure("LifecycleOrderMissing", "Resolved startup order is missing", nil)
	end

	self._state = "Starting"
	for _, name in order do
		local definition = self._definitions[name]
		local ok, cause = xpcall(function()
			definition.hooks.Start()
		end, tracebackError)

		if not ok then
			self:_destroyInitialized()
			self._state = "Destroyed"
			return failure("LifecycleStartFailed", "Lifecycle Start failed", {
				name = name,
				cause = cause,
			})
		end
	end

	self._state = "Started"
	return AppTypes.success(true)
end

function LifecycleRegistry.DestroyAll(self: Registry): Result<true>
	if self._state == "Destroyed" then
		return AppTypes.success(true)
	end

	self._state = "Destroyed"
	self:_destroyInitialized()
	return AppTypes.success(true)
end

function LifecycleRegistry.GetState(self: Registry): RegistryState
	return self._state
end

return table.freeze(LifecycleRegistry)
