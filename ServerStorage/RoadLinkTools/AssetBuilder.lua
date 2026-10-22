-- Builds RoadLink's custom low-poly models from Parts. Run from the command bar (edit mode):
--   require(game.ServerStorage.RoadLinkTools.AssetBuilder:Clone()).build()
-- Output: ServerStorage.RoadLinkAssets.Models. Every model's pivot is its ground centre; +Z is the front.
local AssetBuilder = {}

local P = {
	grass = Color3.fromRGB(124, 198, 92),
	leaf = Color3.fromRGB(86, 168, 72),
	leafLight = Color3.fromRGB(118, 190, 78),
	leafDark = Color3.fromRGB(58, 128, 66),
	pine = Color3.fromRGB(44, 108, 72),
	pineDark = Color3.fromRGB(34, 88, 62),
	trunk = Color3.fromRGB(112, 80, 56),
	rock = Color3.fromRGB(138, 136, 132),
	rockDark = Color3.fromRGB(108, 106, 104),
	cream = Color3.fromRGB(244, 230, 200),
	white = Color3.fromRGB(240, 240, 236),
	paleYellow = Color3.fromRGB(246, 222, 150),
	paleBlue = Color3.fromRGB(200, 222, 236),
	peach = Color3.fromRGB(244, 196, 160),
	roofRed = Color3.fromRGB(200, 76, 58),
	roofBrown = Color3.fromRGB(128, 86, 66),
	roofSlate = Color3.fromRGB(78, 84, 98),
	roofGreen = Color3.fromRGB(78, 128, 96),
	barnRed = Color3.fromRGB(184, 54, 46),
	door = Color3.fromRGB(104, 72, 52),
	glass = Color3.fromRGB(146, 202, 236),
	metal = Color3.fromRGB(176, 180, 186),
	concrete = Color3.fromRGB(206, 204, 198),
	darkGrey = Color3.fromRGB(70, 74, 82),
	tan = Color3.fromRGB(214, 176, 126),
	orange = Color3.fromRGB(242, 140, 70),
	wheat = Color3.fromRGB(236, 194, 76),
}
AssetBuilder.Palette = P

local function add(model, className, name, size, cf, color, extra)
	local p = Instance.new(className)
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	p.Parent = model
	return p
end
AssetBuilder.add = add

local function box(model, name, size, pos, color, extra)
	return add(model, "Part", name, size, CFrame.new(pos), color, extra)
end

-- Vertical cylinder: height h, diameter d.
local function cyl(model, name, h, d, pos, color, extra)
	return add(model, "Part", name, Vector3.new(h, d, d), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color,
		(function()
			local e = extra or {}
			e.Shape = Enum.PartType.Cylinder
			return e
		end)())
end
AssetBuilder.cyl = cyl

-- Gable roof: ridge runs along X when alongX, otherwise along Z. Base centre at pos.
local function gable(model, name, width, height, depth, pos, color, alongZ)
	local yaw = alongZ and math.rad(90) or 0
	local base = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, yaw, 0)
	local half = depth / 2
	add(model, "WedgePart", name, Vector3.new(width, height, half), base * CFrame.new(0, 0, -half / 2), color)
	add(model, "WedgePart", name, Vector3.new(width, height, half), base * CFrame.new(0, 0, half / 2) * CFrame.Angles(0, math.pi, 0), color)
end
AssetBuilder.gable = gable

local function newModel(name)
	local model = Instance.new("Model")
	model.Name = name
	return model
end

local function finish(model)
	model.WorldPivot = CFrame.new()
	return model
end

local builders = {}

