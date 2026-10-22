-- Turns the connected network into population, income, upkeep and milestones. Runs on change and once per tick.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local BuildingConfig = require(Shared.BuildingConfig)
local Rules = require(Shared.Rules)

local EconomyService = {}

function EconomyService.recalc(state)
	local Types = BuildingConfig.Types
	local connectedCount = {}
	local connectedLocations, connectedBusinesses = 0, 0
	for _, b in ipairs(state.buildings) do
		if b.connected then
			connectedCount[b.kind] = (connectedCount[b.kind] or 0) + 1
			connectedLocations += 1
			if (Types[b.kind].Income or 0) > 0 then
				connectedBusinesses += 1
			end
		end
	end

	local warehouseBoost = math.min(connectedCount.Warehouse or 0, Types.Warehouse.MaxStack) * Types.Warehouse.ProductionBoost
	local serviceBoost = math.min(connectedCount.Service or 0, Types.Service.MaxStack) * Types.Service.PopulationBoost

	local residents = 0
	for _, b in ipairs(state.buildings) do
		local data = Types[b.kind]
		if (data.Population or 0) > 0 then
			local base = data.Population * (b.connected and 1 or (data.DisconnectedFactor or 0))
			b.population = math.floor(base * (1 + serviceBoost) + 0.5)
			residents += b.population
		else
			b.population = 0
		end
	end
	local population = GameConfig.BasePopulation + residents

	local shops = connectedCount.Commercial or 0
	local customerFactor = 1
	if shops > 0 then
		customerFactor = math.clamp(population / (shops * Types.Commercial.CustomersPerShop), 0.25, 1)
	end

	local income = 0
	local breakdown = {}
	for _, b in ipairs(state.buildings) do
		local data = Types[b.kind]
		local output = 0
		if b.connected and (data.Income or 0) > 0 then
			output = data.Income * (b.roadMultiplier or 1)
			if data.UsesWarehouses then
				output *= 1 + warehouseBoost
			end
			if b.kind == "Commercial" then
				output *= customerFactor
			end
		end
		b.output = math.floor(output + 0.5)
		income += b.output
		local row = breakdown[b.kind] or { count = 0, connected = 0, income = 0, population = 0 }
		row.count += 1
		if b.connected then
			row.connected += 1
		end
		row.income += b.output
		row.population += b.population
		breakdown[b.kind] = row
	end

	local upkeep = 0
	for _, edge in pairs(state.graph.edges) do
		upkeep += Rules.edgeUpkeep(edge.kind, edge.x1, edge.z1, edge.x2, edge.z2)
	end

	local regionsUnlocked = 0
	for _ in pairs(state.unlocked) do
		regionsUnlocked += 1
	end

	state.stats = {
		population = population,
		income = income,
		upkeep = upkeep,
		net = income - upkeep,
		roadTiles = state.graph.edgeCount,
		connectedLocations = connectedLocations,
		connectedBusinesses = connectedBusinesses,
		regionsUnlocked = regionsUnlocked,
		warehouseBoost = warehouseBoost,
		serviceBoost = serviceBoost,
		customerFactor = customerFactor,
		breakdown = breakdown,
	}
end

-- Pays one economy tick. Cash never drops below zero from upkeep.
function EconomyService.tick(state)
	local net = state.stats.net
	state.cash = math.max(0, state.cash + net)
	state.dirty = true
	return net
end

-- Awards any newly reached milestones. Returns the list reached this call.
function EconomyService.checkMilestones(state)
	local reached = {}
	for _, milestone in ipairs(GameConfig.Milestones) do
		if not state.milestones[milestone.id] and (state.stats[milestone.stat] or 0) >= milestone.target then
			state.milestones[milestone.id] = true
			state.cash += milestone.reward
			table.insert(reached, milestone)
		end
	end
	return reached
end

return EconomyService
