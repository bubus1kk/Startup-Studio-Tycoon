--!strict

local Theme = require(script.Parent.BuildMenuTheme)

export type CatalogItem = {
	itemId: string,
	displayName: string,
	description: string,
	price: number,
	state: string,
	lockText: string?,
	currentLevel: number?,
	maxLevel: number?,
}

type ViewData = {
	_gui: ScreenGui,
	_panel: Frame,
	_cards: ScrollingFrame,
	_cashLabel: TextLabel,
	_tierLabel: TextLabel,
	_pageLabel: TextLabel,
	_statusLabel: TextLabel,
	_buildButton: TextButton,
	_closeButton: TextButton,
	_previousButton: TextButton,
	_nextButton: TextButton,
	_categoryButtons: { [string]: TextButton },
}

local BuildMenuView = {}
BuildMenuView.__index = BuildMenuView
export type View = typeof(setmetatable({} :: ViewData, BuildMenuView))

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
	value.TextSize = 16
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
	value.AutoButtonColor = true
	value.Font = Theme.fontBold
	value.Text = text
	value.TextColor3 = Theme.text
	value.TextSize = 15
	value.Parent = parent
	corner(value, 8)
	return value
end

function BuildMenuView.new(playerGui: PlayerGui): View
	local gui = Instance.new("ScreenGui")
	gui.Name = "OfficeBuildGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 20
	gui.Parent = playerGui

	local buildButton = button(gui, "BuildButton", "BUILD  [B]", UDim2.fromOffset(146, 46), UDim2.new(0, 22, 1, -70))
	buildButton.BackgroundColor3 = Theme.accent

	local panel = Instance.new("Frame")
	panel.Name = "BuildPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.78, 0.78)
	panel.BackgroundColor3 = Theme.background
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 14)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(760, 500)
	sizeConstraint.MaxSize = Vector2.new(1120, 760)
	sizeConstraint.Parent = panel

	local title = label(panel, "Title", "OFFICE BUILDER", UDim2.new(0.5, 0, 0, 46), UDim2.fromOffset(22, 12))
	title.Font = Theme.fontBold
	title.TextSize = 24
	local cashLabel = label(panel, "Cash", "Cash: —", UDim2.fromOffset(190, 30), UDim2.new(1, -420, 0, 19))
	local tierLabel = label(panel, "Tier", "Tier: —", UDim2.fromOffset(190, 30), UDim2.new(1, -230, 0, 19))
	local closeButton = button(panel, "Close", "×", UDim2.fromOffset(38, 38), UDim2.new(1, -52, 0, 12))
	closeButton.TextSize = 24
	closeButton.BackgroundColor3 = Theme.card

	local tabs = Instance.new("Frame")
	tabs.Name = "Categories"
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.fromOffset(20, 66)
	tabs.Size = UDim2.new(1, -40, 0, 42)
	tabs.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabs
	local categoryButtons = {}
	for _, category in { "Tiers", "Rooms", "Equipment", "Furniture", "Upgrades" } do
		local categoryButton = button(tabs, category, category, UDim2.new(0.2, -7, 1, 0), UDim2.new())
		categoryButton.BackgroundColor3 = Theme.card
		categoryButtons[category] = categoryButton
	end

	local cards = Instance.new("ScrollingFrame")
	cards.Name = "Items"
	cards.Position = UDim2.fromOffset(20, 122)
	cards.Size = UDim2.new(1, -40, 1, -206)
	cards.BackgroundColor3 = Theme.panel
	cards.BorderSizePixel = 0
	cards.ScrollBarThickness = 6
	cards.AutomaticCanvasSize = Enum.AutomaticSize.Y
	cards.CanvasSize = UDim2.new()
	cards.Parent = panel
	corner(cards, 10)
	local cardsPadding = Instance.new("UIPadding")
	cardsPadding.PaddingTop = UDim.new(0, 12)
	cardsPadding.PaddingBottom = UDim.new(0, 12)
	cardsPadding.PaddingLeft = UDim.new(0, 12)
	cardsPadding.PaddingRight = UDim.new(0, 12)
	cardsPadding.Parent = cards
	local cardsLayout = Instance.new("UIListLayout")
	cardsLayout.Padding = UDim.new(0, 10)
	cardsLayout.Parent = cards

	local previousButton =
		button(panel, "PreviousPage", "‹ PREV", UDim2.fromOffset(100, 36), UDim2.new(0, 20, 1, -64))
	local pageLabel = label(panel, "Page", "Page 1 / 1", UDim2.fromOffset(140, 36), UDim2.new(0, 132, 1, -64))
	pageLabel.TextXAlignment = Enum.TextXAlignment.Center
	local nextButton = button(panel, "NextPage", "NEXT ›", UDim2.fromOffset(100, 36), UDim2.new(0, 284, 1, -64))
	local statusLabel = label(panel, "Status", "", UDim2.new(1, -430, 0, 36), UDim2.new(0, 414, 1, -64))
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right

	return setmetatable({
		_gui = gui,
		_panel = panel,
		_cards = cards,
		_cashLabel = cashLabel,
		_tierLabel = tierLabel,
		_pageLabel = pageLabel,
		_statusLabel = statusLabel,
		_buildButton = buildButton,
		_closeButton = closeButton,
		_previousButton = previousButton,
		_nextButton = nextButton,
		_categoryButtons = categoryButtons,
	}, BuildMenuView)
