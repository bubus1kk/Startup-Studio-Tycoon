--!strict

local ServerApplication = require(script.Parent.ServerApplication)

local applicationResult = ServerApplication.new()
if not applicationResult.ok then
	error(`Server application construction failed: {applicationResult.error.code}`)
end

local application = applicationResult.value
local startResult = application:Start()
if not startResult.ok then
	error(`Server application startup failed: {startResult.error.code}`)
end

game:BindToClose(function()
	application:Destroy()
end)
