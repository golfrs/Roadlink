-- Connectivity queries over each player's road graph. Recalculated only when the network or buildings change.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoadConfig = require(Shared.RoadConfig)
local Grid = require(Shared.Grid)

local NetworkService = {}

-- Updates state.connected (nodes reachable from the Town Junction) and each building's access + road bonus.
function NetworkService.recompute(state)
	local graph = state.graph
	state.connected = graph:componentFrom(Grid.rootKey())
	for _, building in ipairs(state.buildings) do
		local best = 0
		for dx = -1, 1 do
			for dz = -1, 1 do
				if dx ~= 0 or dz ~= 0 then
					local key = Grid.key(building.x + dx, building.z + dz)
					local neighbours = graph.adjacency[key]
					if neighbours and state.connected[key] then
						for _, edgeKey in pairs(neighbours) do
							local multiplier = RoadConfig.Types[graph.edges[edgeKey].kind].IncomeMultiplier
							if multiplier > best then
								best = multiplier
							end
						end
					end
				end
			end
		end
		building.connected = best > 0
		building.roadMultiplier = best
	end
end

function NetworkService.isNodeConnected(state, x, z)
	return state.connected[Grid.key(x, z)] == true
end

function NetworkService.areConnected(state, x1, z1, x2, z2)
	return state.graph:areConnected(Grid.key(x1, z1), Grid.key(x2, z2))
end

function NetworkService.gateReached(state, gateId)
	local gate = Grid.gates[gateId]
	if not gate then
		return false
	end
	local key = Grid.key(gate.x, gate.z)
	return state.graph.adjacency[key] ~= nil and state.connected[key] == true
end

function NetworkService.buildingHasAccess(state, buildingId)
	local building = state.buildingsById[buildingId]
	return building ~= nil and building.connected == true
end

function NetworkService.connectedBuildingSet(state)
	local set = {}
	for _, building in ipairs(state.buildings) do
		if building.connected then
			set[building.id] = true
		end
	end
	return set
end

return NetworkService
