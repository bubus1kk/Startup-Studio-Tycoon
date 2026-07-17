--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local ConfigLoader = require(ReplicatedStorage.Shared.Config.ConfigLoader)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local OfficeRemoteTypes = require(ReplicatedStorage.Shared.Types.OfficeRemoteTypes)
local OfficeConfigValidator = require(ServerScriptService.Config.OfficeConfigValidator)
local OfficeCatalog = require(ServerScriptService.Domain.OfficeCatalog)
local OfficePlacement = require(ServerScriptService.Domain.OfficePlacement)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)
local RequestRateLimiter = require(ServerScriptService.Security.RequestRateLimiter)
local OfficeBuildingService = require(ServerScriptService.Services.OfficeBuildingService)
local SessionCurrencyService = require(ServerScriptService.Services.SessionCurrencyService)
local OfficeLayoutBuilder = require(ServerScriptService.Systems.OfficeLayoutBuilder)
local OfficeDefinitions = require(ServerStorage.Config.OfficeDefinitions)
local PlotTestUtils = require(script.Parent.PlotTestUtils)

type BuildHook = OfficeLayoutBuilder.BuildHook
type DependencyResolver = LifecycleRegistry.DependencyResolver
type OfficeConfig = OfficeTypes.OfficeConfig
type OfficePurchaseResponse = OfficeRemoteTypes.OfficePurchaseResponse

export type Fixture = {
	userId: number,
	config: OfficeConfig,
	progression: OfficeProgression.Progression,
	catalog: OfficeCatalog.Catalog,
	placement: OfficePlacement.Placement,
	currency: SessionCurrencyService.Service,
	office: OfficeBuildingService.Service,
	plot: PlotTestUtils.Fixture,
	Purchase: (self: Fixture, itemId: string) -> OfficePurchaseResponse,
	Destroy: (self: Fixture) -> (),
}

local OfficeTestUtils = {}

function OfficeTestUtils.validatedConfig(): OfficeConfig
	local result =
		ConfigLoader.validateAndFreeze("OfficeDefinitions", OfficeDefinitions, OfficeConfigValidator.validate)
	if not result.ok then
		error(`Office test config failed validation: {result.error.code}`)
	end
	return result.value
end

<<<<<<< HEAD
function OfficeTestUtils.createFixture(
	userId: number,
	buildHook: BuildHook?,
	initialCash: number?,
	configOverride: OfficeConfig?
): Fixture
	local config = configOverride or OfficeTestUtils.validatedConfig()
=======
function OfficeTestUtils.createFixture(userId: number, buildHook: BuildHook?, initialCash: number?): Fixture
	local config = OfficeTestUtils.validatedConfig()
>>>>>>> 94818332a6f52a94409e8f7b68c861c2ad26d4b6
	local progression = OfficeProgression.new(config)
	local catalog = OfficeCatalog.new(config, progression)
	local placement = OfficePlacement.new(progression)
	local templates = ServerStorage:FindFirstChild("OfficeTemplates")
	if templates == nil then
		error("OfficeTemplates missing from test DataModel")
	end
	local builder = OfficeLayoutBuilder.new(templates, config, progression, placement, buildHook)
	local logger = Logger.new("Test", "runtime", "OfficeTestFixture", true)
	local limiterClock = 0
	local limiter = RequestRateLimiter.new(function(): number
		limiterClock += 1
		return limiterClock
	end)
	local currency = SessionCurrencyService.new(initialCash or 250000)
	local emptyResolver: DependencyResolver = {
		Get = function(_self: DependencyResolver, _name: string): unknown
			return nil
		end,
		Require = function(_self: DependencyResolver, name: string): unknown
			error(`Unexpected dependency: {name}`)
		end,
	}
	currency:Init(emptyResolver)
	currency:Start()
	local plot = PlotTestUtils.createFixture(nil)
	local assignment = plot.service:AssignPlayer(userId)
	if not assignment.ok then
		error(`Plot assignment failed: {assignment.error.code}`)
	end
	local office = OfficeBuildingService.new(config, progression, catalog, builder, limiter, logger)
	local function dependency(name: string): unknown
		if name == "PlotService" then
			return plot.service
		elseif name == "SessionCurrencyService" then
			return currency
		elseif name == "ServerRemoteRegistry" then
			return {}
		end
		return nil
	end
	local resolver: DependencyResolver = {
		Get = function(_self: DependencyResolver, name: string): unknown
			return dependency(name)
		end,
		Require = function(_self: DependencyResolver, name: string): unknown
			local value = dependency(name)
			if value == nil then
				error(`Missing test dependency {name}`)
			end
			return value
		end,
	}
	office:Init(resolver)
	local openResult = currency:OpenSession(userId)
	if not openResult.ok then
		error(`Currency open failed: {openResult.error.code}`)
	end
	local prepareResult = office:PrepareSession(userId, nil)
	if not prepareResult.ok then
		error(`Office prepare failed: {prepareResult.error.code}`)
	end

	local requestIndex = 0
	local fixture: Fixture
	fixture = {
		userId = userId,
		config = config,
		progression = progression,
		catalog = catalog,
		placement = placement,
		currency = currency,
		office = office,
		plot = plot,
		Purchase = function(self: Fixture, itemId: string): OfficePurchaseResponse
			requestIndex += 1
			return self.office:Purchase(self.userId, {
				requestId = `test-{requestIndex}`,
				itemId = itemId,
			})
		end,
		Destroy = function(self: Fixture)
			self.office:Destroy()
			self.currency:Destroy()
			self.plot:Destroy()
		end,
	}
	return fixture
end

function OfficeTestUtils.purchaseDiagnostic(itemId: string, response: OfficePurchaseResponse): string
	local errorCode = if response.error ~= nil then response.error.code else "none"
	local errorMessage = if response.error ~= nil then response.error.message else "none"
	return `itemId={itemId}; error.code={errorCode}; error.message={errorMessage}; state={response.state}; currentTierId={response.currentTierId}; revision={response.revision}; Cash={response.cash}`
end

function OfficeTestUtils.fullProgressionOrder(config: OfficeConfig): { string }
	local order = {
		"room_development",
		"room_design",
		"tier_small_loft",
		"room_qa",
		"room_marketing",
		"room_meeting",
		"tier_downtown",
		"room_server",
		"room_recreation",
		"tier_tech_campus",
		"room_executive",
		"room_research",
		"tier_global_hq",
	}
	for _, item in config.items do
		if item.kind == "Equipment" then
			table.insert(order, item.id)
		end
	end
	for _, item in config.items do
		if item.kind == "Furniture" then
			table.insert(order, item.id)
		end
	end
	for _, upgrade in config.upgrades do
		table.insert(order, upgrade.id)
		table.insert(order, upgrade.id)
	end
	return order
end

return table.freeze(OfficeTestUtils)
