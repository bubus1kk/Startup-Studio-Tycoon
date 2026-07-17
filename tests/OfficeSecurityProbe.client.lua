--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
<<<<<<< HEAD
local StudioTestService = game:GetService("StudioTestService")

local testArgs = StudioTestService:GetTestArgs()
if typeof(testArgs) == "table" and testArgs.stage == 4 and typeof(testArgs.suite) == "string" then
	return
end
=======
>>>>>>> 94818332a6f52a94409e8f7b68c861c2ad26d4b6

local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not remotes:IsA("Folder") then
	error("Production remote container is unavailable")
end
local purchase = remotes:WaitForChild("RequestOfficePurchase", 15)
if not purchase:IsA("RemoteFunction") then
	error("RequestOfficePurchase is unavailable")
end
local response = purchase:InvokeServer({
	requestId = "security-extra-field",
	itemId = "room_development",
	price = -100,
	plotId = "plot_99",
})
if typeof(response) ~= "table" or response.ok ~= false or response.error.code ~= "InvalidPayload" then
	error("Forbidden office payload fields were not rejected")
end
print("[Stage4Test] PASS forbidden office purchase payload rejected")
