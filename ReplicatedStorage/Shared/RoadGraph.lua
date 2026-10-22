-- Road network graph. Junctions are nodes ("x,z"), one-tile road segments are edges.
-- Pure data: used by the server for authority and by the client for previews.
local Grid = require(script.Parent:WaitForChild("Grid"))

local RoadGraph = {}
RoadGraph.__index = RoadGraph

function RoadGraph.new()
	return setmetatable({ edges = {}, adjacency = {}, edgeCount = 0 }, RoadGraph)
end

-- Adds a one-tile edge. Returns the edge, or nil if it already exists.
function RoadGraph:addEdge(x1, z1, x2, z2, kind)
	local key = Grid.edgeKey(x1, z1, x2, z2)
	if self.edges[key] then
		return nil
	end
	local a, b = Grid.key(x1, z1), Grid.key(x2, z2)
	local edge = { key = key, x1 = x1, z1 = z1, x2 = x2, z2 = z2, kind = kind, a = a, b = b }
	self.edges[key] = edge
	self.adjacency[a] = self.adjacency[a] or {}
	self.adjacency[b] = self.adjacency[b] or {}
	self.adjacency[a][b] = key
	self.adjacency[b][a] = key
	self.edgeCount += 1
	return edge
end

function RoadGraph:removeEdge(key)
	local edge = self.edges[key]
	if not edge then
		return false
	end
	self.edges[key] = nil
	for _, pair in ipairs({ { edge.a, edge.b }, { edge.b, edge.a } }) do
		local neighbours = self.adjacency[pair[1]]
		if neighbours then
			neighbours[pair[2]] = nil
			if next(neighbours) == nil then
				self.adjacency[pair[1]] = nil
			end
		end
	end
	self.edgeCount -= 1
	return true
end

function RoadGraph:getEdge(key)
	return self.edges[key]
end

function RoadGraph:degree(nodeKey)
	local count = 0
	for _ in pairs(self.adjacency[nodeKey] or {}) do
		count += 1
	end
	return count
end

function RoadGraph:hasNode(nodeKey)
	return self.adjacency[nodeKey] ~= nil
end

-- Breadth-first search. Returns a set of every node reachable from startKey (including startKey).
function RoadGraph:componentFrom(startKey)
	local seen = { [startKey] = true }
	local queue = { startKey }
	local index = 1
	while index <= #queue do
		local node = queue[index]
		index += 1
		for neighbour in pairs(self.adjacency[node] or {}) do
			if not seen[neighbour] then
				seen[neighbour] = true
				table.insert(queue, neighbour)
			end
		end
	end
	return seen
end

function RoadGraph:areConnected(keyA, keyB)
	if keyA == keyB then
		return true
	end
	return self:componentFrom(keyA)[keyB] == true
end

-- Every separate road network as a list of node sets.
function RoadGraph:components()
	local seen, result = {}, {}
	for node in pairs(self.adjacency) do
		if not seen[node] then
			local component = self:componentFrom(node)
			for key in pairs(component) do
				seen[key] = true
			end
			table.insert(result, component)
		end
	end
	return result
end

return RoadGraph
