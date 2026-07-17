--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")

local testArgs = StudioTestService:GetTestArgs()
if typeof(testArgs) == "table" and testArgs.stage == 4 and typeof(testArgs.suite) == "string" then
	return
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not remotes:IsA("Folder") then
	error("Production remote container is unavailable")
end
if remotes:FindFirstChild("TestOfficePurchase") ~= nil then
	error("Test-only office remote leaked into production registry")
end
script:SetAttribute("OfficeSecurityProbeReady", true)
print("[Stage4Test] PASS office security server probe ready")
