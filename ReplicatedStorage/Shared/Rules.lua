-- Construction rules shared by the server (authoritative checks) and the client (previews only).
-- A "view" describes one player's city: cash, unlocked, connected, edgeKind(), roadNode(), buildingAt(), buildings, edgeCount, buildingCount.
local Shared = script.Parent
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RoadConfig = require(Shared:WaitForChild("RoadConfig"))
local BuildingConfig = require(Shared:WaitForChild("BuildingConfig"))
local RegionConfig = require(Shared:WaitForChild("RegionConfig"))
local Grid = require(Shared:WaitForChild("Grid"))

local Rules = {}

function Rules.money(value)
	local n = math.floor((value or 0) + 0.5)
	local digits = tostring(math.abs(n))
	local withCommas = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(withCommas, 1, 1) == "," then
		withCommas = string.sub(withCommas, 2)
	end
	return (n < 0 and "-$" or "$") .. withCommas
end

local function fail(message, code, extra)
	local result = extra or {}
	result.ok = false
	result.message = message
	result.code = code or "invalid"
	return result
end

function Rules.isBridgeEdge(x1, z1, x2, z2)
	return Grid.isRiver(x1, z1) or Grid.isRiver(x2, z2)
end

function Rules.isTunnelEdge(x1, z1, x2, z2)
	return Grid.isMountain(x1, z1) or Grid.isMountain(x2, z2)
end

-- True when a bridge edge would run along the river instead of across it.
function Rules.alongRiver(x1, z1, x2, z2)
	local river = Grid.riverAt(x1, z1) or Grid.riverAt(x2, z2)
	if not river then
		return false
	end
	if river.Axis == "X" then
		return x1 == x2
	end
	return z1 == z2
end

function Rules.edgeCost(kind, x1, z1, x2, z2)
	local cost = RoadConfig.Types[kind].CostPerTile
	local river = Grid.riverAt(x1, z1) or Grid.riverAt(x2, z2)
	if river then
		cost = math.max(cost, river.BridgeCostPerTile)
	end
	if Rules.isTunnelEdge(x1, z1, x2, z2) then
		cost = math.max(cost, RoadConfig.TunnelCostPerTile)
	end
	return cost
end

function Rules.edgeUpkeep(kind, x1, z1, x2, z2)
	local upkeep = RoadConfig.Types[kind].UpkeepPerTile
	if Rules.isBridgeEdge(x1, z1, x2, z2) then
		upkeep += RoadConfig.BridgeUpkeepPerTile
	end
	if Rules.isTunnelEdge(x1, z1, x2, z2) then
		upkeep += RoadConfig.TunnelUpkeepPerTile
	end
	return upkeep
end

-- Can a road pass through this node?
function Rules.nodeBuildable(view, x, z)
	local region = Grid.regionAt(x, z)
	if not region then
		return false, "That's outside your land.", "bounds"
	end
	if not view.unlocked[region] then
		return false, RegionConfig.Regions[region].DisplayName .. " is locked. Unlock it from the Regions panel.", "locked"
	end
	if view.buildingAt(Grid.key(x, z)) then
		return false, "A building is in the way.", "blocked"
	end
	local blocked = Grid.blockedAt(x, z)
	if blocked then
		return false, "The " .. blocked.name .. " is in the way.", "blocked"
	end
	if Grid.isRiver(x, z) and not Grid.isCrossing(x, z) then
		return false, "Roads can only cross the river at the marked bridge sites.", "river"
	end
	return true
end

-- Splits a straight run into one-tile steps. Returns nil and a message if the run is not straight.
function Rules.runEdges(x1, z1, x2, z2, maxSpan)
	if not (Grid.isInt(x1) and Grid.isInt(z1) and Grid.isInt(x2) and Grid.isInt(z2)) then
		return nil, "Invalid road position."
	end
	if (x1 == x2) == (z1 == z2) then
		return nil, "Roads must be straight and at least one tile long."
	end
	local span = math.abs(x2 - x1) + math.abs(z2 - z1)
	if span > (maxSpan or 64) then
		return nil, "That road section is too long."
	end
	local dx = x2 > x1 and 1 or (x2 < x1 and -1 or 0)
	local dz = z2 > z1 and 1 or (z2 < z1 and -1 or 0)
	local steps = {}
	local cx, cz = x1, z1
	for _ = 1, span do
		local nx, nz = cx + dx, cz + dz
		table.insert(steps, { x1 = cx, z1 = cz, x2 = nx, z2 = nz, key = Grid.edgeKey(cx, cz, nx, nz) })
		cx, cz = nx, nz
	end
	return steps
end

