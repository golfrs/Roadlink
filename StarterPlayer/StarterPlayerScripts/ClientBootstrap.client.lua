-- RoadLink client entry point: wires state, camera, construction tools and HUD.
local StarterGui = game:GetService("StarterGui")
local Controllers = script.Parent:WaitForChild("Controllers")
local ClientState = require(Controllers:WaitForChild("ClientState"))
local CameraController = require(Controllers:WaitForChild("CameraController"))
local ConstructionController = require(Controllers:WaitForChild("ConstructionController"))
local Hud = require(Controllers:WaitForChild("Hud"))
local TrafficController = require(Controllers:WaitForChild("TrafficController"))

task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

local deps = { state = ClientState, camera = CameraController, construction = ConstructionController, hud = Hud }
Hud.init(deps)
CameraController.init(deps)
ConstructionController.init(deps)
TrafficController.init(deps)
ClientState.start()
