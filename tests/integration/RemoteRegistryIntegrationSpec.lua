--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local RemoteDefinitionValidator = require(ReplicatedStorage.Shared.Remotes.RemoteDefinitionValidator)
local ServerRemoteRegistry = require(ServerScriptService.Infrastructure.ServerRemoteRegistry)
local TestHarness = require(script.Parent.Parent.TestHarness)
local TestRemoteDefinitions = require(ReplicatedStorage.TestSupport.TestRemoteDefinitions)

type TestCase = TestHarness.TestCase

local RemoteRegistryIntegrationSpec = {}
local TEST_CLIENT_SESSION_TIMEOUT_SECONDS = 20

local function tracebackError(errorValue: unknown): string
	return debug.traceback(tostring(errorValue), 2)
end

local function duplicateRemoteDefinitionTest()
	local definition = TestRemoteDefinitions.definitions[1]
	local result = RemoteDefinitionValidator.validate({ definition, definition })
	TestHarness.assertTrue(not result.ok)
	if not result.ok then
		TestHarness.assertEqual(result.error.code, "DuplicateRemoteDefinition")
	end
end

local function duplicateRemoteInstanceTest()
	local parent = Instance.new("Folder")
	local remoteFolder = Instance.new("Folder")
	remoteFolder.Name = TestRemoteDefinitions.folderName
	remoteFolder.Parent = parent
	local existingRemote = Instance.new("RemoteEvent")
	existingRemote.Name = "TestRequest"
	existingRemote.Parent = remoteFolder

	local logger = Logger.new("Test", "studio-runtime", "RemoteCollisionIntegration", true)
	local lifecycleRegistry = LifecycleRegistry.new(nil)
	local remoteRegistry =
		ServerRemoteRegistry.new(parent, TestRemoteDefinitions.folderName, TestRemoteDefinitions.definitions, logger)
	local registrationResult = lifecycleRegistry:Register({
		name = "CollisionRegistry",
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

	TestHarness.assertTrue(registrationResult.ok)
	TestHarness.assertTrue(lifecycleRegistry:InitAll().ok)
	local startResult = lifecycleRegistry:StartAll()
	TestHarness.assertTrue(not startResult.ok)
	if not startResult.ok then
		TestHarness.assertEqual(startResult.error.code, "LifecycleStartFailed")
	end
	TestHarness.assertTrue(existingRemote.Parent == remoteFolder)
	parent:Destroy()
end

local function remoteRuntimeTest()
	local logger = Logger.new("Test", "studio-runtime", "RemoteRegistryIntegration", true)
	local registry = LifecycleRegistry.new(nil)
	local remoteRegistry = ServerRemoteRegistry.new(
		ReplicatedStorage,
		TestRemoteDefinitions.folderName,
		TestRemoteDefinitions.definitions,
		logger
	)

	local completed = Instance.new("BindableEvent")
	local completionState: boolean? = nil
	local function complete(value: boolean)
		if completionState ~= nil then
			return
		end
		completionState = value
		completed:Fire(value)
	end
	local timeoutThread: thread? = nil
	local scenarioOk, scenarioCause = xpcall(function()
		local registrationResult = registry:Register({
			name = "TestServerRemoteRegistry",
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
		TestHarness.assertTrue(registrationResult.ok)
		TestHarness.assertTrue(registry:InitAll().ok)
		TestHarness.assertTrue(registry:StartAll().ok)

		local callbackCount = 0
		local eventBindingResult = remoteRegistry:BindEvent("TestRequest", function(_player, payload)
			callbackCount += 1
			TestHarness.assertTrue(typeof(payload) == "table")
			complete(true)
		end)
		TestHarness.assertTrue(eventBindingResult.ok)

		local duplicateBindingResult = remoteRegistry:BindEvent("TestRequest", function(_player, _payload) end)
		TestHarness.assertTrue(not duplicateBindingResult.ok)

		local functionBindingResult = remoteRegistry:BindFunction("TestFunction", function(_player, _payload)
			return { ok = true }
		end)
		TestHarness.assertTrue(functionBindingResult.ok)

		local remoteFolder = ReplicatedStorage:FindFirstChild(TestRemoteDefinitions.folderName)
		TestHarness.assertTrue(remoteFolder ~= nil and remoteFolder:IsA("Folder"))
		if remoteFolder == nil or not remoteFolder:IsA("Folder") then
			return
		end

		local ready = Instance.new("BoolValue")
		ready.Name = "Ready"
		ready.Value = true
		ready.Parent = remoteFolder

		timeoutThread = task.delay(TEST_CLIENT_SESSION_TIMEOUT_SECONDS, function()
			complete(false)
		end)
		local receivedValidRequest: unknown = completionState
		if receivedValidRequest == nil then
			receivedValidRequest = completed.Event:Wait()
		end

		TestHarness.assertTrue(receivedValidRequest == true, "Timed out waiting for the test client")
		TestHarness.assertEqual(callbackCount, 1, "Only the valid event payload should reach the handler")
	end, tracebackError)

	if timeoutThread ~= nil then
		pcall(task.cancel, timeoutThread)
	end
	registry:DestroyAll()
	completed:Destroy()
	TestHarness.assertTrue(ReplicatedStorage:FindFirstChild(TestRemoteDefinitions.folderName) == nil)
	if not scenarioOk then
		error(scenarioCause)
	end
end

function RemoteRegistryIntegrationSpec.tests(): { TestCase }
	return {
		{ name = "remote definitions reject duplicates", run = duplicateRemoteDefinitionTest },
		{ name = "server remote registry rejects Instance collisions", run = duplicateRemoteInstanceTest },
		{ name = "server remote registry validates client runtime requests", run = remoteRuntimeTest },
	}
end

return table.freeze(RemoteRegistryIntegrationSpec)
