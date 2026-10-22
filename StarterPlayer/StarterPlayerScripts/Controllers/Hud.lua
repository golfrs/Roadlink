-- RoadLink HUD: stats bar, toolbar, option cards, inspector, region & stats panels, notifications.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RoadConfig = require(Shared:WaitForChild("RoadConfig"))
local BuildingConfig = require(Shared:WaitForChild("BuildingConfig"))
local RegionConfig = require(Shared:WaitForChild("RegionConfig"))
local Grid = require(Shared:WaitForChild("Grid"))
local Rules = require(Shared:WaitForChild("Rules"))

local player = Players.LocalPlayer
local Hud = {}
local deps
local gui, uiScale
local blockers = {}
local refs = { tools = {} }
local currentMode = "Select"
local openModal
local toastOrder = 0

local C = {
	panel = Color3.fromRGB(21, 29, 35),
	panel2 = Color3.fromRGB(33, 44, 52),
	panel3 = Color3.fromRGB(50, 64, 74),
	stroke = Color3.fromRGB(80, 98, 108),
	text = Color3.fromRGB(238, 243, 240),
	muted = Color3.fromRGB(152, 168, 164),
	green = Color3.fromRGB(104, 204, 130),
	greenDark = Color3.fromRGB(42, 116, 74),
	gold = Color3.fromRGB(246, 198, 92),
	red = Color3.fromRGB(236, 100, 90),
	redDark = Color3.fromRGB(122, 44, 42),
}

local function make(className, props)
	local object = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for key, value in pairs(props) do
		object[key] = value
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local function corner(object, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = object })
end

local function stroke(object, color, transparency)
	return make("UIStroke", { Color = color or C.stroke, Transparency = transparency or 0.45, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = object })
end

local function padding(object, x, y)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, x), PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y or x), PaddingBottom = UDim.new(0, y or x), Parent = object,
	})
end

local function label(parent, props)
	local settings = {
		BackgroundTransparency = 1, TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Text = "", Parent = parent,
	}
	for key, value in pairs(props or {}) do
		settings[key] = value
	end
	return make("TextLabel", settings)
end

local function panel(parent, props)
	local settings = { BackgroundColor3 = C.panel, BackgroundTransparency = 0.04, BorderSizePixel = 0, Active = true, Parent = parent }
	for key, value in pairs(props or {}) do
		settings[key] = value
	end
	local frame = make("Frame", settings)
	corner(frame, 12)
	stroke(frame)
	return frame
end

local STYLES = {
	normal = { bg = C.panel2, line = C.stroke },
	primary = { bg = C.greenDark, line = C.green },
	danger = { bg = C.redDark, line = C.red },
}

local function setBase(btn, color)
	btn:SetAttribute("Base", color)
	btn.BackgroundColor3 = color
end

local function button(parent, props, styleName)
	local style = STYLES[styleName or "normal"]
	local settings = {
		AutoButtonColor = false, BackgroundColor3 = style.bg, BorderSizePixel = 0, Font = Enum.Font.GothamBold,
		TextSize = 13, TextColor3 = C.text, Parent = parent,
	}
	for key, value in pairs(props or {}) do
		settings[key] = value
	end
	local btn = make("TextButton", settings)
	btn:SetAttribute("Base", btn.BackgroundColor3)
	corner(btn, 9)
	stroke(btn, style.line, 0.35)
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = btn:GetAttribute("Base"):Lerp(Color3.new(1, 1, 1), 0.1)
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = btn:GetAttribute("Base")
	end)
	return btn
end

local function block(frame)
	table.insert(blockers, frame)
	return frame
end

local function isShown(object)
	local current = object
	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current ~= nil
end

-- True when a screen point (viewport coordinates) is over HUD that should swallow world clicks.
function Hud.isOverUi(position)
	for index = #blockers, 1, -1 do
		local frame = blockers[index]
		if not frame.Parent then
			table.remove(blockers, index)
		elseif isShown(frame) then
			local p, s = frame.AbsolutePosition, frame.AbsoluteSize
			if position.X >= p.X and position.X <= p.X + s.X and position.Y >= p.Y and position.Y <= p.Y + s.Y then
				return true
			end
		end
	end
	return false
