-- City-builder camera: angled overhead view. WASD / arrows / right-drag pan, wheel zooms, Q/E rotate.
-- Touch: one-finger drag pans, pinch zooms, short taps are passed to the construction controller.
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RegionConfig = require(Shared:WaitForChild("RegionConfig"))
local Grid = require(Shared:WaitForChild("Grid"))

local CameraController = {}
local deps
local PITCH = math.rad(56)
local FOV = 45
local MIN_ZOOM, MAX_ZOOM = 45, 340
local focus, targetFocus = Vector3.zero, Vector3.zero
local zoom, targetZoom = 160, 160
local yaw, targetYaw = 0, 0
local keys = {}
local drag
local touches = {}
local touchCount = 0
local pinchBase
local tapCallback, rightClickCallback
local initialised = false

local KEYMAP = {
	[Enum.KeyCode.W] = "f", [Enum.KeyCode.Up] = "f",
	[Enum.KeyCode.S] = "b", [Enum.KeyCode.Down] = "b",
	[Enum.KeyCode.A] = "l", [Enum.KeyCode.Left] = "l",
	[Enum.KeyCode.D] = "r", [Enum.KeyCode.Right] = "r",
}

local function basis()
	local rotation = CFrame.Angles(0, yaw, 0)
	return rotation:VectorToWorldSpace(Vector3.new(0, 0, -1)), rotation:VectorToWorldSpace(Vector3.new(1, 0, 0))
end

local function clampFocus(v)
	local snapshot = deps.state.snapshot
	if not snapshot then
		return v
	end
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, id in ipairs(RegionConfig.Order) do
		local b = RegionConfig.Regions[id].Bounds
		minX, maxX = math.min(minX, b.MinX), math.max(maxX, b.MaxX)
		minZ, maxZ = math.min(minZ, b.MinZ), math.max(maxZ, b.MaxZ)
	end
	local g = GameConfig.GridSize
	return Vector3.new(
		math.clamp(v.X, snapshot.originX + minX * g - 30, snapshot.originX + maxX * g + 30),
		0,
		math.clamp(v.Z, snapshot.originZ + minZ * g - 30, snapshot.originZ + maxZ * g + 30)
	)
end

local function worldPerPixel()
	local camera = Workspace.CurrentCamera
	local height = math.max(camera.ViewportSize.Y, 1)
	return 2 * zoom * math.tan(math.rad(FOV) / 2) / height
end

local function pan(delta)
	local forward, right = basis()
	local scale = worldPerPixel() * 1.2
	targetFocus = clampFocus(targetFocus - right * delta.X * scale + forward * delta.Y * scale)
end

function CameraController.onTap(callback)
	tapCallback = callback
end

function CameraController.onRightClick(callback)
	rightClickCallback = callback
end

function CameraController.focusCell(x, z, instant)
	local snapshot = deps.state.snapshot
	if not snapshot then
		return
	end
	targetFocus = clampFocus(Grid.toWorld(snapshot.originX, snapshot.originZ, x, z, 0))
	if instant then
		focus = targetFocus
	end
end

function CameraController.focusRegion(regionId)
	local cx, cz = Grid.regionCenter(regionId)
	CameraController.focusCell(cx, cz)
	targetZoom = 200
end

function CameraController.focusGate(gateId)
	local gate = Grid.gates[gateId]
	if gate then
		CameraController.focusCell(gate.x, gate.z)
		targetZoom = 120
	end
end

function CameraController.getFocusCell()
	local snapshot = deps and deps.state.snapshot
	if not snapshot then
		return nil
	end
	return Grid.toCell(snapshot.originX, snapshot.originZ, targetFocus)
end

function CameraController.isDragging()
	return drag ~= nil and drag.moved
end

function CameraController.init(dependencies)
	deps = dependencies

	deps.state.Changed:Connect(function()
		if not initialised then
			initialised = true
			CameraController.focusCell(0, 0, true)
		end
	end)

	RunService:BindToRenderStep("RoadLinkCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		if not UserInputService:GetFocusedTextBox() then
			local forward, right = basis()
			local move = Vector3.zero
			if keys.f then move += forward end
			if keys.b then move -= forward end
			if keys.r then move += right end
			if keys.l then move -= right end
			if move.Magnitude > 0 then
				targetFocus = clampFocus(targetFocus + move.Unit * zoom * 0.9 * dt)
			end
		end
		local alpha = 1 - math.exp(-dt * 14)
		focus = focus:Lerp(targetFocus, alpha)
		zoom += (targetZoom - zoom) * alpha
		yaw += (targetYaw - yaw) * alpha
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = FOV
		local offset = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(0, math.sin(PITCH) * zoom, math.cos(PITCH) * zoom))
		camera.CFrame = CFrame.lookAt(focus + offset, focus)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch then
			if processed then
				return
			end
			touches[input] = { start = Vector2.new(input.Position.X, input.Position.Y), last = Vector2.new(input.Position.X, input.Position.Y), t = os.clock(), moved = false }
			touchCount += 1
			if touchCount > 1 then
				for _, info in pairs(touches) do
					info.multi = true
				end
			end
			return
		end
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
			local location = UserInputService:GetMouseLocation()
			drag = { start = location, last = location, moved = false, button = input.UserInputType }
		elseif input.UserInputType == Enum.UserInputType.Keyboard and not UserInputService:GetFocusedTextBox() then
			local direction = KEYMAP[input.KeyCode]
			if direction then
				keys[direction] = true
			elseif input.KeyCode == Enum.KeyCode.Q then
				targetYaw += math.rad(45)
			elseif input.KeyCode == Enum.KeyCode.E then
				targetYaw -= math.rad(45)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if not processed then
				targetZoom = math.clamp(targetZoom * (1 - input.Position.Z * 0.12), MIN_ZOOM, MAX_ZOOM)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			if drag then
				local now = UserInputService:GetMouseLocation()
				if (now - drag.start).Magnitude > 4 then
					drag.moved = true
				end
				pan(now - drag.last)
				drag.last = now
			end
		elseif input.UserInputType == Enum.UserInputType.Touch then
			local info = touches[input]
			if not info then
				return
			end
			local position = Vector2.new(input.Position.X, input.Position.Y)
			if (position - info.start).Magnitude > 14 then
				info.moved = true
			end
			if touchCount == 1 and info.moved then
				pan(position - info.last)
			end
			info.last = position
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local direction = KEYMAP[input.KeyCode]
			if direction then
				keys[direction] = false
			end
		elseif drag and input.UserInputType == drag.button then
			if not drag.moved and drag.button == Enum.UserInputType.MouseButton2 and rightClickCallback then
				rightClickCallback()
			end
			drag = nil
		elseif input.UserInputType == Enum.UserInputType.Touch then
			local info = touches[input]
			if not info then
				return
			end
			touches[input] = nil
			touchCount = math.max(0, touchCount - 1)
			if not info.moved and not info.multi and os.clock() - info.t < 0.45 and tapCallback then
				local inset = GuiService:GetGuiInset()
				tapCallback(info.start + inset)
			end
		end
	end)

	UserInputService.TouchPinch:Connect(function(_, scale, _, inputState, processed)
		if processed then
			return
		end
		if inputState == Enum.UserInputState.Begin then
			pinchBase = targetZoom
		elseif inputState == Enum.UserInputState.Change and pinchBase then
			targetZoom = math.clamp(pinchBase / math.max(scale, 0.05), MIN_ZOOM, MAX_ZOOM)
		else
			pinchBase = nil
		end
	end)
end

return CameraController
