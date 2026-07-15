--!strict

local ServerApplication = require(script.Parent.ServerApplication)

script:SetAttribute("ServerBootstrapState", "Starting")

local applicationResult = ServerApplication.new()
if not applicationResult.ok then
	script:SetAttribute("ServerBootstrapState", "Failed")
	script:SetAttribute("ServerBootstrapErrorCode", applicationResult.error.code)

	error(`Server application construction failed: {applicationResult.error.code}`)
end

local application = applicationResult.value
local startResult = application:Start()

if not startResult.ok then
	script:SetAttribute("ServerBootstrapState", "Failed")
	script:SetAttribute("ServerBootstrapErrorCode", startResult.error.code)

	error(`Server application startup failed: {startResult.error.code}`)
end

script:SetAttribute("ServerBootstrapState", "Ready")

game:BindToClose(function()
	application:Destroy()
end)