end

local function statChip(parent, width, order, caption, color)
	local chip = panel(parent, { Size = UDim2.fromOffset(width, 50), LayoutOrder = order })
	padding(chip, 11, 6)
	label(chip, { Text = caption, TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 14) })
	local value = label(chip, {
		Text = "—", TextSize = 17, Font = Enum.Font.GothamBold, TextColor3 = color or C.text,
		Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return chip, value
end

local function buildTopBar()
	local bar = make("Frame", {
		Name = "TopBar", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X, Parent = gui,
	})
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
	block(bar)

	local brand = panel(bar, { Size = UDim2.fromOffset(140, 50), LayoutOrder = 1 })
	padding(brand, 11, 6)
	label(brand, { Text = "ROADLINK", Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = C.green, Size = UDim2.new(1, 0, 0, 20) })
	refs.region = label(brand, { Text = "Green Valley", TextSize = 12, TextColor3 = C.muted, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })

	refs.cashChip, refs.cash = statChip(bar, 120, 2, "CASH", C.gold)
	refs.cashChip.ClipsDescendants = false
	refs.popChip, refs.population = statChip(bar, 104, 3, "POPULATION")
	refs.incomeChip, refs.income = statChip(bar, 132, 4, "NET INCOME / " .. GameConfig.EconomyInterval .. "s", C.green)

	local nextButton = make("TextButton", {
		Name = "NextRegion", Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(220, 50), LayoutOrder = 5,
		BackgroundColor3 = C.panel, BackgroundTransparency = 0.04, BorderSizePixel = 0, Parent = bar,
	})
	corner(nextButton, 12)
	stroke(nextButton)
	padding(nextButton, 11, 6)
	refs.nextCaption = label(nextButton, { Text = "NEXT REGION", TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd })
	refs.nextValue = label(nextButton, { Text = "", TextSize = 14, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	local track = make("Frame", { BackgroundColor3 = C.panel3, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 6), Parent = nextButton })
	corner(track, 3)
	refs.nextFill = make("Frame", { BackgroundColor3 = C.gold, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
	corner(refs.nextFill, 3)
	nextButton.MouseButton1Click:Connect(function()
		Hud.openRegions()
	end)

	refs.saveChip, refs.saveValue = statChip(bar, 112, 6, "SAVING", C.red)
	refs.saveChip.Visible = false
end

local TOOLS = {
	{ id = "Select", name = "SELECT", key = "V" },
	{ id = "Road", name = "ROADS", key = "R" },
	{ id = "Building", name = "BUILD", key = "B" },
	{ id = "Regions", name = "REGIONS", key = "M" },
	{ id = "Stats", name = "STATS", key = "T" },
}

local function buildToolbar()
	local width = #TOOLS * 92 + (#TOOLS - 1) * 6 + 12
	local bar = panel(gui, { Name = "Toolbar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(width, 60) })
	padding(bar, 6, 6)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
	block(bar)
	for index, tool in ipairs(TOOLS) do
		local btn = button(bar, { Text = "", Size = UDim2.fromOffset(92, 48), LayoutOrder = index })
		label(btn, { Text = tool.name, Font = Enum.Font.GothamBold, TextSize = 13, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
		label(btn, { Text = tool.key, Font = Enum.Font.GothamMedium, TextSize = 10, TextColor3 = C.muted, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center })
		btn.MouseButton1Click:Connect(function()
			if tool.id == "Regions" then
				Hud.openRegions()
			elseif tool.id == "Stats" then
				Hud.openStats()
			else
				deps.construction.setMode(tool.id)
			end
		end)
		refs.tools[tool.id] = btn
	end
end

local function buildOptions()
	refs.options = make("ScrollingFrame", {
		Name = "Options", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.fromOffset(500, 86), BackgroundColor3 = C.panel, BackgroundTransparency = 0.04, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X, Visible = false, Active = true, Parent = gui,
	})
	corner(refs.options, 12)
	stroke(refs.options)
	padding(refs.options, 8, 8)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = refs.options })
	block(refs.options)
end

local function rebuildOptions()
	for _, child in ipairs(refs.options:GetChildren()) do
		if child.Name == "Card" then
			child:Destroy()
		end
	end
	local list = currentMode == "Road" and RoadConfig.Order or (currentMode == "Building" and BuildingConfig.Order or nil)
	if not list then
		refs.options.Visible = false
		return
	end
	local snapshot = deps.state.snapshot
	for index, id in ipairs(list) do
		local data, costText, locked, selected
		if currentMode == "Road" then
			data = RoadConfig.Types[id]
			costText = Rules.money(data.CostPerTile) .. " / tile"
			locked = data.RequiresRegion ~= nil and not (snapshot and snapshot.unlocked[data.RequiresRegion])
			selected = deps.construction.roadType == id
		else
			data = BuildingConfig.Types[id]
			costText = Rules.money(data.Cost)
			locked = false
			selected = deps.construction.buildingType == id
		end
		local card
		local cardProps = {
			Name = "Card", Size = UDim2.fromOffset(168, 68), LayoutOrder = index, BorderSizePixel = 0,
			BackgroundColor3 = selected and C.greenDark or C.panel2, BackgroundTransparency = locked and 0.5 or 0, Parent = refs.options,
		}
		if locked then
			card = make("Frame", cardProps)
		else
			cardProps.Text = ""
			cardProps.AutoButtonColor = false
			card = make("TextButton", cardProps)
			card.MouseButton1Click:Connect(function()
				if currentMode == "Road" then
					deps.construction.setRoadType(id)
				else
					deps.construction.setBuildingType(id)
				end
			end)
		end
		corner(card, 10)
		stroke(card, selected and C.green or C.stroke, selected and 0 or 0.55)
		padding(card, 9, 7)
		label(card, { Text = index .. "  " .. data.DisplayName, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = locked and C.muted or C.text, Size = UDim2.new(1, 0, 0, 16) })
		label(card, { Text = locked and "LOCKED" or costText, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = locked and C.muted or C.gold, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 15) })
		label(card, {
			Text = locked and ("Unlocks with the " .. RegionConfig.Regions[data.RequiresRegion].DisplayName) or data.Benefit,
			TextSize = 10, TextColor3 = C.muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(0, 35), Size = UDim2.new(1, 0, 0, 22),
		})
	end
	refs.options.Size = UDim2.fromOffset(math.min(#list * 176 + 8, 1060), 86)
	refs.options.Visible = true
end

local function layoutBottom()
	local hintY = refs.options.Visible and -174 or -80
	refs.hint.Position = UDim2.new(0.5, 0, 1, hintY)
	refs.confirm.Position = UDim2.new(0.5, 0, 1, hintY - 50)
	refs.cancel.Visible = currentMode ~= "Select"
end

local function buildHint()
	refs.hint = panel(gui, { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -80), Size = UDim2.fromOffset(680, 40) })
	block(refs.hint)
	refs.hintText = label(refs.hint, {
		Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -140, 1, 0), TextSize = 12, TextColor3 = C.muted,
		TextWrapped = true, Font = Enum.Font.GothamMedium,
	})
	refs.cancel = button(refs.hint, { Text = "CANCEL (Esc)", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(116, 28), TextSize = 11 })
	refs.cancel.MouseButton1Click:Connect(function()
		deps.construction.cancelStep()
	end)
end

local function buildConfirm()
	refs.confirm = panel(gui, { Name = "Confirm", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -130), Size = UDim2.fromOffset(420, 52), Visible = false })
	block(refs.confirm)
	refs.confirmText = label(refs.confirm, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -210, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd })
	refs.confirmYes = button(refs.confirm, { Text = "BUILD", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -102, 0.5, 0), Size = UDim2.fromOffset(90, 36) }, "primary")
	refs.confirmNo = button(refs.confirm, { Text = "CANCEL", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(90, 36) })
	refs.confirmYes.MouseButton1Click:Connect(function()
		if refs.onConfirm then
			refs.onConfirm()
		end
	end)
	refs.confirmNo.MouseButton1Click:Connect(function()
		if refs.onCancelConfirm then
			refs.onCancelConfirm()
		end
	end)
end

function Hud.showConfirm(text, onConfirm, onCancel)
	refs.confirmText.Text = text
	refs.onConfirm, refs.onCancelConfirm = onConfirm, onCancel
	refs.confirm.Visible = true
end

function Hud.hideConfirm()
	refs.confirm.Visible = false
	refs.onConfirm, refs.onCancelConfirm = nil, nil
end

local function buildInspect()
	refs.inspect = panel(gui, {
		Name = "Inspect", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false,
	})
	padding(refs.inspect, 14, 14)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = refs.inspect })
	block(refs.inspect)
end

function Hud.showInspect(info)
	for _, child in ipairs(refs.inspect:GetChildren()) do
		if child.Name == "Row" then
			child:Destroy()
		end
	end
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local header = make("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nextOrder(), Parent = refs.inspect })
	label(header, { Text = info.title, Font = Enum.Font.GothamBold, TextSize = 17, Size = UDim2.new(1, -70, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	local close = button(header, { Text = "CLOSE", TextSize = 10, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(60, 24) })
	close.MouseButton1Click:Connect(function()
		deps.construction.clearSelection()
	end)
	label(refs.inspect, { Name = "Row", Text = info.subtitle or "", TextSize = 12, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = nextOrder() })
	for _, line in ipairs(info.lines or {}) do
		label(refs.inspect, {
			Name = "Row", Text = line.text, TextSize = 13, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 16), LayoutOrder = nextOrder(),
			TextColor3 = line.tone == "good" and C.green or (line.tone == "bad" and C.red or C.text),
		})
	end
	for _, action in ipairs(info.actions or {}) do
		local btn = button(refs.inspect, { Name = "Row", Text = action.label, TextSize = 12, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder() }, action.style)
		btn.MouseButton1Click:Connect(action.callback)
	end
	refs.inspect.Visible = true
end

function Hud.hideInspect()
	if refs.inspect then
		refs.inspect.Visible = false
	end
end

local function buildToasts()
	refs.toasts = make("Frame", {
		Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(520, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = gui,
	})
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = refs.toasts })
end

local function floatIncome(text)
	local positive = string.sub(text, 1, 1) ~= "-"
	local floater = label(refs.cashChip, {
		Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = positive and C.green or C.red,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(100, 16),
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5,
	})
	local tween = TweenService:Create(floater, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, 0, 0, -18), TextTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		floater:Destroy()
	end)
end

function Hud.toast(message, kind)
	if not refs.toasts or not message or message == "" then
		return
	end
	if kind == "income" then
		floatIncome(message)
		return
	end
	local accent = ({ success = C.green, error = C.red, milestone = C.gold, warning = C.gold })[kind] or C.stroke
	toastOrder += 1
	local toast = label(refs.toasts, {
		Name = "Toast", Text = message, TextWrapped = true, TextSize = 13, Font = kind == "milestone" and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		TextColor3 = kind == "milestone" and C.gold or C.text, TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = C.panel, BackgroundTransparency = 0.02, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = toastOrder,
	})
	corner(toast, 10)
	local line = stroke(toast, accent, 0)
	padding(toast, 14, 9)
	local existing = {}
	for _, child in ipairs(refs.toasts:GetChildren()) do
		if child.Name == "Toast" then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #existing > 3 do
		table.remove(existing, 1):Destroy()
	end
	task.delay(kind == "error" and 4.2 or (kind == "milestone" and 5 or 3.2), function()
		if not toast.Parent then
			return
		end
		local info = TweenInfo.new(0.35)
		TweenService:Create(toast, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		TweenService:Create(line, info, { Transparency = 1 }):Play()
		task.wait(0.4)
		toast:Destroy()
	end)
end

function Hud.setHint(text)
	refs.hintText.Text = text
end

function Hud.onModeChanged(mode)
	currentMode = mode
	for id, btn in pairs(refs.tools) do
		local active = id == mode
		setBase(btn, active and C.greenDark or C.panel2)
		local line = btn:FindFirstChildOfClass("UIStroke")
		if line then
			line.Color = active and C.green or C.stroke
			line.Transparency = active and 0 or 0.35
		end
	end
	rebuildOptions()
	layoutBottom()
end

function Hud.onOptionChanged()
	rebuildOptions()
	layoutBottom()
end

local function closeModal()
	if refs.modal then
		refs.modal:Destroy()
	end
	refs.modal, refs.modalList, openModal = nil, nil, nil
end

local function modalShell(title, kind, keepScroll)
	local scroll = keepScroll and refs.modalList and refs.modalList.CanvasPosition or nil
	if refs.modal then
		refs.modal:Destroy()
	end
	openModal = kind
	local overlay = make("TextButton", {
		Name = "ModalOverlay", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 20, Parent = gui,
	})
	block(overlay)
	overlay.MouseButton1Click:Connect(closeModal)
	local frame = panel(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 520), ZIndex = 21 })
	label(frame, { Text = title, Font = Enum.Font.GothamBlack, TextSize = 20, Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -120, 0, 32), ZIndex = 22 })
	local close = button(frame, { Text = "CLOSE", TextSize = 11, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(74, 30), ZIndex = 22 })
	close.MouseButton1Click:Connect(closeModal)
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 56), Size = UDim2.new(1, -32, 1, -70), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 22, Parent = frame,
	})
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	refs.modal, refs.modalList = overlay, list
	if scroll then
		task.defer(function()
			if list.Parent then
				list.CanvasPosition = scroll
			end
		end)
	end
	return list
