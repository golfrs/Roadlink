# RoadLink — working notes for Claude

- The live game is the Roblox Studio place "g0lfrr's Place: 10212026_1" (placeId 83812853867504). Studio is the source of truth.
- **After every change made in Studio, sync this repo and push to `main`** (the owner asked for every update to be pushed).
  - Export each changed script's `.Source` into the matching file here (Rojo naming: `*.server.lua` Script, `*.client.lua` LocalScript, `*.lua` ModuleScript).
  - Commit with a short message describing the update, then `git push origin main`.
- Generated models and the map template are not stored as files; they come from `ServerStorage/RoadLinkTools` (`Rebuild`).
- Run `RoadLinkDiagnostics` during a playtest before pushing gameplay changes.
- The old disabled scripts (`RoadLinkServer`, `RoadLinkClient`, `RoadLinkConfig`) are intentionally not tracked.