end

function BuildMenuView.SetOpen(self: View, isOpen: boolean)
	self._panel.Visible = isOpen
end

function BuildMenuView.IsOpen(self: View): boolean
	return self._panel.Visible
end

function BuildMenuView.SetReady(self: View, isReady: boolean)
	self._buildButton.Active = isReady
	self._buildButton.BackgroundColor3 = if isReady then Theme.accent else Theme.cardLocked
	self._buildButton.Text = if isReady then "BUILD  [B]" else "OFFICE LOADING"
	if not isReady then
		self._panel.Visible = false
	end
end

function BuildMenuView.SetHeader(self: View, cash: number, tierId: string)
	self._cashLabel.Text = `Cash: ${cash}`
	self._tierLabel.Text = `Tier: {string.gsub(tierId, "tier_", "")}`
end

function BuildMenuView.SetPage(self: View, page: number, pageCount: number)
	self._pageLabel.Text = if pageCount == 0 then "No items" else `Page {page} / {pageCount}`
	self._previousButton.Active = page > 1
	self._nextButton.Active = pageCount > 0 and page < pageCount
end

function BuildMenuView.SetCategory(self: View, selected: string)
	for category, categoryButton in self._categoryButtons do
		categoryButton.BackgroundColor3 = if category == selected then Theme.accent else Theme.card
	end
end

function BuildMenuView.SetStatus(self: View, text: string, isError: boolean)
	self._statusLabel.Text = text
	self._statusLabel.TextColor3 = if isError then Theme.error else Theme.success
end

function BuildMenuView.ClearItems(self: View)
	for _, child in self._cards:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

function BuildMenuView.RenderItems(self: View, items: { CatalogItem }): { [string]: TextButton }
	self:ClearItems()
	local buttons = {}
	for _, item in items do
		local card = Instance.new("Frame")
		card.Name = item.itemId
		card.Size = UDim2.new(1, 0, 0, 112)
		card.BackgroundColor3 = if item.state == "Locked" then Theme.cardLocked else Theme.card
		card.Parent = self._cards
		corner(card, 9)
		local name = label(card, "Name", item.displayName, UDim2.new(0.58, 0, 0, 28), UDim2.fromOffset(14, 10))
		name.Font = Theme.fontBold
		name.TextSize = 18
		local description =
			label(card, "Description", item.description, UDim2.new(0.65, 0, 0, 42), UDim2.fromOffset(14, 40))
		description.TextWrapped = true
		description.TextSize = 13
		description.TextColor3 = Theme.mutedText
		local details = item.lockText or item.state
		if item.currentLevel ~= nil and item.maxLevel ~= nil then
			details = `{details} • Level {item.currentLevel}/{item.maxLevel}`
		end
		local stateLabel = label(card, "State", details, UDim2.new(0.65, 0, 0, 22), UDim2.fromOffset(14, 84))
		stateLabel.TextSize = 12
		stateLabel.TextColor3 = if item.state == "Locked" then Theme.warning else Theme.mutedText
		local action = button(
			card,
			"Action",
			if item.state == "Available" then `$ {item.price}` else item.state,
			UDim2.fromOffset(156, 42),
			UDim2.new(1, -172, 0.5, -21)
		)
		action.Active = item.state == "Available"
		action.BackgroundColor3 = if item.state == "Available" then Theme.accent else Theme.cardLocked
		buttons[item.itemId] = action
	end
	return buttons
end

function BuildMenuView.GetBuildButton(self: View): TextButton
	return self._buildButton
end
function BuildMenuView.GetCloseButton(self: View): TextButton
	return self._closeButton
end
function BuildMenuView.GetPreviousButton(self: View): TextButton
	return self._previousButton
end
function BuildMenuView.GetNextButton(self: View): TextButton
	return self._nextButton
end
function BuildMenuView.GetCategoryButtons(self: View): { [string]: TextButton }
	return self._categoryButtons
end
function BuildMenuView.Destroy(self: View)
	self._gui:Destroy()
end

return table.freeze(BuildMenuView)
