--!strict

local AppTypes = require(script.Parent.Parent.Types.AppTypes)

type AppError = AppTypes.AppError
type Result<T> = AppTypes.Result<T>

export type ClientDependencies = {
	infrastructure: Folder,
	controllerRegistry: ModuleScript,
	remoteClient: ModuleScript,
}

local ClientDependencyResolver = {}

local function waitForChildUntil(
	parent: Instance,
	childName: string,
	deadline: number,
	totalTimeoutSeconds: number,
	path: string
): Result<Instance>
	local child = parent:FindFirstChild(childName)
	if child ~= nil then
		return AppTypes.success(child)
	end

	local remainingSeconds = deadline - time()
	if remainingSeconds > 0 then
		child = parent:WaitForChild(childName, remainingSeconds)
	end
	if child == nil then
		return AppTypes.failure("StartupDependencyTimeout", "Client startup dependency was not available", {
			path = path,
			timeoutSeconds = tostring(totalTimeoutSeconds),
		})
	end

	return AppTypes.success(child)
end

local function waitForFolderUntil(
	parent: Instance,
	childName: string,
	deadline: number,
	totalTimeoutSeconds: number,
	path: string
): Result<Folder>
	local childResult = waitForChildUntil(parent, childName, deadline, totalTimeoutSeconds, path)
	if not childResult.ok then
		return AppTypes.failure(childResult.error.code, childResult.error.message, childResult.error.details)
	end

	local child = childResult.value
	if not child:IsA("Folder") then
		return AppTypes.failure("StartupDependencyClassMismatch", "Client startup dependency has the wrong class", {
			path = path,
			expectedClass = "Folder",
			actualClass = child.ClassName,
		})
	end

	return AppTypes.success(child)
end

local function waitForModuleScriptUntil(
	parent: Instance,
	childName: string,
	deadline: number,
	totalTimeoutSeconds: number,
	path: string
): Result<ModuleScript>
	local childResult = waitForChildUntil(parent, childName, deadline, totalTimeoutSeconds, path)
	if not childResult.ok then
		return AppTypes.failure(childResult.error.code, childResult.error.message, childResult.error.details)
	end

	local child = childResult.value
	if not child:IsA("ModuleScript") then
		return AppTypes.failure("StartupDependencyClassMismatch", "Client startup dependency has the wrong class", {
			path = path,
			expectedClass = "ModuleScript",
			actualClass = child.ClassName,
		})
	end

	return AppTypes.success(child)
end

function ClientDependencyResolver.waitForModuleScript(
	parent: Instance,
	childName: string,
	timeoutSeconds: number,
	path: string
): Result<ModuleScript>
	return waitForModuleScriptUntil(parent, childName, time() + timeoutSeconds, timeoutSeconds, path)
end

function ClientDependencyResolver.resolvePlayerScripts(
	playerScripts: Instance,
	timeoutSeconds: number
): Result<ClientDependencies>
	local deadline = time() + timeoutSeconds
	local infrastructureResult =
		waitForFolderUntil(playerScripts, "Infrastructure", deadline, timeoutSeconds, "PlayerScripts.Infrastructure")
	if not infrastructureResult.ok then
		return AppTypes.failure(
			infrastructureResult.error.code,
			infrastructureResult.error.message,
			infrastructureResult.error.details
		)
	end

	local infrastructure = infrastructureResult.value
	local controllerRegistryResult = waitForModuleScriptUntil(
		infrastructure,
		"ControllerRegistry",
		deadline,
		timeoutSeconds,
		"PlayerScripts.Infrastructure.ControllerRegistry"
	)
	if not controllerRegistryResult.ok then
		return AppTypes.failure(
			controllerRegistryResult.error.code,
			controllerRegistryResult.error.message,
			controllerRegistryResult.error.details
		)
	end

	local remoteClientResult = waitForModuleScriptUntil(
		infrastructure,
		"RemoteClient",
		deadline,
		timeoutSeconds,
		"PlayerScripts.Infrastructure.RemoteClient"
	)
	if not remoteClientResult.ok then
		return AppTypes.failure(
			remoteClientResult.error.code,
			remoteClientResult.error.message,
			remoteClientResult.error.details
		)
	end

	return AppTypes.success({
		infrastructure = infrastructure,
		controllerRegistry = controllerRegistryResult.value,
		remoteClient = remoteClientResult.value,
	})
end

function ClientDependencyResolver.formatStartupError(errorValue: AppError): string
	local details = errorValue.details or {}
	local path = details.path or "unknown client dependency"
	if errorValue.code == "StartupDependencyTimeout" then
		return `StartupError: Client startup failed: {path} was not available within {details.timeoutSeconds or "unknown"} seconds ({errorValue.code})`
	end
	if errorValue.code == "StartupDependencyClassMismatch" then
		return `StartupError: Client startup failed: {path} expected {details.expectedClass or "unknown"}, got {details.actualClass or "unknown"} ({errorValue.code})`
	end

	return `StartupError: Client startup failed: {path} ({errorValue.code})`
end

return table.freeze(ClientDependencyResolver)