end

local function card(list, order)
	local frame = make("Frame", {
		Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.panel2,
		BorderSizePixel = 0, LayoutOrder = order, ZIndex = 23, Parent = list,
	})
	corner(frame, 12)
	padding(frame, 14, 12)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
	return frame
end

local function row(parent, order, left, right, color)
	local frame = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, ZIndex = 24, Parent = parent })
	label(frame, { Text = left, TextSize = 13, TextColor3 = color or C.text, Size = UDim2.new(0.62, 0, 1, 0), ZIndex = 24, TextTruncate = Enum.TextTruncate.AtEnd })
	label(frame, { Text = right or "", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = color or C.text, Position = UDim2.fromScale(0.62, 0), Size = UDim2.new(0.38, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 24 })
	return frame
end

local function formatProgress(req)
	if req.flag then
		return req.met and "Done" or "Not yet"
	end
	if req.money then
		return Rules.money(req.current) .. " / " .. Rules.money(req.target)
	end
	return tostring(req.current) .. " / " .. tostring(req.target)
end

function Hud.openRegions(keepScroll)
	local snapshot = deps.state.snapshot
	if not snapshot then
		return
	end
	local list = modalShell("Regions", "Regions", keepScroll)
	for index, region in ipairs(snapshot.regions) do
		local frame = card(list, index)
		local header = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, ZIndex = 24, Parent = frame })
		label(header, { Text = region.name, Font = Enum.Font.GothamBold, TextSize = 17, Size = UDim2.new(1, -150, 1, 0), ZIndex = 24 })
		local status = region.unlocked and "UNLOCKED" or (region.canUnlock and "READY TO UNLOCK" or "LOCKED")
		local statusColor = region.unlocked and C.green or (region.canUnlock and C.gold or C.muted)
		label(header, { Text = status, Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = statusColor, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 150, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 24 })
		label(frame, { Text = region.description, TextSize = 12, TextColor3 = C.muted, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 2, ZIndex = 24 })
		if not region.unlocked then
			for reqIndex, req in ipairs(region.requirements) do
				row(frame, 2 + reqIndex, (req.met and "✓  " or "•  ") .. req.label, formatProgress(req), req.met and C.green or C.text)
			end
		end
		local actions = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 50, ZIndex = 24, Parent = frame })
		local btn
		if region.unlocked then
			btn = button(actions, { Text = "VIEW ON MAP", Size = UDim2.fromOffset(150, 34), ZIndex = 25 })
			btn.MouseButton1Click:Connect(function()
				deps.camera.focusRegion(region.id)
				closeModal()
			end)
		elseif region.canUnlock then
			btn = button(actions, { Text = "UNLOCK · " .. Rules.money(region.cost), Size = UDim2.fromOffset(190, 34), ZIndex = 25 }, "primary")
			btn.MouseButton1Click:Connect(function()
				local result = deps.state.invoke("UnlockRegion", { regionId = region.id })
				Hud.toast(result.message, result.ok and "milestone" or "error")
				if result.ok then
					closeModal()
					if region.entryGate then
						deps.camera.focusGate(region.entryGate)
					else
						deps.camera.focusRegion(region.id)
					end
				end
			end)
		elseif region.entryGate then
			btn = button(actions, { Text = "SHOW ENTRY GATE", Size = UDim2.fromOffset(170, 34), ZIndex = 25 })
			btn.MouseButton1Click:Connect(function()
				deps.camera.focusGate(region.entryGate)
				closeModal()
			end)
		end
	end
