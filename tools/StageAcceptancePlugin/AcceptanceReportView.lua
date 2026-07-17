--!strict

local AcceptanceTypes = require(script.Parent.AcceptanceTypes)

type Result = AcceptanceTypes.Result

type ViewData = {
	widget: DockWidgetPluginGui,
	statusLabel: TextLabel,
	summaryLabel: TextLabel,
	detailsLabel: TextLabel,
}

local AcceptanceReportView = {}
AcceptanceReportView.__index = AcceptanceReportView
export type View = typeof(setmetatable({} :: ViewData, AcceptanceReportView))

local STATUS_COLORS = {
	PASS = Color3.fromRGB(72, 190, 118),
	FAIL = Color3.fromRGB(232, 86, 86),
	SKIPPED = Color3.fromRGB(229, 180, 72),
	RUNNING = Color3.fromRGB(86, 156, 232),
}

local function createLabel(parent: Instance, name: string, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextColor3 = Color3.fromRGB(230, 234, 241)
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

function AcceptanceReportView.new(plugin: Plugin): View
	local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 720, 520, 480, 320)
	local widget = plugin:CreateDockWidgetPluginGui("StartupStudioStage4Acceptance", info)
	widget.Title = "Startup Studio — Stage 4 Acceptance"
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(27, 31, 40)
	root.Parent = widget
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = root

	local statusLabel = createLabel(root, "Status", 24)
	statusLabel.Font = Enum.Font.SourceSansBold
	statusLabel.Size = UDim2.new(1, 0, 0, 36)
	statusLabel.Text = "READY"
	statusLabel.TextColor3 = STATUS_COLORS.RUNNING
	local summaryLabel = createLabel(root, "Summary", 16)
	summaryLabel.Position = UDim2.fromOffset(0, 42)
	summaryLabel.Size = UDim2.new(1, 0, 0, 54)
	summaryLabel.Text = "Choose a Stage 4 acceptance suite from the toolbar."
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Details"
	scroll.Position = UDim2.fromOffset(0, 104)
	scroll.Size = UDim2.new(1, 0, 1, -104)
	scroll.BackgroundColor3 = Color3.fromRGB(20, 23, 30)
	scroll.BorderSizePixel = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 7
	scroll.Parent = root
	local detailsLabel = createLabel(scroll, "Report", 14)
	detailsLabel.Position = UDim2.fromOffset(10, 10)
	detailsLabel.Size = UDim2.new(1, -20, 0, 0)
	detailsLabel.AutomaticSize = Enum.AutomaticSize.Y
	detailsLabel.Text = "No report yet."

	return setmetatable({
		widget = widget,
		statusLabel = statusLabel,
		summaryLabel = summaryLabel,
		detailsLabel = detailsLabel,
	}, AcceptanceReportView)
end

function AcceptanceReportView.ShowRunning(self: View, displayName: string)
	self.widget.Enabled = true
	self.statusLabel.Text = "RUNNING"
	self.statusLabel.TextColor3 = STATUS_COLORS.RUNNING
	self.summaryLabel.Text = `{displayName} is running. Other toolbar actions are disabled.`
	self.detailsLabel.Text = "Waiting for StudioTestService:EndTest(result)…"
end

function AcceptanceReportView.ShowResult(self: View, result: Result)
	self.widget.Enabled = true
	local status = AcceptanceTypes.Status(result)
	self.statusLabel.Text = status
	self.statusLabel.TextColor3 = STATUS_COLORS[status] or STATUS_COLORS.FAIL
	self.summaryLabel.Text = string.format(
		"%s — %.3fs — total %d / passed %d / failed %d / skipped %d",
		result.suite,
		result.durationSeconds,
		result.total,
		result.passed,
		result.failed,
		result.skipped
	)
	self.detailsLabel.Text = AcceptanceTypes.Format(result)
end

return table.freeze(AcceptanceReportView)
