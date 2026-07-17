--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local OfficePlacement = require(ServerScriptService.Domain.OfficePlacement)
local OfficeProgression = require(ServerScriptService.Domain.OfficeProgression)
local OfficeLayoutBuilder = require(ServerScriptService.Systems.OfficeLayoutBuilder)
local TestHarness = require(script.Parent.Parent.TestHarness)
local FailureOfficeTemplates = require(script.Parent.Parent.ServerFixtures.FailureOfficeTemplates)
local OfficeTestUtils = require(script.Parent.Parent.ServerFixtures.OfficeTestUtils)
local PlotTestUtils = require(script.Parent.Parent.ServerFixtures.PlotTestUtils)

type TestCase = TestHarness.TestCase
local OfficeRollbackSpec = {}

local function generationFailureRestoresStateTest()
	local failTemplate: string? = nil
	local fixture = OfficeTestUtils.createFixture(5501, function(stage: string, id: string)
		if stage == "CloneTemplate" and id == failTemplate then
			error("injected office template failure")
		end
	end)
	local before = fixture.currency:GetBalance(fixture.userId, "Cash")
	failTemplate = "DevelopmentRoom"
	local response = fixture:Purchase("room_development")
	TestHarness.assertTrue(response.ok == false, OfficeTestUtils.purchaseDiagnostic("room_development", response))
	local after = fixture.currency:GetBalance(fixture.userId, "Cash")
	TestHarness.assertTrue(before.ok and after.ok and before.value == after.value)
	local layout = fixture.office:ExportLayout(fixture.userId)
	TestHarness.assertTrue(layout.ok and not layout.value.purchasedRooms.room_development)
	TestHarness.assertTrue(fixture.office:ValidateRuntimeState(fixture.userId).ok)
	fixture:Destroy()
end

local function orphanRootInvariantTest()
	local fixture = OfficeTestUtils.createFixture(5503, nil)
	local context = fixture.plot.service:GetOwnedPlotContextForUserId(fixture.userId)
	TestHarness.assertTrue(context.ok)
	if context.ok then
		local orphan = Instance.new("Model")
		orphan.Name = "OfficeBuildRoot__old__injected"
		orphan.Parent = context.value.model
		local invalid = fixture.office:ValidateRuntimeState(fixture.userId)
		TestHarness.assertTrue(not invalid.ok and invalid.error.code == "OrphanedOfficeRoot")
		orphan:Destroy()
		TestHarness.assertTrue(fixture.office:ValidateRuntimeState(fixture.userId).ok)
	end
	fixture:Destroy()
end

local function invalidTemplateDestroysPendingRootTest()
	local config = OfficeTestUtils.validatedConfig()
	local progression = OfficeProgression.new(config)
	local templates = FailureOfficeTemplates.missingPivot()
	local builder = OfficeLayoutBuilder.new(templates, config, progression, OfficePlacement.new(progression), nil)
	local plot = PlotTestUtils.createFixture(nil)
	TestHarness.assertTrue(plot.service:AssignPlayer(5502).ok)
	local context = plot.service:GetOwnedPlotContextForUserId(5502)
	TestHarness.assertTrue(context.ok)
	if context.ok then
		local result = builder:BuildReplacementRoot(context.value, progression:CreateInitialLayout())
		TestHarness.assertTrue(not result.ok and result.error.code == "TemplateInvalid")
		TestHarness.assertTrue(context.value.model:FindFirstChild("OfficeBuildRoot") == nil)
	end
	templates:Destroy()
	plot:Destroy()
end

function OfficeRollbackSpec.tests(): { TestCase }
	return {
		{
			name = "office generation failure rolls back Cash layout and roots",
			run = generationFailureRestoresStateTest,
		},
		{
			name = "invalid server template destroys uncommitted office root",
			run = invalidTemplateDestroysPendingRootTest,
		},
		{
			name = "office root invariant detects and recovers from cleanup orphan",
			run = orphanRootInvariantTest,
		},
	}
end
return table.freeze(OfficeRollbackSpec)