end

function Hud.openStats(keepScroll)
	local snapshot = deps.state.snapshot
	if not snapshot then
		return
	end
	local list = modalShell("City statistics", "Stats", keepScroll)
	local tick = snapshot.tickSeconds .. "s"

	local economy = card(list, 1)
	label(economy, { Text = "ECONOMY", Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, ZIndex = 24 })
	row(economy, 1, "Cash", Rules.money(snapshot.cash), C.gold)
	row(economy, 2, "Population", tostring(snapshot.population))
	row(economy, 3, "Income every " .. tick, "+" .. Rules.money(snapshot.income), C.green)
	row(economy, 4, "Road upkeep every " .. tick, "-" .. Rules.money(snapshot.upkeep), C.red)
	row(economy, 5, "Net every " .. tick, (snapshot.net >= 0 and "+" or "") .. Rules.money(snapshot.net), snapshot.net >= 0 and C.green or C.red)

	local network = card(list, 2)
	label(network, { Text = "NETWORK", Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, ZIndex = 24 })
	row(network, 1, "Road tiles", tostring(snapshot.roadTiles))
	row(network, 2, "Connected locations", tostring(snapshot.connectedLocations))
	row(network, 3, "Connected businesses", tostring(snapshot.connectedBusinesses))

	local buildings = card(list, 3)
	label(buildings, { Text = "BUILDINGS", Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, ZIndex = 24 })
	local kinds = table.clone(BuildingConfig.Order)
	for _, kind in ipairs(BuildingConfig.Landmarks) do
		table.insert(kinds, kind)
	end
	for index, kind in ipairs(kinds) do
		local data = BuildingConfig.Types[kind]
		local entry = snapshot.breakdown[kind]
		if entry then
			local right = (data.Population or 0) > 0 and (entry.population .. " residents") or (Rules.money(entry.income) .. " / " .. tick)
			row(buildings, index, data.DisplayName .. "  ·  " .. entry.connected .. " of " .. entry.count .. " connected", right)
		end
	end

	local milestones = card(list, 4)
	label(milestones, { Text = "MILESTONES", Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, ZIndex = 24 })
	for index, milestone in ipairs(GameConfig.Milestones) do
		local done = snapshot.milestones[milestone.id] == true
		local reward = milestone.reward > 0 and ("+" .. Rules.money(milestone.reward)) or ""
		row(milestones, index, (done and "✓  " or "•  ") .. milestone.name, done and "Done" or reward, done and C.green or C.text)
	end

	local saving = card(list, 5)
	label(saving, { Text = "SAVING", Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, ZIndex = 24 })
	local savingText = ({
		ok = "Your city saves automatically and when you leave.",
		new = "Your city saves automatically and when you leave.",
		disabled = "Saving is off: DataStore access isn't available (in Studio, enable API access in Game Settings → Security).",
		failed = "Your save couldn't be loaded, so saving is paused this session to protect it.",
	})[snapshot.persistence] or "Checking…"
	label(saving, { Text = savingText, TextSize = 12, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 1, ZIndex = 24 })
