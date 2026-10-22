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

## Traffic (Milestone 1)

Cars are simulated **on each player's own client** for their own city (no physics, no network traffic):

- `ReplicatedStorage/Shared/TrafficConfig` – speeds, spacing, light timings, `DriveOnLeft`.
- `ReplicatedStorage/Shared/TrafficNetwork` – builds lanes and junction turn paths from the road graph.
- `ReplicatedStorage/Shared/TrafficSignals` – traffic light timing (east-west and north-south take turns).
- `StarterPlayer/.../Controllers/TrafficController` – spawning, driving (Intelligent Driver Model), lights, junction reservations, rendering via `BulkMoveTo`.
- `VehicleFactory` (car models) and `SignalVisuals` (light poles + stop lines).

Every junction where 3+ roads meet gets traffic lights automatically. Cars travel between connected buildings and road ends.

### Testing traffic in Studio

Build a few roads with a crossing, press Play, then in the **client** command bar:

```lua
local dbg = workspace.RoadLinkTraffic.Debug
dbg:Invoke("max", 20)          -- force a vehicle count (nil = automatic)
print(dbg:Invoke("stats"))     -- overlapFrames, redEntries, hardStops, jumps and stuckRemoved should stay 0
```

If roads are built from a test script instead of the UI, call `dbg:Invoke("refresh")` so the client sees them.
