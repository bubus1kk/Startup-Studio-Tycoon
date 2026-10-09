--!strict

local EmployeeRemoteTypes = require(game:GetService("ReplicatedStorage").Shared.Types.EmployeeRemoteTypes)
local Theme = require(script.Parent.EmployeesTheme)

type CandidateView = EmployeeRemoteTypes.CandidateView
type EmployeeView = EmployeeRemoteTypes.EmployeeView

export type TeamActions = { reassign: TextButton, dismiss: TextButton }

type ViewData = {
	_gui: ScreenGui,
	_panel: Frame,
	_cards: ScrollingFrame,
	_employeesButton: TextButton,
	_closeButton: TextButton,
	_candidateTab: TextButton,
	_teamTab: TextButton,
	_refreshButton: TextButton,
	_previousButton: TextButton,
	_nextButton: TextButton,
	_statusLabel: TextLabel,
	_headerLabel: TextLabel,
	_pageLabel: TextLabel,
	_countdownLabels: { [string]: TextLabel },
	_countdownButtons: { [string]: TextButton },
}

local EmployeesView = {}
EmployeesView.__index = EmployeesView
export type View = typeof(setmetatable({} :: ViewData, EmployeesView))

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextLabel
	local value = Instance.new("TextLabel")
	value.Name = name
	value.BackgroundTransparency = 1
	value.Size = size
	value.Position = position
	value.Font = Theme.font
	value.Text = text
	value.TextColor3 = Theme.text
	value.TextSize = 15
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = parent
	return value
end

local function button(parent: Instance, name: string, text: string, size: UDim2, position: UDim2): TextButton
	local value = Instance.new("TextButton")
	value.Name = name
	value.Size = size
	value.Position = position
	value.BackgroundColor3 = Theme.accent
	value.Font = Theme.fontBold
	value.Text = text
	value.TextColor3 = Theme.text
	value.TextSize = 14
	value.Parent = parent
	corner(value, 8)
	return value
end

