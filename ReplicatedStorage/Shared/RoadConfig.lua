-- Road types. Highways cost more but boost the output of buildings beside them.
-- Terrain surcharges: bridges over rivers and tunnels through mountains.
local RoadConfig = {}

RoadConfig.Order = { "Basic", "Highway" }

RoadConfig.Types = {
	Basic = {
		DisplayName = "Road",
		CostPerTile = 250,
		UpkeepPerTile = 5,
		Width = 6,
		IncomeMultiplier = 1.0,
		Color = Color3.fromRGB(74, 78, 86),
		Benefit = "Cheap local road for villages and farms",
	},
	Highway = {
		DisplayName = "Highway",
		CostPerTile = 1000,
		UpkeepPerTile = 15,
		Width = 10,
		IncomeMultiplier = 1.5,
		Color = Color3.fromRGB(58, 62, 70),
		LineColor = Color3.fromRGB(240, 240, 232),
		CenterColor = Color3.fromRGB(246, 196, 66),
		RequiresRegion = "Riverside",
		Benefit = "Wide, fast link · +50% output beside it",
	},
}

-- Old save data may contain removed road types.
RoadConfig.Aliases = { Main = "Basic" }

RoadConfig.BridgeUpkeepPerTile = 40
RoadConfig.TunnelCostPerTile = 3000
RoadConfig.TunnelUpkeepPerTile = 30

return RoadConfig
