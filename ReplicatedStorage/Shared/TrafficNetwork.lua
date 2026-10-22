-- Drivable lane geometry built from a player's RoadGraph.
-- Every one-tile road edge becomes two directed lane pieces (one per side of the road), and every
-- junction becomes a set of smooth turn pieces joining incoming lanes to outgoing lanes.
-- Pure data (no instances), so it can be reused by the server later.
local Shared = script.Parent
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RoadConfig = require(Shared:WaitForChild("RoadConfig"))
local TrafficConfig = require(Shared:WaitForChild("TrafficConfig"))
local Grid = require(Shared:WaitForChild("Grid"))
local Rules = require(Shared:WaitForChild("Rules"))

local TrafficNetwork = {}
TrafficNetwork.__index = TrafficNetwork

local UP = Vector3.new(0, 1, 0)
local G = GameConfig.GridSize
local SIDE = TrafficConfig.DriveOnLeft and -1 or 1
local TURN_SEGMENTS = 10

local function laneOffset(kind)
	return RoadConfig.Types[kind].Width / 4
end

local function atY(v, y)
	return Vector3.new(v.X, y, v.Z)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function newPiece(kind, key, points, speed)
	local cum = { 0 }
	for i = 2, #points do
		cum[i] = cum[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return { kind = kind, key = key, points = points, cum = cum, length = cum[#points], speed = speed }
end

-- Position at distance s along a piece. Extrapolates in a straight line beyond either end.
function TrafficNetwork.pointAt(piece, s)
	local points, cum = piece.points, piece.cum
	local n = #points
	if s <= 0 then
		local dir = points[2] - points[1]
		return dir.Magnitude > 0 and points[1] + dir.Unit * s or points[1]
	end
	if s >= piece.length then
		local dir = points[n] - points[n - 1]
		return dir.Magnitude > 0 and points[n] + dir.Unit * (s - piece.length) or points[n]
	end
	for i = 2, n do
		if s <= cum[i] then
			local seg = cum[i] - cum[i - 1]
			local t = seg > 0 and (s - cum[i - 1]) / seg or 0
			return points[i - 1]:Lerp(points[i], t)
		end
	end
	return points[n]
end

-- Closest distance along a piece to a world position (ignores height). Returns s, distance.
function TrafficNetwork.project(piece, position)
	local p = flat(position)
	local bestD, bestS = math.huge, 0
	for i = 2, #piece.points do
		local a, b = flat(piece.points[i - 1]), flat(piece.points[i])
		local ab = b - a
		local len2 = ab:Dot(ab)
		local t = len2 > 0 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
		local d = (a + ab * t - p).Magnitude
		if d < bestD then
			bestD = d
			bestS = piece.cum[i - 1] + (piece.cum[i] - piece.cum[i - 1]) * t
		end
	end
	return bestS, bestD
end

function TrafficNetwork.new(graph, originX, originZ)
	local self = setmetatable({ nodes = {}, lanes = {}, junctions = {}, conflictCache = {}, signalNodes = {} }, TrafficNetwork)
	self.adjacency = graph.adjacency

	-- Nodes: junction size, height and whether the junction has traffic lights.
	for key, neighbours in pairs(graph.adjacency) do
		local x, z = Grid.parse(key)
		local links, maxWidth = {}, 0
		for other, edgeKey in pairs(neighbours) do
			local edge = graph.edges[edgeKey]
			table.insert(links, { node = other, edge = edge })
			maxWidth = math.max(maxWidth, RoadConfig.Types[edge.kind].Width)
		end
		local degree = #links
		local through = false
		if degree == 2 then
			local a, b = links[1], links[2]
			local ax, az = Grid.parse(a.node)
			local bx, bz = Grid.parse(b.node)
			local straight = (ax == x and bx == x) or (az == z and bz == z)
			through = straight and a.edge.kind == b.edge.kind
				and Rules.isBridgeEdge(a.edge.x1, a.edge.z1, a.edge.x2, a.edge.z2) == Rules.isBridgeEdge(b.edge.x1, b.edge.z1, b.edge.x2, b.edge.z2)
		end
		local node = {
			key = key, x = x, z = z,
			pos = Vector3.new(originX + x * G, 0, originZ + z * G),
			degree = degree,
			links = links,
			maxWidth = maxWidth,
			h = (degree <= 1 or through) and 0 or math.min(maxWidth / 2, TrafficConfig.MaxJunctionInset),
			y = Grid.isRiver(x, z) and TrafficConfig.BridgeY or TrafficConfig.RoadY,
			signal = degree >= 3,
			phaseSeed = ((x * 7919 + z * 104729) % 1000) / 1000,
		}
		self.nodes[key] = node
		if node.signal then
			table.insert(self.signalNodes, node)
		end
	end

	-- Lanes: one per direction per edge, offset to the driving side.
	for _, edge in pairs(graph.edges) do
		self:_addLane(edge.a, edge.b, edge)
		self:_addLane(edge.b, edge.a, edge)
	end

	-- Junction movements: every incoming lane to every outgoing lane except a U-turn.
	for _, node in pairs(self.nodes) do
		if node.h > 0 then
			for _, inLink in ipairs(node.links) do
				for _, outLink in ipairs(node.links) do
					if inLink.node ~= outLink.node then
						self:_addMovement(node, inLink.node, outLink.node)
					end
				end
			end
		end
	end
	return self
end

function TrafficNetwork:_addLane(fromKey, toKey, edge)
	local A, B = self.nodes[fromKey], self.nodes[toKey]
	local d = (B.pos - A.pos).Unit
	local r = d:Cross(UP) * SIDE
	local o = laneOffset(edge.kind)
	local p0 = A.pos + d * A.h + r * o
	local p1 = B.pos - d * B.h + r * o
	local points
	local bridge = Rules.isBridgeEdge(edge.x1, edge.z1, edge.x2, edge.z2)
	if bridge and (p1 - p0).Magnitude > 2.4 then
		local y = TrafficConfig.BridgeY
		points = { atY(p0, A.y), atY(p0 + d, y), atY(p1 - d, y), atY(p1, B.y) }
	else
		points = { atY(p0, A.y), atY(p1, B.y) }
	end
	local piece = newPiece("lane", "L|" .. fromKey .. ">" .. toKey, points, TrafficConfig.Speed[edge.kind])
	piece.from, piece.to, piece.dir, piece.roadKind = fromKey, toKey, d, edge.kind
	self.lanes[fromKey .. ">" .. toKey] = piece
end

function TrafficNetwork:_addMovement(node, fromKey, toKey)
	local inLane = self.lanes[fromKey .. ">" .. node.key]
	local outLane = self.lanes[node.key .. ">" .. toKey]
	local E = flat(inLane.points[#inLane.points])
	local X = flat(outLane.points[1])
	local dIn, dOut = inLane.dir, outLane.dir
	local dot = dIn:Dot(dOut)
	local cross = dIn.X * dOut.Z - dIn.Z * dOut.X
	local points = {}
	local speed = math.min(inLane.speed, outLane.speed)
	local turn = "straight"
	if dot > 0.99 then
		points = { atY(E, node.y), atY(X, node.y) }
	else
		-- Quadratic Bezier whose control point is where the two lane centre lines meet,
		-- so the curve leaves and joins each lane tangentially (no sudden direction change).
		local det = dIn.X * dOut.Z - dIn.Z * dOut.X
		local w = X - E
		local t = (w.X * dOut.Z - w.Z * dOut.X) / det
		local Cp = E + dIn * t
		for i = 0, TURN_SEGMENTS do
			local u = i / TURN_SEGMENTS
			local p = E * (1 - u) ^ 2 + Cp * (2 * (1 - u) * u) + X * u ^ 2
			table.insert(points, atY(p, node.y))
		end
		local radius = (Cp - E).Magnitude
		speed = math.clamp(math.sqrt(TrafficConfig.LateralAccel * radius), TrafficConfig.MinTurnSpeed, speed)
		turn = cross > 0 and "right" or "left"
	end
	local fx = Grid.parse(fromKey)
	local piece = newPiece("junction", "J|" .. node.key .. "|" .. fromKey .. ">" .. toKey, points, speed)
	piece.node, piece.from, piece.to = node.key, fromKey, toKey
	piece.approachKey = node.key .. "|" .. fromKey
	piece.axis = fx ~= node.x and "X" or "Z"
	piece.turn = turn
	self.junctions[node.key .. "|" .. fromKey .. ">" .. toKey] = piece
end

-- Shortest route (fewest tiles) between two road nodes. Returns a list of node keys or nil.
function TrafficNetwork:path(fromKey, toKey)
	if fromKey == toKey or not self.nodes[fromKey] or not self.nodes[toKey] then
		return nil
	end
	local previous = { [fromKey] = false }
	local queue, head = { fromKey }, 1
	while head <= #queue do
		local key = queue[head]
		head += 1
		if key == toKey then
			break
		end
		for other in pairs(self.adjacency[key] or {}) do
			if previous[other] == nil then
				previous[other] = key
				table.insert(queue, other)
			end
		end
	end
	if previous[toKey] == nil then
		return nil
	end
	local path = {}
	local key = toKey
	while key do
		table.insert(path, 1, key)
		key = previous[key]
	end
	return path
end

-- Converts a node route into the ordered list of lane and junction pieces a vehicle drives.
function TrafficNetwork:routePieces(nodes)
	local pieces = {}
	for i = 1, #nodes - 1 do
		local lane = self.lanes[nodes[i] .. ">" .. nodes[i + 1]]
		if not lane then
			return nil
		end
		table.insert(pieces, lane)
		if i + 1 < #nodes then
			local node = self.nodes[nodes[i + 1]]
			if node.h > 0 then
				local movement = self.junctions[node.key .. "|" .. nodes[i] .. ">" .. nodes[i + 2]]
				if not movement then
					return nil
				end
				table.insert(pieces, movement)
			end
		end
	end
	return pieces
end

-- Evenly spaced flat points along a piece (cached), used for path-crossing tests.
function TrafficNetwork.samples(piece)
	if not piece.samples then
		local list = {}
		local steps = math.max(2, math.ceil(piece.length / 0.4))
		for i = 0, steps do
			table.insert(list, flat(TrafficNetwork.pointAt(piece, piece.length * i / steps)))
		end
		piece.samples = list
	end
	return piece.samples
end

-- Two junction movements conflict when their paths come too close (crossing or merging).
-- Movements from the same approach never conflict: those vehicles simply follow each other.
function TrafficNetwork:conflicts(a, b)
	if a.from == b.from then
		return false
	end
	local key = a.key < b.key and (a.key .. "#" .. b.key) or (b.key .. "#" .. a.key)
	local cached = self.conflictCache[key]
	if cached ~= nil then
		return cached
	end
	local result = a.to == b.to
	if not result then
		local limit = TrafficConfig.ConflictDistance
		local samplesA, samplesB = TrafficNetwork.samples(a), TrafficNetwork.samples(b)
		for _, p in ipairs(samplesA) do
			for _, q in ipairs(samplesB) do
				if (p - q).Magnitude < limit then
					result = true
					break
				end
			end
			if result then
				break
			end
		end
	end
	self.conflictCache[key] = result
	return result
end

return TrafficNetwork
