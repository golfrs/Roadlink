-- Builds and updates each player's world: a clone of the shared map template, region lock tints,
-- custom building models, road geometry (rounded corners, bridges, tunnel portals) and self-clearing forests.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local RoadConfig = require(Shared.RoadConfig)
local BuildingConfig = require(Shared.BuildingConfig)
local RegionConfig = require(Shared.RegionConfig)
local Grid = require(Shared.Grid)
local Rules = require(Shared.Rules)

local Assets = ServerStorage:WaitForChild("RoadLinkAssets")
local Models = Assets:WaitForChild("Models")
local Template = Assets:WaitForChild("MapTemplate")

local G = GameConfig.GridSize
local WorldService = {}
local worldsFolder

local ON_COLOR = Color3.fromRGB(92, 222, 120)
local OFF_COLOR = Color3.fromRGB(238, 86, 76)
local GOLD = Color3.fromRGB(246, 198, 92)
local STONE = Color3.fromRGB(176, 170, 160)
local LOCKED_GREY = Color3.fromRGB(168, 166, 152)
local KERB = Color3.fromRGB(200, 196, 186)
local KERB_WIDTH = 0.7
local ROAD_TOP = 0.3

local function part(parent, props, className)
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function addLabel(adornee, text, color, height, maxDistance, size, textSize)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = size or UDim2.fromOffset(170, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height or 6, 0)
	gui.MaxDistance = maxDistance or 320
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 28, 34)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
	pad.Parent = label
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = textSize or 14
	limit.Parent = label
	label.Parent = gui
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

