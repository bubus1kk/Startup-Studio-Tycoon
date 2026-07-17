--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")

local testArgs = StudioTestService:GetTestArgs()
if typeof(testArgs) == "table" and testArgs.stage == 4 and typeof(testArgs.suite) == "string" then
	return
end

local localPlayer = Players.LocalPlayer
local PROBE_TIMEOUT_SECONDS = 10

local function waitUntil(predicate: () -> boolean, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	repeat
		if predicate() then
			return true
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return predicate()
end

local remotes = ReplicatedStorage:WaitForChild("Stage3TestRemotes", 10)
if remotes == nil or not remotes:IsA("Folder") then
	error("Stage 3 foreign ownership probe remote folder was not replicated")
end
local mutationRemote = remotes:WaitForChild("TestPlotMutation", 10)
if mutationRemote == nil or not mutationRemote:IsA("RemoteFunction") then
	error("Stage 3 TestPlotMutation RemoteFunction was not replicated")
end

local ownPlotReady = waitUntil(function()
	return localPlayer:GetAttribute("Stage3ProbePlotId") ~= nil
		or localPlayer:GetAttribute("Stage3ProbeErrorCode") ~= nil
end, PROBE_TIMEOUT_SECONDS)
if not ownPlotReady then
	error("Stage 3 probe plot assignment timed out")
end
local ownPlotId = localPlayer:GetAttribute("Stage3ProbePlotId")
if typeof(ownPlotId) ~= "string" then
	error(`Stage 3 probe plot assignment failed: {tostring(localPlayer:GetAttribute("Stage3ProbeErrorCode"))}`)
end

local ownResponse: unknown = mutationRemote:InvokeServer({ plotId = ownPlotId })
if typeof(ownResponse) ~= "table" then
	error("Stage 3 owner probe returned an invalid response")
end
local ownResult = ownResponse :: { [string]: unknown }
if ownResult.ok ~= true or ownResult.code ~= "OK" then
	error(`Stage 3 owner probe was rejected: {tostring(ownResult.code)}`)
end
print("[Stage3Test] PASS owner mutation probe")

local foreignPlayer: Player? = nil
waitUntil(function()
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and typeof(player:GetAttribute("Stage3ProbePlotId")) == "string" then
			foreignPlayer = player
			return true
		end
	end
	return false
end, 3)

if foreignPlayer == nil then
	print("[Stage3Test] MANUAL foreign ownership probe requires Start Server + 2 or more Players")
	return
end

local foreignPlotId = foreignPlayer:GetAttribute("Stage3ProbePlotId")
if typeof(foreignPlotId) ~= "string" then
	error("Stage 3 foreign player has no probe plot")
end
local foreignResponse: unknown = mutationRemote:InvokeServer({ plotId = foreignPlotId })
if typeof(foreignResponse) ~= "table" then
	error("Stage 3 foreign probe returned an invalid response")
end
local foreignResult = foreignResponse :: { [string]: unknown }
if
	foreignResult.ok ~= false
	or foreignResult.code ~= "PlotOwnershipMismatch"
	or foreignResult.mutationUnchanged ~= true
then
	error(`Stage 3 foreign ownership probe failed: {tostring(foreignResult.code)}`)
end
print("[Stage3Test] PASS foreign ownership rejected without mutation")
