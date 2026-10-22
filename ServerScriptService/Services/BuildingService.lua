-- Validates and applies building placement and demolition.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local BuildingConfig = require(Shared.BuildingConfig)
local Rules = require(Shared.Rules)
local Services = script.Parent
local PlayerDataService = require(Services.PlayerDataService)
local NetworkService = require(Services.NetworkService)
local WorldService = require(Services.WorldService)

local BuildingService = {}

function BuildingService.build(state, payload)
	local kind = payload.buildingType
	local plan = Rules.planBuilding(PlayerDataService.makeView(state), kind, payload.x, payload.z)
	if not plan.ok then
		return { ok = false, message = plan.message, code = plan.code }
	end
	local data = BuildingConfig.Types[kind]
	state.cash -= plan.cost
	local id = "b" .. state.nextBuildingId
	state.nextBuildingId += 1
	local building = PlayerDataService.addBuilding(state, {
		id = id, kind = kind, x = payload.x, z = payload.z, name = data.DisplayName, seeded = false,
	})
	NetworkService.recompute(state)
	WorldService.addBuilding(state, building)
	local message = data.DisplayName .. " built for " .. Rules.money(plan.cost) .. "."
	if building.connected then
		message ..= " It's connected and working."
	else
		message ..= " Build a connected road within 1 tile to activate it."
	end
	return { ok = true, changed = true, message = message }
end

function BuildingService.demolish(state, payload)
	local id = payload.id
	local building = typeof(id) == "string" and state.buildingsById[id]
	if not building then
		return { ok = false, message = "That building no longer exists." }
	end
	if building.seeded then
		return { ok = false, message = "Original town buildings can't be demolished." }
	end
	local refund = math.floor(BuildingConfig.Types[building.kind].Cost * GameConfig.RefundFraction)
	PlayerDataService.removeBuilding(state, id)
	WorldService.removeBuilding(state, id)
	state.cash += refund
	return { ok = true, changed = true, message = building.name .. " demolished. Refunded " .. Rules.money(refund) .. "." }
end

return BuildingService