-- One cohesive village palette: warm plaster walls and terracotta / brown roofs.
local HOUSE_STYLES = {
	{ wall = Color3.fromRGB(246, 234, 208), roof = Color3.fromRGB(190, 84, 60) },
	{ wall = Color3.fromRGB(240, 238, 230), roof = Color3.fromRGB(132, 88, 66) },
	{ wall = Color3.fromRGB(236, 214, 172), roof = Color3.fromRGB(166, 68, 54) },
	{ wall = Color3.fromRGB(242, 208, 178), roof = Color3.fromRGB(110, 86, 80) },
}
local WINDOW = Color3.fromRGB(150, 196, 226)
local FRAME = Color3.fromRGB(250, 248, 242)
for index, style in ipairs(HOUSE_STYLES) do
	builders["House_" .. index] = function()
		local m = newModel("House_" .. index)
		local h = 4.6
		box(m, "Walls", Vector3.new(6.4, h, 5.8), Vector3.new(0, h / 2, 0), style.wall)
		box(m, "Plinth", Vector3.new(6.6, 0.5, 6), Vector3.new(0, 0.25, 0), Color3.fromRGB(176, 166, 150))
		gable(m, "Roof", 7.1, 2.7, 6.8, Vector3.new(0, h, 0), style.roof)
		box(m, "Door", Vector3.new(1.2, 2.1, 0.15), Vector3.new(1.4, 1.05 + 0.4, 2.95), P.door)
		for _, w in ipairs({ { -1.5, 1.6 }, { -1.5, 3.5 }, { 1.4, 3.5 } }) do
			box(m, "WindowFrame", Vector3.new(1.3, 1.1, 0.12), Vector3.new(w[1], w[2], 2.93), FRAME)
			box(m, "Window", Vector3.new(1, 0.85, 0.14), Vector3.new(w[1], w[2], 2.95), WINDOW)
		end
		box(m, "Window", Vector3.new(0.14, 0.9, 1.1), Vector3.new(3.24, 2.6, 0.6), WINDOW)
		box(m, "Window", Vector3.new(0.14, 0.9, 1.1), Vector3.new(-3.24, 2.6, -0.6), WINDOW)
		box(m, "Chimney", Vector3.new(0.8, 2, 0.8), Vector3.new(-1.9, h + 1.9, -1.3), Color3.fromRGB(150, 96, 80))
		return finish(m)
	end
end

builders.Farmhouse = function()
	local m = newModel("Farmhouse")
	local h = 4.4
	box(m, "Walls", Vector3.new(7, h, 5.4), Vector3.new(0, h / 2, 0), Color3.fromRGB(246, 242, 232))
	gable(m, "Roof", 7.7, 2.6, 6.4, Vector3.new(0, h, 0), Color3.fromRGB(150, 58, 48))
	box(m, "PorchRoof", Vector3.new(4.4, 0.25, 1.8), Vector3.new(0, 2.6, 3.6), Color3.fromRGB(150, 58, 48))
	box(m, "PorchPost", Vector3.new(0.25, 2.4, 0.25), Vector3.new(-2, 1.2, 4.3), FRAME)
	box(m, "PorchPost", Vector3.new(0.25, 2.4, 0.25), Vector3.new(2, 1.2, 4.3), FRAME)
	box(m, "Door", Vector3.new(1.1, 2, 0.15), Vector3.new(0, 1, 2.75), P.door)
	box(m, "Window", Vector3.new(1, 0.9, 0.14), Vector3.new(-2.2, 1.6, 2.75), WINDOW)
	box(m, "Window", Vector3.new(1, 0.9, 0.14), Vector3.new(2.2, 1.6, 2.75), WINDOW)
	box(m, "Chimney", Vector3.new(0.8, 2.2, 0.8), Vector3.new(2.4, h + 1.8, -1), Color3.fromRGB(150, 96, 80))
	return finish(m)
end

builders.Church = function()
	local m = newModel("Church")
	box(m, "Nave", Vector3.new(5, 4.6, 8), Vector3.new(0, 2.3, 1), P.white)
	gable(m, "Roof", 8.4, 2.6, 5.6, Vector3.new(0, 4.6, 1), P.roofRed, true)
	box(m, "Tower", Vector3.new(2.8, 8.4, 2.8), Vector3.new(0, 4.2, -3.6), P.white)
	gable(m, "Spire", 3.2, 4.2, 3.2, Vector3.new(0, 8.4, -3.6), P.roofRed)
	gable(m, "Spire", 3.2, 4.2, 3.2, Vector3.new(0, 8.4, -3.6), P.roofRed, true)
	cyl(m, "Clock", 0.15, 1.3, Vector3.new(0, 6.6, -2.15), P.paleYellow).CFrame = CFrame.new(0, 6.6, -2.13) * CFrame.Angles(0, math.rad(90), 0)
	box(m, "Door", Vector3.new(1.4, 2.4, 0.15), Vector3.new(0, 1.2, 5.05), P.door)
	box(m, "Window", Vector3.new(0.12, 1.6, 0.8), Vector3.new(2.55, 2.6, 2.4), P.glass)
	box(m, "Window", Vector3.new(0.12, 1.6, 0.8), Vector3.new(-2.55, 2.6, 2.4), P.glass)
	return finish(m)
end

