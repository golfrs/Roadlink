-- Grid helpers shared by server and client: node keys, coordinate conversion, region/gate/river lookups.
local Shared = script.Parent
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RegionConfig = require(Shared:WaitForChild("RegionConfig"))

local Grid = {}
local SIZE = GameConfig.GridSize
Grid.Size = SIZE

function Grid.key(x, z)
	return tostring(x) .. "," .. tostring(z)
end

function Grid.parse(key)
	local xs, zs = string.match(key, "^(-?%d+),(-?%d+)$")
	return tonumber(xs), tonumber(zs)
end

function Grid.edgeKey(x1, z1, x2, z2)
	local a, b = Grid.key(x1, z1), Grid.key(x2, z2)
	if a < b then
		return a .. "|" .. b
	end
	return b .. "|" .. a
end

function Grid.isInt(value)
	return typeof(value) == "number" and value == value and value == math.floor(value) and math.abs(value) < 10000
end

function Grid.toWorld(originX, originZ, x, z, y)
	return Vector3.new(originX + x * SIZE, y or 0, originZ + z * SIZE)
end

function Grid.toCell(originX, originZ, position)
	return math.floor((position.X - originX) / SIZE + 0.5), math.floor((position.Z - originZ) / SIZE + 0.5)
end

function Grid.rootKey()
	return Grid.key(GameConfig.RootX, GameConfig.RootZ)
end

function Grid.regionAt(x, z)
	for _, id in ipairs(RegionConfig.Order) do
		local b = RegionConfig.Regions[id].Bounds
		if x >= b.MinX and x <= b.MaxX and z >= b.MinZ and z <= b.MaxZ then
			return id
		end
	end
	return nil
end

-- Returns centre cell (x, z) and size in studs (x, z) of a region.
function Grid.regionCenter(regionId)
	local b = RegionConfig.Regions[regionId].Bounds
	return (b.MinX + b.MaxX) / 2, (b.MinZ + b.MaxZ) / 2, (b.MaxX - b.MinX + 1) * SIZE, (b.MaxZ - b.MinZ + 1) * SIZE
end

-- A river covers Width lines of cells from Line: Axis "X" runs north-south (x lines), "Z" runs east-west (z lines).
function Grid.riverAt(x, z)
	local id = Grid.regionAt(x, z)
	local river = id and RegionConfig.Regions[id].River
	local width = river and (river.Width or 1) or 1
	local along = river and (river.Axis == "X" and x or z)
	if river and along >= river.Line and along < river.Line + width then
		return river
	end
	return nil
end

function Grid.isRiver(x, z)
	return Grid.riverAt(x, z) ~= nil
end

function Grid.isCrossing(x, z)
	local river = Grid.riverAt(x, z)
	if not river then
		return false
	end
	return table.find(river.Crossings, river.Axis == "X" and z or x) ~= nil
end

local function inRect(rect, x, z)
	return x >= rect.MinX and x <= rect.MaxX and z >= rect.MinZ and z <= rect.MaxZ
end

-- Mountain cells can only be crossed by tunnels.
function Grid.isMountain(x, z)
	local id = Grid.regionAt(x, z)
	for _, rect in ipairs(id and RegionConfig.Regions[id].Mountains or {}) do
		if inRect(rect, x, z) then
			return true
		end
	end
	return false
end

-- Landmark areas (fields, church, runway…) where nothing can be built. Returns the blocked entry or nil.
function Grid.blockedAt(x, z)
	local id = Grid.regionAt(x, z)
	for _, rect in ipairs(id and RegionConfig.Regions[id].Blocked or {}) do
		if inRect(rect, x, z) then
			return rect
		end
	end
	return nil
end

function Grid.worldBounds()
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, id in ipairs(RegionConfig.Order) do
		local b = RegionConfig.Regions[id].Bounds
		minX, maxX = math.min(minX, b.MinX), math.max(maxX, b.MaxX)
		minZ, maxZ = math.min(minZ, b.MinZ), math.max(maxZ, b.MaxZ)
	end
	return minX, maxX, minZ, maxZ
end

Grid.gates = {}
Grid.gateList = {}
local gatesByNode = {}
for _, regionId in ipairs(RegionConfig.Order) do
	for _, gate in ipairs(RegionConfig.Regions[regionId].Gates or {}) do
		local entry = table.clone(gate)
		entry.region = regionId
		Grid.gates[entry.id] = entry
		table.insert(Grid.gateList, entry)
		gatesByNode[Grid.key(entry.x, entry.z)] = entry
	end
end

function Grid.gateAt(x, z)
	return gatesByNode[Grid.key(x, z)]
end

return Grid
