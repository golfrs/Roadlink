# RoadLink — Product Direction & Quality Bar

## The game in one sentence
A living city grows automatically; the player builds roads and controls traffic to keep the city moving.

## Audience and usability
Design for Roblox players under 16. The game must be immediately understandable without reading a manual:
- One obvious primary action at a time.
- Large, readable buttons with plain words and clear icons.
- Short contextual hints and a friendly first-time tutorial.
- Clear visual feedback for valid placement, invalid placement, congestion, and success.
- Avoid jargon, dense dashboards, tiny text, and management spreadsheets.
- Make the world itself explain the game: visible queues, traffic lights, delivery vehicles, and simple cause-and-effect.

## Core gameplay
1. The city and businesses operate automatically.
2. Residents commute and businesses generate delivery traffic.
3. The player builds roads and junctions and controls traffic lights.
4. Congestion appears when road capacity or signal timing is poor.
5. Good traffic flow supports gradual city growth and rewards the player.
6. The challenge grows gradually, without sudden unfair failure or a punishing death spiral.

The player does NOT manually manage individual businesses, trade routes, fuel, vehicle maintenance, staffing, or individual deliveries. AI handles those systems.

## Quality bar — non-negotiable
- Visual polish: coherent art direction, consistent scale, appealing materials, clean silhouettes, readable road markings, attractive lighting, no default-looking placeholder geometry in finished features.
- Readability: players can tell where cars are going, which light controls them, and why a queue is forming.
- Motion: smooth acceleration, braking, lane keeping, and turns; no teleporting, jittering, sideways sliding, clipping, or sudden direction changes.
- Traffic safety: vehicles stop at red lights and stop lines, keep safe following distances, avoid entering blocked intersections, and recover from deadlocks.
- Road awareness: vehicles follow valid connected routes, stay on roads, and use consistent left/right-side driving rules.
- Performance: use efficient, predictable simulation suitable for Roblox; do not rely on expensive physics for every car or create an uncontrolled number of instances.
- Reliability: server validates important state changes; client/server responsibilities are clear; avoid duplicate systems and hidden race conditions.
- Accessibility: works on desktop and mobile, with large touch targets and simple controls.
- Save safety: do not break existing player data or delete unrelated work.

## Development rules
- Inspect the existing repository before changing architecture.
- Work in small, complete milestones. Do not build a giant pile of unfinished features.
- Preserve and reuse useful existing systems where practical.
- For each milestone: implement, test what can be tested, fix defects, and report what remains unverified in Roblox Studio.
- Never claim a test passed unless it was actually run.
- Do not replace working code merely for stylistic reasons.
- Keep changes focused, readable, modular, and easy to maintain.
- Commit work to the existing repository and provide the commit link.
- Do not add new features until the current milestone meets its quality bar.

## Milestone order
### 1. Traffic foundation
Understand the existing road graph and world coordinates. Implement a small, polished proof of concept: vehicles travel between connected road points, maintain spacing, stop at red lights, and turn smoothly through one intersection. Use simple but good-looking vehicle models. Test edge cases and performance before scaling up.

### 2. Player traffic controls
Provide an easy way to select a traffic light and switch its phase. Show the current state clearly. Prevent conflicting movements from receiving green simultaneously. Make controls discoverable and forgiving.

### 3. Traffic feedback and rewards
Show simple, understandable feedback such as traffic flow, average waiting, and deliveries completed. Reward good flow; penalties must be gradual and explainable.

### 4. Automatic city life
Add demand-driven growth: homes, offices, shops, warehouses and services appear near suitable roads over time. Businesses generate trips and deliveries automatically. Growth should be controlled by road access and demand, not random sprawl.

### 5. Gradual expansion and polish
Introduce new districts and more complex junctions only after the first district is fun, stable, attractive, and understandable.

## First-time player experience
A short tutorial should:
1. Show cars moving through a simple junction.
2. Point out a red light and let the player change it.
3. Explain a queue in one short sentence.
4. Let the player build or improve a road.
5. Reward them for improving traffic flow.

Do not overwhelm the player with every system at once.

## Definition of a release-ready first district
A player can enter, understand the goal quickly, control a light, build a road, observe the traffic consequences, earn a clear reward, and continue playing without confusion. Vehicles move reliably; the UI is readable on mobile; no core interaction is a placeholder; and known limitations are documented.

## Required completion report
For every milestone, report:
- What changed and why.
- Files changed.
- Tests actually run and their results.
- What still requires manual Roblox Studio testing.
- Known bugs and performance limits.
- Commit URL.
