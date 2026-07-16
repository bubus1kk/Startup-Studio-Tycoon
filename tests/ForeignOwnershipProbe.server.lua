--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local ServerRemoteRegistry = require(script.Parent.Parent.Infrastructure.ServerRemoteRegistry)
local PlotTestUtils = require(script.Parent.ServerFixtures.PlotTestUtils)
local TestPlotRemoteDefinitions = require(ReplicatedStorage.TestSupport.TestPlotRemoteDefinitions)

local logger = Logger.new("Test", "studio-runtime", "ForeignOwnershipProbe", true)
local fixture = PlotTestUtils.createFixture(nil)
local remoteRegistry = ServerRemoteRegistry.new(
	ReplicatedStorage,
	TestPlotRemoteDefinitions.folderName,
	TestPlotRemoteDefinitions.definitions,
	logger
)
local remoteLifecycle = LifecycleRegistry.new(nil)
local registrationResult = remoteLifecycle:Register({
	name = "Stage3TestRemoteRegistry",
	dependencies = {},
	value = remoteRegistry,
	hooks = {
		Init = function(dependencies)
			remoteRegistry:Init(dependencies)
		end,
		Start = function()
			remoteRegistry:Start()
		end,
		Destroy = function()
			remoteRegistry:Destroy()
		end,
	},
})
if not registrationResult.ok then
	error(`Foreign ownership probe registration failed: {registrationResult.error.code}`)
end
local initResult = remoteLifecycle:InitAll()
if not initResult.ok then
	error(`Foreign ownership probe Init failed: {initResult.error.code}`)
end
local startResult = remoteLifecycle:StartAll()
if not startResult.ok then
	error(`Foreign ownership probe Start failed: {startResult.error.code}`)
end

local function assignProbePlot(player: Player)
	local assignmentResult = fixture.service:AssignPlayer(player.UserId)
	if not assignmentResult.ok then
		player:SetAttribute("Stage3ProbeErrorCode", assignmentResult.error.code)
		return
	end
	player:SetAttribute("Stage3ProbePlotId", assignmentResult.value.plotId)
end

local playerAddedConnection = Players.PlayerAdded:Connect(assignProbePlot)
local playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
	player:SetAttribute("Stage3ProbePlotId", nil)
	fixture.service:ReleasePlayer(player.UserId)
end)
for _, player in Players:GetPlayers() do
	assignProbePlot(player)
end

local bindingResult = remoteRegistry:BindFunction(
	"TestPlotMutation",
	function(player: Player, payload: unknown): unknown
		local request = payload :: { plotId: string }
		local targetModel = fixture.service:GetRuntimePlotModel(request.plotId)
		local countBefore = if targetModel ~= nil then targetModel:GetAttribute("TestMutationCount") else 0
		if typeof(countBefore) ~= "number" then
			countBefore = 0
		end

		local ownershipResult = fixture.service:RequireOwnership(player.UserId, request.plotId)
		if not ownershipResult.ok then
			local countAfter = if targetModel ~= nil then targetModel:GetAttribute("TestMutationCount") else 0
			return {
				ok = false,
				code = ownershipResult.error.code,
				mutationCount = if typeof(countAfter) == "number" then countAfter else 0,
				mutationUnchanged = countAfter == countBefore,
			}
		end

		local mutationCount = countBefore + 1
		ownershipResult.value.model:SetAttribute("TestMutationCount", mutationCount)
		return {
			ok = true,
			code = "OK",
			mutationCount = mutationCount,
			mutationUnchanged = false,
		}
	end
)
if not bindingResult.ok then
	error(`Foreign ownership probe binding failed: {bindingResult.error.code}`)
end

game:BindToClose(function()
	playerAddedConnection:Disconnect()
	playerRemovingConnection:Disconnect()
	remoteLifecycle:DestroyAll()
	fixture:Destroy()
end)
