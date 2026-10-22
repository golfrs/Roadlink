-- Global tuning values for RoadLink. Change numbers here rather than inside the services.
local GameConfig = {}

GameConfig.GridSize = 8 -- studs between road nodes
GameConfig.RootX = 0 -- the Town Junction: every road network grows from here
GameConfig.RootZ = 0

GameConfig.StartingCash = 75000
GameConfig.BasePopulation = 100
GameConfig.EconomyInterval = 20 -- seconds between income payouts
GameConfig.RefundFraction = 0.5 -- share of construction cost returned when bulldozing or demolishing

GameConfig.MaxRoadSpan = 24 -- tiles in one straight segment
GameConfig.MaxRoadEdges = 600 -- road tiles per player (prototype cap)
GameConfig.MaxBuildings = 80

GameConfig.PlayerPlotSpacing = 480 -- studs between player worlds along X
GameConfig.RequestCooldown = 0.08 -- minimum seconds between construction requests

GameConfig.DataStoreName = "RoadLink_PlayerData"
GameConfig.SaveVersion = 1
GameConfig.AutosaveInterval = 120

-- One-off goals that reward planning. stat names match EconomyService stats.
GameConfig.Milestones = {
	{ id = "first_road", name = "First Road", stat = "roadTiles", target = 1, reward = 0 },
	{ id = "open_for_business", name = "Open for Business", stat = "connectedBusinesses", target = 1, reward = 2500 },
	{ id = "network_25", name = "Growing Network", stat = "roadTiles", target = 25, reward = 5000 },
	{ id = "small_town", name = "Small Town", stat = "population", target = 300, reward = 7500 },
	{ id = "network_60", name = "Road Builder", stat = "roadTiles", target = 60, reward = 10000 },
	{ id = "explorer", name = "Explorer", stat = "regionsUnlocked", target = 2, reward = 10000 },
	{ id = "market_town", name = "Market Town", stat = "population", target = 600, reward = 15000 },
	{ id = "network_120", name = "Network Planner", stat = "roadTiles", target = 120, reward = 20000 },
}

return GameConfig