builders.Shop = function()
	local m = newModel("Shop")
	local h = 6.6
	box(m, "Walls", Vector3.new(6.8, h, 6), Vector3.new(0, h / 2, 0), Color3.fromRGB(238, 196, 150))
	box(m, "Cornice", Vector3.new(7.1, 0.5, 6.3), Vector3.new(0, h + 0.25, 0), Color3.fromRGB(250, 244, 230))
	box(m, "RoofSlab", Vector3.new(6.6, 0.3, 5.8), Vector3.new(0, h + 0.6, 0), Color3.fromRGB(110, 86, 80))
	box(m, "ShopWindow", Vector3.new(6, 2.3, 0.15), Vector3.new(0, 1.35, 3.05), Color3.fromRGB(150, 196, 226))
	for i, color in ipairs({ P.roofRed, FRAME, P.roofRed, FRAME, P.roofRed, FRAME }) do
		box(m, "Awning", Vector3.new(1.13, 0.3, 1.5), Vector3.new(-2.83 + (i - 1) * 1.13, 3, 3.65), color)
	end
	box(m, "Sign", Vector3.new(4, 0.9, 0.2), Vector3.new(0, 4.3, 3.1), Color3.fromRGB(64, 92, 132))
	for _, x in ipairs({ -2, 0, 2 }) do
		box(m, "WindowFrame", Vector3.new(1.3, 1.1, 0.12), Vector3.new(x, 5.6, 3.03), FRAME)
		box(m, "Window", Vector3.new(1, 0.85, 0.14), Vector3.new(x, 5.6, 3.05), WINDOW)
	end
	return finish(m)
end

builders.Clinic = function()
	local m = newModel("Clinic")
	box(m, "Walls", Vector3.new(6, 4.2, 5.6), Vector3.new(0, 2.1, 0), P.white)
	box(m, "RoofSlab", Vector3.new(6.4, 0.4, 6), Vector3.new(0, 4.4, 0), P.metal)
	box(m, "Cross", Vector3.new(2.6, 0.3, 0.8), Vector3.new(0, 4.75, 0), P.roofRed)
	box(m, "Cross", Vector3.new(0.8, 0.3, 2.6), Vector3.new(0, 4.75, 0), P.roofRed)
	box(m, "Doors", Vector3.new(1.8, 2.2, 0.15), Vector3.new(0, 1.1, 2.85), P.glass)
	box(m, "Stripe", Vector3.new(6.05, 0.4, 5.65), Vector3.new(0, 3.2, 0), P.roofRed)
	return finish(m)
end

builders.Warehouse = function()
	local m = newModel("Warehouse")
	box(m, "Walls", Vector3.new(7.2, 3.8, 6.2), Vector3.new(0, 1.9, 0), P.tan)
	gable(m, "Roof", 7.6, 1.3, 6.6, Vector3.new(0, 3.8, 0), P.roofGreen)
	box(m, "Door", Vector3.new(3, 2.8, 0.15), Vector3.new(-0.8, 1.4, 3.15), P.metal)
	box(m, "Trim", Vector3.new(7.25, 0.35, 6.25), Vector3.new(0, 3.2, 0), P.roofBrown)
	return finish(m)
end

builders.Factory = function()
	local m = newModel("Factory")
	box(m, "Walls", Vector3.new(7, 4.4, 5.6), Vector3.new(0, 2.2, 0.2), P.concrete)
	for i = 0, 2 do
		local wedge = add(m, "WedgePart", "Sawtooth", Vector3.new(5.6, 1.5, 2.33),
			CFrame.new(-2.33 + i * 2.33, 4.4 + 0.75, 0.2) * CFrame.Angles(0, math.rad(90), 0), P.roofSlate)
		wedge.Name = "Sawtooth"
	end
	cyl(m, "Chimney", 8.5, 1.3, Vector3.new(-2.6, 4.25, -2.3), P.roofRed)
	cyl(m, "ChimneyBand", 0.6, 1.36, Vector3.new(-2.6, 7.4, -2.3), P.white)
	box(m, "Door", Vector3.new(2.4, 2.6, 0.15), Vector3.new(1.8, 1.3, 3.05), P.darkGrey)
	box(m, "Windows", Vector3.new(3, 0.9, 0.12), Vector3.new(-1.6, 2.8, 3.04), P.glass)
	return finish(m)
end

