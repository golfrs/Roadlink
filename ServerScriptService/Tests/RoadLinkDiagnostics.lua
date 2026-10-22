-- Diagnostics for RoadLink's graph, rules, economy, regions, ownership and save format.
-- Run during a playtest from the server command bar:
--   print(require(game.ServerScriptService.Tests.RoadLinkDiagnostics).run().summary)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Grid = require(Shared.Grid)
local Rules = require(Shared.Rules)
local RoadGraph = require(Shared.RoadGraph)
local Services = ServerScriptService:WaitForChild("Services")
local PlayerDataService = require(Services.PlayerDataService)
local NetworkService = require(Services.NetworkService)
local EconomyService = require(Services.EconomyService)
local RegionService = require(Services.RegionService)
local PersistenceService = require(Services.PersistenceService)

local Diagnostics = {}

function Diagnostics.run()
	local lines, passed, failed = {}, 0, 0
	local function check(name, condition, detail)
		if condition then
			passed += 1
		else
			failed += 1
		end
		table.insert(lines, (condition and "PASS  " or "FAIL  ") .. name .. ((not condition and detail ~= nil) and ("  [" .. tostring(detail) .. "]") or ""))
	end

	local temp = {}
	local function fakeState(id)
		local state = PlayerDataService.create({ UserId = id, Name = "Diag" .. id })
		PlayerDataService.addSeeds(state, "GreenValley")
		NetworkService.recompute(state)
		EconomyService.recalc(state)
		table.insert(temp, state)
		return state
	end
	local function addRoad(state, x1, z1, x2, z2, kind)
		local plan = Rules.planRoad(PlayerDataService.makeView(state), x1, z1, x2, z2, kind or "Basic")
		if plan.ok then
			state.cash -= plan.cost
			for _, edge in ipairs(plan.edges) do
				state.graph:addEdge(edge.x1, edge.z1, edge.x2, edge.z2, edge.kind)
			end
			NetworkService.recompute(state)
			EconomyService.recalc(state)
		end
		return plan
	end
	local function region(state, id)
		for _, entry in ipairs(RegionService.progress(state)) do
			if entry.id == id then
				return entry
			end
		end
	end

	-- Graph
	local g = RoadGraph.new()
	g:addEdge(0, 0, 1, 0, "Basic")
	g:addEdge(1, 0, 2, 0, "Basic")
	g:addEdge(5, 5, 6, 5, "Basic")
	check("graph: two joined segments form one network", g:areConnected("0,0", "2,0"))
	check("graph: separate road is its own component", (not g:areConnected("0,0", "6,5")) and #g:components() == 2, #g:components())
	check("graph: duplicate edge rejected", g:addEdge(1, 0, 0, 0, "Basic") == nil)
	g:removeEdge(Grid.edgeKey(1, 0, 2, 0))
	check("graph: removing a segment splits the network", not g:areConnected("0,0", "2,0"))

	-- Road rules
	local s = fakeState(-9001)
	local view = PlayerDataService.makeView(s)
	local plan = Rules.planRoad(view, 0, 0, 3, 0, "Basic")
	check("road: valid 3-tile road from junction costs $750", plan.ok and plan.cost == 750, plan.message)
	check("road: reversed drag (end on junction) accepted", Rules.planRoad(view, 3, 0, 0, 0, "Basic").ok)
	check("road: disconnected start rejected", Rules.planRoad(view, 5, 5, 8, 5, "Basic").code == "disconnected")
	check("road: diagonal rejected", Rules.planRoad(view, 0, 0, 3, 3, "Basic").code == "diagonal")
	check("road: highway locked at start", Rules.planRoad(view, 0, 0, 3, 0, "Highway").code == "locked")
	check("road: road into locked region rejected", Rules.planRoad(view, 0, 0, 0, -12, "Basic").code == "locked")
	local churchOk, _, churchCode = Rules.nodeBuildable(view, -7, -5)
	check("road: church grounds block roads", churchOk == false and churchCode == "blocked")
	local poor = PlayerDataService.makeView(s)
	poor.cash = 100
	check("road: insufficient funds rejected", Rules.planRoad(poor, 0, 0, 3, 0, "Basic").code == "funds")

	-- Building rules
	check("building: occupied site rejected", Rules.planBuilding(view, "Residential", 3, -3).code == "blocked")
	check("building: Town Junction kept clear", Rules.planBuilding(view, "Residential", 0, 0).code == "blocked")
	check("building: outside land rejected", Rules.planBuilding(view, "Residential", 60, 60).code == "bounds")
	check("building: wheat field is blocked", Rules.planBuilding(view, "Residential", -11, 6).code == "blocked")
	check("building: airports can't be player-built", Rules.planBuilding(view, "Airport", 6, 6).ok == false)
	check("building: empty site accepted", Rules.planBuilding(view, "Residential", 6, -5).ok)
	check("building: no access before roads", Rules.planBuilding(view, "Residential", 6, -5).access == false)

	-- Network + economy
	local market = s.buildingsById.seed_market
	check("network: market starts disconnected", not market.connected)
	check("economy: disconnected market earns nothing", market.output == 0, market.output)
	addRoad(s, 0, 0, 0, -2)
	addRoad(s, 0, -2, 2, -2)
	check("network: road beside market connects it", market.connected)
	check("economy: connected market earns income", market.output > 0, market.output)
	check("network: BFS links junction to the far road end", NetworkService.areConnected(s, 0, 0, 2, -2))
	check("road: road through a building rejected", Rules.planRoad(PlayerDataService.makeView(s), 0, -3, -5, -3, "Basic").code == "blocked" or Rules.planRoad(PlayerDataService.makeView(s), 0, -2, 0, -3, "Basic").ok)
	addRoad(s, 0, -2, 0, -3)
	check("road: road through Valley Homes rejected", Rules.planRoad(PlayerDataService.makeView(s), 0, -3, -5, -3, "Basic").code == "blocked")

	-- Regions
	check("region: Riverside locked at start", region(s, "Riverside").canUnlock == false)
	addRoad(s, 0, 0, 9, 0)
	check("network: road reaches the East Gate", NetworkService.gateReached(s, "GV_East"))
	addRoad(s, 0, -2, -2, -2) -- Valley Homes
	addRoad(s, 0, 0, 0, 2)
	addRoad(s, 0, 2, 0, 3)
	addRoad(s, 0, 3, 2, 3) -- Town Clinic (around the Town Square)
	local squareOk, _, squareCode = Rules.nodeBuildable(PlayerDataService.makeView(s), 1, 1)
	check("village: Town Square blocks roads", squareOk == false and squareCode == "blocked")
	addRoad(s, 0, 2, -2, 2) -- Mill Lane
	local riverside = region(s, "Riverside")
	check("region: Riverside unlockable once requirements are met", riverside.canUnlock, riverside.met .. "/" .. riverside.total .. " tiles=" .. s.stats.roadTiles .. " locs=" .. s.stats.connectedLocations)
	check("region: Airport Heights still locked", region(s, "AirportHeights").canUnlock == false)

	-- Terrain costs (simulate unlocked regions)
	s.unlocked.Riverside = true
	s.unlocked.AirportHeights = true
	s.cash = 500000
	local bridge = Rules.planRoad(PlayerDataService.makeView(s), 9, 0, 14, 0, "Basic")
	check("terrain: bridge at a marked crossing costs extra", bridge.ok and bridge.bridgeTiles == 3 and bridge.cost == 3 * 4000 + 2 * 250, bridge.message)
	addRoad(s, 9, 0, 9, 3)
	check("terrain: no bridge away from crossings", Rules.planRoad(PlayerDataService.makeView(s), 9, 3, 14, 3, "Basic").code == "river")
	addRoad(s, 0, 0, 0, -10)
	local tunnel = Rules.planRoad(PlayerDataService.makeView(s), 0, -10, 0, -19, "Basic")
	check("terrain: tunnel through the mountains costs extra", tunnel.ok and tunnel.tunnelTiles == 5 and tunnel.cost == 5 * 3000 + 4 * 250, tunnel.message)
	check("terrain: can't build on mountains", Rules.planBuilding(PlayerDataService.makeView(s), "Residential", -4, -15).code == "blocked")
	local runwayOk, _, runwayCode = Rules.nodeBuildable(PlayerDataService.makeView(s), 20, -29)
	check("terrain: runway blocks roads", runwayOk == false and runwayCode == "blocked")
	s.unlocked.Riverside = nil
	s.unlocked.AirportHeights = nil

	-- Ownership
	local other = fakeState(-9002)
	check("ownership: separate road graphs", other.graph.edgeCount == 0 and s.graph.edgeCount > 0)
	check("ownership: separate plots", other.originX ~= s.originX)

	-- Persistence format
	local saved = PersistenceService.serialize(s)
	local copy = PlayerDataService.create({ UserId = -9003, Name = "DiagCopy" })
	table.insert(temp, copy)
	local dropped = PersistenceService.apply(copy, saved)
	NetworkService.recompute(copy)
	EconomyService.recalc(copy)
	check("save: serialize → apply round trip", dropped == 0 and copy.graph.edgeCount == s.graph.edgeCount and copy.cash == math.floor(s.cash) and copy.stats.income == s.stats.income, dropped)
	check("save: newer schema refused", PersistenceService.migrate({ version = GameConfig.SaveVersion + 1 }) == nil)
	local tampered = PersistenceService.serialize(s)
	table.insert(tampered.roads, "0,0,5,5,Basic")
	table.insert(tampered.roads, "0,0,0,1,Rocket")
	local copy2 = PlayerDataService.create({ UserId = -9004, Name = "DiagCopy2" })
	table.insert(temp, copy2)
	check("save: invalid road entries skipped", PersistenceService.apply(copy2, tampered) == 2)

	for _, state in ipairs(temp) do
		PlayerDataService.release(state)
	end
	local summary = string.format("RoadLink diagnostics: %d passed, %d failed\n%s", passed, failed, table.concat(lines, "\n"))
	return { passed = passed, failed = failed, summary = summary }
end

return Diagnostics
