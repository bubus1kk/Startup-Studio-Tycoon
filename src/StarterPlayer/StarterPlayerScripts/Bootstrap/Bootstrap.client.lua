--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientDependencyResolver = require(ReplicatedStorage.Shared.Infrastructure.ClientDependencyResolver)

local CLIENT_DEPENDENCY_TIMEOUT_SECONDS = 10

script:SetAttribute("ClientBootstrapState", "Starting")

local clientApplicationResult = ClientDependencyResolver.waitForModuleScript(
	script.Parent,
	"ClientApplication",
	CLIENT_DEPENDENCY_TIMEOUT_SECONDS,
	"PlayerScripts.Bootstrap.ClientApplication"
)
if not clientApplicationResult.ok then
	script:SetAttribute("ClientBootstrapState", "Failed")
	script:SetAttribute("ClientBootstrapErrorCode", clientApplicationResult.error.code)
	error(ClientDependencyResolver.formatStartupError(clientApplicationResult.error), 0)
end

-- Capture dependency failures so the test session can reject the normal
-- production bootstrap immediately. The second require is served from cache
-- and preserves the static module type.
local moduleLoaded: boolean, moduleLoadError: unknown = pcall(function()
	require(script.Parent.ClientApplication)
end)
if not moduleLoaded then
	script:SetAttribute("ClientBootstrapState", "Failed")
	script:SetAttribute("ClientBootstrapErrorCode", "ClientApplicationRequireFailed")
	error(tostring(moduleLoadError), 0)
end

local ClientApplication = require(script.Parent.ClientApplication)

local applicationResult = ClientApplication.new()
if not applicationResult.ok then
	script:SetAttribute("ClientBootstrapState", "Failed")
	script:SetAttribute("ClientBootstrapErrorCode", applicationResult.error.code)
	error(`Client application construction failed: {applicationResult.error.code}`)
end

local startResult = applicationResult.value:Start()
if not startResult.ok then
	script:SetAttribute("ClientBootstrapState", "Failed")
	script:SetAttribute("ClientBootstrapErrorCode", startResult.error.code)
	error(`Client application startup failed: {startResult.error.code}`)
end

-- ClientApplication logs client_bootstrap_ready before Start returns success.
script:SetAttribute("ClientBootstrapState", "Ready")

-- ClientApplication exposes Destroy for tests and controlled teardown.
-- Roblox does not provide a reliable client equivalent of BindToClose, so the
-- production bootstrap intentionally does not promise one.
