-- Rebuilds all RoadLink assets and the map template. Usage (edit mode command bar):
--   require(game.ServerStorage.RoadLinkTools.Rebuild:Clone())()
return function()
	local ServerStorage = game:GetService("ServerStorage")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local tools = ServerStorage.RoadLinkTools
	-- Fresh copies so edits to the modules are always picked up.
	local AssetBuilder = require(tools.AssetBuilder:Clone())
	local MapBuilder = require(tools.MapBuilder:Clone())
	AssetBuilder.build()
	local shared = ReplicatedStorage.Shared:Clone()
	shared.Parent = ServerStorage
	local ok, result = pcall(MapBuilder.build, shared, ServerStorage.RoadLinkAssets.Models, AssetBuilder)
	shared:Destroy()
	if not ok then
		error(result)
	end
	local old = ServerStorage.RoadLinkAssets:FindFirstChild("MapTemplate")
	if old then
		old:Destroy()
	end
	result.Parent = ServerStorage.RoadLinkAssets
	local parts = 0
	for _, d in ipairs(result:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return parts
end
