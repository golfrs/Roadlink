-- Validates and applies road construction, upgrades and bulldozing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local RoadConfig = require(Shared.RoadConfig)
local RegionConfig = require(Shared.RegionConfig)
local Grid = require(Shared.Grid)
local Rules = require(Shared.Rules)
local Services = script.Parent
local PlayerDataService = require(Services.PlayerDataService)
local NetworkService = require(Services.NetworkService)
local WorldService = require(Services.WorldService)

local RoadService = {}

local function gateSnapshot(state)
	local reached = {}
	for _, gate in ipairs(Grid.gateList) do
		reached[gate.id] = NetworkService.gateReached(state, gate.id)
	end
	return reached
end

function RoadService.build(state, payload)
	local plan = Rules.planRoad(PlayerDataService.makeView(state), payload.x1, payload.z1, payload.x2, payload.z2, payload.roadType)
	if not plan.ok then
		return { ok = false, message = plan.message, code = plan.code }
	end
	local before = NetworkService.connectedBuildingSet(state)
	local gatesBefore = gateSnapshot(state)
	state.cash -= plan.cost
	for _, edge in ipairs(plan.edges) do
		state.graph:addEdge(edge.x1, edge.z1, edge.x2, edge.z2, edge.kind)
	end
	WorldService.rebuildRoads(state)
	NetworkService.recompute(state)

	local parts = { string.format("Built %d tile%s for %s.", plan.tiles, plan.tiles == 1 and "" or "s", Rules.money(plan.cost)) }
	local newly = {}
	for _, building in ipairs(state.buildings) do
		if building.connected and not before[building.id] then
			table.insert(newly, building.name)
		end
	end
	if #newly > 0 then
		table.insert(parts, "Connected " .. table.concat(newly, ", ") .. "!")
	end
	for _, gate in ipairs(Grid.gateList) do
		if not gatesBefore[gate.id] and NetworkService.gateReached(state, gate.id) then
			table.insert(parts, "Reached the " .. gate.name .. " → " .. RegionConfig.Regions[gate.leadsTo].DisplayName .. ".")
		end
	end
	return { ok = true, changed = true, message = table.concat(parts, " "), newlyConnected = #newly }
end

local function collectRun(state, payload)
	local steps, err = Rules.runEdges(payload.x1, payload.z1, payload.x2, payload.z2, 64)
	if not steps then
		return nil, err
	end
	local edges = {}
	for _, step in ipairs(steps) do
		local edge = state.graph.edges[step.key]
		if not edge then
			return nil, "That road section no longer exists."
		end
		table.insert(edges, edge)
	end
	return edges
end

function RoadService.remove(state, payload)
	local edges, err = collectRun(state, payload)
	if not edges then
		return { ok = false, message = err }
	end
	local before = NetworkService.connectedBuildingSet(state)
	local refund = 0
	for _, edge in ipairs(edges) do
		refund += Rules.edgeCost(edge.kind, edge.x1, edge.z1, edge.x2, edge.z2) * GameConfig.RefundFraction
		state.graph:removeEdge(edge.key)
	end
	refund = math.floor(refund)
	state.cash += refund
	WorldService.rebuildRoads(state)
	NetworkService.recompute(state)
	local lost = {}
	for _, building in ipairs(state.buildings) do
		if before[building.id] and not building.connected then
			table.insert(lost, building.name)
		end
	end
	local message = string.format("Bulldozed %d tile%s. Refunded %s.", #edges, #edges == 1 and "" or "s", Rules.money(refund))
	if #lost > 0 then
		message ..= " Lost road access: " .. table.concat(lost, ", ") .. "."
	end
	return { ok = true, changed = true, message = message }
end

function RoadService.upgrade(state, payload)
	local kind = payload.roadType
	local data = typeof(kind) == "string" and RoadConfig.Types[kind]
	if not data then
		return { ok = false, message = "Choose a road type to upgrade to." }
	end
	if data.RequiresRegion and not state.unlocked[data.RequiresRegion] then
		return { ok = false, message = data.DisplayName .. " unlocks with the " .. RegionConfig.Regions[data.RequiresRegion].DisplayName .. "." }
	end
	local edges, err = collectRun(state, payload)
	if not edges then
		return { ok = false, message = err }
	end
	local cost, changes = 0, {}
	for _, edge in ipairs(edges) do
		if edge.kind ~= kind then
			local old = RoadConfig.Types[edge.kind]
			if data.CostPerTile <= old.CostPerTile then
				return { ok = false, message = "You can only upgrade to a better road type." }
			end
			cost += data.CostPerTile - old.CostPerTile
			table.insert(changes, edge)
		end
	end
	if #changes == 0 then
		return { ok = false, message = "This section is already a " .. data.DisplayName .. "." }
	end
	if state.cash < cost then
		return { ok = false, message = "Not enough cash: the upgrade costs " .. Rules.money(cost) .. ".", code = "funds" }
	end
	state.cash -= cost
	for _, edge in ipairs(changes) do
		edge.kind = kind
	end
	WorldService.rebuildRoads(state)
	return { ok = true, changed = true, message = string.format("Upgraded %d tile%s to %s for %s.", #changes, #changes == 1 and "" or "s", data.DisplayName, Rules.money(cost)) }
end

return RoadService