builders.FarmBarn = function()
	local m = newModel("FarmBarn")
	box(m, "Barn", Vector3.new(4.8, 4, 6.4), Vector3.new(-1.2, 2, 0), P.barnRed)
	gable(m, "Roof", 7, 2.6, 5.6, Vector3.new(-1.2, 4, 0), Color3.fromRGB(84, 80, 84), true)
	box(m, "Door", Vector3.new(2.2, 2.7, 0.15), Vector3.new(-1.2, 1.35, 3.25), Color3.fromRGB(150, 44, 38))
	add(m, "Part", "Trim", Vector3.new(0.18, 3.3, 0.1), CFrame.new(-1.2, 1.35, 3.35) * CFrame.Angles(0, 0, math.rad(39)), P.white)
	add(m, "Part", "Trim", Vector3.new(0.18, 3.3, 0.1), CFrame.new(-1.2, 1.35, 3.35) * CFrame.Angles(0, 0, math.rad(-39)), P.white)
	box(m, "Trim", Vector3.new(2.4, 0.18, 0.1), Vector3.new(-1.2, 2.75, 3.35), P.white)
	box(m, "Trim", Vector3.new(4.85, 0.25, 6.45), Vector3.new(-1.2, 3.9, 0), P.white)
	box(m, "Loft", Vector3.new(1, 1, 0.12), Vector3.new(-1.2, 4.8, 3.2), P.white)
	cyl(m, "Silo", 7.4, 2.3, Vector3.new(2.5, 3.7, -1.5), Color3.fromRGB(196, 200, 206))
	add(m, "Part", "SiloCap", Vector3.new(2.3, 2.3, 2.3), CFrame.new(2.5, 7.4, -1.5), Color3.fromRGB(150, 156, 166), { Shape = Enum.PartType.Ball })
	cyl(m, "Silo", 5.6, 1.9, Vector3.new(2.7, 2.8, 1.5), Color3.fromRGB(196, 200, 206))
	add(m, "Part", "SiloCap", Vector3.new(1.9, 1.9, 1.9), CFrame.new(2.7, 5.6, 1.5), Color3.fromRGB(150, 156, 166), { Shape = Enum.PartType.Ball })
	cyl(m, "SiloBand", 0.3, 2.36, Vector3.new(2.5, 5.2, -1.5), P.barnRed)
	return finish(m)
end

builders.AirportTerminal = function()
	local m = newModel("AirportTerminal")
	local h = 4.4
	box(m, "Hall", Vector3.new(12.6, h, 6.4), Vector3.new(-0.8, h / 2, 0), Color3.fromRGB(240, 242, 244))
	box(m, "Glass", Vector3.new(11.8, 3, 0.15), Vector3.new(-0.8, 1.8, 3.25), Color3.fromRGB(120, 184, 226))
	for _, x in ipairs({ -5.2, -2.3, 0.7, 3.6 }) do
		box(m, "Mullion", Vector3.new(0.25, 3, 0.2), Vector3.new(x, 1.8, 3.3), FRAME)
	end
	-- barrel roof: the top of a long cylinder shows as a gentle curve with overhangs
	add(m, "Part", "Roof", Vector3.new(13.2, 6.8, 6.8), CFrame.new(-0.8, h - 1.15, 0), Color3.fromRGB(176, 184, 194), { Shape = Enum.PartType.Cylinder })
	box(m, "Canopy", Vector3.new(4.6, 0.3, 2.2), Vector3.new(-0.8, 3.4, 4.3), Color3.fromRGB(64, 92, 132))
	local sign = box(m, "Sign", Vector3.new(5.6, 1, 0.2), Vector3.new(-0.8, h + 0.4, 3.4), Color3.fromRGB(64, 92, 132))
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "AIRPORT"
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Parent = surface
	surface.Parent = sign
	sign.CFrame = sign.CFrame * CFrame.Angles(0, math.pi, 0) -- surface Front faces the viewer (+Z)
	cyl(m, "TowerShaft", 12, 1.8, Vector3.new(5.9, 6, -1.6), Color3.fromRGB(240, 242, 244))
	cyl(m, "TowerCab", 2.2, 3.6, Vector3.new(5.9, 13.1, -1.6), Color3.fromRGB(110, 176, 222))
	cyl(m, "TowerRoof", 0.5, 4.2, Vector3.new(5.9, 14.45, -1.6), Color3.fromRGB(64, 92, 132))
	cyl(m, "Antenna", 1.8, 0.25, Vector3.new(5.9, 15.6, -1.6), P.roofRed)
	return finish(m)
end

builders.Hangar = function()
	local m = newModel("Hangar")
	box(m, "Walls", Vector3.new(16, 5, 12), Vector3.new(0, 2.5, 0), Color3.fromRGB(176, 186, 198))
	add(m, "Part", "Roof", Vector3.new(12.6, 16.4, 16.4), CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(118, 136, 158), { Shape = Enum.PartType.Cylinder })
	m.Roof.CFrame = CFrame.new(0, -0.2, 0) * CFrame.Angles(0, math.rad(90), 0)
	box(m, "Door", Vector3.new(12, 4.6, 0.2), Vector3.new(0, 2.3, 6.05), Color3.fromRGB(84, 92, 104))
	box(m, "Stripe", Vector3.new(16.05, 0.5, 12.05), Vector3.new(0, 4.6, 0), Color3.fromRGB(64, 92, 132))
	return finish(m)
