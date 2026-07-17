--!strict

local AcceptanceReportView = require(script.Parent.AcceptanceReportView)
local AcceptanceRunGuard = require(script.Parent.AcceptanceRunGuard)
local AcceptanceRunner = require(script.Parent.AcceptanceRunner)
local AcceptanceTypes = require(script.Parent.AcceptanceTypes)

local toolbar = plugin:CreateToolbar("Startup Studio Tests")
local view = AcceptanceReportView.new(plugin)
local runner = AcceptanceRunner.new()

local buttonDefinitions = {
	{ id = "Stage4Runtime", text = "Stage 4 Runtime", tooltip = "Run Stage 1–4 runtime specs", run = "Runtime" },
	{ id = "Stage4Solo", text = "Stage 4 Solo", tooltip = "Run Stage 4 solo acceptance", run = "Solo" },
	{
		id = "Stage4Multiplayer3",
		text = "Stage 4 Multiplayer 3",
		tooltip = "Run Stage 4 acceptance with three clients",
		run = "Multiplayer3",
	},
	{
		id = "Stage4Performance6",
		text = "Stage 4 Performance 6",
		tooltip = "Run Stage 4 maximum-content performance with six clients",
		run = "Performance6",
	},
	{ id = "Stage4Full", text = "Stage 4 Full", tooltip = "Run all Stage 4 acceptance suites", run = "Full" },
}

local buttons: { PluginToolbarButton } = {}

local function setButtonsEnabled(enabled: boolean)
	for _, button in buttons do
		button.Enabled = enabled
	end
end

local runGuard = AcceptanceRunGuard.new(setButtonsEnabled)

local function execute(runName: string, displayName: string)
	if not runGuard:Begin() then
		warn("[StageAcceptancePlugin] A Stage 4 acceptance run is already active")
		return
	end
	local runningViewOk, runningViewError = pcall(function()
		view:ShowRunning(displayName)
	end)
	if not runningViewOk then
		warn(`[StageAcceptancePlugin] Could not render running state: {tostring(runningViewError)}`)
	end
	task.spawn(function()
		local ok, value = runGuard:RunActive(function(): AcceptanceTypes.Result
			return runner:Run(runName)
		end)
		local result: AcceptanceTypes.Result
		if ok then
			result = value :: AcceptanceTypes.Result
		else
			local detail = value :: AcceptanceRunGuard.ErrorDetail
			result = AcceptanceTypes.FailureResult("Stage4Plugin", "plugin call", detail.message, detail.traceback)
			warn(AcceptanceTypes.Format(result))
		end
		local resultViewOk, resultViewError = pcall(function()
			view:ShowResult(result)
		end)
		if not resultViewOk then
			warn(`[StageAcceptancePlugin] Could not render final report: {tostring(resultViewError)}`)
		end
	end)
end

for _, definition in buttonDefinitions do
	local button = toolbar:CreateButton(definition.id, definition.tooltip, "", definition.text)
	button.ClickableWhenViewportHidden = true
	table.insert(buttons, button)
	button.Click:Connect(function()
		execute(definition.run, definition.text)
	end)
end

print("[StageAcceptancePlugin] Startup Studio Tests toolbar ready")
