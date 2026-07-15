--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CLIENT_BOOTSTRAP_TIMEOUT_SECONDS = 10

local playerScripts = script.Parent
local bootstrapFolder = playerScripts:WaitForChild("Bootstrap", CLIENT_BOOTSTRAP_TIMEOUT_SECONDS)
if bootstrapFolder == nil or not bootstrapFolder:IsA("Folder") then
	error("Stage 2 test failed: production Bootstrap folder was not copied to PlayerScripts")
end

local bootstrapScript = bootstrapFolder:WaitForChild("Bootstrap", CLIENT_BOOTSTRAP_TIMEOUT_SECONDS)
if bootstrapScript == nil or not bootstrapScript:IsA("LocalScript") then
	error("Stage 2 test failed: production Bootstrap LocalScript was not copied to PlayerScripts")
end

local function waitForProductionClientBootstrap(): string
	local currentState = bootstrapScript:GetAttribute("ClientBootstrapState")
	if currentState == "Ready" or currentState == "Failed" then
		return currentState
	end

	local completed = Instance.new("BindableEvent")
	local resolvedState: string? = nil
	local function complete(state: string)
		if resolvedState ~= nil then
			return
		end
		resolvedState = state
		completed:Fire(state)
	end

	local stateConnection = bootstrapScript:GetAttributeChangedSignal("ClientBootstrapState"):Connect(function()
		local state = bootstrapScript:GetAttribute("ClientBootstrapState")
		if state == "Ready" or state == "Failed" then
			complete(state)
		end
	end)
	local timeoutThread = task.delay(CLIENT_BOOTSTRAP_TIMEOUT_SECONDS, function()
		complete("Timeout")
	end)

	currentState = bootstrapScript:GetAttribute("ClientBootstrapState")
	if currentState == "Ready" or currentState == "Failed" then
		complete(currentState)
	end

	local finalState: unknown = resolvedState
	if finalState == nil then
		finalState = completed.Event:Wait()
	end
	stateConnection:Disconnect()
	pcall(task.cancel, timeoutThread)
	completed:Destroy()
	return if typeof(finalState) == "string" then finalState else "InvalidState"
end

local bootstrapState = waitForProductionClientBootstrap()
if bootstrapState ~= "Ready" then
	local errorCode = bootstrapScript:GetAttribute("ClientBootstrapErrorCode")
	error(`Stage 2 test failed: production client bootstrap state was {bootstrapState} ({tostring(errorCode)})`)
end

print("[Stage2Test] PASS production client emitted client_bootstrap_ready")

local folder = ReplicatedStorage:WaitForChild("TestRemotes", 10)
if folder == nil or not folder:IsA("Folder") then
	error("Stage 2 test remote folder was not replicated")
end

local event = folder:WaitForChild("TestRequest", 10)
local remoteFunction = folder:WaitForChild("TestFunction", 10)
local ready = folder:WaitForChild("Ready", 10)
if event == nil or not event:IsA("RemoteEvent") then
	error("TestRequest RemoteEvent was not replicated")
end
if remoteFunction == nil or not remoteFunction:IsA("RemoteFunction") then
	error("TestFunction RemoteFunction was not replicated")
end
if ready == nil or not ready:IsA("BoolValue") or not ready.Value then
	error("Stage 2 remote integration test did not become ready")
end

local invalidResponse: unknown = remoteFunction:InvokeServer({ requestId = "" })
if typeof(invalidResponse) ~= "table" then
	error("Invalid RemoteFunction request did not return a safe error table")
end

local validResponse: unknown = remoteFunction:InvokeServer({ requestId = "valid-function" })
if typeof(validResponse) ~= "table" then
	error("Valid RemoteFunction request did not return a response table")
end

event:FireServer({ requestId = "" })
event:FireServer({ requestId = "valid-extra" }, "unexpected")
event:FireServer({ requestId = "valid-event" })

print("[Stage2Test] PASS client remote runtime checks")