local function anchor(parent, name, position)
	return part(parent, { Name = name, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(position), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
end

local function wp(state, x, z, y)
	return Grid.toWorld(state.originX, state.originZ, x, z, y)
end

function WorldService.init()
	worldsFolder = Workspace:FindFirstChild("RoadLinkWorlds")
	if not worldsFolder then
		worldsFolder = Instance.new("Folder")
		worldsFolder.Name = "RoadLinkWorlds"
		worldsFolder.Parent = Workspace
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Transparency = 1
		baseplate.CanCollide = false
		baseplate.CanQuery = false
		baseplate.CastShadow = false
		local texture = baseplate:FindFirstChildOfClass("Texture")
		if texture then
			texture.Transparency = 1
		end
	end
	-- Characters are disabled, so the template SpawnLocation is only visual clutter.
	for _, item in ipairs(Workspace:GetChildren()) do
		if item:IsA("SpawnLocation") then
			item.Transparency = 1
			item.CanCollide = false
			item.CanQuery = false
			item.CastShadow = false
			for _, decal in ipairs(item:GetChildren()) do
				if decal:IsA("Decal") then
					decal.Transparency = 1
				end
			end
		end
	end
	local old = worldsFolder:FindFirstChild("Backdrop")
	if old then
		old:Destroy()
	end
	part(worldsFolder, {
		Name = "Backdrop", Size = Vector3.new(4096, 1, 4096), CFrame = CFrame.new(1200, -0.65, 0),
		Color = Color3.fromRGB(86, 152, 66), CanQuery = false, CastShadow = false,
	})
end

-- Tints a region's land and shows its lock label or bridge-site labels.
function WorldService.buildRegion(state, regionId)
	local cfg = RegionConfig.Regions[regionId]
	local unlocked = state.unlocked[regionId] == true
	for _, ground in ipairs(state.folders.Map.Ground:GetChildren()) do
		if ground:GetAttribute("RegionId") == regionId then
			local base = ground:GetAttribute("BaseColor")
			ground.Color = unlocked and base or base:Lerp(LOCKED_GREY, 0.32)
		end
	end
	local overlays = state.folders.Overlays
	local old = overlays:FindFirstChild(regionId)
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Folder")
	holder.Name = regionId
	if not unlocked then
		local cx, cz = Grid.regionCenter(regionId)
		local a = anchor(holder, "LockedLabel", wp(state, cx, cz, 8))
		addLabel(a, "LOCKED · " .. cfg.DisplayName, GOLD, 4, 1400, UDim2.fromOffset(300, 40), 20)
	elseif cfg.River then
		local river = cfg.River
		for _, c in ipairs(river.Crossings) do
			local mid = river.Line + ((river.Width or 1) - 1) / 2
			local position = river.Axis == "X" and wp(state, mid, c, 1) or wp(state, c, mid, 1)
			local a = anchor(holder, "BridgeSite", position)
			addLabel(a, "Bridge site", GOLD, 3, 260, UDim2.fromOffset(110, 22), 12)
		end
	end
	holder.Parent = overlays
end

function WorldService.buildMarkers(state)
	local markers = state.folders.Markers
	markers:ClearAllChildren()
	local root = anchor(markers, "TownJunction", wp(state, GameConfig.RootX, GameConfig.RootZ, 1))
	addLabel(root, "Town Junction · roads start here", GOLD, 5, 600, UDim2.fromOffset(220, 26))
	for _, gate in ipairs(Grid.gateList) do
		if state.unlocked[gate.region] then
			local center = wp(state, gate.x, gate.z, 0)
			local alongX = gate.direction == "East" or gate.direction == "West"
			local open = gate.leadsTo and state.unlocked[gate.leadsTo]
			local color = open and ON_COLOR or GOLD
			for _, side in ipairs({ -1, 1 }) do
				local offset = alongX and Vector3.new(0, 0, side * 7) or Vector3.new(side * 7, 0, 0)
				part(markers, { Name = "GatePillar", Size = Vector3.new(1.4, 4, 1.4), CFrame = CFrame.new(center + offset + Vector3.new(0, 2, 0)), Color = STONE, CanQuery = false })
				part(markers, { Name = "GateLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), CFrame = CFrame.new(center + offset + Vector3.new(0, 4.5, 0)), Color = color, Material = Enum.Material.Neon, CanQuery = false, CastShadow = false })
			end
			local target = RegionConfig.Regions[gate.leadsTo]
			local a = anchor(markers, "GateLabel_" .. gate.id, center + Vector3.new(0, 5, 0))
			addLabel(a, gate.name .. " → " .. (target and target.DisplayName or "?") .. (open and "" or " (locked)"), color, 3, 800, UDim2.fromOffset(260, 28))
		end
	end
end

local function variantFor(id, count)
	local sum = 0
	for i = 1, #id do
		sum += string.byte(id, i)
	end
	return sum % count + 1
end

function WorldService.addBuilding(state, building)
	local data = BuildingConfig.Types[building.kind]
	local origin = wp(state, building.x, building.z, 0)
	local footprint = data.Footprint or Vector2.new(8, 8)
	local model = Instance.new("Model")
	model.Name = building.id
	model:SetAttribute("BuildingId", building.id)
	model:SetAttribute("BuildingType", building.kind)
	model:SetAttribute("OwnerUserId", state.userId)
	model:SetAttribute("GridX", building.x)
	model:SetAttribute("GridZ", building.z)
	local foundation = part(model, {
		Name = "Foundation", Size = Vector3.new(footprint.X, 0.4, footprint.Y), CFrame = CFrame.new(origin + Vector3.new(0, 0.2, 0)),
		Color = building.kind == "Residential" and Color3.fromRGB(126, 196, 92) or Color3.fromRGB(214, 208, 194),
	})
	if building.kind == "Residential" then
		-- a small garden: path to the door, a hedge and a bush
		part(model, { Name = "Path", Size = Vector3.new(1.2, 0.06, 1.4), CFrame = CFrame.new(origin + Vector3.new(1.1, 0.43, 3.3)), Color = Color3.fromRGB(214, 202, 176), CanQuery = false })
		part(model, { Name = "Hedge", Size = Vector3.new(0.6, 0.8, 6.8), CFrame = CFrame.new(origin + Vector3.new(-3.6, 0.8, 0)), Color = Color3.fromRGB(70, 140, 70), CanQuery = false })
		part(model, { Name = "Bush", Size = Vector3.new(1.3, 1.1, 1.3), CFrame = CFrame.new(origin + Vector3.new(-2.4, 0.95, 3.2)) * CFrame.Angles(0, math.rad(30), 0), Color = Color3.fromRGB(96, 170, 80), CanQuery = false })
	end
	local assetName = data.Asset[variantFor(building.id, #data.Asset)]
	local asset = Models:FindFirstChild(assetName)
	if asset then
		local clone = asset:Clone()
		clone:PivotTo(CFrame.new(origin + Vector3.new(0, 0.4, 0)))
		for _, child in ipairs(clone:GetChildren()) do
			child.Parent = model
		end
		clone:Destroy()
	end
	part(model, {
		Name = "StatusLight", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1),
		CFrame = CFrame.new(origin + Vector3.new(footprint.X / 2 - 0.8, 0.85, footprint.Y / 2 - 0.8)),
		Color = building.connected and ON_COLOR or OFF_COLOR, Material = Enum.Material.Neon, CastShadow = false,
	})
	if building.seeded then
		addLabel(foundation, building.name, Color3.new(1, 1, 1), building.kind == "Airport" and 16 or 11, 300, UDim2.fromOffset(150, 24), 13)
	end
	model.PrimaryPart = foundation
	model.Parent = state.folders.Buildings
	WorldService.refreshDecor(state)
	return model
end

function WorldService.removeBuilding(state, id)
	local model = state.folders.Buildings:FindFirstChild(id)
	if model then
		model:Destroy()
	end
	WorldService.refreshDecor(state)
end

-- Trees are decoration: any tree standing on a road or building tile is cleared (no cost), and returns if the tile is freed.
function WorldService.refreshDecor(state)
	if not state.trees then
		return
	end
	local occupied = {}
	for node in pairs(state.graph.adjacency) do
		occupied[node] = true
	end
	for key in pairs(state.buildingNodes) do
		occupied[key] = true
	end
	for _, tree in ipairs(state.trees) do
		local blocked = false
		for _, node in ipairs(tree.nodes) do
			if occupied[node] then
				blocked = true
				break
			end
		end
		if blocked ~= tree.hidden then
			tree.hidden = blocked
			tree.model.Parent = not blocked and tree.home or nil
		end
	end
end

function WorldService.updateBuildingStatus(state)
	local buildings = state.folders and state.folders.Buildings
	if not buildings then
		return
	end
	for _, b in ipairs(state.buildings) do
		local model = buildings:FindFirstChild(b.id)
		if model then
			local light = model:FindFirstChild("StatusLight")
			if light then
				light.Color = b.connected and ON_COLOR or OFF_COLOR
			end
			model:SetAttribute("Connected", b.connected == true)
		end
	end
	WorldService.refreshDecor(state)
end

-- Road geometry ------------------------------------------------------------------------------------

local function surface(parent, name, center, sizeX, sizeZ, color, top)
	top = top or ROAD_TOP
	return part(parent, {
		Name = name, Size = Vector3.new(sizeX, top, sizeZ), CFrame = CFrame.new(center.X, top / 2, center.Z),
		Color = color, Material = Enum.Material.SmoothPlastic, CastShadow = false,
	})
end

-- A light kerb under every road piece, slightly wider than the asphalt, outlines roads and junctions.
local function kerb(parent, center, sizeX, sizeZ, rounded)
	local p
	if rounded then
		p = part(parent, {
			Name = "Kerb", Shape = Enum.PartType.Cylinder, Size = Vector3.new(ROAD_TOP - 0.08, sizeX + KERB_WIDTH * 2, sizeX + KERB_WIDTH * 2),
			CFrame = CFrame.new(center.X, (ROAD_TOP - 0.08) / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color = KERB, CastShadow = false,
		})
	else
		p = part(parent, {
			Name = "Kerb", Size = Vector3.new(sizeX, ROAD_TOP - 0.08, sizeZ), CFrame = CFrame.new(center.X, (ROAD_TOP - 0.08) / 2, center.Z),
			Color = KERB, CastShadow = false,
		})
	end
	p.CanQuery = false
	return p
end

local function lines(parent, center, length, horizontal, data, top)
	if not data.LineColor or length < 1.5 then
		return
	end
	local y = (top or ROAD_TOP) + 0.02
	local function strip(offset, width, color)
		local pos = horizontal and Vector3.new(center.X, y, center.Z + offset) or Vector3.new(center.X + offset, y, center.Z)
		part(parent, {
			Name = "Marking", Size = horizontal and Vector3.new(length, 0.04, width) or Vector3.new(width, 0.04, length),
			CFrame = CFrame.new(pos), Color = color, CanQuery = false, CanCollide = false, CastShadow = false,
		})
	end
	local edge = data.Width / 2 - 0.7
	strip(edge, 0.3, data.LineColor)
	strip(-edge, 0.3, data.LineColor)
	strip(0.3, 0.22, data.CenterColor)
	strip(-0.3, 0.22, data.CenterColor)
end

local function makeRun(state, parent, sx, sz, fx, fz, kind, bridge, pads)
	local data = RoadConfig.Types[kind]
	local a, b = wp(state, sx, sz, 0), wp(state, fx, fz, 0)
	local horizontal = sz == fz
	local padA, padB = pads[Grid.key(sx, sz)], pads[Grid.key(fx, fz)]
	local insetA, insetB = padA and padA.width / 2 or 0, padB and padB.width / 2 or 0
	local length = (b - a).Magnitude - insetA - insetB
	if length <= 0.05 then
		return
	end
	local direction = (b - a).Unit
	local center = a + direction * (insetA + length / 2)
	local width = data.Width
	local sizeX, sizeZ = horizontal and length or width, horizontal and width or length
	local piece
	if bridge then
		local deckWidth = width + 2.6
		local deckColor = Color3.fromRGB(204, 200, 192)
		local function along(len, across, y, h, color, name, offset, query)
			local pos = horizontal and Vector3.new(center.X, y, center.Z + (offset or 0)) or Vector3.new(center.X + (offset or 0), y, center.Z)
			return part(parent, {
				Name = name, Size = horizontal and Vector3.new(len, h, across) or Vector3.new(across, h, len), CFrame = CFrame.new(pos),
				Color = color, CanQuery = query == true,
			})
		end
		piece = along(length, deckWidth, -0.1, 1.2, deckColor, "BridgeDeck", 0, true)
		surface(parent, "BridgeRoad", center, sizeX, sizeZ, data.Color, 0.56)
		lines(parent, center, length, horizontal, data, 0.56)
		for _, side in ipairs({ -1, 1 }) do
			local edgeOffset = (deckWidth / 2) * side
			along(length, 1.1, 0.62, 0.25, Color3.fromRGB(222, 218, 210), "Sidewalk", edgeOffset - 0.55 * side)
			along(length, 0.3, -0.35, 1.5, Color3.fromRGB(86, 104, 128), "Girder", edgeOffset + 0.1 * side)
			along(length, 0.22, 1.85, 0.22, Color3.fromRGB(246, 246, 244), "Railing", edgeOffset - 0.15 * side)
			local posts = math.max(2, math.floor(length / 2.6))
			for i = 0, posts do
				local t = -length / 2 + length * i / posts
				local pos = horizontal and Vector3.new(center.X + t, 1.3, center.Z + edgeOffset - 0.15 * side) or Vector3.new(center.X + edgeOffset - 0.15 * side, 1.3, center.Z + t)
				part(parent, { Name = "RailPost", Size = Vector3.new(0.22, 1.1, 0.22), CFrame = CFrame.new(pos), Color = Color3.fromRGB(246, 246, 244), CanQuery = false, CastShadow = false })
			end
			for _, endT in ipairs({ -length / 2 + 0.6, length / 2 - 0.6 }) do
				local base = horizontal and Vector3.new(center.X + endT, 0, center.Z + edgeOffset - 0.5 * side) or Vector3.new(center.X + edgeOffset - 0.5 * side, 0, center.Z + endT)
				part(parent, { Name = "LampPost", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 0.3, 0.3), CFrame = CFrame.new(base + Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 64, 72), CanQuery = false })
				part(parent, { Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(base + Vector3.new(0, 4.2, 0)), Color = Color3.fromRGB(255, 236, 180), Material = Enum.Material.Neon, CanQuery = false, CastShadow = false })
			end
		end
		-- stone piers with cutwaters under every river tile of the span
		local steps = math.floor((b - a).Magnitude / G + 0.5)
		for i = 1, steps - 1 do
			local px, pz = sx + (fx - sx) / steps * i, sz + (fz - sz) / steps * i
			if Grid.isRiver(px, pz) then
				local pos = wp(state, px, pz, 0)
				local pierLength = deckWidth - 0.8
				local pierColor = Color3.fromRGB(176, 170, 160)
				part(parent, {
					Name = "Pier", Size = horizontal and Vector3.new(1.8, 5, pierLength) or Vector3.new(pierLength, 5, 1.8),
					CFrame = CFrame.new(pos.X, -3.2, pos.Z), Color = pierColor, CanQuery = false,
				})
				part(parent, {
					Name = "PierCap", Size = horizontal and Vector3.new(2.4, 0.5, deckWidth) or Vector3.new(deckWidth, 0.5, 2.4),
					CFrame = CFrame.new(pos.X, -0.85, pos.Z), Color = Color3.fromRGB(190, 184, 174), CanQuery = false,
				})
				for _, dir in ipairs({ -1, 1 }) do
					-- pointed cutwater on the upstream and downstream ends of the pier
					local offset = (pierLength / 2 + 0.7) * dir
					local cutPos = horizontal and Vector3.new(pos.X, -3.2, pos.Z + offset) or Vector3.new(pos.X + offset, -3.2, pos.Z)
					local yaw = horizontal and (dir > 0 and 0 or math.pi) or (dir > 0 and -math.pi / 2 or math.pi / 2)
					part(parent, { Name = "Cutwater", Shape = Enum.PartType.Block, Size = Vector3.new(1.27, 5, 1.27), CFrame = CFrame.new(cutPos) * CFrame.Angles(0, yaw + math.rad(45), 0), Color = pierColor, CanQuery = false })
				end
			end
		end
		piece:SetAttribute("Bridge", true)
	else
		kerb(parent, center, horizontal and length or width + KERB_WIDTH * 2, horizontal and width + KERB_WIDTH * 2 or length)
		piece = surface(parent, "Road", center, sizeX, sizeZ, data.Color)
		lines(parent, center, length, horizontal, data)
	end
	piece:SetAttribute("RoadRun", true)
	piece:SetAttribute("X1", sx)
	piece:SetAttribute("Z1", sz)
	piece:SetAttribute("X2", fx)
	piece:SetAttribute("Z2", fz)
	piece:SetAttribute("RoadType", kind)
	piece:SetAttribute("OwnerUserId", state.userId)
end

local function makePortal(state, parent, outsideX, outsideZ, insideX, insideZ, kind)
	local data = RoadConfig.Types[kind]
	local inside = wp(state, insideX, insideZ, 0)
	local direction = (inside - wp(state, outsideX, outsideZ, 0)).Unit
	local face = inside - direction * (G / 2 + 1.2)
	local alongX = insideZ == outsideZ
	local w = data.Width + 1
	local function block(name, lateral, y, sizeLateral, sizeY, depth, color)
		local pos = face + (alongX and Vector3.new(0, y, lateral) or Vector3.new(lateral, y, 0))
		part(parent, {
			Name = name, Size = alongX and Vector3.new(depth, sizeY, sizeLateral) or Vector3.new(sizeLateral, sizeY, depth),
			CFrame = CFrame.new(pos), Color = color, CanQuery = false,
		})
	end
	block("PortalDark", 0, 2.3, w, 4.6, 0.6, Color3.fromRGB(28, 30, 34))
	block("PortalPost", -(w / 2 + 0.8), 2.6, 1.6, 5.2, 2.2, STONE)
	block("PortalPost", w / 2 + 0.8, 2.6, 1.6, 5.2, 2.2, STONE)
	block("PortalLintel", 0, 5.6, w + 3.2, 1.4, 2.4, Color3.fromRGB(160, 154, 146))
end

-- Rebuilds road geometry: one part per straight run, rounded pads at corners and ends,
-- square pads at junctions, bridges over rivers and portals where tunnels enter mountains.
function WorldService.rebuildRoads(state)
	local roads = state.folders.Roads
	roads:ClearAllChildren()
	local graph = state.graph
	local Types = RoadConfig.Types

	local pads = {}
	for node, neighbours in pairs(graph.adjacency) do
		local degree, maxWidth, bestKind = 0, 0, nil
		local list = {}
		for _, edgeKey in pairs(neighbours) do
			local edge = graph.edges[edgeKey]
			degree += 1
			table.insert(list, edge)
			local width = Types[edge.kind].Width
			if width > maxWidth then
				maxWidth, bestKind = width, edge.kind
			end
		end
		local throughRoad, corner = false, false
		if degree == 2 then
			local a, b = list[1], list[2]
			local straight = (a.z1 == a.z2) == (b.z1 == b.z2)
			corner = not straight
			throughRoad = straight and a.kind == b.kind
				and Rules.isBridgeEdge(a.x1, a.z1, a.x2, a.z2) == Rules.isBridgeEdge(b.x1, b.z1, b.x2, b.z2)
		end
		if not throughRoad then
			-- rounded outer edge on corners; square pads on dead ends, junctions and straight transitions
			local inner
			if corner then
				-- direction of the inside of the bend (sum of the two directions leaving this node)
				local nx, nz = Grid.parse(node)
				inner = Vector3.zero
				for _, edge in ipairs(list) do
					local ox, oz = edge.x1, edge.z1
					if ox == nx and oz == nz then
						ox, oz = edge.x2, edge.z2
					end
					inner += Vector3.new(ox - nx, 0, oz - nz)
				end
			end
			pads[node] = { width = maxWidth, kind = bestKind, rounded = corner, inner = inner }
		end
	end

	local visited = {}
	for key, edge in pairs(graph.edges) do
		if not visited[key] then
			visited[key] = true
			local dx, dz = edge.x2 - edge.x1, edge.z2 - edge.z1
			local sx, sz = edge.x1, edge.z1
			while not pads[Grid.key(sx, sz)] do
				local previous = Grid.edgeKey(sx, sz, sx - dx, sz - dz)
				if not graph.edges[previous] or visited[previous] then
					break
				end
				visited[previous] = true
				sx, sz = sx - dx, sz - dz
			end
			local fx, fz = edge.x2, edge.z2
			while not pads[Grid.key(fx, fz)] do
				local following = Grid.edgeKey(fx, fz, fx + dx, fz + dz)
				if not graph.edges[following] or visited[following] then
					break
				end
				visited[following] = true
				fx, fz = fx + dx, fz + dz
			end
			makeRun(state, roads, sx, sz, fx, fz, edge.kind, Rules.isBridgeEdge(edge.x1, edge.z1, edge.x2, edge.z2), pads)
		end
	end

	for node, pad in pairs(pads) do
		local x, z = Grid.parse(node)
		local center = wp(state, x, z, 0)
		local color = Types[pad.kind].Color
		local piece
		local onBridge = Grid.isRiver(x, z)
		if not onBridge then
			kerb(roads, center, pad.width + KERB_WIDTH * 2, pad.width + KERB_WIDTH * 2, pad.rounded)
			if pad.rounded then
				local fill = kerb(roads, center + pad.inner * (pad.width / 4), pad.width / 2, pad.width / 2)
				fill.Name = "KerbFill"
			end
		end
		if pad.rounded then
			piece = part(roads, {
				Name = "Junction", Shape = Enum.PartType.Cylinder, Size = Vector3.new(ROAD_TOP, pad.width, pad.width),
				CFrame = CFrame.new(center.X, ROAD_TOP / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
				Color = color, CastShadow = false,
			})
			local quarter = surface(roads, "CornerFill", center + pad.inner * (pad.width / 4), pad.width / 2, pad.width / 2, color)
			quarter.CanQuery = false
		else
			piece = surface(roads, "Junction", center, pad.width, pad.width, color)
		end
		piece:SetAttribute("Pad", true)
		piece:SetAttribute("NodeX", x)
		piece:SetAttribute("NodeZ", z)
	end

	for _, edge in pairs(graph.edges) do
		local mountainA, mountainB = Grid.isMountain(edge.x1, edge.z1), Grid.isMountain(edge.x2, edge.z2)
		if mountainA ~= mountainB then
			if mountainB then
				makePortal(state, roads, edge.x1, edge.z1, edge.x2, edge.z2, edge.kind)
			else
				makePortal(state, roads, edge.x2, edge.z2, edge.x1, edge.z1, edge.kind)
			end
		end
	end
	WorldService.refreshDecor(state)
end

function WorldService.createWorld(state)
	local root = Instance.new("Folder")
	root.Name = "Player_" .. state.userId
	root:SetAttribute("OwnerUserId", state.userId)
	root.Parent = worldsFolder
	local map = Template:Clone()
	map.Name = "Map"
	map:PivotTo(CFrame.new(state.originX, 0, state.originZ))
	map.Parent = root
	state.folders = { Root = root, Map = map, Terrain = map }
	for _, name in ipairs({ "Roads", "Buildings", "Markers", "Overlays" }) do
		local child = Instance.new("Folder")
		child.Name = name
		child.Parent = root
		state.folders[name] = child
	end
	state.trees = {}
	local treeFolder = map:FindFirstChild("Trees")
	for _, tree in ipairs(treeFolder and treeFolder:GetChildren() or {}) do
		local nodes = string.split(tree:GetAttribute("Nodes") or "", ";")
		if #nodes > 0 and nodes[1] ~= "" then
			table.insert(state.trees, { model = tree, nodes = nodes, home = treeFolder, hidden = false })
		end
	end
	for _, regionId in ipairs(RegionConfig.Order) do
		WorldService.buildRegion(state, regionId)
	end
	WorldService.buildMarkers(state)
	for _, building in ipairs(state.buildings) do
		WorldService.addBuilding(state, building)
	end
	WorldService.rebuildRoads(state)
end

function WorldService.destroyWorld(state)
	if state.folders and state.folders.Root then
		state.folders.Root:Destroy()
	end
	state.folders = nil
	state.trees = nil
end

return WorldService