-- Plans a straight road segment. One end must already be connected to the Town Junction.
function Rules.planRoad(view, x1, z1, x2, z2, kind)
	local data = RoadConfig.Types[kind]
	if not data then
		return fail("Choose a road type first.")
	end
	if data.RequiresRegion and not view.unlocked[data.RequiresRegion] then
		return fail(data.DisplayName .. " unlocks with the " .. RegionConfig.Regions[data.RequiresRegion].DisplayName .. ".", "locked")
	end
	if not (Grid.isInt(x1) and Grid.isInt(z1) and Grid.isInt(x2) and Grid.isInt(z2)) then
		return fail("Roads must snap to the grid.")
	end
	if x1 == x2 and z1 == z2 then
		return fail("Move to choose where the road ends.", "short")
	end
	if x1 ~= x2 and z1 ~= z2 then
		return fail("Roads run in straight lines. Add corners one segment at a time.", "diagonal")
	end
	local span = math.abs(x2 - x1) + math.abs(z2 - z1)
	if span > GameConfig.MaxRoadSpan then
		return fail("One segment can be at most " .. GameConfig.MaxRoadSpan .. " tiles long.", "long")
	end
	if not view.connected[Grid.key(x1, z1)] then
		if view.connected[Grid.key(x2, z2)] then
			x1, z1, x2, z2 = x2, z2, x1, z1
		else
			return fail("Start from the Town Junction or a road that's already connected.", "disconnected")
		end
	end
	local steps = Rules.runEdges(x1, z1, x2, z2, GameConfig.MaxRoadSpan)
	local result = { x1 = x1, z1 = z1, x2 = x2, z2 = z2, edges = {}, cost = 0, tiles = 0, bridgeTiles = 0, tunnelTiles = 0 }
	for _, step in ipairs(steps) do
		local okNode, why, code = Rules.nodeBuildable(view, step.x2, step.z2)
		if not okNode then
			return fail(why, code, result)
		end
		local bridge = Rules.isBridgeEdge(step.x1, step.z1, step.x2, step.z2)
		if bridge and Rules.alongRiver(step.x1, step.z1, step.x2, step.z2) then
			return fail("Roads can't run along the river.", "river", result)
		end
		local tunnel = Rules.isTunnelEdge(step.x1, step.z1, step.x2, step.z2)
		if not view.edgeKind(step.key) then
			local cost = Rules.edgeCost(kind, step.x1, step.z1, step.x2, step.z2)
			step.kind, step.bridge, step.cost = kind, bridge, cost
			table.insert(result.edges, step)
			result.cost += cost
			result.tiles += 1
			if bridge then
				result.bridgeTiles += 1
			end
			if tunnel then
				result.tunnelTiles += 1
			end
		end
	end
	if result.tiles == 0 then
		return fail("That road is already built.", "exists", result)
	end
	if view.edgeCount + result.tiles > GameConfig.MaxRoadEdges then
		return fail("Your network has reached the prototype limit of " .. GameConfig.MaxRoadEdges .. " tiles.", "limit", result)
	end
	if view.cash < result.cost then
		return fail("Not enough cash: this road costs " .. Rules.money(result.cost) .. ".", "funds", result)
	end
	result.ok = true
	result.message = string.format("%d tile%s · %s", result.tiles, result.tiles == 1 and "" or "s", Rules.money(result.cost))
	return result
end

-- A building has road access when a connected road node lies within one tile (including diagonals).
function Rules.hasAccess(view, x, z)
	for dx = -1, 1 do
		for dz = -1, 1 do
			if dx ~= 0 or dz ~= 0 then
				local key = Grid.key(x + dx, z + dz)
				if view.connected[key] and view.roadNode(key) then
					return true
				end
			end
		end
	end
	return false
end

function Rules.planBuilding(view, kind, x, z)
	local data = BuildingConfig.Types[kind]
	if not data then
		return fail("Choose a building type first.")
	end
	if data.Buildable == false then
		return fail(data.DisplayName .. "s can't be built.")
	end
	if not (Grid.isInt(x) and Grid.isInt(z)) then
		return fail("Buildings must snap to the grid.")
	end
	local region = Grid.regionAt(x, z)
	if not region then
		return fail("That's outside your land.", "bounds")
	end
	if not view.unlocked[region] then
		return fail(RegionConfig.Regions[region].DisplayName .. " is locked.", "locked")
	end
	if Grid.isRiver(x, z) then
		return fail("You can't build on the river.", "river")
	end
	if Grid.isMountain(x, z) then
		return fail("You can't build on the mountains.", "blocked")
	end
	local blocked = Grid.blockedAt(x, z)
	if blocked then
		return fail("You can't build on the " .. blocked.name .. ".", "blocked")
	end
	local key = Grid.key(x, z)
	if key == Grid.rootKey() then
		return fail("Keep the Town Junction clear for roads.", "blocked")
	end
	if Grid.gateAt(x, z) then
		return fail("Keep the region gate clear for roads.", "blocked")
	end
	if view.roadNode(key) then
		return fail("There's a road here. Pick an empty tile beside it.", "blocked")
	end
	for _, other in ipairs(view.buildings) do
		if math.abs(other.x - x) < 2 and math.abs(other.z - z) < 2 then
			return fail("Too close to " .. (other.name or "another building") .. ". Leave a free tile between buildings.", "blocked")
		end
	end
	if view.buildingCount >= GameConfig.MaxBuildings then
		return fail("Your city has reached the prototype limit of " .. GameConfig.MaxBuildings .. " buildings.", "limit")
	end
	local result = { cost = data.Cost, access = Rules.hasAccess(view, x, z) }
	if view.cash < data.Cost then
		return fail("Not enough cash: " .. data.DisplayName .. " costs " .. Rules.money(data.Cost) .. ".", "funds", result)
	end
	result.ok = true
	return result
end

return Rules
