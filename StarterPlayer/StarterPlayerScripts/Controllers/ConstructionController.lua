-- Construction controller: tool modes, snapped previews with live cost, click/tap handling and inspection.
-- Every action is only a request; the server re-validates and charges.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
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
local Construction = {}
Construction.roadType = "Basic"
Construction.buildingType = "Residential"

local OK_COLOR = Color3.fromRGB(92, 222, 122)
local BAD_COLOR = Color3.fromRGB(240, 88, 78)
local HINT_COLOR = Color3.fromRGB(250, 200, 88)
local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
}

local deps
local mode = "Select"
local roadStart, hoverCell, pending, selection
local busy, dirty = false, true
local previewFolder, roadGhost, startMarker, footprintGhost, bodyGhost, infoAnchor, infoGui, infoLabel, highlight, dotsFolder

local function snapshot()
	return deps.state.snapshot
end

local function touchOnly()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function cellWorld(x, z, y)
	local s = snapshot()
	return Grid.toWorld(s.originX, s.originZ, x, z, y)
end

local function ghostPart(name, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	if shape then
		p.Shape = shape
	end
	p.Parent = previewFolder
	return p
end

local function createPreviewObjects()
	previewFolder = Instance.new("Folder")
	previewFolder.Name = "RoadLinkPreview"
	previewFolder.Parent = Workspace
	roadGhost = ghostPart("RoadGhost")
	startMarker = ghostPart("StartMarker", Enum.PartType.Cylinder)
	footprintGhost = ghostPart("FootprintGhost")
	bodyGhost = ghostPart("BodyGhost")
	infoAnchor = ghostPart("InfoAnchor")
	infoAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	infoGui = Instance.new("BillboardGui")
	infoGui.Size = UDim2.fromOffset(300, 36)
	infoGui.AlwaysOnTop = true
	infoGui.LightInfluence = 0
	infoGui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	infoGui.Enabled = false
	infoGui.Adornee = infoAnchor
	infoGui.Parent = infoAnchor
	infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.fromScale(1, 1)
	infoLabel.BackgroundColor3 = Color3.fromRGB(18, 26, 32)
	infoLabel.BackgroundTransparency = 0.08
	infoLabel.Font = Enum.Font.GothamBold
	infoLabel.TextScaled = true
	infoLabel.TextColor3 = Color3.new(1, 1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = infoLabel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = infoLabel
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 16
	limit.Parent = infoLabel
	infoLabel.Parent = infoGui
	highlight = Instance.new("Highlight")
	highlight.FillColor = HINT_COLOR
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = Color3.fromRGB(255, 226, 130)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = previewFolder
	dotsFolder = Instance.new("Folder")
	dotsFolder.Name = "StartPoints"
	dotsFolder.Parent = previewFolder
end

local function hidePreview()
	roadGhost.Transparency = 1
	startMarker.Transparency = 1
	footprintGhost.Transparency = 1
	bodyGhost.Transparency = 1
	infoGui.Enabled = false
end

local function setInfo(x, z, text, color)
	infoAnchor.Position = cellWorld(x, z, 1)
	infoLabel.Text = text
	infoLabel.TextColor3 = color
	infoGui.Enabled = true
end

local function showMarker(x, z, color)
	startMarker.Size = Vector3.new(0.3, 5, 5)
	startMarker.CFrame = CFrame.new(cellWorld(x, z, 0.55)) * CFrame.Angles(0, 0, math.rad(90))
	startMarker.Color = color
	startMarker.Transparency = 0.2
end

local function showRoadGhost(x1, z1, x2, z2, kind, color)
	local width = RoadConfig.Types[kind].Width
	local a, b = cellWorld(x1, z1, 0.5), cellWorld(x2, z2, 0.5)
	local length = (b - a).Magnitude + width
	roadGhost.Size = z1 == z2 and Vector3.new(length, 0.25, width) or Vector3.new(width, 0.25, length)
	roadGhost.CFrame = CFrame.new((a + b) / 2)
	roadGhost.Color = color
	roadGhost.Transparency = 0.4
end

local function showBuildingGhost(x, z, color)
	footprintGhost.Size = Vector3.new(8, 0.3, 8)
	footprintGhost.CFrame = CFrame.new(cellWorld(x, z, 0.5))
	footprintGhost.Color = color
	footprintGhost.Transparency = 0.35
	bodyGhost.Size = Vector3.new(6, 5, 6)
	bodyGhost.CFrame = CFrame.new(cellWorld(x, z, 3.1))
	bodyGhost.Color = color
	bodyGhost.Transparency = 0.6
end

local function snappedEnd(cell)
	if not roadStart then
		return cell
	end
	if math.abs(cell.x - roadStart.x) >= math.abs(cell.z - roadStart.z) then
		return { x = cell.x, z = roadStart.z }
	end
	return { x = roadStart.x, z = cell.z }
end

-- Glowing dots on the Town Junction and connected road ends show where a road can start.
local function refreshStartDots()
	dotsFolder:ClearAllChildren()
	if not snapshot() or mode ~= "Road" or roadStart then
		return
	end
	local root = Grid.rootKey()
	local points = { root }
	for node, neighbours in pairs(deps.state.graph.adjacency) do
		local degree = 0
		for _ in pairs(neighbours) do
			degree += 1
		end
		if degree == 1 and node ~= root and deps.state.connected[node] then
			table.insert(points, node)
		end
	end
	for _, node in ipairs(points) do
		local x, z = Grid.parse(node)
		local dot = Instance.new("Part")
		dot.Name = "StartDot"
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.new(2.2, 2.2, 2.2)
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CastShadow = false
		dot.Material = Enum.Material.Neon
		dot.Color = OK_COLOR
		dot.Transparency = 0.15
		dot.Position = cellWorld(x, z, 1.4)
		dot.Parent = dotsFolder
	end
end

local function refreshPreview()
	hidePreview()
	if not snapshot() then
		return
	end
	local view = deps.state.view()
	local cell = pending and pending.cell or hoverCell
	if mode == "Road" then
		if not roadStart then
			if cell then
				local connected = deps.state.connected[Grid.key(cell.x, cell.z)] == true
				showMarker(cell.x, cell.z, connected and OK_COLOR or HINT_COLOR)
				setInfo(cell.x, cell.z, connected and "Click to start a road here" or "Start from a green dot (connected road)", connected and OK_COLOR or HINT_COLOR)
			end
			return
		end
		showMarker(roadStart.x, roadStart.z, OK_COLOR)
		if not cell then
			return
		end
		local finish = snappedEnd(cell)
		local plan = Rules.planRoad(view, roadStart.x, roadStart.z, finish.x, finish.z, Construction.roadType)
		if plan.code == "short" then
			setInfo(roadStart.x, roadStart.z, "Move to choose where the road ends", HINT_COLOR)
			return
		end
		showRoadGhost(roadStart.x, roadStart.z, finish.x, finish.z, Construction.roadType, plan.ok and OK_COLOR or BAD_COLOR)
		local text = plan.ok and plan.message or plan.message
		if plan.ok and plan.bridgeTiles > 0 then
			text ..= " · incl. bridge"
		end
		if plan.ok and plan.tunnelTiles > 0 then
			text ..= " · incl. tunnel"
		end
		setInfo(finish.x, finish.z, text, plan.ok and OK_COLOR or BAD_COLOR)
	elseif mode == "Building" and cell then
		local plan = Rules.planBuilding(view, Construction.buildingType, cell.x, cell.z)
		local data = BuildingConfig.Types[Construction.buildingType]
		local color = plan.ok and (plan.access and OK_COLOR or HINT_COLOR) or BAD_COLOR
		showBuildingGhost(cell.x, cell.z, plan.ok and OK_COLOR or BAD_COLOR)
		local text
		if plan.ok then
			text = data.DisplayName .. " · " .. Rules.money(data.Cost) .. (plan.access and " · road access ✓" or " · needs a road within 1 tile")
		else
			text = plan.message
		end
		setInfo(cell.x, cell.z, text, color)
	end
end

local function updateHint()
	local touch = touchOnly()
	local hint
	if pending then
		hint = touch and "Tap BUILD to confirm, or CANCEL." or "Press Enter or BUILD to confirm."
	elseif mode == "Road" then
		local data = RoadConfig.Types[Construction.roadType]
		if roadStart then
			hint = (touch and "Tap" or "Click") .. " where the road should end. Keep going to add corners. " .. (touch and "CANCEL" or "Right-click / Esc") .. " to stop."
		else
			hint = data.DisplayName .. " selected. " .. (touch and "Tap" or "Click") .. " a green dot to start: the Town Junction or the end of a connected road."
		end
	elseif mode == "Building" then
		hint = (touch and "Tap" or "Click") .. " an empty tile next to a connected road. Red status lights mean no road access."
	else
		hint = touch and "Tap a road or building to inspect it · Drag to move · Pinch to zoom"
			or "Click a road or building to inspect it · WASD / right-drag to move · Scroll to zoom · Q/E rotate"
	end
	deps.hud.setHint(hint)
end

local function worldFolder()
	local worlds = Workspace:FindFirstChild("RoadLinkWorlds")
	return worlds and worlds:FindFirstChild("Player_" .. player.UserId)
end

local function cellAtViewport(position)
	local camera = Workspace.CurrentCamera
	if not camera or not snapshot() then
		return nil
	end
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	if ray.Direction.Y > -0.001 then
		return nil
	end
	local hit = ray.Origin + ray.Direction * (-ray.Origin.Y / ray.Direction.Y)
	local s = snapshot()
	local x, z = Grid.toCell(s.originX, s.originZ, hit)
	return { x = x, z = z }
end

local function pickInstance(position)
	local world = worldFolder()
	local camera = Workspace.CurrentCamera
	if not world or not camera then
		return nil
	end
	local include = {}
	for _, name in ipairs({ "Buildings", "Roads" }) do
		local child = world:FindFirstChild(name)
		if child then
			table.insert(include, child)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	return result and result.Instance
end

function Construction.clearSelection()
	selection = nil
	highlight.Adornee = nil
	highlight.Enabled = false
	deps.hud.hideInspect()
end

local function runAction(action, payload)
	if busy then
		return
	end
	busy = true
	local result = deps.state.invoke(action, payload)
	busy = false
	deps.hud.toast(result.message or (result.ok and "Done." or "That didn't work."), result.ok and "success" or "error")
	if result.ok then
		Construction.clearSelection()
	end
	dirty = true
	return result
end

local function showBuildingInspect(building)
	local data = BuildingConfig.Types[building.kind]
	local s = snapshot()
	local lines = {}
	table.insert(lines, {
		text = building.connected and "Connected to the road network" or "No road access: build a connected road within 1 tile",
		tone = building.connected and "good" or "bad",
	})
	if (data.Population or 0) > 0 then
		table.insert(lines, { text = "Residents: " .. building.population })
	end
	if (data.Income or 0) > 0 then
		table.insert(lines, { text = "Income: " .. Rules.money(building.output) .. " every " .. s.tickSeconds .. "s" })
	end
	if building.connected and building.multiplier > 1 then
		table.insert(lines, { text = string.format("Road bonus: ×%.2f from the best road beside it", building.multiplier) })
	end
	if data.ProductionBoost then
		table.insert(lines, { text = "Boosts connected farms and factories by +" .. math.floor(data.ProductionBoost * 100) .. "% (max " .. data.MaxStack .. ")" })
	end
	if data.PopulationBoost then
		table.insert(lines, { text = "Adds +" .. math.floor(data.PopulationBoost * 100) .. "% population (max " .. data.MaxStack .. ")" })
	end
	local actions = {}
	if not building.seeded then
		local refund = math.floor(data.Cost * GameConfig.RefundFraction)
		table.insert(actions, {
			label = "Demolish · refund " .. Rules.money(refund),
			style = "danger",
			callback = function()
				runAction("DemolishBuilding", { id = building.id })
			end,
		})
	end
	deps.hud.showInspect({
		title = building.name,
		subtitle = data.DisplayName .. (building.seeded and " · original town building" or " · built by you"),
		lines = lines,
		actions = actions,
	})
end

local function showRoadInspect(sel)
	local steps = Rules.runEdges(sel.x1, sel.z1, sel.x2, sel.z2, 64)
	local graph = deps.state.graph
	local kind, tiles, refund, upkeep, bridge = nil, 0, 0, 0, false
	for _, step in ipairs(steps or {}) do
		local edge = graph.edges[step.key]
		if edge then
			kind = edge.kind
			tiles += 1
			refund += Rules.edgeCost(edge.kind, edge.x1, edge.z1, edge.x2, edge.z2)
			upkeep += Rules.edgeUpkeep(edge.kind, edge.x1, edge.z1, edge.x2, edge.z2)
			if Rules.isBridgeEdge(edge.x1, edge.z1, edge.x2, edge.z2) then
				bridge = "bridge"
			elseif Rules.isTunnelEdge(edge.x1, edge.z1, edge.x2, edge.z2) then
				bridge = "tunnel"
			end
		end
	end
	if not kind then
		Construction.clearSelection()
		return
	end
	refund = math.floor(refund * GameConfig.RefundFraction)
	local data = RoadConfig.Types[kind]
	local s = snapshot()
	local connected = deps.state.connected[Grid.key(sel.x1, sel.z1)] == true
	local lines = {
		{ text = connected and "Connected to the Town Junction" or "Not connected to the town", tone = connected and "good" or "bad" },
		{ text = tiles .. " tile" .. (tiles == 1 and "" or "s") .. (bridge and (" · " .. bridge) or "") },
		{ text = "Upkeep: " .. Rules.money(upkeep) .. " every " .. s.tickSeconds .. "s" },
		{ text = data.Benefit },
	}
	local actions = {}
	for _, id in ipairs(RoadConfig.Order) do
		local target = RoadConfig.Types[id]
		if target.CostPerTile > data.CostPerTile and (not target.RequiresRegion or s.unlocked[target.RequiresRegion]) then
			local cost = (target.CostPerTile - data.CostPerTile) * tiles
			table.insert(actions, {
				label = "Upgrade to " .. target.DisplayName .. " · " .. Rules.money(cost),
				style = "primary",
				callback = function()
					runAction("UpgradeRoad", { x1 = sel.x1, z1 = sel.z1, x2 = sel.x2, z2 = sel.z2, roadType = id })
				end,
			})
		end
	end
	table.insert(actions, {
		label = "Bulldoze · refund " .. Rules.money(refund),
		style = "danger",
		callback = function()
			runAction("RemoveRoad", { x1 = sel.x1, z1 = sel.z1, x2 = sel.x2, z2 = sel.z2 })
		end,
	})
	deps.hud.showInspect({ title = data.DisplayName, subtitle = "Straight road section", lines = lines, actions = actions })
end

function Construction.selectInstance(instance)
	Construction.clearSelection()
	if not instance then
		return
	end
	local model = instance:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("BuildingId") then
		local building = deps.state.buildingsById[model:GetAttribute("BuildingId")]
		if building then
			selection = { kind = "building", id = building.id }
			highlight.Adornee = model
			highlight.Enabled = true
			showBuildingInspect(building)
		end
		return
	end
	if instance:GetAttribute("RoadRun") then
		selection = {
			kind = "road",
			x1 = instance:GetAttribute("X1"), z1 = instance:GetAttribute("Z1"),
			x2 = instance:GetAttribute("X2"), z2 = instance:GetAttribute("Z2"),
		}
		highlight.Adornee = instance
		highlight.Enabled = true
		showRoadInspect(selection)
	end
end

local function commitRoad(finish)
	local start = roadStart
	busy = true
	local result = deps.state.invoke("BuildRoad", { x1 = start.x, z1 = start.z, x2 = finish.x, z2 = finish.z, roadType = Construction.roadType })
	busy = false
	if result.ok then
		deps.hud.toast(result.message, "success")
		if mode == "Road" then
			roadStart = { x = finish.x, z = finish.z }
		end
	else
		deps.hud.toast(result.message or "Road placement was rejected.", "error")
	end
	dirty = true
	refreshStartDots()
	updateHint()
end

local function commitBuilding(cell)
	busy = true
	local result = deps.state.invoke("BuildBuilding", { buildingType = Construction.buildingType, x = cell.x, z = cell.z })
	busy = false
	deps.hud.toast(result.message or (result.ok and "Built." or "Building placement was rejected."), result.ok and "success" or "error")
	dirty = true
end

function Construction.confirmPending()
	if not pending then
		return
	end
	local action = pending
	pending = nil
	deps.hud.hideConfirm()
	if action.kind == "road" then
		commitRoad(action.cell)
	else
		commitBuilding(action.cell)
	end
	updateHint()
end

function Construction.cancelPending()
	pending = nil
	deps.hud.hideConfirm()
	dirty = true
	updateHint()
end

function Construction.handlePointer(position, isTouch)
	if busy or not snapshot() then
		return
	end
	if deps.hud.isOverUi(position) then
		return
	end
	if mode == "Select" then
		Construction.selectInstance(pickInstance(position))
		return
	end
	local cell = cellAtViewport(position)
	if not cell then
		return
	end
	if isTouch then
		hoverCell = cell
	end
	local view = deps.state.view()
	if mode == "Road" then
		if not roadStart then
			roadStart = cell
			if not deps.state.connected[Grid.key(cell.x, cell.z)] then
				deps.hud.toast("Tip: roads must connect back to the town. End this one on a green dot.", "info")
			end
			refreshStartDots()
			updateHint()
			dirty = true
			return
		end
		local finish = snappedEnd(cell)
		if finish.x == roadStart.x and finish.z == roadStart.z then
			roadStart = nil
			refreshStartDots()
			updateHint()
			dirty = true
			return
		end
		local plan = Rules.planRoad(view, roadStart.x, roadStart.z, finish.x, finish.z, Construction.roadType)
		if not plan.ok then
			deps.hud.toast(plan.message, "error")
			return
		end
		if isTouch then
			pending = { kind = "road", cell = finish }
			deps.hud.showConfirm("Build " .. plan.message, Construction.confirmPending, Construction.cancelPending)
			updateHint()
			dirty = true
			return
		end
		commitRoad(finish)
	elseif mode == "Building" then
		local plan = Rules.planBuilding(view, Construction.buildingType, cell.x, cell.z)
		if not plan.ok then
			deps.hud.toast(plan.message, "error")
			return
		end
		if isTouch then
			local data = BuildingConfig.Types[Construction.buildingType]
			pending = { kind = "building", cell = cell }
			deps.hud.showConfirm("Build " .. data.DisplayName .. " · " .. Rules.money(data.Cost), Construction.confirmPending, Construction.cancelPending)
			updateHint()
			dirty = true
			return
		end
		commitBuilding(cell)
	end
end

function Construction.getMode()
	return mode
end

function Construction.setMode(newMode)
	mode = newMode
	roadStart = nil
	pending = nil
	deps.hud.hideConfirm()
	Construction.clearSelection()
	deps.hud.onModeChanged(newMode)
	refreshStartDots()
	updateHint()
	dirty = true
end

function Construction.setRoadType(id)
	local data = RoadConfig.Types[id]
	local s = snapshot()
	if not data then
		return
	end
	if data.RequiresRegion and not (s and s.unlocked[data.RequiresRegion]) then
		deps.hud.toast(data.DisplayName .. " unlocks with the " .. RegionConfig.Regions[data.RequiresRegion].DisplayName .. ".", "error")
		return
	end
	Construction.roadType = id
	if mode ~= "Road" then
		Construction.setMode("Road")
	else
		deps.hud.onOptionChanged()
		updateHint()
	end
	dirty = true
end

function Construction.setBuildingType(id)
	if not BuildingConfig.Types[id] then
		return
	end
	Construction.buildingType = id
	if mode ~= "Building" then
		Construction.setMode("Building")
	else
		deps.hud.onOptionChanged()
	end
	dirty = true
end

-- Steps back one level: pending confirmation → road start → tool → selection.
function Construction.cancelStep()
	if pending then
		Construction.cancelPending()
	elseif roadStart then
		roadStart = nil
		refreshStartDots()
		updateHint()
		dirty = true
	elseif mode ~= "Select" then
		Construction.setMode("Select")
	elseif selection then
		Construction.clearSelection()
	end
end

function Construction.init(dependencies)
	deps = dependencies
	createPreviewObjects()

	deps.camera.onTap(function(position)
		Construction.handlePointer(position, true)
	end)
	deps.camera.onRightClick(Construction.cancelStep)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Construction.handlePointer(UserInputService:GetMouseLocation(), false)
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.R then
			Construction.setMode("Road")
		elseif key == Enum.KeyCode.B then
			Construction.setMode("Building")
		elseif key == Enum.KeyCode.V then
			Construction.setMode("Select")
		elseif key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace then
			Construction.cancelStep()
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
			Construction.confirmPending()
		else
			local index = NUMBER_KEYS[key]
			if index then
				if mode == "Road" and RoadConfig.Order[index] then
					Construction.setRoadType(RoadConfig.Order[index])
				elseif mode == "Building" and BuildingConfig.Order[index] then
					Construction.setBuildingType(BuildingConfig.Order[index])
				end
			end
		end
	end)

	deps.state.Changed:Connect(function()
		dirty = true
		refreshStartDots()
		if selection and selection.kind == "building" then
			local building = deps.state.buildingsById[selection.id]
			if building then
				showBuildingInspect(building)
			else
				Construction.clearSelection()
			end
		elseif selection and selection.kind == "road" then
			-- road geometry is rebuilt on change, so the old part reference is stale
			if not highlight.Adornee or not highlight.Adornee.Parent then
				Construction.clearSelection()
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not snapshot() then
			return
		end
		if UserInputService.MouseEnabled and not pending then
			local position = UserInputService:GetMouseLocation()
			local cell = nil
			if not deps.hud.isOverUi(position) then
				cell = cellAtViewport(position)
			end
			local changed = (cell == nil) ~= (hoverCell == nil)
				or (cell ~= nil and hoverCell ~= nil and (cell.x ~= hoverCell.x or cell.z ~= hoverCell.z))
			if changed then
				hoverCell = cell
				dirty = true
			end
		end
		if dirty then
			dirty = false
			refreshPreview()
		end
	end)

	deps.hud.onModeChanged(mode)
	updateHint()
end

return Construction
