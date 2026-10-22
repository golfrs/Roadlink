-- Client-side copy of the player's city. Display only: the server owns every real value.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Grid = require(Shared:WaitForChild("Grid"))
local RoadGraph = require(Shared:WaitForChild("RoadGraph"))
local Remotes = ReplicatedStorage:WaitForChild("RoadLinkRemotes")
local Request = Remotes:WaitForChild("Request")
local StateChanged = Remotes:WaitForChild("StateChanged")

local ClientState = {}
ClientState.snapshot = nil
ClientState.graph = RoadGraph.new()
ClientState.connected = {}
ClientState.buildingNodes = {}
ClientState.buildingsById = {}

local changedEvent = Instance.new("BindableEvent")
local messageEvent = Instance.new("BindableEvent")
ClientState.Changed = changedEvent.Event
ClientState.Message = messageEvent.Event

function ClientState.apply(snapshot)
	if typeof(snapshot) ~= "table" then
		return
	end
	local graph = RoadGraph.new()
	for _, road in ipairs(snapshot.roads or {}) do
		graph:addEdge(road[1], road[2], road[3], road[4], road[5])
	end
	local nodes, byId = {}, {}
	for _, building in ipairs(snapshot.buildings or {}) do
		nodes[Grid.key(building.x, building.z)] = building
		byId[building.id] = building
	end
	ClientState.graph = graph
	ClientState.connected = graph:componentFrom(Grid.rootKey())
	ClientState.buildingNodes = nodes
	ClientState.buildingsById = byId
	ClientState.snapshot = snapshot
	changedEvent:Fire(snapshot)
end

-- Same shape as the server's view so Shared.Rules can preview construction locally.
function ClientState.view()
	local snapshot = ClientState.snapshot
	local graph = ClientState.graph
	return {
		cash = snapshot.cash,
		unlocked = snapshot.unlocked,
		connected = ClientState.connected,
		edgeKind = function(key)
			local edge = graph.edges[key]
			return edge and edge.kind
		end,
		roadNode = function(key)
			return graph.adjacency[key] ~= nil
		end,
		buildingAt = function(key)
			return ClientState.buildingNodes[key]
		end,
		buildings = snapshot.buildings,
		edgeCount = graph.edgeCount,
		buildingCount = #snapshot.buildings,
	}
end

function ClientState.notify(message, kind)
	messageEvent:Fire(message, kind)
end

function ClientState.invoke(action, payload)
	local ok, result = pcall(function()
		return Request:InvokeServer(action, payload or {})
	end)
	if not ok or typeof(result) ~= "table" then
		return { ok = false, message = "The server didn't respond. Try again." }
	end
	if result.state then
		ClientState.apply(result.state)
	end
	for _, notice in ipairs(result.notices or {}) do
		messageEvent:Fire(notice.message, notice.kind)
	end
	return result
end

function ClientState.start()
	StateChanged.OnClientEvent:Connect(function(snapshot, message, kind)
		if snapshot then
			ClientState.apply(snapshot)
		end
		if message then
			messageEvent:Fire(message, kind or "info")
		end
	end)
	task.spawn(function()
		while not ClientState.snapshot do
			local result = ClientState.invoke("GetState")
			if result.ok then
				break
			end
			task.wait(1)
		end
	end)
end

return ClientState