end

local function onState(snapshot)
	if refs.loading then
		refs.loading:Destroy()
		refs.loading = nil
	end
	refs.cash.Text = Rules.money(snapshot.cash)
	refs.population.Text = tostring(snapshot.population)
	refs.income.Text = (snapshot.net >= 0 and "+" or "") .. Rules.money(snapshot.net)
	refs.income.TextColor3 = snapshot.net >= 0 and C.green or C.red

	local nextRegion
	for _, region in ipairs(snapshot.regions) do
		if not region.unlocked then
			nextRegion = region
			break
		end
	end
	if nextRegion then
		refs.nextCaption.Text = "NEXT: " .. string.upper(nextRegion.name)
		refs.nextValue.Text = nextRegion.canUnlock and "Ready to unlock! Click here" or (nextRegion.met .. " of " .. nextRegion.total .. " goals met")
		refs.nextValue.TextColor3 = nextRegion.canUnlock and C.gold or C.text
		refs.nextFill.Size = UDim2.fromScale(nextRegion.total > 0 and nextRegion.met / nextRegion.total or 1, 1)
	else
		refs.nextCaption.Text = "REGIONS"
		refs.nextValue.Text = "All regions unlocked"
		refs.nextFill.Size = UDim2.fromScale(1, 1)
	end

	if snapshot.persistence == "disabled" then
		refs.saveChip.Visible = true
		refs.saveValue.Text = "OFF"
	elseif snapshot.persistence == "failed" then
		refs.saveChip.Visible = true
		refs.saveValue.Text = "PAUSED"
	else
		refs.saveChip.Visible = false
	end

	if currentMode == "Road" then
		rebuildOptions()
	end
	if openModal == "Regions" then
		Hud.openRegions(true)
	elseif openModal == "Stats" then
		Hud.openStats(true)
	end
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	uiScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1.0)
end

