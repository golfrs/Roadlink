-- The whole world is defined here. Coordinates are grid cells (8 studs each).
-- Rivers: Width lines of cells starting at Line; bridges only at Crossings. Mountains: tunnels only. Blocked: landmarks nothing can be built on.
-- Forests: decoration (trees clear themselves when you build through them).
local RegionConfig = {}

RegionConfig.Order = { "GreenValley", "Riverside", "AirportHeights" }

local RIVER_LINE = 11 -- the river runs north-south along x = 11

RegionConfig.Regions = {
	GreenValley = {
		DisplayName = "Green Valley",
		Description = "Your starter village, its church and the Sunrise Farm fields.",
		Bounds = { MinX = -12, MaxX = 9, MinZ = -10, MaxZ = 12 },
		TerrainColor = Color3.fromRGB(108, 160, 76),
		StartUnlocked = true,
		Neighbours = { "Riverside", "AirportHeights" },
		Gates = {
			{ id = "GV_East", name = "East Gate", x = 9, z = 0, direction = "East", leadsTo = "Riverside" },
			{ id = "GV_North", name = "North Gate", x = 0, z = -10, direction = "North", leadsTo = "AirportHeights" },
		},
		Seeds = {
			{ id = "seed_homes", kind = "Residential", x = -3, z = -3, name = "Valley Homes" },
			{ id = "seed_millane", kind = "Residential", x = -3, z = 3, name = "Mill Lane" },
			{ id = "seed_churchrow", kind = "Residential", x = -6, z = 0, name = "Church Row" },
			{ id = "seed_market", kind = "Commercial", x = 3, z = -3, name = "Valley Market" },
			{ id = "seed_clinic", kind = "Service", x = 3, z = 3, name = "Town Clinic" },
			{ id = "seed_farm", kind = "Farm", x = -8, z = 7, name = "Sunrise Farm" },
			{ id = "seed_store", kind = "Warehouse", x = -4, z = 8, name = "Grain Store" },
		},
		Blocked = {
			{ name = "church", kind = "Church", MinX = -8, MaxX = -7, MinZ = -6, MaxZ = -5 },
			{ name = "Town Square", kind = "TownSquare", MinX = 1, MaxX = 2, MinZ = 1, MaxZ = 2 },
			{ name = "Sunrise Farm fields", kind = "Field", MinX = -12, MaxX = -10, MinZ = 4, MaxZ = 10 },
		},
		Forests = {
			{ MinX = -12, MaxX = -10, MinZ = -10, MaxZ = -8 },
			{ MinX = 5, MaxX = 8, MinZ = 9, MaxZ = 12 },
			{ MinX = 6, MaxX = 8, MinZ = -10, MaxZ = -8 },
		},
	},
	Riverside = {
		DisplayName = "Riverside Farms",
		Description = "Rich farmland across the river. Bridges can only be built at the marked crossings. Unlocks highways.",
		Bounds = { MinX = 10, MaxX = 32, MinZ = -10, MaxZ = 12 },
		TerrainColor = Color3.fromRGB(108, 160, 76),
		Neighbours = { "GreenValley", "AirportHeights" },
		EntryGate = "GV_East",
		Requirements = { Gate = "GV_East", MinimumRoadTiles = 20, MinimumConnectedLocations = 4, UnlockCost = 30000 },
		River = { Axis = "X", Line = RIVER_LINE, Width = 2, Crossings = { -7, 0, 8 }, BridgeCostPerTile = 4000 },
		Seeds = {
			{ id = "seed_hilltop", kind = "Farm", x = 17, z = 4, name = "Hilltop Farm" },
			{ id = "seed_riverhomes", kind = "Residential", x = 15, z = -5, name = "Riverside Homes" },
			{ id = "seed_mill", kind = "Factory", x = 24, z = -6, name = "Riverside Mill" },
			{ id = "seed_depot", kind = "Warehouse", x = 28, z = 2, name = "Freight Depot" },
			{ id = "seed_harbour", kind = "Commercial", x = 16, z = 10, name = "Harbour Shops" },
		},
		Blocked = {
			{ name = "Hilltop Farm fields", kind = "Field", MinX = 19, MaxX = 24, MinZ = 2, MaxZ = 7 },
		},
		Forests = {
			{ MinX = 29, MaxX = 32, MinZ = 8, MaxZ = 12 },
			{ MinX = 27, MaxX = 32, MinZ = -10, MaxZ = -8 },
			{ MinX = 20, MaxX = 24, MinZ = 10, MaxZ = 12 },
		},
	},
	AirportHeights = {
		DisplayName = "Airport Heights",
		Description = "The airport and hill villages beyond the mountains. Tunnel through, or go the long way round.",
		Bounds = { MinX = -12, MaxX = 32, MinZ = -32, MaxZ = -11 },
		TerrainColor = Color3.fromRGB(108, 160, 76),
		Neighbours = { "GreenValley", "Riverside" },
		EntryGate = "GV_North",
		Requirements = { Gate = "GV_North", MinimumPopulation = 350, MinimumConnectedBusinesses = 3, UnlockCost = 45000 },
		River = { Axis = "X", Line = RIVER_LINE, Width = 2, Crossings = { -22 }, BridgeCostPerTile = 4000 },
		Mountains = {
			{ MinX = -12, MaxX = 10, MinZ = -17, MaxZ = -14 },
		},
		Seeds = {
			{ id = "seed_airport", kind = "Airport", x = 19, z = -20, name = "RoadLink Airport" },
			{ id = "seed_hillside", kind = "Residential", x = -5, z = -22, name = "Hillside Homes" },
			{ id = "seed_lodge", kind = "Commercial", x = 2, z = -26, name = "Summit Lodge" },
			{ id = "seed_hotel", kind = "Commercial", x = 26, z = -14, name = "Airport Hotel" },
		},
		Blocked = {
			{ name = "airport apron", kind = "Apron", MinX = 15, MaxX = 26, MinZ = -27, MaxZ = -22 },
			{ name = "runway", kind = "Runway", MinX = 13, MaxX = 31, MinZ = -31, MaxZ = -28 },
		},
		Forests = {
			{ MinX = -12, MaxX = -8, MinZ = -32, MaxZ = -27 },
			{ MinX = 4, MaxX = 9, MinZ = -32, MaxZ = -29 },
			{ MinX = -12, MaxX = -9, MinZ = -21, MaxZ = -19 },
			{ MinX = 28, MaxX = 32, MinZ = -21, MaxZ = -17 },
		},
	},
}

return RegionConfig
