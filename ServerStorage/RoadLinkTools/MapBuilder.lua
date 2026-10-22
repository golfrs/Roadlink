-- Generates RoadLink's map template from Shared.RegionConfig: ground, river with natural banks, rolling hills,
-- the mountain ridge, forests and landmarks (town square, church, fields, farmhouse, airport).
-- The template is cloned for every player. Rebuild (edit mode): require(game.ServerStorage.RoadLinkTools.Rebuild:Clone())()
local MapBuilder = {}

function MapBuilder.build(shared, models, AssetBuilder)
	local GameConfig = require(shared.GameConfig)
	local RegionConfig = require(shared.RegionConfig)
	local Grid = require(shared.Grid)
	local P = AssetBuilder.Palette
	local cyl = AssetBuilder.cyl
	local G = GameConfig.GridSize
	local rng = Random.new(20261022)

	local function add(parent, a, b, ...)
		if typeof(b) == "Vector3" then
			return AssetBuilder.add(parent, "Part", a, b, ...)
		end
		return AssetBuilder.add(parent, a, b, ...)
	end

	local map = Instance.new("Model")
	map.Name = "MapTemplate"
	local function folder(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = map
		return f
	end
	local groundF, riverF, natureF, treesF, landmarksF = folder("Ground"), folder("River"), folder("Nature"), folder("Trees"), folder("Landmarks")

	-- Palette: calm, slightly warm greens; earthy banks; deep blue water.
	local GRASS = Color3.fromRGB(108, 160, 76)
	local HILL = { Color3.fromRGB(96, 148, 70), Color3.fromRGB(104, 156, 74), Color3.fromRGB(112, 162, 78) }
	local ROCK = { Color3.fromRGB(128, 124, 116), Color3.fromRGB(144, 140, 132), Color3.fromRGB(116, 112, 106) }
	local EARTH = Color3.fromRGB(150, 126, 96)
	local SAND = Color3.fromRGB(226, 206, 156)
	local PAVING = Color3.fromRGB(206, 194, 168)

	local minX, maxX, minZ, maxZ = Grid.worldBounds()
	local MARGIN = 56
	local innerX0, innerX1 = minX * G - G / 2, maxX * G + G / 2
	local innerZ0, innerZ1 = minZ * G - G / 2, maxZ * G + G / 2
	local wx0, wx1, wz0, wz1 = innerX0 - MARGIN, innerX1 + MARGIN, innerZ0 - MARGIN, innerZ1 + MARGIN

	local riverLine, riverWidth = nil, 1
	for _, id in ipairs(RegionConfig.Order) do
		local river = RegionConfig.Regions[id].River
		if river then
			riverLine, riverWidth = river.Line, river.Width or 1
		end
	end
	local cx0 = (riverLine or 0) * G - 6
	local cx1 = ((riverLine or 0) + riverWidth - 1) * G + 6
	local RX = (cx0 + cx1) / 2

	local function slab(parent, name, x0, x1, z0, z1, top, thick, color, extra)
		if x1 - x0 < 0.05 or z1 - z0 < 0.05 then
			return nil
		end
		return add(parent, name, Vector3.new(x1 - x0, thick, z1 - z0), CFrame.new((x0 + x1) / 2, top - thick / 2, (z0 + z1) / 2), color, extra)
	end
	local function splitX(x0, x1, fn)
		if not riverLine or x1 <= cx0 or x0 >= cx1 then
			fn(x0, x1)
			return
		end
		if x0 < cx0 then fn(x0, cx0) end
		if x1 > cx1 then fn(cx1, x1) end
	end
	local function rectStuds(rect)
		return rect.MinX * G - G / 2, rect.MaxX * G + G / 2, rect.MinZ * G - G / 2, rect.MaxZ * G + G / 2
	end
	local function place(name, cf, scale, parent)
		local model = models[name]:Clone()
		if scale and scale ~= 1 then
			model:ScaleTo(scale)
		end
		model:PivotTo(cf)
		model.Parent = parent
		return model
	end
	local function pick(list)
		return list[rng:NextInteger(1, #list)]
	end
	local function nodesNear(x, z, radius)
		local nodes = {}
		for nx = math.floor((x - radius) / G), math.ceil((x + radius) / G) do
			for nz = math.floor((z - radius) / G), math.ceil((z + radius) / G) do
				if (Vector2.new(nx * G, nz * G) - Vector2.new(x, z)).Magnitude < radius + 3 then
					table.insert(nodes, Grid.key(nx, nz))
				end
			end
		end
		return table.concat(nodes, ";")
	end

	-- Cells kept clear of decoration.
	local reserved = {}
	local function reserve(x, z, radius)
		for dx = -radius, radius do
			for dz = -radius, radius do
				reserved[Grid.key(x + dx, z + dz)] = true
			end
		end
	end
	reserve(GameConfig.RootX, GameConfig.RootZ, 2)
	for _, gate in ipairs(Grid.gateList) do
		reserve(gate.x, gate.z, 1)
	end
	for _, id in ipairs(RegionConfig.Order) do
		local cfg = RegionConfig.Regions[id]
		for _, seed in ipairs(cfg.Seeds or {}) do
			reserve(seed.x, seed.z, 1)
		end
		if cfg.River then
			for _, c in ipairs(cfg.River.Crossings) do
				for line = cfg.River.Line - 1, cfg.River.Line + (cfg.River.Width or 1) do
					reserve(line, c, 1)
				end
			end
		end
	end
	local function cellFree(x, z)
		return not reserved[Grid.key(x, z)] and not Grid.isMountain(x, z) and not Grid.blockedAt(x, z) and not Grid.isRiver(x, z)
	end

	-- 1. Ground --------------------------------------------------------------------------------------
	-- Region land plus a meadow ring around it, all the same tone so no rectangles show.
	for _, id in ipairs(RegionConfig.Order) do
		local cfg = RegionConfig.Regions[id]
		local x0, x1, z0, z1 = rectStuds(cfg.Bounds)
		splitX(x0, x1, function(a, b)
			local part = slab(groundF, "Ground", a, b, z0, z1, 0, 10, cfg.TerrainColor)
			part:SetAttribute("RegionId", id)
			part:SetAttribute("BaseColor", cfg.TerrainColor)
		end)
	end
	for _, band in ipairs({
		{ wx0, wx1, wz0, innerZ0 }, { wx0, wx1, innerZ1, wz1 },
		{ wx0, innerX0, innerZ0, innerZ1 }, { innerX1, wx1, innerZ0, innerZ1 },
	}) do
		splitX(band[1], band[2], function(a, b)
			slab(groundF, "Meadow", a, b, band[3], band[4], 0, 10, GRASS)
		end)
	end
	-- 2. River ---------------------------------------------------------------------------------------
	if riverLine then
		slab(riverF, "Water", cx0, cx1, wz0, wz1, -2.2, 1.2, Color3.fromRGB(52, 128, 198), { Material = Enum.Material.Glass, Transparency = 0.08, CanQuery = false, CastShadow = false })
		slab(riverF, "Shallows", cx0 + 2.2, cx0 + 4.2, wz0, wz1, -2.15, 0.1, Color3.fromRGB(86, 164, 206), { Transparency = 0.35, CanQuery = false, CastShadow = false })
		slab(riverF, "Shallows", cx1 - 4.2, cx1 - 2.2, wz0, wz1, -2.15, 0.1, Color3.fromRGB(86, 164, 206), { Transparency = 0.35, CanQuery = false, CastShadow = false })
		slab(riverF, "Riverbed", cx0, cx1, wz0, wz1, -3.6, 2, Color3.fromRGB(44, 86, 120), { CanQuery = false })
		-- Banks: sloping wedges (rock, earth or sandy beach) from the grass edge down into the water.
		for _, side in ipairs({ -1, 1 }) do
			local edge = side < 0 and cx0 or cx1
			local yaw = side < 0 and -math.pi / 2 or math.pi / 2
			local z = wz0
			while z < wz1 do
				local length = rng:NextNumber(10, 18)
				local roll = rng:NextNumber()
				local width, height, color
				if roll < 0.28 then
					width, height, color = 3.6, 2.9, SAND -- beach
				elseif roll < 0.6 then
					width, height, color = 2.6, 3.2, EARTH:Lerp(ROCK[1], rng:NextNumber(0, 0.5))
				else
					width, height, color = 2.2, 3.4, pick(ROCK)
				end
				local x = edge - side * width / 2
				add(riverF, "WedgePart", "Bank", Vector3.new(length + 0.2, height, width), CFrame.new(x, 0.02 - height / 2, z + length / 2) * CFrame.Angles(0, yaw, 0), color, { CanQuery = false })
				if roll >= 0.6 and rng:NextNumber() < 0.5 then
					add(riverF, "Outcrop", Vector3.new(rng:NextNumber(2, 3.2), rng:NextNumber(1.2, 2.2), rng:NextNumber(2.4, 4)), CFrame.new(edge - side * 0.8, 0.1, z + length / 2) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-12, 12))), pick(ROCK), { CanQuery = false })
				end
				z += length
			end
			for _ = 1, 3 do
				place("Rock", CFrame.new(edge - side * rng:NextNumber(3, 5), -2.5, rng:NextNumber(wz0 + 10, wz1 - 10)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(0.6, 1), riverF)
			end
		end
		-- Stone abutments mark every bridge site and anchor the bridges.
		for _, id in ipairs(RegionConfig.Order) do
			local river = RegionConfig.Regions[id].River
			if river then
				for _, c in ipairs(river.Crossings) do
					local zc = c * G
					for _, side in ipairs({ -1, 1 }) do
						local x = (side < 0 and cx0 or cx1) - side * 0.6
						add(riverF, "Abutment", Vector3.new(2.6, 3.2, 12), CFrame.new(x, -1.5, zc), Color3.fromRGB(184, 176, 164), { CanQuery = false })
					end
				end
			end
		end
	end

	-- 3. Rolling hills around the edge (buried spheres give soft domes). Kept outside the playable land.
	local function dome(parent, x, z, r, h, color)
		local R = (r * r + h * h) / (2 * h)
		return add(parent, "Hill", Vector3.new(2 * R, 2 * R, 2 * R), CFrame.new(x, h - R, z), color, { Shape = Enum.PartType.Ball, CanQuery = false })
	end
	local function hillCluster(x, z, size)
		local r = size
		local h = rng:NextNumber(4, 8)
		local R = (r * r + h * h) / (2 * h)
		if math.abs(x - RX) < R + 10 then
			return
		end
		dome(natureF, x, z, r, h, pick(HILL))
		for _ = 1, rng:NextInteger(1, 2) do
			local angle = rng:NextNumber(0, 6.28)
			local d = r * rng:NextNumber(0.5, 0.8)
			local sx, sz = x + math.cos(angle) * d, z + math.sin(angle) * d
			local sr, sh = r * rng:NextNumber(0.5, 0.75), h * rng:NextNumber(0.5, 0.8)
			local sR = (sr * sr + sh * sh) / (2 * sh)
			if math.abs(sx - RX) > sR + 10 then
				dome(natureF, sx, sz, sr, sh, pick(HILL))
			end
		end
		if rng:NextNumber() < 0.5 then
			for _ = 1, rng:NextInteger(1, 3) do
				local angle = rng:NextNumber(0, 6.28)
				local d = rng:NextNumber(0, r * 0.45)
				local tx, tz = x + math.cos(angle) * d, z + math.sin(angle) * d
				local ty = (h - R) + math.sqrt(math.max(R * R - d * d, 0))
				place(rng:NextNumber() < 0.6 and "TreePine" or "TreeRound", CFrame.new(tx, ty - 0.3, tz) * CFrame.Angles(0, angle, 0), rng:NextNumber(0.9, 1.3), natureF)
			end
		end
	end
	local function edgeRun(fromA, toA, fixed, alongX, outward)
		local t = fromA + rng:NextNumber(10, 30)
		while t < toA - 10 do
			local size = rng:NextNumber(18, 28)
			local offset = fixed + outward * rng:NextNumber(size * 0.75, MARGIN - 6)
			if alongX then
				hillCluster(t, offset, size)
			else
				hillCluster(offset, t, size)
			end
			t += size * 1.9 + rng:NextNumber(10, 30)
		end
	end
	edgeRun(wx0, wx1, innerZ0, true, -1)
	edgeRun(wx0, wx1, innerZ1, true, 1)
	edgeRun(innerZ0, innerZ1, innerX0, false, -1)
	edgeRun(innerZ0, innerZ1, innerX1, false, 1)

	-- 4. Mountains: a grassy foothill with sloped sides and jagged rocky peaks. Roads only cross by tunnel.
	for _, id in ipairs(RegionConfig.Order) do
		for _, rect in ipairs(RegionConfig.Regions[id].Mountains or {}) do
			local x0, x1, z0, z1 = rectStuds(rect)
			x1 = math.min(x1, cx0 - 0.5)
			local slope = 6
			local baseH = 4.5
			slab(natureF, "Foothill", x0, x1, z0 + slope, z1 - slope, baseH, baseH, HILL[1])
			for _, side in ipairs({ -1, 1 }) do
				local zc = side < 0 and (z0 + slope / 2) or (z1 - slope / 2)
				add(natureF, "WedgePart", "FoothillSlope", Vector3.new(x1 - x0, baseH, slope), CFrame.new((x0 + x1) / 2, baseH / 2, zc) * CFrame.Angles(0, side < 0 and 0 or math.pi, 0), HILL[2], { CanQuery = false })
			end
			add(natureF, "WedgePart", "FoothillSlope", Vector3.new(z1 - z0 - slope * 2, baseH, slope), CFrame.new(x0 + slope / 2 - slope, baseH / 2, (z0 + z1) / 2) * CFrame.Angles(0, -math.pi / 2, 0), HILL[2], { CanQuery = false })
			local span = (x1 - 8) - (x0 + 8)
			local count = math.max(2, math.floor(span / 15))
			for i = 0, count - 1 do
				local t = i / (count - 1)
				local x = x0 + 8 + span * t + rng:NextNumber(-3, 3)
				local z = (z0 + z1) / 2 + rng:NextNumber(-2.5, 2.5)
				local h = 14 + 12 * math.sin(t * math.pi) + rng:NextNumber(-3, 4)
				local s = rng:NextNumber(12, 15)
				local base = baseH - 0.5
				local tiers = { { s, h * 0.45, ROCK[3] }, { s * 0.66, h * 0.33, ROCK[1] }, { s * 0.36, h * 0.27, ROCK[2] } }
				for _, tier in ipairs(tiers) do
					add(natureF, "Peak", Vector3.new(tier[1], tier[2], tier[1] * rng:NextNumber(0.8, 1)),
						CFrame.new(x, base + tier[2] / 2, z) * CFrame.Angles(math.rad(rng:NextNumber(-9, 9)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-9, 9))),
						tier[3], { CanQuery = false })
					base += tier[2] * 0.85
				end
				if h > 19 then
					add(natureF, "Snow", Vector3.new(s * 0.3, 1.4, s * 0.3), CFrame.new(x, base + 0.2, z) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), math.rad(rng:NextNumber(0, 90)), 0), Color3.fromRGB(248, 250, 252), { CanQuery = false })
				end
			end
			for _ = 1, 9 do
				local tx = rng:NextNumber(x0 + 4, x1 - 4)
				local tz = rng:NextNumber() < 0.5 and (z0 + slope + 1.5) or (z1 - slope - 1.5)
				place("TreePine", CFrame.new(tx, baseH, tz) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(0.8, 1.1), natureF)
			end
		end
	end

	-- 5. Trees. Each records the grid nodes it covers so the game clears it when you build there.
	local planted = {}
	local function plant(x, z, kind, scale, parent)
		for _, other in ipairs(planted) do
			if (other - Vector2.new(x, z)).Magnitude < 5 then
				return false
			end
		end
		if math.abs(x - RX) < (cx1 - cx0) / 2 + 5 then
			return false
		end
		local tree = place(kind, CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), scale, parent or treesF)
		tree:SetAttribute("Nodes", nodesNear(x, z, 3))
		table.insert(planted, Vector2.new(x, z))
		return true
	end
	for _, id in ipairs(RegionConfig.Order) do
		local cfg = RegionConfig.Regions[id]
		local pineShare = id == "AirportHeights" and 0.7 or 0.35
		for _, rect in ipairs(cfg.Forests or {}) do
			local x0, x1, z0, z1 = rectStuds(rect)
			local target = math.floor((rect.MaxX - rect.MinX + 1) * (rect.MaxZ - rect.MinZ + 1) * 0.5)
			local tries, count = 0, 0
			while count < target and tries < target * 12 do
				tries += 1
				local x, z = rng:NextNumber(x0 + 2, x1 - 2), rng:NextNumber(z0 + 2, z1 - 2)
				local cx, cz = math.floor(x / G + 0.5), math.floor(z / G + 0.5)
				if cellFree(cx, cz) and plant(x, z, rng:NextNumber() < pineShare and "TreePine" or "TreeRound", rng:NextNumber(0.9, 1.3)) then
					count += 1
				end
			end
		end
	end
	for _ = 1, 55 do
		local side = rng:NextInteger(1, 4)
		local x, z
		if side == 1 then
			x, z = rng:NextNumber(wx0 + 6, wx1 - 6), rng:NextNumber(wz0 + 6, innerZ0 - 4)
		elseif side == 2 then
			x, z = rng:NextNumber(wx0 + 6, wx1 - 6), rng:NextNumber(innerZ1 + 4, wz1 - 6)
		elseif side == 3 then
			x, z = rng:NextNumber(wx0 + 6, innerX0 - 4), rng:NextNumber(wz0 + 6, wz1 - 6)
		else
			x, z = rng:NextNumber(innerX1 + 4, wx1 - 6), rng:NextNumber(wz0 + 6, wz1 - 6)
		end
		plant(x, z, rng:NextNumber() < 0.5 and "TreePine" or "TreeRound", rng:NextNumber(0.95, 1.35))
	end

	-- 6. Village: paved plaza at the Town Junction with lamp posts.
	-- Small props are cleared like trees when a road is built over them.
	local root = Vector3.new(GameConfig.RootX * G, 0, GameConfig.RootZ * G)
	cyl(landmarksF, "PlazaEdge", 0.08, 16, root + Vector3.new(0, 0.04, 0), Color3.fromRGB(168, 156, 132), { CanQuery = false, CastShadow = false })
	cyl(landmarksF, "Plaza", 0.1, 14.6, root + Vector3.new(0, 0.05, 0), PAVING, { CanQuery = false, CastShadow = false })
	-- lamp posts around the plaza on the diagonals (between road lines)
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		local pos = root + Vector3.new(math.cos(angle) * 9.2, 0, math.sin(angle) * 9.2)
		local lamp = Instance.new("Model")
		lamp.Name = "Lamp"
		cyl(lamp, "Post", 4.2, 0.35, pos + Vector3.new(0, 2.1, 0), Color3.fromRGB(60, 64, 72), { CanQuery = false })
		add(lamp, "Light", Vector3.new(0.9, 0.9, 0.9), CFrame.new(pos + Vector3.new(0, 4.5, 0)), Color3.fromRGB(255, 236, 180), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, CanQuery = false, CastShadow = false })
		lamp:SetAttribute("Nodes", nodesNear(pos.X, pos.Z, 1))
		lamp.Parent = treesF
	end

	-- 7. Landmarks on blocked land.
	for _, id in ipairs(RegionConfig.Order) do
		for _, rect in ipairs(RegionConfig.Regions[id].Blocked or {}) do
			local x0, x1, z0, z1 = rectStuds(rect)
			local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
			local holder = Instance.new("Model")
			holder.Name = rect.kind
			if rect.kind == "Church" then
				slab(holder, "Churchyard", x0 + 1, x1 - 1, z0 + 1, z1 - 1, 0.06, 0.1, Color3.fromRGB(122, 174, 88), { CanQuery = false })
				slab(holder, "ChurchPath", cx - 0.9, cx + 0.9, cz + 4, z1 - 1, 0.08, 0.1, PAVING, { CanQuery = false })
				place("Church", CFrame.new(cx, 0.06, cz - 1), 1.15, holder)
				place("TreeRound", CFrame.new(x0 + 2.5, 0.06, z1 - 2.5), 0.8, holder)
			elseif rect.kind == "TownSquare" then
				slab(holder, "SquareEdge", x0 + 0.6, x1 - 0.6, z0 + 0.6, z1 - 0.6, 0.08, 0.12, Color3.fromRGB(168, 156, 132), { CanQuery = false })
				slab(holder, "Square", x0 + 1.2, x1 - 1.2, z0 + 1.2, z1 - 1.2, 0.1, 0.12, PAVING, { CanQuery = false })
				cyl(holder, "FountainBase", 0.8, 6.4, Vector3.new(cx, 0.5, cz), Color3.fromRGB(196, 188, 174), { CanQuery = false })
				cyl(holder, "FountainWater", 0.1, 5.4, Vector3.new(cx, 0.9, cz), Color3.fromRGB(86, 168, 220), { Material = Enum.Material.Glass, CanQuery = false })
				cyl(holder, "FountainColumn", 2.2, 0.8, Vector3.new(cx, 1.6, cz), Color3.fromRGB(196, 188, 174), { CanQuery = false })
				cyl(holder, "FountainBowl", 0.4, 2.4, Vector3.new(cx, 2.8, cz), Color3.fromRGB(196, 188, 174), { CanQuery = false })
				for _, corner in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
					local px, pz = cx + corner[1] * 5, cz + corner[2] * 5
					cyl(holder, "Planter", 0.5, 2.2, Vector3.new(px, 0.4, pz), Color3.fromRGB(176, 166, 148), { CanQuery = false })
					place("TreeRound", CFrame.new(px, 0.6, pz) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), 0.7, holder)
				end
				for _, b in ipairs({ { 0, -4.4, 0 }, { 0, 4.4, 0 }, { -4.4, 0, 90 }, { 4.4, 0, 90 } }) do
					local bench = add(holder, "Bench", Vector3.new(2.2, 0.3, 0.7), CFrame.new(cx + b[1], 0.7, cz + b[2]) * CFrame.Angles(0, math.rad(b[3]), 0), Color3.fromRGB(150, 104, 66), { CanQuery = false })
					bench.Name = "Bench"
				end
			elseif rect.kind == "Field" then
				slab(holder, "Soil", x0 + 1, x1 - 1, z0 + 1, z1 - 1, 0.12, 0.2, Color3.fromRGB(146, 110, 72), { CanQuery = false })
				local width = x1 - x0 - 3
				local rows = math.floor(width / 2.2)
				local crop = rng:NextNumber() < 0.5
				-- crops everywhere except a farmyard corner (north-east) that holds the farmhouse
				local yardX, yardZ = x1 - 13, z0 + 13
				for i = 0, rows - 1 do
					local x = x0 + 1.5 + (i + 0.5) * (width / rows)
					local rz0, rz1 = z0 + 1.5, z1 - 1.5
					if x > yardX then
						rz0 = yardZ
					end
					local color = crop and (i % 2 == 0 and P.wheat or Color3.fromRGB(226, 178, 62)) or (i % 2 == 0 and Color3.fromRGB(110, 170, 70) or Color3.fromRGB(96, 156, 64))
					if rz1 - rz0 > 2 then
						add(holder, "Crop", Vector3.new(width / rows - 0.6, 0.7, rz1 - rz0), CFrame.new(x, 0.45, (rz0 + rz1) / 2), color, { CanQuery = false })
					end
				end
				slab(holder, "Farmyard", yardX + 0.5, x1 - 1.2, z0 + 1.2, yardZ - 0.5, 0.16, 0.1, Color3.fromRGB(196, 178, 140), { CanQuery = false })
				place("Farmhouse", CFrame.new(yardX + 6.3, 0.2, z0 + 6.6), 1, holder)
				local rail = Color3.fromRGB(156, 116, 78)
				for _, f in ipairs({
					{ Vector3.new(x1 - x0 - 1, 0.3, 0.25), Vector3.new(cx, 1.0, z0 + 0.5) }, { Vector3.new(x1 - x0 - 1, 0.3, 0.25), Vector3.new(cx, 1.0, z1 - 0.5) },
					{ Vector3.new(0.25, 0.3, z1 - z0 - 1), Vector3.new(x0 + 0.5, 1.0, cz) }, { Vector3.new(0.25, 0.3, z1 - z0 - 1), Vector3.new(x1 - 0.5, 1.0, cz) },
				}) do
					add(holder, "Fence", f[1], CFrame.new(f[2]), rail, { CanQuery = false })
					add(holder, "Fence", Vector3.new(f[1].X, 0.25, f[1].Z), CFrame.new(f[2] - Vector3.new(0, 0.5, 0)), rail, { CanQuery = false })
				end
				for _, corner in ipairs({ { x0 + 0.5, z0 + 0.5 }, { x1 - 0.5, z0 + 0.5 }, { x0 + 0.5, z1 - 0.5 }, { x1 - 0.5, z1 - 0.5 } }) do
					add(holder, "Post", Vector3.new(0.45, 1.5, 0.45), CFrame.new(corner[1], 0.75, corner[2]), rail, { CanQuery = false })
				end
				for _ = 1, 3 do
					local bale = cyl(holder, "HayBale", 1.3, 1.3, Vector3.new(0, 0, 0), Color3.fromRGB(230, 200, 110), { CanQuery = false })
					bale.CFrame = CFrame.new(rng:NextNumber(x0 + 3, x1 - 3), 0.95, z1 - 1.8)
				end
			elseif rect.kind == "Apron" then
				-- compact apron with a grass verge, two airliners, a hangar and a taxiway to the runway
				slab(holder, "Verge", x0, x1, z0, z1, 0.05, 0.1, Color3.fromRGB(118, 168, 82), { CanQuery = false })
				local ax0, ax1 = x0 + 4, x1 - 22
				slab(holder, "Apron", ax0, ax1, z0 + 6, z1 - 2, 0.12, 0.2, Color3.fromRGB(178, 180, 182), { CanQuery = false })
				slab(holder, "Stand", ax0 + 6, ax0 + 6.3, z0 + 8, z1 - 4, 0.14, 0.05, Color3.fromRGB(246, 204, 70), { CanQuery = false })
				slab(holder, "Stand", ax0 + 30, ax0 + 30.3, z0 + 8, z1 - 4, 0.14, 0.05, Color3.fromRGB(246, 204, 70), { CanQuery = false })
				place("Plane", CFrame.new(ax0 + 16, 0.12, (z0 + z1) / 2 + 2) * CFrame.Angles(0, math.rad(90), 0), 1.35, holder)
				place("Plane", CFrame.new(ax0 + 40, 0.12, (z0 + z1) / 2 + 2) * CFrame.Angles(0, math.rad(90), 0), 1.35, holder)
				local hx = x1 - 11
				place("Hangar", CFrame.new(hx, 0.05, cz + 2), 1, holder)
				local tx = ax0 + 4
				slab(holder, "Taxiway", tx - 3.5, tx + 3.5, z0 - 2, z0 + 6, 0.13, 0.2, Color3.fromRGB(70, 74, 80), { CanQuery = false })
				slab(holder, "TaxiLine", tx - 0.15, tx + 0.15, z0 - 2, z0 + 6, 0.15, 0.05, Color3.fromRGB(246, 204, 70), { CanQuery = false })
			elseif rect.kind == "Runway" then
				local runway = Color3.fromRGB(64, 67, 74)
				local white = Color3.fromRGB(244, 244, 240)
				slab(holder, "RunwayVerge", x0, x1, z0, z1, 0.06, 0.1, Color3.fromRGB(122, 170, 86), { CanQuery = false })
				slab(holder, "Runway", x0 + 2, x1 - 2, z0 + 3, z1 - 3, 0.14, 0.2, runway, { CanQuery = false })
				slab(holder, "Edge", x0 + 3, x1 - 3, z0 + 3.8, z0 + 4.2, 0.16, 0.05, white, { CanQuery = false })
				slab(holder, "Edge", x0 + 3, x1 - 3, z1 - 4.2, z1 - 3.8, 0.16, 0.05, white, { CanQuery = false })
				local x = x0 + 16
				while x < x1 - 16 do
					slab(holder, "Centreline", x, x + 6, cz - 0.3, cz + 0.3, 0.16, 0.05, white, { CanQuery = false })
					x += 12
				end
				for _, endX in ipairs({ x0 + 4, x1 - 10 }) do
					for i = -3, 3 do
						if i ~= 0 then
							slab(holder, "Threshold", endX, endX + 6, cz + i * 2.6 - 0.5, cz + i * 2.6 + 0.5, 0.16, 0.05, white, { CanQuery = false })
						end
					end
				end
				for i = 0, math.floor((x1 - x0) / 10) do
					for _, ez in ipairs({ z0 + 3, z1 - 3 }) do
						add(holder, "RunwayLight", Vector3.new(0.4, 0.4, 0.4), CFrame.new(x0 + 4 + i * 10, 0.35, ez), Color3.fromRGB(255, 220, 140), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, CanQuery = false, CastShadow = false })
					end
				end
			end
			holder.Parent = landmarksF
		end
	end

	map.WorldPivot = CFrame.new()
	return map
end

return MapBuilder
