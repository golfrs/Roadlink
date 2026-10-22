-- Owns each player's authoritative city state and builds client snapshots from it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local RegionConfig = require(Shared.RegionConfig)
local Grid = require(Shared.Grid)
local RoadGraph = require(Shared.RoadGraph)

local PlayerDataService = {}
local states = {}
local freeSlots = {}
local nextSlot = 0

function PlayerDataService.create(player)
	local slot
	if #freeSlots > 0 then
		table.sort(freeSlots)
		slot = table.remove(freeSlots, 1)
	else
		slot = nextSlot
		nextSlot += 1
	end
	local state = {
		userId = player.UserId,
		player = player,
		slot = slot,
		originX = slot * GameConfig.PlayerPlotSpacing,
		originZ = 0,
		cash = GameConfig.StartingCash,
		graph = RoadGraph.new(),
		buildings = {},
		buildingsById = {},
		buildingNodes = {},
		unlocked = {},
		milestones = {},
		nextBuildingId = 1,
		connected = {},
		stats = { population = GameConfig.BasePopulation, income = 0, upkeep = 0, net = 0, roadTiles = 0, connectedLocations = 0, connectedBusinesses = 0, regionsUnlocked = 1, breakdown = {} },
		folders = nil,
		ready = false,
		dirty = false,
		persistence = "pending",
		lastRequest = 0,
	}
	for _, id in ipairs(RegionConfig.Order) do
		if RegionConfig.Regions[id].StartUnlocked then
			state.unlocked[id] = true
		end
	end
	states[player.UserId] = state
	return state
end

function PlayerDataService.get(player)
	return states[player.UserId]
end

function PlayerDataService.all()
	return states
end

function PlayerDataService.release(state)
	if states[state.userId] == state then
		states[state.userId] = nil
	end
	table.insert(freeSlots, state.slot)
end

function PlayerDataService.addBuilding(state, building)
	building.connected = building.connected == true
	building.output = building.output or 0
	table.insert(state.buildings, building)
	state.buildingsById[building.id] = building
	state.buildingNodes[Grid.key(building.x, building.z)] = building
	return building
end

function PlayerDataService.removeBuilding(state, id)
	local building = state.buildingsById[id]
	if not building then
		return nil
	end
	state.buildingsById[id] = nil
	state.buildingNodes[Grid.key(building.x, building.z)] = nil
	local index = table.find(state.buildings, building)
	if index then
		table.remove(state.buildings, index)
	end
	return building
end

-- Adds the pre-placed points of interest for a region. Returns the buildings that were added.
function PlayerDataService.addSeeds(state, regionId)
	local added = {}
	for _, seed in ipairs(RegionConfig.Regions[regionId].Seeds or {}) do
		if not state.buildingsById[seed.id] then
			table.insert(added, PlayerDataService.addBuilding(state, {
				id = seed.id, kind = seed.kind, x = seed.x, z = seed.z, name = seed.name, seeded = true,
			}))
		end
	end
	return added
end

-- A rules "view" of this player's city (see Shared.Rules).
function PlayerDataService.makeView(state)
	local graph = state.graph
	return {
		cash = state.cash,
		unlocked = state.unlocked,
		connected = state.connected,
		edgeKind = function(key)
			local edge = graph.edges[key]
			return edge and edge.kind
		end,
		roadNode = function(key)
			return graph.adjacency[key] ~= nil
		end,
		buildingAt = function(key)
			return state.buildingNodes[key]
		end,
		buildings = state.buildings,
		edgeCount = graph.edgeCount,
		buildingCount = #state.buildings,
	}
end

function PlayerDataService.snapshot(state, regions)
	local roads = {}
	for _, edge in pairs(state.graph.edges) do
		table.insert(roads, { edge.x1, edge.z1, edge.x2, edge.z2, edge.kind })
	end
	local buildings = {}
	for _, b in ipairs(state.buildings) do
		table.insert(buildings, {
			id = b.id, kind = b.kind, x = b.x, z = b.z, name = b.name,
			connected = b.connected == true, output = b.output or 0, population = b.population or 0,
			multiplier = b.roadMultiplier or 0, seeded = b.seeded == true,
		})
	end
	local s = state.stats
	return {
		userId = state.userId,
		originX = state.originX,
		originZ = state.originZ,
		cash = math.floor(state.cash),
		population = s.population,
		income = s.income,
		upkeep = s.upkeep,
		net = s.net,
		roadTiles = s.roadTiles,
		connectedLocations = s.connectedLocations,
		connectedBusinesses = s.connectedBusinesses,
		breakdown = s.breakdown,
		tickSeconds = GameConfig.EconomyInterval,
		unlocked = table.clone(state.unlocked),
		milestones = table.clone(state.milestones),
		roads = roads,
		buildings = buildings,
		regions = regions,
		persistence = state.persistence,
	}
end

return PlayerDataService
