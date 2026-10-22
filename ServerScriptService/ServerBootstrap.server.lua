-- RoadLink server entry point: wires the services, remotes, player lifecycle, economy ticks and autosaves.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local RegionConfig = require(Shared.RegionConfig)
local Rules = require(Shared.Rules)

local Services = script.Parent:WaitForChild("Services")
local PlayerDataService = require(Services.PlayerDataService)
local WorldService = require(Services.WorldService)
local NetworkService = require(Services.NetworkService)
local EconomyService = require(Services.EconomyService)
local RegionService = require(Services.RegionService)
local RoadService = require(Services.RoadService)
local BuildingService = require(Services.BuildingService)
local PersistenceService = require(Services.PersistenceService)

-- City builder: no avatar, the player controls a camera.
Players.CharacterAutoLoads = false

local remotes = ReplicatedStorage:FindFirstChild("RoadLinkRemotes") or Instance.new("Folder")
remotes.Name = "RoadLinkRemotes"
local Request = remotes:FindFirstChild("Request") or Instance.new("RemoteFunction")
Request.Name = "Request"
Request.Parent = remotes
local StateChanged = remotes:FindFirstChild("StateChanged") or Instance.new("RemoteEvent")
StateChanged.Name = "StateChanged"
StateChanged.Parent = remotes
remotes.Parent = ReplicatedStorage

WorldService.init()
PersistenceService.init()

-- Recalculates everything derived from the network and returns a fresh client snapshot.
local function commit(state)
	NetworkService.recompute(state)
	EconomyService.recalc(state)
	local notices = {}
	for _, milestone in ipairs(EconomyService.checkMilestones(state)) do
		state.dirty = true
		local reward = milestone.reward > 0 and ("  +" .. Rules.money(milestone.reward)) or ""
		table.insert(notices, { message = "Milestone reached: " .. milestone.name .. reward, kind = "milestone" })
	end
	WorldService.updateBuildingStatus(state)
	return PlayerDataService.snapshot(state, RegionService.progress(state)), notices
end

local handlers = {
	GetState = function()
		return { ok = true }
	end,
	BuildRoad = RoadService.build,
	RemoveRoad = RoadService.remove,
	UpgradeRoad = RoadService.upgrade,
	BuildBuilding = BuildingService.build,
	DemolishBuilding = BuildingService.demolish,
	UnlockRegion = RegionService.unlock,
}

Request.OnServerInvoke = function(player, action, payload)
	if typeof(action) ~= "string" or not handlers[action] then
		return { ok = false, message = "Unknown request." }
	end
	local state = PlayerDataService.get(player)
	if not state or not state.ready then
		return { ok = false, message = "Your city is still loading." }
	end
	if action ~= "GetState" then
		local now = os.clock()
		if now - state.lastRequest < GameConfig.RequestCooldown then
			return { ok = false, message = "Slow down a little." }
		end
		state.lastRequest = now
	end
	payload = typeof(payload) == "table" and payload or {}
	local ok, result = pcall(handlers[action], state, payload)
	if not ok then
		warn("[RoadLink] " .. action .. " failed for " .. player.Name .. ": " .. tostring(result))
		result = { ok = false, message = "Something went wrong on the server. Please try again." }
	end
	if result.changed then
		state.dirty = true
	end
	result.changed = nil
	result.state, result.notices = commit(state)
	return result
end

local function onPlayerAdded(player)
	if PlayerDataService.get(player) then
		return
	end
	local state = PlayerDataService.create(player)
	local status, data, err = PersistenceService.load(player.UserId)
	if status == "ok" then
		local dropped = PersistenceService.apply(state, data)
		if dropped > 0 then
			warn(string.format("[RoadLink] Skipped %d invalid saved entries for %s", dropped, player.Name))
		end
	else
		for _, id in ipairs(RegionConfig.Order) do
			if state.unlocked[id] then
				PlayerDataService.addSeeds(state, id)
			end
		end
		if err then
			warn("[RoadLink] Load for " .. player.Name .. " → " .. status .. ": " .. tostring(err))
		end
	end
	state.persistence = status
	if not player.Parent then
		PlayerDataService.release(state)
		return
	end
	WorldService.createWorld(state)
	state.ready = true
	local snapshot = commit(state)
	local welcome = status == "ok" and "Welcome back! Your city has been restored."
		or "Welcome to Green Valley! Choose ROADS, then click the glowing Town Junction to start your first road."
	StateChanged:FireClient(player, snapshot, welcome, "info")
	if status == "disabled" then
		StateChanged:FireClient(player, nil, "Saving is off in this session (DataStore access unavailable), so progress won't persist.", "warning")
	elseif status == "failed" then
		StateChanged:FireClient(player, nil, "Your saved city couldn't be loaded. Saving is paused this session to protect it. Rejoin to try again.", "error")
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local state = PlayerDataService.get(player)
	if not state then
		return
	end
	state.leaving = true
	if state.ready then
		PersistenceService.save(state)
	end
	WorldService.destroyWorld(state)
	PlayerDataService.release(state)
end)

game:BindToClose(function()
	for _, state in pairs(PlayerDataService.all()) do
		if state.ready and not state.saving then
			task.spawn(PersistenceService.save, state)
		end
	end
	local deadline = os.clock() + 25
	repeat
		local busy = false
		for _, state in pairs(PlayerDataService.all()) do
			if state.saving then
				busy = true
			end
		end
		if busy then
			task.wait(0.5)
		end
	until not busy or os.clock() > deadline
end)

-- Economy: one predictable payout per interval for every city.
task.spawn(function()
	while true do
		task.wait(GameConfig.EconomyInterval)
		for _, state in pairs(PlayerDataService.all()) do
			if state.ready and not state.leaving and state.player.Parent then
				local net = EconomyService.tick(state)
				local snapshot, notices = commit(state)
				StateChanged:FireClient(state.player, snapshot, (net >= 0 and "+" or "") .. Rules.money(net), "income")
				for _, notice in ipairs(notices) do
					StateChanged:FireClient(state.player, nil, notice.message, notice.kind)
				end
			end
		end
	end
end)

-- Autosave only cities that changed.
task.spawn(function()
	while true do
		task.wait(GameConfig.AutosaveInterval)
		for _, state in pairs(PlayerDataService.all()) do
			if state.ready and state.dirty and not state.leaving then
				task.spawn(PersistenceService.save, state)
			end
		end
	end
end)