function EmployeesView.new(playerGui: PlayerGui): View
	local existing = playerGui:FindFirstChild("EmployeesGui")
	if existing ~= nil then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "EmployeesGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 21
	gui.Parent = playerGui
	local employeesButton =
		button(gui, "EmployeesButton", "EMPLOYEES  [E]", UDim2.fromOffset(170, 46), UDim2.new(0, 22, 1, -124))
	local panel = Instance.new("Frame")
	panel.Name = "EmployeesPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.82, 0.8)
	panel.BackgroundColor3 = Theme.background
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(760, 500)
	constraint.MaxSize = Vector2.new(1180, 780)
	constraint.Parent = panel
	local title = label(panel, "Title", "EMPLOYEES", UDim2.fromOffset(230, 40), UDim2.fromOffset(22, 12))
	title.Font = Theme.fontBold
	title.TextSize = 24
	local header = label(panel, "Header", "Cash: —", UDim2.new(1, -330, 0, 32), UDim2.fromOffset(220, 17))
	header.TextXAlignment = Enum.TextXAlignment.Right
	local closeButton = button(panel, "Close", "×", UDim2.fromOffset(38, 38), UDim2.new(1, -52, 0, 12))
	closeButton.BackgroundColor3 = Theme.card
	closeButton.TextSize = 24
	local candidateTab =
		button(panel, "CandidatesTab", "CANDIDATES", UDim2.fromOffset(150, 38), UDim2.fromOffset(20, 66))
	local teamTab = button(panel, "TeamTab", "TEAM", UDim2.fromOffset(120, 38), UDim2.fromOffset(180, 66))
	teamTab.BackgroundColor3 = Theme.card
	local refreshButton = button(panel, "Refresh", "REFRESH", UDim2.fromOffset(150, 38), UDim2.new(1, -170, 0, 66))
	refreshButton.BackgroundColor3 = Theme.accentSecondary
	local cards = Instance.new("ScrollingFrame")
	cards.Name = "Cards"
	cards.Position = UDim2.fromOffset(20, 116)
	cards.Size = UDim2.new(1, -40, 1, -202)
	cards.BackgroundColor3 = Theme.panel
	cards.BorderSizePixel = 0
	cards.ScrollBarThickness = 6
	cards.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cards.CanvasSize = UDim2.new()
	cards.Parent = panel
	corner(cards, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = cards
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.Parent = cards
	local previous = button(panel, "Previous", "‹ PREV", UDim2.fromOffset(100, 36), UDim2.new(0, 20, 1, -62))
	local pageLabel = label(panel, "Page", "Page 1 / 1", UDim2.fromOffset(130, 36), UDim2.new(0, 130, 1, -62))
	pageLabel.TextXAlignment = Enum.TextXAlignment.Center
	local nextButton = button(panel, "Next", "NEXT ›", UDim2.fromOffset(100, 36), UDim2.new(0, 270, 1, -62))
	local status = label(panel, "Status", "", UDim2.new(1, -410, 0, 36), UDim2.new(0, 390, 1, -62))
	status.TextXAlignment = Enum.TextXAlignment.Right
	return setmetatable({
		_gui = gui,
		_panel = panel,
		_cards = cards,
		_employeesButton = employeesButton,
		_closeButton = closeButton,
		_candidateTab = candidateTab,
		_teamTab = teamTab,
		_refreshButton = refreshButton,
		_previousButton = previous,
		_nextButton = nextButton,
		_statusLabel = status,
		_headerLabel = header,
		_pageLabel = pageLabel,
		_countdownLabels = {},
		_countdownButtons = {},
	}, EmployeesView)
end

function EmployeesView.SetOpen(self: View, value: boolean)
	self._panel.Visible = value
end
function EmployeesView.IsOpen(self: View): boolean
	return self._panel.Visible
end
function EmployeesView.SetReady(self: View, ready: boolean)
	self._employeesButton.Active = ready
	self._employeesButton.BackgroundColor3 = if ready then Theme.accent else Theme.cardMuted
	self._employeesButton.Text = if ready then "EMPLOYEES  [E]" else "TEAM LOADING"
	if not ready then
		self._panel.Visible = false
	end
end
function EmployeesView.SetTab(self: View, tab: string)
	self._candidateTab.BackgroundColor3 = if tab == "Candidates" then Theme.accent else Theme.card
	self._teamTab.BackgroundColor3 = if tab == "Team" then Theme.accent else Theme.card
	self._refreshButton.Visible = tab == "Candidates"
end
function EmployeesView.SetHeader(self: View, cash: number, payroll: number, refresh: number)
	self._headerLabel.Text = `Cash: ${cash}  •  Payroll: {math.ceil(payroll)}s`
	self._refreshButton.Active = refresh <= 0
	self._refreshButton.Text = if refresh <= 0 then "REFRESH" else `REFRESH {math.ceil(refresh)}s`
	self._refreshButton.BackgroundColor3 = if refresh <= 0 then Theme.accentSecondary else Theme.cardMuted
end
function EmployeesView.SetPage(self: View, page: number, pageCount: number)
	self._pageLabel.Text = if pageCount == 0 then "No employees" else `Page {page} / {pageCount}`
	self._previousButton.Active = page > 1
	self._nextButton.Active = pageCount > 0 and page < pageCount
end
function EmployeesView.SetStatus(self: View, text: string, isError: boolean)
	self._statusLabel.Text = text
	self._statusLabel.TextColor3 = if isError then Theme.error else Theme.success
end
function EmployeesView.ClearCards(self: View)
	for _, child in self._cards:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(self._countdownLabels)
	table.clear(self._countdownButtons)
end

function EmployeesView.RenderCandidates(self: View, candidates: { CandidateView }): { [string]: TextButton }
	self:ClearCards()
	local buttons = {}
	for _, candidate in candidates do
		local card = Instance.new("Frame")
		card.Name = candidate.candidateId
		card.Size = UDim2.new(1, 0, 0, 126)
		card.BackgroundColor3 = Theme.card
		card.Parent = self._cards
		corner(card, 9)
		local name = label(
			card,
			"Name",
			`{candidate.displayName} — {candidate.roleId}`,
			UDim2.new(0.58, 0, 0, 26),
			UDim2.fromOffset(14, 9)
		)
		name.Font = Theme.fontBold
		name.TextSize = 17
		label(
			card,
			"GradeTrait",
			`{candidate.grade} • {candidate.traitId}`,
			UDim2.new(0.62, 0, 0, 22),
			UDim2.fromOffset(14, 36)
		).TextColor3 =
			Theme.mutedText
		label(
			card,
			"Stats",
			`Speed {candidate.speed}  Quality {candidate.quality}  Reliability {candidate.reliability}`,
			UDim2.new(0.68, 0, 0, 22),
			UDim2.fromOffset(14, 61)
		)
		label(
			card,
			"Cost",
			`Hire ${candidate.hiringCost}  •  Salary ${candidate.salaryPerCycle}/60s`,
			UDim2.new(0.68, 0, 0, 22),
			UDim2.fromOffset(14, 88)
		).TextColor3 =
			Theme.mutedText
		local countdown = label(
			card,
			"Expiry",
			`{math.ceil(candidate.expiresInSeconds)}s`,
			UDim2.fromOffset(90, 22),
			UDim2.new(1, -270, 0, 13)
		)
		countdown.TextXAlignment = Enum.TextXAlignment.Right
		countdown:SetAttribute("Remaining", candidate.expiresInSeconds)
		self._countdownLabels[candidate.candidateId] = countdown
		local hire = button(card, "Hire", "HIRE", UDim2.fromOffset(150, 42), UDim2.new(1, -166, 0.5, -21))
		buttons[candidate.candidateId] = hire
		self._countdownButtons[candidate.candidateId] = hire
	end
	return buttons
end

function EmployeesView.TickCountdowns(self: View, deltaSeconds: number)
	for candidateId, countdown in self._countdownLabels do
		local remaining = math.max(0, (countdown:GetAttribute("Remaining") :: number? or 0) - deltaSeconds)
		countdown:SetAttribute("Remaining", remaining)
		countdown.Text = `{math.ceil(remaining)}s`
		countdown.TextColor3 = if remaining <= 10 then Theme.warning else Theme.text
		local hire = self._countdownButtons[candidateId]
		if hire ~= nil and remaining <= 0 then
			hire.Active = false
			hire.Text = "EXPIRED"
			hire.BackgroundColor3 = Theme.cardMuted
		end
	end
end

function EmployeesView.RenderTeam(self: View, roster: { EmployeeView }): { [string]: TeamActions }
	self:ClearCards()
	local actions = {}
	for _, employee in roster do
		local card = Instance.new("Frame")
		card.Name = employee.employeeId
		card.Size = UDim2.new(1, 0, 0, 132)
		card.BackgroundColor3 = Theme.card
		card.Parent = self._cards
		corner(card, 9)
		local name = label(
			card,
			"Name",
			`{employee.displayName} — {employee.roleId}`,
			UDim2.new(0.56, 0, 0, 26),
			UDim2.fromOffset(14, 9)
		)
		name.Font = Theme.fontBold
		name.TextSize = 17
		label(
			card,
			"Career",
			`{employee.grade} L{employee.level}  XP {math.floor(employee.xp)}/{math.floor(employee.requiredXp)}  •  {employee.traitId}`,
			UDim2.new(0.67, 0, 0, 22),
			UDim2.fromOffset(14, 36)
		).TextColor3 =
			Theme.mutedText
		label(
			card,
			"Stats",
			`Speed {employee.speed}  Quality {employee.quality}  Reliability {employee.reliability}`,
			UDim2.new(0.67, 0, 0, 22),
			UDim2.fromOffset(14, 61)
		)
		label(
			card,
			"State",
			`Morale {math.floor(employee.morale)}  •  {employee.status}  •  {employee.assignedWorkstationId or "Unassigned"}`,
			UDim2.new(0.67, 0, 0, 36),
			UDim2.fromOffset(14, 86)
		).TextColor3 =
			Theme.mutedText
		local reassign = button(card, "Reassign", "REASSIGN", UDim2.fromOffset(136, 38), UDim2.new(1, -292, 0.5, -19))
		reassign.BackgroundColor3 = Theme.accentSecondary
		local dismiss = button(card, "Dismiss", "DISMISS", UDim2.fromOffset(136, 38), UDim2.new(1, -146, 0.5, -19))
		dismiss.BackgroundColor3 = Theme.error
		actions[employee.employeeId] = { reassign = reassign, dismiss = dismiss }
	end
	return actions
end

function EmployeesView.MarkDismissConfirm(_self: View, buttonValue: TextButton)
	buttonValue.Text = "CONFIRM?"
	buttonValue.BackgroundColor3 = Theme.warning
end
function EmployeesView.GetEmployeesButton(self: View): TextButton
	return self._employeesButton
end
function EmployeesView.GetCloseButton(self: View): TextButton
	return self._closeButton
end
function EmployeesView.GetCandidateTab(self: View): TextButton
	return self._candidateTab
end
function EmployeesView.GetTeamTab(self: View): TextButton
	return self._teamTab
end
function EmployeesView.GetRefreshButton(self: View): TextButton
	return self._refreshButton
end
function EmployeesView.GetPreviousButton(self: View): TextButton
	return self._previousButton
end
function EmployeesView.GetNextButton(self: View): TextButton
	return self._nextButton
end
function EmployeesView.Destroy(self: View)
	self._gui:Destroy()
end

return table.freeze(EmployeesView)
