-- Building types. Buildings only work properly when a connected road passes within one tile.
local BuildingConfig = {}

-- Types the player can place (shown in the BUILD toolbar, in this order).
BuildingConfig.Order = { "Residential", "Commercial", "Farm", "Factory", "Warehouse", "Service" }
-- Pre-placed landmarks that can't be built by players.
BuildingConfig.Landmarks = { "Airport" }

BuildingConfig.Types = {
	Residential = {
		DisplayName = "Housing", Cost = 8000, Population = 80, Income = 0, DisconnectedFactor = 0.25,
		Asset = { "House_1", "House_2", "House_3", "House_4" },
		Benefit = "+80 population (25% without a road)",
	},
	Commercial = {
		DisplayName = "Shops", Cost = 12000, Income = 2000, CustomersPerShop = 120,
		Asset = { "Shop" },
		Benefit = "$2,000 income · needs 120 residents each",
	},
	Farm = {
		DisplayName = "Farm", Cost = 9000, Income = 1200, UsesWarehouses = true,
		Asset = { "FarmBarn" },
		Benefit = "$1,200 income · boosted by warehouses",
	},
	Factory = {
		DisplayName = "Factory", Cost = 20000, Income = 3000, UsesWarehouses = true,
		Asset = { "Factory" },
		Benefit = "$3,000 income · boosted by warehouses",
	},
	Warehouse = {
		DisplayName = "Warehouse", Cost = 15000, Income = 500, ProductionBoost = 0.2, MaxStack = 3,
		Asset = { "Warehouse" },
		Benefit = "+20% farm & factory output (max 3)",
	},
	Service = {
		DisplayName = "Clinic", Cost = 12000, Income = 0, PopulationBoost = 0.1, MaxStack = 3,
		Asset = { "Clinic" },
		Benefit = "+10% population (max 3)",
	},
	Airport = {
		DisplayName = "Airport", Cost = 0, Income = 5000, Buildable = false,
		Asset = { "AirportTerminal" }, Footprint = Vector2.new(14, 8),
		Benefit = "Big income once a road reaches it",
	},
}

return BuildingConfig