function Hud.init(dependencies)
	deps = dependencies
	gui = make("ScreenGui", {
		Name = "RoadLinkHUD", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
	})
	uiScale = make("UIScale", { Parent = gui })
	updateScale()
	local watched
	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera and camera ~= watched then
			watched = camera
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

	buildTopBar()
	buildOptions()
	buildHint()
	buildConfirm()
	buildToolbar()
	buildInspect()
	buildToasts()
	refs.loading = label(gui, {
		Text = "Loading your city…", Font = Enum.Font.GothamBold, TextSize = 22, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(400, 40), TextXAlignment = Enum.TextXAlignment.Center,
	})

	deps.state.Changed:Connect(onState)
	deps.state.Message:Connect(Hud.toast)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			if openModal == "Regions" then closeModal() else Hud.openRegions() end
		elseif input.KeyCode == Enum.KeyCode.T then
			if openModal == "Stats" then closeModal() else Hud.openStats() end
		elseif input.KeyCode == Enum.KeyCode.Escape and openModal then
			closeModal()
		end
	end)

	task.spawn(function()
		while gui.Parent do
			local x, z = deps.camera.getFocusCell()
			if x then
				local regionId = Grid.regionAt(x, z)
				local snapshot = deps.state.snapshot
				if regionId then
					local locked = snapshot and not snapshot.unlocked[regionId]
					refs.region.Text = RegionConfig.Regions[regionId].DisplayName .. (locked and " (locked)" or "")
				else
					refs.region.Text = "Outside your land"
				end
			end
			task.wait(0.3)
		end
	end)
end

return Hud
