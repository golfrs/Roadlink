-- Builds the low-poly traffic vehicles. Each vehicle is a handful of anchored, non-colliding parts
-- plus their offsets from the vehicle pivot (ground centre, front facing -Z), so the traffic
-- controller can move every car in one Workspace:BulkMoveTo call per frame.
local VehicleFactory = {}

local PAINT = {
	Color3.fromRGB(200, 76, 58), -- red
	Color3.fromRGB(64, 112, 170), -- blue
	Color3.fromRGB(236, 236, 230), -- white
	Color3.fromRGB(236, 194, 72), -- yellow
	Color3.fromRGB(72, 150, 150), -- teal
	Color3.fromRGB(232, 134, 66), -- orange
	Color3.fromRGB(104, 152, 90), -- green
	Color3.fromRGB(150, 154, 162), -- silver
}
local GLASS = Color3.fromRGB(64, 90, 116)
local TYRE = Color3.fromRGB(36, 38, 42)
local TRIM = Color3.fromRGB(60, 64, 72)
local HEADLIGHT = Color3.fromRGB(255, 244, 214)
VehicleFactory.TailOff = Color3.fromRGB(128, 34, 34)
VehicleFactory.TailOn = Color3.fromRGB(255, 58, 46)

local function builder()
	local list = { parts = {}, offsets = {}, base = {}, tails = {} }
	function list.add(name, size, offset, color, extra)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(extra or {}) do
			p[k] = v
		end
		table.insert(list.parts, p)
		table.insert(list.offsets, typeof(offset) == "CFrame" and offset or CFrame.new(offset))
		table.insert(list.base, p.Transparency)
		return p
	end
	function list.wheels(width, diameter, frontZ, rearZ)
		local x = width / 2 - 0.12
		for _, z in ipairs({ frontZ, rearZ }) do
			for _, side in ipairs({ -1, 1 }) do
				list.add("Wheel", Vector3.new(0.32, diameter, diameter), Vector3.new(side * x, diameter / 2, z), TYRE, { Shape = Enum.PartType.Cylinder })
			end
		end
	end
	function list.lights(width, length, y)
		for _, side in ipairs({ -1, 1 }) do
			list.add("Headlight", Vector3.new(0.38, 0.18, 0.06), Vector3.new(side * (width / 2 - 0.3), y, -length / 2 - 0.02), HEADLIGHT, { Material = Enum.Material.Neon })
			local tail = list.add("Taillight", Vector3.new(0.36, 0.18, 0.06), Vector3.new(side * (width / 2 - 0.28), y, length / 2 + 0.02), VehicleFactory.TailOff)
			table.insert(list.tails, tail)
		end
		list.add("Bumper", Vector3.new(width + 0.04, 0.2, 0.14), Vector3.new(0, 0.36, -length / 2 - 0.04), TRIM)
		list.add("Bumper", Vector3.new(width + 0.04, 0.2, 0.14), Vector3.new(0, 0.36, length / 2 + 0.04), TRIM)
	end
	return list
end

