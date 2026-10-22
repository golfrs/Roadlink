-- DataStore persistence with a versioned schema. A failed load disables saving for that session so
-- a temporary outage can never overwrite real progress with a fresh city.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local RoadConfig = require(Shared.RoadConfig)
local BuildingConfig = require(Shared.BuildingConfig)
local RegionConfig = require(Shared.RegionConfig)
local Grid = require(Shared.Grid)
local Rules = require(Shared.Rules)
local PlayerDataService = require(script.Parent.PlayerDataService)

local PersistenceService = {}
local store
local storeError

function PersistenceService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result
	else
		storeError = tostring(result)
		warn("[RoadLink] DataStore unavailable: " .. storeError)
	end
end

local function keyFor(userId)
	return "player_" .. tostring(userId)
end

local function isAccessError(err)
	local text = tostring(err)
	return string.find(text, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(text, "Studio access to APIs", 1, true) ~= nil
		or string.find(text, "403", 1, true) ~= nil
		or string.find(text, "publish", 1, true) ~= nil
end

local function withRetries(fn)
	local lastError
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if isAccessError(result) then
			break
		end
		task.wait(attempt * 1.5)
	end
	return false, lastError
end

-- Returns ("ok" | "new" | "failed" | "disabled"), data, error
function PersistenceService.load(userId)
	if not store then
		return "disabled", nil, storeError
	end
	local ok, result = withRetries(function()
		return store:GetAsync(keyFor(userId))
	end)
	if not ok then
		if isAccessError(result) then
			return "disabled", nil, result
		end
		return "failed", nil, result
	end
	if result == nil then
		return "new", nil
	end
	local data = PersistenceService.migrate(result)
	if not data then
		return "failed", nil, "Save data could not be read"
	end
	return "ok", data
end

-- Upgrades older save versions. Returns nil for unreadable data or data written by a newer version.
function PersistenceService.migrate(raw)
	if typeof(raw) ~= "table" then
		return nil
	end
	local version = tonumber(raw.version)
	if not version or version < 1 or version > GameConfig.SaveVersion then
		return nil
	end
	-- Future schema changes: transform version N into N + 1 here.
	return raw
end

function PersistenceService.serialize(state)
	local roads = {}
	for _, edge in pairs(state.graph.edges) do
		table.insert(roads, string.format("%d,%d,%d,%d,%s", edge.x1, edge.z1, edge.x2, edge.z2, edge.kind))
	end
	table.sort(roads)
	local buildings = {}
	for _, b in ipairs(state.buildings) do
		if not b.seeded then
			table.insert(buildings, { id = b.id, kind = b.kind, x = b.x, z = b.z })
		end
	end
	local unlocked, milestones = {}, {}
	for id in pairs(state.unlocked) do
		table.insert(unlocked, id)
	end
	for id in pairs(state.milestones) do
		table.insert(milestones, id)
	end
	table.sort(unlocked)
	table.sort(milestones)
	return {
		version = GameConfig.SaveVersion,
		cash = math.floor(state.cash),
		unlocked = unlocked,
		roads = roads,
		buildings = buildings,
		milestones = milestones,
		nextBuildingId = state.nextBuildingId,
		savedAt = os.time(),
	}
end

-- Rebuilds state from validated save data. Invalid entries are skipped. Returns the number skipped.
function PersistenceService.apply(state, data)
	local dropped = 0
	state.cash = math.clamp(tonumber(data.cash) or GameConfig.StartingCash, 0, 1e12)
	if typeof(data.unlocked) == "table" then
		for _, id in ipairs(data.unlocked) do
			if typeof(id) == "string" and RegionConfig.Regions[id] then
				state.unlocked[id] = true
			end
		end
	end
	for _, id in ipairs(RegionConfig.Order) do
		if state.unlocked[id] then
			PlayerDataService.addSeeds(state, id)
		end
	end

	local highestId = 0
	if typeof(data.buildings) == "table" then
		for _, b in ipairs(data.buildings) do
			local valid = typeof(b) == "table" and typeof(b.id) == "string" and #b.id <= 24
				and BuildingConfig.Types[b.kind] ~= nil and BuildingConfig.Types[b.kind].Buildable ~= false and Grid.isInt(b.x) and Grid.isInt(b.z)
				and state.buildingsById[b.id] == nil
			if valid then
				local region = Grid.regionAt(b.x, b.z)
				valid = region ~= nil and state.unlocked[region] == true and not Grid.isRiver(b.x, b.z)
					and not Grid.isMountain(b.x, b.z) and Grid.blockedAt(b.x, b.z) == nil
				if valid then
					for _, other in ipairs(state.buildings) do
						if math.abs(other.x - b.x) < 2 and math.abs(other.z - b.z) < 2 then
							valid = false
							break
						end
					end
				end
			end
			if valid then
				PlayerDataService.addBuilding(state, { id = b.id, kind = b.kind, x = b.x, z = b.z, name = BuildingConfig.Types[b.kind].DisplayName, seeded = false })
				local number = tonumber(string.match(b.id, "^b(%d+)$"))
				if number then
					highestId = math.max(highestId, number)
				end
			else
				dropped += 1
			end
		end
	end

	local view = PlayerDataService.makeView(state)
	if typeof(data.roads) == "table" then
		for _, entry in ipairs(data.roads) do
			local added = false
			if typeof(entry) == "string" then
				local a, b, c, d, kind = string.match(entry, "^(-?%d+),(-?%d+),(-?%d+),(-?%d+),(%a+)$")
				kind = kind and (RoadConfig.Aliases[kind] or kind)
				local x1, z1, x2, z2 = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
				if x1 and RoadConfig.Types[kind] and math.abs(x1 - x2) + math.abs(z1 - z2) == 1 and state.graph.edgeCount < GameConfig.MaxRoadEdges then
					local okA = Rules.nodeBuildable(view, x1, z1)
					local okB = Rules.nodeBuildable(view, x2, z2)
					local alongRiver = Rules.isBridgeEdge(x1, z1, x2, z2) and Rules.alongRiver(x1, z1, x2, z2)
					if okA and okB and not alongRiver then
						added = state.graph:addEdge(x1, z1, x2, z2, kind) ~= nil
					end
				end
			end
			if not added then
				dropped += 1
			end
		end
	end

	if typeof(data.milestones) == "table" then
		for _, id in ipairs(data.milestones) do
			if typeof(id) == "string" then
				state.milestones[id] = true
			end
		end
	end
	state.nextBuildingId = math.max(tonumber(data.nextBuildingId) or 1, highestId + 1)
	return dropped
end

function PersistenceService.canSave(state)
	return store ~= nil and (state.persistence == "ok" or state.persistence == "new")
end

function PersistenceService.save(state)
	if not PersistenceService.canSave(state) then
		return false, "saving disabled for this session"
	end
	if state.saving then
		return false, "save already in progress"
	end
	state.saving = true
	state.dirty = false
	local data = PersistenceService.serialize(state)
	local ok, err = withRetries(function()
		return store:UpdateAsync(keyFor(state.userId), function(old)
			if typeof(old) == "table" and tonumber(old.version) and tonumber(old.version) > GameConfig.SaveVersion then
				return nil -- never overwrite data from a newer game version
			end
			return data
		end)
	end)
	state.saving = false
	if not ok then
		state.dirty = true
		warn("[RoadLink] Save failed for " .. tostring(state.userId) .. ": " .. tostring(err))
	end
	return ok, err
end

return PersistenceService
