--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not remotes:IsA("Folder") then
	error("Production remote container is unavailable")
end
if remotes:FindFirstChild("TestOfficePurchase") ~= nil then
	error("Test-only office remote leaked into production registry")
end
script:SetAttribute("OfficeSecurityProbeReady", true)
print("[Stage4Test] PASS office security server probe ready")
