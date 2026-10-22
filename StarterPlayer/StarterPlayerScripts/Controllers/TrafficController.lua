-- Client-side traffic simulation for the local player's city.
-- Vehicles are visual only (the server's economy does not depend on them), so each client simulates
-- just its own city: no network traffic and no physics. Every car follows a precomputed lane path,
-- drives with the Intelligent Driver Model (smooth acceleration, braking and spacing), obeys traffic
-- lights, and reserves its path through a junction so crossing movements never overlap.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TrafficConfig = require(Shared:WaitForChild("TrafficConfig"))
local TrafficNetwork = require(Shared:WaitForChild("TrafficNetwork"))
local TrafficSignals = require(Shared:WaitForChild("TrafficSignals"))
local Grid = require(Shared:WaitForChild("Grid"))
local Controllers = script.Parent
local VehicleFactory = require(Controllers:WaitForChild("VehicleFactory"))
local SignalVisuals = require(Controllers:WaitForChild("SignalVisuals"))

local C = TrafficConfig
local pointAt = TrafficNetwork.pointAt

local Traffic = {}
local deps
local folder
local network
local signature
local vehicles = {}
local places = {}
local spawnClock = 0
local overlapClock = 0
local nextId = 0
local rng = Random.new()
local enabled = true
local maxOverride
local stats = { spawned = 0, arrived = 0, stuckRemoved = 0, roadRemoved = 0, redEntries = 0, overlapChecks = 0, overlapFrames = 0, worstOverlap = 0, hardStops = 0, jumps = 0 }

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function roadSignature(snapshot)
	local list = {}
	for _, road in ipairs(snapshot.roads or {}) do
		table.insert(list, road[1] .. "," .. road[2] .. "," .. road[3] .. "," .. road[4] .. road[5])
	end
	table.sort(list)
	return tostring(snapshot.originX) .. ":" .. tostring(snapshot.originZ) .. ":" .. table.concat(list, ";")
end

-- Places cars travel between: one road node beside each connected building, plus every road end.
local function computePlaces()
	places = {}
	local graph, connected, snapshot = deps.state.graph, deps.state.connected, deps.state.snapshot
	local seen = {}
	local function add(key)
		if not seen[key] and graph.adjacency[key] and connected[key] then
			seen[key] = true
			table.insert(places, key)
			return true
		end
		return false
	end
	for _, building in ipairs(snapshot.buildings or {}) do
		if building.connected then
			local done = false
			for dx = -1, 1 do
				for dz = -1, 1 do
					if not done and (dx ~= 0 or dz ~= 0) then
						local key = Grid.key(building.x + dx, building.z + dz)
						if graph.adjacency[key] and connected[key] then
							add(key)
							done = true
						end
					end
				end
			end
		end
	end
	for key, neighbours in pairs(graph.adjacency) do
		local count = 0
		for _ in pairs(neighbours) do
			count += 1
		end
		if count == 1 then
			add(key)
		end
	end
	table.sort(places)
end

local function targetCount()
	if #places < 2 or not network then
		return 0
	end
	if maxOverride then
		return maxOverride
	end
	return math.min(C.MaxVehicles, #places * C.VehiclesPerPlace)
end

local function setTransparency(v, alpha)
	for i, p in ipairs(v.model.parts) do
		p.Transparency = v.model.base[i] + (1 - v.model.base[i]) * (1 - alpha)
	end
end

local function removeVehicle(index)
	local v = vehicles[index]
	v.model.folder:Destroy()
	table.remove(vehicles, index)
end

-- Re-attaches vehicles to a freshly built network (roads were added or removed).
local function migrate()
	for _, v in ipairs(vehicles) do
		if v.state ~= "out" then
			local pieces = network:routePieces(v.nodes)
			if not pieces then
				-- A road on the planned route was removed: re-plan from the piece the car is on.
				local current = v.route[v.index]
				local stillThere = current.kind == "lane" and network.lanes[current.from .. ">" .. current.to]
					or current.kind == "junction" and network.junctions[current.node .. "|" .. current.from .. ">" .. current.to]
				if stillThere then
					local prefix = current.kind == "lane" and { current.from, current.to } or { current.from, current.node, current.to }
					local destinations = { v.nodes[#v.nodes] }
					for _ = 1, 4 do
						table.insert(destinations, places[rng:NextInteger(1, math.max(#places, 1))])
					end
					for _, destination in ipairs(destinations) do
						local rest = destination and network:path(current.to, destination)
						if rest then
							local nodes = table.clone(prefix)
							for i = 2, #rest do
								table.insert(nodes, rest[i])
							end
							local replanned = network:routePieces(nodes)
							if replanned then
								v.nodes, pieces = nodes, replanned
								break
							end
						end
					end
				end
			end
			if not pieces then
				v.state = "out"
				v.commit = nil
				stats.roadRemoved += 1
			else
				local oldKey = v.route[v.index].key
				local bestIndex, bestS, bestScore = 1, 0, math.huge
				for i, piece in ipairs(pieces) do
					local s, d = TrafficNetwork.project(piece, v.position)
					local score = d + math.abs(i - v.index) * 0.01 - (piece.key == oldKey and 0.5 or 0)
					if score < bestScore then
						bestIndex, bestS, bestScore = i, s, score
					end
				end
				local commitKey = v.commit and v.commit.piece.key
				v.route, v.index, v.s, v.prev = pieces, bestIndex, bestS, pieces[bestIndex - 1]
				v.commit = nil
				if commitKey then
					for i, piece in ipairs(pieces) do
						if piece.key == commitKey and i >= bestIndex then
							v.commit = { piece = piece, index = i, node = piece.node, time = serverNow() }
							break
						end
					end
				end
			end
		end
	end
end

local function rebuildNetwork()
	local snapshot = deps.state.snapshot
	network = TrafficNetwork.new(deps.state.graph, snapshot.originX, snapshot.originZ)
	migrate()
	SignalVisuals.rebuild(network)
end

local function onState()
	local snapshot = deps.state.snapshot
	if not snapshot then
		return
	end
	local sig = roadSignature(snapshot)
	if sig ~= signature then
		signature = sig
		rebuildNetwork()
	end
	computePlaces()
end

local function spawnClear(position, length)
	for _, other in ipairs(vehicles) do
		local stopping = other.v * other.v / (2 * C.ComfortDecel) + other.v * C.TimeHeadway
		if other.position and (flat(other.position) - flat(position)).Magnitude < (other.length + length) / 2 + 2.5 + stopping then
			return false
		end
	end
	return true
end

local function trySpawn()
	for _ = 1, 4 do
		local origin = places[rng:NextInteger(1, #places)]
		local destination = places[rng:NextInteger(1, #places)]
		if origin ~= destination then
			local nodes = network:path(origin, destination)
			local pieces = nodes and network:routePieces(nodes)
			if pieces and #pieces > 0 then
				local model = VehicleFactory.create(folder, rng)
				local s = math.min(model.length / 2, pieces[1].length)
				local position = pointAt(pieces[1], s)
				if spawnClear(position, model.length) then
					nextId += 1
					local v = {
						id = nextId, model = model, length = model.length, width = model.width,
						nodes = nodes, route = pieces, index = 1, s = s, v = 0, alpha = 0, state = "in",
						position = position, y = position.Y, heading = pieces[1].points[#pieces[1].points] - pieces[1].points[1],
						stuck = 0, wait = 0, braking = false,
					}
					setTransparency(v, 0)
					table.insert(vehicles, v)
					stats.spawned += 1
					return true
				end
				model.folder:Destroy()
			end
		end
	end
	return false
end

-- Intelligent Driver Model acceleration.
local function idm(speed, desired, gap, closing, minGap)
	desired = math.max(desired, 0.1)
	local free = 1 - (speed / desired) ^ 4
	if gap == math.huge then
		return C.Accel * free
	end
	local sStar = minGap + math.max(0, speed * C.TimeHeadway + speed * closing / (2 * math.sqrt(C.Accel * C.ComfortDecel)))
	return C.Accel * (free - (sStar / math.max(gap, 0.05)) ^ 2)
end

-- Nearest vehicle ahead on this car's own path (including whoever is already in the junction it is about to enter).
local function findLeader(v, occupancy, approaches)
	local piece = v.route[v.index]
	local bestGap, bestSpeed = math.huge, 0
	for _, other in ipairs(occupancy[piece] or {}) do
		if other ~= v and (other.s > v.s or (other.s == v.s and other.id < v.id)) then
			local gap = other.s - v.s - (other.length + v.length) / 2
			if gap < bestGap then
				bestGap, bestSpeed = gap, other.v
			end
		end
	end
	if piece.kind == "junction" then
		-- Cars from the same approach taking a different turn share the first stretch of the junction.
		for _, other in ipairs(approaches[piece.approachKey] or {}) do
			if other ~= v and other.route[other.index] ~= piece and other.s > v.s and other.s - other.length / 2 < C.SharedEntryLength then
				local gap = other.s - v.s - (other.length + v.length) / 2
				if gap < bestGap then
					bestGap, bestSpeed = gap, other.v
				end
			end
		end
	end
	if bestGap < math.huge then
		return bestGap, bestSpeed
	end
	local ahead = piece.length - v.s
	for i = v.index + 1, #v.route do
		if ahead > C.LookAhead then
			break
		end
		local nextPiece = v.route[i]
		local list = nextPiece.kind == "junction" and approaches[nextPiece.approachKey] or occupancy[nextPiece]
		local minS, minSpeed, minLength = math.huge, 0, 0
		for _, other in ipairs(list or {}) do
			if other ~= v and other.s < minS then
				minS, minSpeed, minLength = other.s, other.v, other.length
			end
		end
		if minS < math.huge then
			return ahead + minS - (minLength + v.length) / 2, minSpeed
		end
		ahead += nextPiece.length
	end
	return math.huge, 0
end

-- May this car enter the junction now? Checks the light, crossing traffic, and room on the far side.
local function gateOpen(v, movement, toLine, now, occupancy, reservations)
	local node = network.nodes[movement.node]
	local light = TrafficSignals.state(node, movement.axis, now)
	if light == "red" then
		return false, light
	end
	if light == "yellow" and toLine > (v.v * v.v) / (2 * C.ComfortDecel) + 0.5 then
		return false, light
	end
	local queued = 0
	for _, other in ipairs(reservations[node.key] or {}) do
		if other ~= v then
			if network:conflicts(other.commit.piece, movement) then
				return false, light
			end
			if other.commit.piece.to == movement.to then
				queued += other.length + C.MinGap
			end
		end
	end
	local exit = v.route[v.index + 2]
	if exit then
		local needed = v.length + C.MinGap + queued
		for _, other in ipairs(occupancy[exit] or {}) do
			if other.s - other.length / 2 < needed then
				return false, light
			end
		end
	end
	return true, light
end

local function sampleAlong(v, offset)
	local index, s = v.index, v.s + offset
	local piece = v.route[index]
	if s < 0 and v.prev then
		return pointAt(v.prev, v.prev.length + s)
	end
	while s > piece.length and index < #v.route do
		s -= piece.length
		index += 1
		piece = v.route[index]
	end
	return pointAt(piece, s)
end

local function listRemove(list, v)
	if list then
		local i = table.find(list, v)
		if i then
			table.remove(list, i)
		end
	end
end

local function listAdd(map, key, v)
	local list = map[key] or {}
	map[key] = list
	table.insert(list, v)
end

-- Keeps the occupancy lists exact while cars move between pieces during a frame.
local function movePiece(v, oldPiece, newPiece, occupancy, approaches)
	listRemove(occupancy[oldPiece], v)
	if oldPiece.kind == "junction" then
		listRemove(approaches[oldPiece.approachKey], v)
	end
	listAdd(occupancy, newPiece, v)
	if newPiece.kind == "junction" then
		listAdd(approaches, newPiece.approachKey, v)
	end
end

local function stepVehicle(v, dt, now, occupancy, approaches, reservations)
	if v.state == "out" then
		v.v = 0
		return
	end
	local piece = v.route[v.index]

	-- Desired speed: the road's limit, eased down early for slower curves ahead.
	local desired = piece.speed
	local ahead = piece.length - v.s
	for i = v.index + 1, #v.route do
		if ahead > C.LookAhead then
			break
		end
		local nextPiece = v.route[i]
		desired = math.min(desired, math.sqrt(nextPiece.speed ^ 2 + 2 * C.ComfortDecel * math.max(ahead - v.length / 2, 0)))
		ahead += nextPiece.length
	end

	local gap, leaderSpeed = findLeader(v, occupancy, approaches)
	local acc = idm(v.v, desired, gap, v.v - leaderSpeed, C.MinGap)

	-- Stop line at a signalised junction.
	local stopGap
	v.waitingAtLight = false
	local nextPiece = v.route[v.index + 1]
	if not v.commit and piece.kind == "lane" and nextPiece and nextPiece.kind == "junction" and network.nodes[nextPiece.node].signal then
		local toLine = piece.length - v.s - v.length / 2
		if toLine < (v.v * v.v) / (2 * C.ComfortDecel) + C.CommitMargin then
			local open, light = gateOpen(v, nextPiece, toLine, now, occupancy, reservations)
			if toLine < -0.05 then
				open = true -- already over the line (a junction was just built under this car): clear it
			end
			if open then
				v.commit = { piece = nextPiece, index = v.index + 1, node = nextPiece.node, time = now, light = light }
				local list = reservations[nextPiece.node] or {}
				reservations[nextPiece.node] = list
				table.insert(list, v)
			else
				stopGap = toLine
				v.waitingAtLight = true
			end
		end
	end
	if stopGap then
		acc = math.min(acc, idm(v.v, desired, stopGap, v.v, C.StopLineGap))
	end

	-- End of the trip: pull up gently at the destination.
	local finalPiece = v.index == #v.route
	if finalPiece then
		acc = math.min(acc, idm(v.v, desired, piece.length - v.s, v.v, 0.1))
	end

	acc = math.clamp(acc, -C.MaxDecel, C.Accel)
	v.braking = acc < -1.2 or v.v < 0.3
	v.v = math.max(0, v.v + acc * dt)
	local advance = v.v * dt
	-- Hard limits: never move into the car ahead or past a closed stop line.
	if gap < math.huge then
		advance = math.min(advance, math.max(0, gap - 0.2))
	end
	if stopGap then
		advance = math.min(advance, math.max(0, stopGap - 0.02))
	end
	if advance < v.v * dt then
		v.v = advance / dt
	end
	local decel = (v.lastSpeed or v.v) - v.v
	if decel / dt > C.MaxDecel + 0.5 then
		stats.hardStops += 1
		stats.lastHardStop = string.format("%s s=%.1f gap=%.2f stop=%s", piece.key, v.s, gap, tostring(stopGap))
	end
	v.lastSpeed = v.v
	v.s += advance

	while v.s > piece.length and v.index < #v.route do
		v.s -= piece.length
		v.prev = piece
		v.index += 1
		movePiece(v, piece, v.route[v.index], occupancy, approaches)
		piece = v.route[v.index]
		if piece.kind == "junction" and network.nodes[piece.node].signal then
			local light = TrafficSignals.state(network.nodes[piece.node], piece.axis, now)
			local committedLate = not v.commit or (now - v.commit.time) > C.Signal.Yellow + C.Signal.AllRed
			if light == "red" and committedLate then
				stats.redEntries += 1
			end
		end
	end
	if v.index == #v.route and v.s >= piece.length - 0.35 then
		v.s = math.min(v.s, piece.length)
		if v.v < 1 then
			v.state = "out"
			stats.arrived += 1
		end
	end

	-- Release the junction once the whole car has left it.
	if v.commit and (v.index > v.commit.index + 1 or (v.index == v.commit.index + 1 and v.s - v.length / 2 > 0.3)) then
		v.commit = nil
	end

	if v.v < 0.05 then
		v.stuck += dt
		v.wait += dt
	else
		v.stuck = 0
	end
	if v.stuck > C.StuckTimeout then
		v.state = "out"
		v.commit = nil
		stats.stuckRemoved += 1
	end
end

local UP = Vector3.new(0, 1, 0)

-- Penetration depth between two vehicles' footprints (0 when apart), using the separating axis test.
local function footprintOverlap(a, b)
	local ha, hb = flat(a.heading), flat(b.heading)
	if ha.Magnitude < 0.01 or hb.Magnitude < 0.01 then
		return 0
	end
	ha, hb = ha.Unit, hb.Unit
	local ra, rb = ha:Cross(UP), hb:Cross(UP)
	local d = flat(b.position) - flat(a.position)
	local la, wa, lb, wb = a.length / 2 - 0.1, a.width / 2 - 0.1, b.length / 2 - 0.1, b.width / 2 - 0.1
	local depth = math.huge
	for _, axis in ipairs({ ha, ra, hb, rb }) do
		local extentA = math.abs(ha:Dot(axis)) * la + math.abs(ra:Dot(axis)) * wa
		local extentB = math.abs(hb:Dot(axis)) * lb + math.abs(rb:Dot(axis)) * wb
		local overlap = extentA + extentB - math.abs(d:Dot(axis))
		if overlap <= 0 then
			return 0
		end
		depth = math.min(depth, overlap)
	end
	return depth
end

local function overlapCheck()
	local worst = 0
	for i = 1, #vehicles do
		local a = vehicles[i]
		for j = i + 1, #vehicles do
			local b = vehicles[j]
			local amount = footprintOverlap(a, b)
			if amount > worst then
				worst = amount
				stats.lastOverlap = string.format("%s@%.1f(%s) vs %s@%.1f(%s)", a.route[a.index].key, a.s, a.state, b.route[b.index].key, b.s, b.state)
			end
		end
	end
	stats.overlapChecks += 1
	if worst > 0 then
		stats.overlapFrames += 1
		stats.worstOverlap = math.max(stats.worstOverlap, worst)
	end
end

local partBuffer, cframeBuffer = {}, {}

local function step(dt)
	if not network or not deps.state.snapshot then
		return
	end
	dt = math.min(dt, 0.1)
	local now = serverNow()
	local started = os.clock()

	if enabled then
		spawnClock += dt
		if spawnClock >= C.SpawnInterval then
			spawnClock = 0
			if #vehicles < targetCount() then
				trySpawn()
			end
		end
	end

	-- Who is on which piece, and who holds which junction.
	local occupancy, approaches, reservations = {}, {}, {}
	for _, v in ipairs(vehicles) do
		local piece = v.route[v.index]
		local list = occupancy[piece] or {}
		occupancy[piece] = list
		table.insert(list, v)
		if piece.kind == "junction" then
			local group = approaches[piece.approachKey] or {}
			approaches[piece.approachKey] = group
			table.insert(group, v)
		end
		if v.commit then
			local held = reservations[v.commit.node] or {}
			reservations[v.commit.node] = held
			table.insert(held, v)
		end
	end

	for _, v in ipairs(vehicles) do
		stepVehicle(v, dt, now, occupancy, approaches, reservations)
	end

	-- Fade in/out and render everything with one BulkMoveTo.
	table.clear(partBuffer)
	table.clear(cframeBuffer)
	for i = #vehicles, 1, -1 do
		local v = vehicles[i]
		if v.state == "in" then
			v.alpha = math.min(1, v.alpha + dt / C.FadeTime)
			setTransparency(v, v.alpha)
			if v.alpha >= 1 then
				v.state = "drive"
			end
		elseif v.state == "out" then
			v.alpha -= dt / C.FadeTime
			if v.alpha <= 0 then
				removeVehicle(i)
				continue
			end
			setTransparency(v, v.alpha)
		end
		local center = sampleAlong(v, 0)
		local front = sampleAlong(v, v.length * 0.38)
		local rear = sampleAlong(v, -v.length * 0.38)
		local heading = flat(front - rear)
		if heading.Magnitude > 0.01 then
			v.heading = heading
		end
		if v.lastRender and v.state ~= "in" then
			local jump = (flat(center) - flat(v.lastRender)).Magnitude
			if jump > (math.max(v.v, v.lastSpeed or 0) + 1) * dt * 1.5 + 0.2 then
				stats.jumps += 1
				stats.lastJump = string.format("%s %.2f studs", v.route[v.index].key, jump)
			end
		end
		v.lastRender = center
		v.position = center
		v.y += (center.Y - v.y) * math.min(1, dt * 12)
		local pos = Vector3.new(center.X, v.y, center.Z)
		local cf = CFrame.lookAt(pos, pos + flat(v.heading))
		for k, p in ipairs(v.model.parts) do
			table.insert(partBuffer, p)
			table.insert(cframeBuffer, cf * v.model.offsets[k])
		end
		if v.braking ~= v.brakeShown then
			v.brakeShown = v.braking
			for _, tail in ipairs(v.model.tails) do
				tail.Color = v.braking and VehicleFactory.TailOn or VehicleFactory.TailOff
				tail.Material = v.braking and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
		end
	end
	if #partBuffer > 0 then
		Workspace:BulkMoveTo(partBuffer, cframeBuffer, Enum.BulkMoveMode.FireCFrameChanged)
	end
	SignalVisuals.update(now)
	local ms = (os.clock() - started) * 1000
	stats.stepMs = (stats.stepMs or ms) * 0.95 + ms * 0.05
	stats.peakStepMs = math.max(stats.peakStepMs or 0, ms)

	overlapClock += dt
	if overlapClock > 0.2 then
		overlapClock = 0
		overlapCheck()
	end
end

-- Snapshot for tests and future traffic feedback (Milestone 3).
function Traffic.getStats()
	local waiting, moving = 0, 0
	for _, v in ipairs(vehicles) do
		if v.v < 0.3 then
			waiting += 1
		else
			moving += 1
		end
	end
	local result = table.clone(stats)
	result.vehicles = #vehicles
	result.target = targetCount()
	result.places = #places
	result.waiting = waiting
	result.moving = moving
	result.signals = network and #network.signalNodes or 0
	return result
end

function Traffic.init(dependencies)
	deps = dependencies
	folder = Workspace:FindFirstChild("RoadLinkTraffic") or Instance.new("Folder")
	folder.Name = "RoadLinkTraffic"
	folder.Parent = Workspace
	SignalVisuals.init(folder)

	-- Debug hook for automated tests: workspace.RoadLinkTraffic.Debug:Invoke(command, value)
	local debugHook = Instance.new("BindableFunction")
	debugHook.Name = "Debug"
	debugHook.OnInvoke = function(command, value)
		if command == "stats" then
			return Traffic.getStats()
		elseif command == "reset" then
			for i = #vehicles, 1, -1 do
				removeVehicle(i)
			end
			for key, value in pairs(stats) do
				stats[key] = typeof(value) == "number" and 0 or nil
			end
			return true
		elseif command == "max" then
			maxOverride = value
			return true
		elseif command == "refresh" then
			deps.state.invoke("GetState")
			return true
		elseif command == "enabled" then
			enabled = value
			return true
		elseif command == "vehicles" then
			local list = {}
			for _, v in ipairs(vehicles) do
				local piece = v.route[v.index]
				table.insert(list, { id = v.id, style = v.model.style, piece = piece.key, s = v.s, v = v.v, state = v.state, committed = v.commit ~= nil, waitingAtLight = v.waitingAtLight == true, x = v.position.X, z = v.position.Z })
			end
			return list
		end
		return nil
	end
	debugHook.Parent = folder

	deps.state.Changed:Connect(onState)
	if deps.state.snapshot then
		onState()
	end
	RunService.Heartbeat:Connect(step)
end

return Traffic