end

builders.Plane = function()
	local m = newModel("Plane")
	add(m, "Part", "Fuselage", Vector3.new(13, 2, 2), CFrame.new(0, 2, 0), P.white, { Shape = Enum.PartType.Cylinder })
	add(m, "Part", "Nose", Vector3.new(2, 2, 2), CFrame.new(6.5, 2, 0), P.white, { Shape = Enum.PartType.Ball })
	box(m, "Wing", Vector3.new(2.6, 0.3, 13), Vector3.new(0.4, 1.6, 0), P.metal)
	box(m, "Stabilizer", Vector3.new(1.4, 0.25, 5), Vector3.new(-5.8, 2.3, 0), P.metal)
	add(m, "Part", "Fin", Vector3.new(0.3, 2.6, 2.4), CFrame.new(-5.8, 3.9, 0) * CFrame.Angles(0, math.rad(90), 0), P.roofRed, nil)
	m.Fin:Destroy()
	add(m, "WedgePart", "Fin", Vector3.new(0.3, 2.6, 2.4), CFrame.new(-5.8, 4.1, 0) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(0, 0, 0), P.roofRed)
	box(m, "Stripe", Vector3.new(10, 0.35, 2.05), Vector3.new(0.5, 2.1, 0), Color3.fromRGB(64, 92, 132))
	cyl(m, "Engine", 0.9, 0.9, Vector3.new(0.9, 1.1, 3), P.darkGrey).CFrame = CFrame.new(0.9, 1.1, 3)
	m.Engine.Size = Vector3.new(1.8, 0.9, 0.9)
	local engine2 = m.Engine:Clone()
	engine2.CFrame = CFrame.new(0.9, 1.1, -3)
	engine2.Parent = m
	return finish(m)
end

builders.TreeRound = function()
	local m = newModel("TreeRound")
	box(m, "Trunk", Vector3.new(0.8, 2.6, 0.8), Vector3.new(0, 1.3, 0), P.trunk)
	box(m, "Leaves", Vector3.new(4.2, 3.4, 4.2), Vector3.new(0, 4.2, 0), P.leaf)
	add(m, "Part", "Leaves", Vector3.new(3, 2.4, 3), CFrame.new(0.2, 6.2, -0.2) * CFrame.Angles(0, math.rad(45), 0), P.leafLight)
	return finish(m)
end

builders.TreePine = function()
	local m = newModel("TreePine")
	box(m, "Trunk", Vector3.new(0.7, 1.8, 0.7), Vector3.new(0, 0.9, 0), P.trunk)
	local tiers = { { 4.4, 1.8, 2.5 }, { 3.4, 1.7, 4.1 }, { 2.4, 1.6, 5.6 }, { 1.3, 1.5, 7 } }
	for i, t in ipairs(tiers) do
		add(m, "Part", "Needles", Vector3.new(t[1], t[2], t[1]), CFrame.new(0, t[3], 0) * CFrame.Angles(0, math.rad((i % 2) * 45), 0), i % 2 == 0 and P.pine or P.pineDark)
	end
	return finish(m)
end

builders.Rock = function()
	local m = newModel("Rock")
	add(m, "Part", "Stone", Vector3.new(3.2, 2, 2.6), CFrame.new(0, 0.8, 0) * CFrame.Angles(math.rad(8), math.rad(25), math.rad(-6)), P.rock)
	add(m, "Part", "Stone", Vector3.new(1.8, 1.4, 1.6), CFrame.new(0.9, 1.6, 0.4) * CFrame.Angles(math.rad(-10), math.rad(60), math.rad(12)), P.rockDark)
	return finish(m)
end

function AssetBuilder.build()
	local ServerStorage = game:GetService("ServerStorage")
	local root = ServerStorage:FindFirstChild("RoadLinkAssets") or Instance.new("Folder")
	root.Name = "RoadLinkAssets"
	root.Parent = ServerStorage
	local models = root:FindFirstChild("Models")
	if models then
		models:Destroy()
	end
	models = Instance.new("Folder")
	models.Name = "Models"
	local names = {}
	for name, builder in pairs(builders) do
		local model = builder()
		model.Parent = models
		table.insert(names, name)
	end
	models.Parent = root
	table.sort(names)
	return names
end

return AssetBuilder
