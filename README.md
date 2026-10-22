# RoadLink

A Roblox city-building strategy game: build roads, connect places, grow your economy and unlock new regions.

## Layout (Rojo-compatible)

| Folder | Roblox location |
|---|---|
| `ReplicatedStorage/Shared` | Config + shared logic (`GameConfig`, `RoadConfig`, `BuildingConfig`, `RegionConfig`, `Grid`, `RoadGraph`, `Rules`) |
| `ServerScriptService/ServerBootstrap.server.lua` | Server entry point |
| `ServerScriptService/Services` | Player data, world, network, economy, regions, roads, buildings, persistence |
| `ServerScriptService/Tests` | `RoadLinkDiagnostics` (run during a playtest) |
| `ServerStorage/RoadLinkTools` | `AssetBuilder`, `MapBuilder`, `Rebuild` — generate models and the map template |
| `StarterPlayer/StarterPlayerScripts` | `ClientBootstrap.client.lua` + `Controllers` (state, camera, construction, HUD) |

`*.server.lua` = Script, `*.client.lua` = LocalScript, `*.lua` = ModuleScript.

## Setup in Studio

1. Put each script in the matching location (or sync with Rojo using `default.project.json`).
2. Generate the models and map — run in the Command Bar (Edit mode):
   `require(game.ServerStorage.RoadLinkTools.Rebuild:Clone())()`
3. Workspace → **StreamingEnabled = false** (the camera-only player has no character).
4. Optional: Game Settings → Security → **Enable Studio Access to API Services** to test saving.

## Tests

During a playtest, in the server Command Bar:

```lua
print(require(game.ServerScriptService.Tests.RoadLinkDiagnostics).run().summary)
```
