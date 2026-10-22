-- Traffic light poles and stop lines for every signalised junction in the local player's city.
-- Lamps only change appearance when their state changes, so updating every frame is cheap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoadConfig = require(Shared:WaitForChild("RoadConfig"))
local TrafficConfig = require(Shared:WaitForChild("TrafficConfig"))
local TrafficSignals = require(Shared:WaitForChild("TrafficSignals"))

local SignalVisuals = {}
local UP = Vector3.new(0, 1, 0)
local SIDE = TrafficConfig.DriveOnLeft and -1 or 1
local folder
local heads = {}

local LIT = {
	red = Color3.fromRGB(255, 64, 52),
	yellow = Color3.fromRGB(255, 196, 60),
	green = Color3.fromRGB(80, 236, 120),
}
local DIM = {
	red = Color3.fromRGB(78, 30, 30),
	yellow = Color3.fromRGB(78, 64, 26),
	green = Color3.fromRGB(26, 64, 36),
}

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

function SignalVisuals.init(parent)
	folder = Instance.new("Folder")
	folder.Name = "Signals"
	folder.Parent = parent
end

function SignalVisuals.rebuild(network)
	folder:ClearAllChildren()
	heads = {}
	if not network then
		return
	end
	for _, node in ipairs(network.signalNodes) do
		local nodeFolder = Instance.new("Folder")
		nodeFolder.Name = node.key
		for _, link in ipairs(node.links) do
			local lane = network.lanes[link.node .. ">" .. node.key]
			if lane then
				local dIn = lane.dir
				local r = dIn:Cross(UP) * SIDE
				local roadHalf = RoadConfig.Types[link.edge.kind].Width / 2
				local nodeHalf = node.maxWidth / 2
				-- Pole on the kerb at the driver's side corner, just before the junction.
				local base = node.pos - dIn * (nodeHalf + 0.75) + r * (roadHalf + 0.75)
				local facing = -dIn
				local pole = part(nodeFolder, {
					Name = "Pole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 0.3, 0.3),
					CFrame = CFrame.new(base + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(58, 62, 70),
				})
				local headCF = CFrame.lookAt(base + Vector3.new(0, 3.05, 0), base + Vector3.new(0, 3.05, 0) + facing)
				part(nodeFolder, { Name = "Housing", Size = Vector3.new(0.62, 1.55, 0.46), CFrame = headCF, Color = Color3.fromRGB(34, 38, 44) })
				part(nodeFolder, { Name = "Backplate", Size = Vector3.new(0.86, 1.8, 0.06), CFrame = headCF * CFrame.new(0, 0, 0.26), Color = Color3.fromRGB(240, 196, 64) })
				local lamps = {}
				for i, colour in ipairs({ "red", "yellow", "green" }) do
					lamps[colour] = part(nodeFolder, {
						Name = "Lamp_" .. colour, Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4),
						CFrame = headCF * CFrame.new(0, 0.48 - (i - 1) * 0.48, -0.2), Color = DIM[colour], CastShadow = false,
					})
				end
				-- White stop line across the incoming lane.
				local stop = lane.points[#lane.points]
				local laneWidth = roadHalf - 0.3
				part(nodeFolder, {
					Name = "StopLine", Size = Vector3.new(0.42, 0.04, laneWidth),
					CFrame = CFrame.lookAt(Vector3.new(stop.X, stop.Y + 0.02, stop.Z) - dIn * 0.25, Vector3.new(stop.X, stop.Y + 0.02, stop.Z) - dIn * 0.25 + r),
					Color = Color3.fromRGB(244, 244, 240), CastShadow = false,
				})
				local axis = select(1, string.match(link.node, "^(-?%d+)")) ~= tostring(node.x) and "X" or "Z"
				table.insert(heads, { node = node, axis = axis, lamps = lamps, state = nil, pole = pole })
			end
		end
		nodeFolder.Parent = folder
	end
end

function SignalVisuals.update(now)
	for _, head in ipairs(heads) do
		local state = TrafficSignals.state(head.node, head.axis, now)
		if state ~= head.state then
			head.state = state
			for colour, lamp in pairs(head.lamps) do
				local on = colour == state
				lamp.Color = on and LIT[colour] or DIM[colour]
				lamp.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
		end
	end
end

return SignalVisuals
