-- Region progress and unlocking. Requirements come entirely from RegionConfig.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RegionConfig = require(Shared.RegionConfig)
local Grid = require(Shared.Grid)
local Rules = require(Shared.Rules)
local Services = script.Parent
local PlayerDataService = require(Services.PlayerDataService)
local NetworkService = require(Services.NetworkService)
local WorldService = require(Services.WorldService)

local RegionService = {}

function RegionService.progress(state)
	local list = {}
	local stats = state.stats
	for _, id in ipairs(RegionConfig.Order) do
		local cfg = RegionConfig.Regions[id]
		local unlocked = state.unlocked[id] == true
		local requirements = {}
		local function add(labelText, current, target, isMoney)
			table.insert(requirements, { label = labelText, current = current, target = target, met = current >= target, money = isMoney == true })
		end
		local req = cfg.Requirements
		if req then
			if req.Prerequisite then
				local met = state.unlocked[req.Prerequisite] == true
				table.insert(requirements, { label = "Unlock " .. RegionConfig.Regions[req.Prerequisite].DisplayName, current = met and 1 or 0, target = 1, met = met, flag = true })
			end
			if req.Gate then
				local gate = Grid.gates[req.Gate]
				local met = NetworkService.gateReached(state, req.Gate)
				table.insert(requirements, { label = "Connect a road to the " .. gate.name, current = met and 1 or 0, target = 1, met = met, flag = true })
			end
			if req.MinimumRoadTiles then add("Road tiles built", stats.roadTiles, req.MinimumRoadTiles) end
			if req.MinimumConnectedLocations then add("Connected locations", stats.connectedLocations, req.MinimumConnectedLocations) end
			if req.MinimumConnectedBusinesses then add("Connected businesses", stats.connectedBusinesses, req.MinimumConnectedBusinesses) end
			if req.MinimumPopulation then add("Population", stats.population, req.MinimumPopulation) end
			if req.UnlockCost then add("Cash for the unlock", math.floor(state.cash), req.UnlockCost, true) end
		end
		local metCount = 0
		for _, r in ipairs(requirements) do
			if r.met then
				metCount += 1
			end
		end
		table.insert(list, {
			id = id,
			name = cfg.DisplayName,
			description = cfg.Description,
			unlocked = unlocked,
			cost = req and req.UnlockCost or 0,
			requirements = requirements,
			met = metCount,
			total = #requirements,
			canUnlock = not unlocked and metCount == #requirements,
			entryGate = cfg.EntryGate,
		})
	end
	return list
end

function RegionService.unlock(state, payload)
	local id = payload.regionId
	local cfg = typeof(id) == "string" and RegionConfig.Regions[id]
	if not cfg then
		return { ok = false, message = "Choose a region to unlock." }
	end
	if state.unlocked[id] then
		return { ok = false, message = cfg.DisplayName .. " is already unlocked." }
	end
	local entry
	for _, item in ipairs(RegionService.progress(state)) do
		if item.id == id then
			entry = item
		end
	end
	if not entry.canUnlock then
		for _, r in ipairs(entry.requirements) do
			if not r.met then
				local progressText = r.flag and "" or (" (" .. (r.money and Rules.money(r.current) or r.current) .. " / " .. (r.money and Rules.money(r.target) or r.target) .. ")")
				return { ok = false, message = "Not yet: " .. r.label .. progressText .. "." }
			end
		end
	end
	state.cash -= entry.cost
	state.unlocked[id] = true
	local seeds = PlayerDataService.addSeeds(state, id)
	WorldService.buildRegion(state, id)
	WorldService.buildMarkers(state)
	for _, building in ipairs(seeds) do
		WorldService.addBuilding(state, building)
	end
	local gate = cfg.EntryGate and Grid.gates[cfg.EntryGate]
	return {
		ok = true,
		changed = true,
		message = cfg.DisplayName .. " unlocked! Extend your road through the " .. (gate and gate.name or "gate") .. " to connect it.",
		regionId = id,
	}
end

return RegionService
