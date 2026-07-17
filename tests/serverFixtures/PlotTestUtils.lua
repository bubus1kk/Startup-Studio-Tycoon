--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local ConfigLoader = require(ReplicatedStorage.Shared.Config.ConfigLoader)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local PlotConfigValidator = require(ServerScriptService.Config.PlotConfigValidator)
local PlotService = require(ServerScriptService.Services.PlotService)
local PlotRuntimeBuilder = require(ServerScriptService.Systems.PlotRuntimeBuilder)
local PlotDefinitions = require(ServerStorage.Config.PlotDefinitions)

export type Fixture = {
	root: Folder,
	service: PlotService.Service,
	registry: LifecycleRegistry.Registry,
	config: PlotConfigValidator.PlotConfig,
	Destroy: (self: Fixture) -> (),
}

local PlotTestUtils = {}

function PlotTestUtils.validatedConfig(): PlotConfigValidator.PlotConfig
	local result = ConfigLoader.validateAndFreeze("TestPlotDefinitions", PlotDefinitions, PlotConfigValidator.validate)
	if not result.ok then
		error(`Test plot configuration is invalid: {result.error.code}`)
	end
	return result.value
end

function PlotTestUtils.createFixture(partCreationHook: PlotRuntimeBuilder.PartCreationHook?): Fixture
	local root = Instance.new("Folder")
	root.Name = "PlotTestRuntime"
	local logger = Logger.new("Test", "studio-runtime", "PlotTestFixture", true)
	local config = PlotTestUtils.validatedConfig()
	local service = PlotService.new(root, config, PlotRuntimeBuilder.new(partCreationHook), logger)
	local registry = LifecycleRegistry.new(nil)
	local registrationResult = registry:Register({
		name = "PlotService",
		dependencies = {},
		value = service,
		hooks = {
			Init = function(dependencies)
				service:Init(dependencies)
			end,
			Start = function()
				service:Start()
			end,
			Destroy = function()
				service:Destroy()
			end,
		},
	})
	if not registrationResult.ok then
		error(`Could not register test PlotService: {registrationResult.error.code}`)
	end
	local initResult = registry:InitAll()
	if not initResult.ok then
		error(`Could not initialize test PlotService: {initResult.error.code}`)
	end
	local startResult = registry:StartAll()
	if not startResult.ok then
		error(`Could not start test PlotService: {startResult.error.code}`)
	end

	local fixture: Fixture = {
		root = root,
		service = service,
		registry = registry,
		config = config,
		Destroy = function(self: Fixture)
			self.registry:DestroyAll()
			self.root:Destroy()
		end,
	}

	return fixture
end

return table.freeze(PlotTestUtils)