local STYLES = {
	{
		name = "Hatchback", weight = 30, length = 3.3, width = 1.7,
		build = function(b, paint)
			local L, W = 3.3, 1.7
			b.add("Body", Vector3.new(W, 0.6, L), Vector3.new(0, 0.55, 0), paint)
			b.add("Cabin", Vector3.new(W - 0.2, 0.6, 1.9), Vector3.new(0, 1.15, 0.4), paint)
			b.add("Glass", Vector3.new(W - 0.14, 0.38, 1.8), Vector3.new(0, 1.12, 0.4), GLASS)
			b.wheels(W, 0.6, -1.0, 1.05)
			b.lights(W, L, 0.68)
		end,
	},
	{
		name = "Sedan", weight = 35, length = 3.9, width = 1.75,
		build = function(b, paint)
			local L, W = 3.9, 1.75
			b.add("Body", Vector3.new(W, 0.6, L), Vector3.new(0, 0.55, 0), paint)
			b.add("Cabin", Vector3.new(W - 0.2, 0.56, 1.9), Vector3.new(0, 1.13, 0.2), paint)
			b.add("Glass", Vector3.new(W - 0.14, 0.36, 1.8), Vector3.new(0, 1.1, 0.2), GLASS)
			b.wheels(W, 0.62, -1.25, 1.25)
			b.lights(W, L, 0.68)
		end,
	},
	{
		name = "Van", weight = 20, length = 4.3, width = 1.85,
		build = function(b, paint)
			local L, W = 4.3, 1.85
			b.add("Body", Vector3.new(W, 0.7, L), Vector3.new(0, 0.6, 0), paint)
			b.add("Upper", Vector3.new(W - 0.04, 0.85, L - 1.0), Vector3.new(0, 1.37, 0.5), paint)
			b.add("Windscreen", Vector3.new(W - 0.3, 0.5, 0.06), Vector3.new(0, 1.42, 0.5 - (L - 1.0) / 2 - 0.02), GLASS)
			b.add("SideGlass", Vector3.new(W + 0.01, 0.34, 1.0), Vector3.new(0, 1.48, -0.55), GLASS)
			b.add("Stripe", Vector3.new(W + 0.02, 0.16, L - 1.2), Vector3.new(0, 1.0, 0.5), Color3.fromRGB(246, 244, 238))
			b.wheels(W, 0.66, -1.35, 1.35)
			b.lights(W, L, 0.75)
		end,
	},
	{
		name = "Truck", weight = 15, length = 5.4, width = 1.95,
		build = function(b, paint)
			local L, W = 5.4, 1.95
			b.add("Chassis", Vector3.new(W - 0.25, 0.3, L), Vector3.new(0, 0.45, 0), TRIM)
			b.add("Cab", Vector3.new(W, 1.25, 1.5), Vector3.new(0, 1.2, -L / 2 + 0.75), paint)
			b.add("Windscreen", Vector3.new(W - 0.3, 0.5, 0.06), Vector3.new(0, 1.5, -L / 2 - 0.02), GLASS)
			b.add("SideGlass", Vector3.new(W + 0.01, 0.42, 0.8), Vector3.new(0, 1.5, -L / 2 + 0.6), GLASS)
			local boxLength = L - 1.65
			local boxZ = (-L / 2 + 1.65 + L / 2) / 2
			b.add("Box", Vector3.new(W + 0.05, 1.9, boxLength), Vector3.new(0, 1.55, boxZ), Color3.fromRGB(244, 242, 236))
			b.add("BoxStripe", Vector3.new(W + 0.08, 0.32, boxLength + 0.02), Vector3.new(0, 1.3, boxZ), paint)
			b.wheels(W, 0.74, -L / 2 + 0.8, L / 2 - 1.0)
			b.lights(W, L, 0.72)
		end,
	},
}
local totalWeight = 0
for _, style in ipairs(STYLES) do
	totalWeight += style.weight
end

-- Creates a vehicle under parent. Returns { parts, offsets, base, tails, length, width, style }.
function VehicleFactory.create(parent, rng)
	local roll = rng:NextNumber(0, totalWeight)
	local style = STYLES[#STYLES]
	for _, candidate in ipairs(STYLES) do
		roll -= candidate.weight
		if roll <= 0 then
			style = candidate
			break
		end
	end
	local b = builder()
	style.build(b, PAINT[rng:NextInteger(1, #PAINT)])
	local folder = Instance.new("Folder")
	folder.Name = style.name
	for _, p in ipairs(b.parts) do
		p.CFrame = CFrame.new(0, -500, 0)
		p.Parent = folder
	end
	folder.Parent = parent
	return { folder = folder, parts = b.parts, offsets = b.offsets, base = b.base, tails = b.tails, length = style.length, width = style.width, style = style.name }
end

return VehicleFactory
