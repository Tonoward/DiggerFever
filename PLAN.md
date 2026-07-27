# Digging Game — Experimental Prototype Plan

## Context

This is a brand-new Godot 4.7 project (`DiggerFeverTest`, mobile renderer, currently just an empty `Main` scene). The goal is not to ship a finished game, but to build a small, tunable prototype that lets you *experiment* with the core loop: procedurally generated terrain made of different materials, a drill that digs through it with limited maneuverability, and resource/item collection gated by drill strength. The priority is fast iteration on tuning knobs (material stats, generation probabilities, cluster sizes, drill feel) over polish or scope.

Confirmed direction from requirements discussion:
- **Perspective:** 2D side-view cross-section (Motherload / SteamWorld Dig style) — camera shows a vertical slice, drill digs down/sideways.
- **Dig model:** Progressive mining — each tile has integrity/HP that depletes based on drill power vs. material hardness; tile is cleared when integrity hits 0.
- **World scope (v0):** Large bounded grid generated once at start (e.g. few hundred cells wide, few thousand deep). No infinite streaming or save system yet — keep the first version simple.

## Concept & Vision (background lore)

*Adapted from the sibling `FeverDiggerPetru` prototype's README, to set long-term direction. None of this is required for the current experiment — it frames where the "dig" core is heading.*

You play a lone astronaut roaming the galaxy aboard a spaceship. You touch down on alien planets, climb into a **drill capsule**, and bore down through their layered crust — soil, stone, and ever-rarer ore the deeper you go — to extract valuable materials and haul them back up.

**Long-term gameplay loop:**
1. **Travel** — pilot the ship between planets across the galaxy.
2. **Land** — touch down on a new planet and prep the drill capsule.
3. **Dig** — descend, break through terrain, and collect materials that grow rarer/more valuable with depth. *(This is the slice the current prototype implements.)*
4. **Resurface** — return to the ship and spend resources (upgrades, fuel, new drills).

**How this prototype maps onto that vision:** the drill capsule = our drill entity; a planet's crust = one procedurally generated `TerrainGrid`; materials/ores = our `MaterialData` resources, distributed by depth so value increases downward; collectibles (diamonds, boxes) = our `ItemData`. Travel, landing, resurfacing, inventory, and upgrades are **future scope** — deliberately out of the current experiment, which focuses on making the *digging* feel good and tunable.

**Planned/adopted feel details** (borrowed from that prototype): drill **vibration** while boring through solid material, and **debris fragments** that pop out of a cell as it's excavated and tumble under gravity — both now implemented here (see below).

## Architecture Overview

- **Engine feature to use:** `TileMapLayer` (Godot 4.3+) for rendering terrain — cheap, built for grids, has built-in culling. A **parallel data grid** (plain arrays, not nodes) stores per-cell gameplay state (material id, current integrity) since TileMapLayer itself only stores visual tile ids.
- **Data-driven tuning:** All tunable values live in custom `Resource` classes editable directly in the Godot Inspector as `.tres` files. This satisfies "easily manage materials/stats" without building any custom editor UI for v0 — you tweak a `.tres`, rerun the scene, see the result immediately.
- **Reproducible generation:** World generation takes a seed; same seed -> same world. Makes it easy to A/B tune parameters.

## Implementation Steps

### 1. Data model (Resources)
- `scripts/data/material_data.gd` (extends `Resource`): `id`, `display_name`, `hardness`, `friction` (how much it slows the drill while digging), `max_integrity`, `tile_atlas_coords`, `resource_yield` (type + amount), `depth_min`/`depth_max`/`depth_peak` (defines a probability curve over depth), `rarity_weight`, `is_cluster` (bool — base filler like dirt/clay vs. vein material like ore/gems), `cluster_size_min`/`cluster_size_max`.
- `scripts/data/drill_stats.gd`: `power` (max hardness it can break), `max_drag_force`, `acceleration`, `maneuverability` (turn/responsiveness damping), `max_speed`.
- `scripts/data/world_gen_config.gd`: `seed`, `grid_width`, `grid_depth`, `cell_size_px`, cluster density params.
- `scripts/data/item_data.gd`: for diamonds/boxes — `required_power`, `reward`, visual.
- Store actual instances as `.tres` files under `res://data/materials/`, `res://data/items/`, one `world_gen_config.tres`, one `drill_stats.tres`.
- `scripts/autoload/material_database.gd` (autoload singleton): loads all `MaterialData` resources from `res://data/materials/` at startup, exposes lookup by id and a sorted-by-depth list for generation.

### 2. Terrain grid
- `scripts/terrain/terrain_grid.gd`: plain class (not a Node) wrapping:
  - `PackedInt32Array material_ids` (flattened width*depth)
  - `PackedFloat32Array integrity` (current HP per cell)
  - Helper methods: `get_cell`, `set_cell`, `damage_cell`, `clear_cell`, index math.
- `scenes/terrain.tscn`: a `TileMapLayer` node whose tile ids mirror `TerrainGrid.material_ids`; a `TileSet` with one tile per material (flat-color placeholder tiles are fine for the prototype).
- Terrain node listens for grid changes and updates the corresponding `TileMapLayer` cell (set tile / erase tile) — keeps rendering and data in sync but decoupled.

### 3. Procedural generation
- `scripts/terrain/world_generator.gd`, run once at scene start using `WorldGenConfig.seed`:
  1. **Base fill pass:** for each cell `(x, y)`, the depth coordinate is first "warped" by a Perlin noise field (`TerrainNoise.warped_depth`, see below), then whichever base material (`is_cluster = false`, e.g. dirt/clay/stone) has the highest depth-probability weight at that *warped* depth wins the cell (deterministic argmax, no per-cell randomness). Because the noise is spatially coherent, neighboring cells warp by similar amounts, so a material wins across a contiguous blob rather than a speckle of random picks — this produces the "big area that gradually gives way to patches of the next material" look instead of a flat per-row boundary or a gradient.
  2. **Cluster pass:** for each `is_cluster = true` material (ores, gems, diamonds), at each depth band compute an expected number of cluster seeds from `rarity_weight` + depth curve, scatter seed points, then grow each seed into a blob via a randomized flood-fill/random-walk (BFS where each neighbor is added with decreasing probability as cluster grows, capped by `cluster_size_min/max`). Cluster cells overwrite the base fill. This pass is intentionally separate from the noise-warped layering — rarity should stay rare and chunky, not blend like the base layers.
  3. **Item placement pass:** scatter `ItemData` entries (diamonds, boxes) similarly to clusters, possibly embedded inside specific materials.
  4. **Surface pass:** forces row `y = 0` to the `grass` material (looked up by id) across every column, overriding whatever the noise-warped base fill picked there. Runs last so nothing else can un-set it. This guarantees a clean, deterministic "starting line" regardless of noise settings — grass has `depth_min = depth_max = 0` so it never wins the normal weighted competition on its own (the override does the placing), and a high `render_priority` (10) so its dual-grid edge always draws over whatever material ends up in row 1.
  - All randomness (cluster/item scatter) goes through a single seeded `RandomNumberGenerator`; the noise field is seeded from the same `WorldGenConfig.seed_value`. Same seed -> same world every time.
- **Background:** `rendering/environment/defaults/default_clear_color` in `project.godot` is set to a sky blue, so any transparent area (above the grass line, and currently also inside dug-out tunnels) shows blue instead of Godot's default black. Simple project-wide setting — no background node/geometry to keep in sync with world size.

#### Noise system (Perlin-based layer blobbing)
- `scripts/data/noise_settings.gd` (`NoiseSettings` Resource): exposes `noise_type` (defaults to Perlin), `frequency` (lower = bigger blobs), `fractal_octaves`/`fractal_lacunarity`/`fractal_gain` (extra detail/roughness), and `warp_amount` (how many cells of depth-distortion the noise applies — `0` disables blobbing entirely and reverts to flat depth bands). Instance lives at `data/noise_settings.tres`, referenced from `data/world_gen_config.tres`.
- `scripts/terrain/terrain_noise.gd` (`TerrainNoise`): thin wrapper around a `FastNoiseLite` configured from `NoiseSettings`; exposes `warped_depth(x, y)` which is the one thing `WorldGenerator` calls during the base-fill pass.
- Tune by editing `data/noise_settings.tres` directly — frequency/octaves control blob size and roughness, `warp_amount` controls how aggressively layers intermix at their boundaries.

### 4. Drill entity & input
- `scenes/drill.tscn`: `CharacterBody2D` (or `RigidBody2D` if you want physics-driven feel) with a `DrillStats` resource reference.
- `scripts/drill/drill_input.gd`: on touch/click-down, record origin point; while dragging, compute vector (clamped magnitude = `max_drag_force`) from origin to current pointer position; **clamp the vector's angle so it can never point upward** (zero/clamp the upward component); on release, feed the vector into drill movement as a target force/direction.
- `scripts/drill/drill_controller.gd`: applies the input vector through `acceleration`/`maneuverability` damping rather than directly setting velocity — i.e., velocity eases toward the target direction/speed rather than snapping, which is what gives the "not too easy to manipulate" feel. Speed is further throttled by the friction of whatever material it's currently digging through.

### 5. Digging interaction
- Each physics frame, find which terrain cells the drill's collision shape currently overlaps (via `TerrainGrid` index math from world position).
- For each overlapped cell:
  - If `drill.power < material.hardness`: cell blocks movement (treat as solid wall — drill decelerates/stops against it).
  - Else: apply damage to `integrity` proportional to drill power and delta time; when integrity <= 0, clear the cell (`TerrainGrid.clear_cell` + tilemap erase), spawn its `resource_yield` as a pickup; while digging, drill speed is divided down by the material's `friction`.
- Items (diamonds/boxes) behave the same way but check `required_power` instead of hardness, and grant `reward` on break.

### 5b. Feedback effects (juice) — adapted from FeverDiggerPetru
- **Drill vibration:** while the drill is actively boring through solid material (its `digging` state), the sprite shakes perpendicular to the drill axis by `DrillStats.vibration_amp` px, eased back to rest otherwise. Sprite-only offset (`_sprite.position`) so it never affects collision/digging math. Lives in `DrillController._process`.
- **Debris fragments:** when a cell is fully dug out, `TerrainGrid` emits `cell_excavated(x, y, material)`. `Main` spawns a small `TileDebris` fragment tinted with the material's color, kicked *toward the drill* (i.e. back into the tunnel it just carved, not out into unexcavated ground) with some sideways scatter, impulse magnitude expressed in cells/sec so it stays proportionate at any `cell_size_px`. It then falls under gravity and bounces off solid cells and the drill's footprint until it settles on the tunnel floor, then frees itself after a lifetime. A same-frame "nearest open cell" safety net guarantees a fragment can never end up permanently embedded in rock (verified with an instrumented headless run: 0 embedded fragments over 240 physics frames of continuous digging). Pooled to a `MAX_DEBRIS` cap and cleared on world regen. Physics is manual grid collision (`TerrainGrid.world_to_cell` / `is_empty`), matching the rest of the project — no physics bodies.
- **Collection:** the moment a cell is excavated, `Main._collect_material` increments a per-material counter (keyed by `MaterialData.id`) — this is instant and guaranteed, independent of debris/animation state, so the count is never wrong or delayed. Separately, `Main` rolls `DEBRIS_COLLECT_CHANCE` (35%) per spawned fragment; a "collectible" fragment pops out normally for a moment (`TileDebris.SUCK_DELAY`) then flies to the drill's current position and shrinks away over `SUCK_DURATION`, as a visual "getting collected" cue — not every fragment needs to fly home for this to read well. Verified with an instrumented headless run: counts track dig events exactly (unaffected by the `MAX_DEBRIS` pool cap), and a healthy fraction of live debris are mid-suck at any time.
- **Materials HUD:** a `GridContainer` (`HUD/MaterialsRow` in `main.tscn`) holds one "color swatch + xN label" entry per material, created the first time that material is collected and updated in place after that — materials never collected simply have no entry. Cleared and rebuilt on world regen.

### 6. Camera
- `Camera2D` child of (or following) the drill scene, using Godot's built-in position smoothing, so it eases toward the drill's position rather than locking 1:1 — gives the small vertical/horizontal lag described.

### 7. Iteration loop for experiments
- No custom tooling UI for v0 — edit the `.tres` resources (material hardness/friction/yield, cluster sizes, drill power/maneuverability) directly in the Inspector and re-run the scene.
- Add one small debug convenience: a key bind (e.g. `R`) that re-runs `WorldGenerator` with a new random seed without restarting the whole game, so terrain-tuning iteration is fast.

### 8. Loading screen (real progress, not a fake animation)
- The actual bottleneck when starting a game isn't the scene file (tiny) — it's `WorldGenerator`'s base-fill pass, which is O(grid_width × grid_depth) and can be well over 100k cells. So `WorldGenerator.generate(config, progress: Callable)` now yields a frame every `depth / PROGRESS_STEPS` rows (via `await Engine.get_main_loop().process_frame`) and reports real fractional progress through that Callable — the percentage on screen tracks actual work done, not a canned animation. The remaining passes (clusters/items/surface) are comparatively cheap and aren't individually instrumented; they're folded into the tail of the bar (0.9 → 1.0).
- `Main` awaits `WorldGenerator.generate(...)` and exposes this as `generation_progress(fraction)` / `generation_finished` signals, so anything can watch a world get built without needing to know how generation works internally.
- `scenes/loading_screen.tscn` + `scripts/loading_screen.gd`: a `CanvasLayer` (high `layer` value, so it always draws over Main's own HUD regardless of node order) shown by `main_menu.gd`'s Play button instead of `main.tscn` directly. It instantiates Main itself, adds it to the tree as a second top-level node (`add_child.call_deferred` — required, since `add_child` on the tree root fails synchronously during another scene's own `_ready()`), and listens for `generation_progress`/`generation_finished` to drive a `ProgressBar` + percentage label. Main generates completely hidden underneath; once `generation_finished` fires, the loading screen promotes Main to `current_scene` and frees itself, revealing a fully-built world with no popping/flash of an empty map.
- Verified headless: progress climbs smoothly from 0% to 100% across ~40 yielded frames for a 160×800 grid, the R-key regenerate path (now also async) still completes correctly end-to-end, and all entry points (`main.tscn` directly, `loading_screen.tscn`, and the full project boot through the menu) produce identical, pre-existing residual shutdown warnings — i.e. no regressions introduced.

## Files created
- `scripts/data/material_data.gd`, `drill_stats.gd`, `world_gen_config.gd`, `item_data.gd`, `noise_settings.gd`
- `scripts/autoload/material_database.gd` (registered as autoload in `project.godot`)
- `scripts/terrain/terrain_grid.gd`, `world_generator.gd`, `terrain_controller.gd`, `terrain_noise.gd`
- `scripts/drill/drill_input.gd`, `drill_controller.gd`
- `scripts/effects/tile_debris.gd`
- `scripts/main.gd`, `scripts/loading_screen.gd`
- `scenes/terrain.tscn`, `scenes/drill.tscn`, `scenes/main.tscn` (composes terrain + drill + camera + HUD), `scenes/loading_screen.tscn`
- `data/materials/*.tres` (grass, dirt, clay, stone, copper_ore, gold_ore, diamond_ore), `data/items/*.tres` (treasure_box, diamond_gem), `data/world_gen_config.tres`, `data/drill_stats.tres`, `data/noise_settings.tres`

## Verification
- Run the project in Godot (F5/F6) and confirm:
  - Terrain generates with dirt/clay near the surface, rarer materials appearing deeper, in visible clusters rather than uniformly scattered.
  - Click-and-drag moves the drill in the dragged direction/force, never upward, with a noticeable "weight" to the control (not 1:1 instant).
  - Drill digs through materials at a rate that reflects hardness/friction; materials above its `power` block it entirely.
  - Diamonds/boxes only break/collect when drill power meets their requirement; otherwise they sit as obstacles.
  - Camera eases to follow the drill rather than snapping.
  - Changing values in a material `.tres` (e.g. raising clay's hardness) visibly changes dig behavior on next run, and pressing the debug regenerate key produces a new layout — confirming the experiment loop works end-to-end.
- Headless sanity check (no editor needed): `Godot_v4.7-stable_win64_console.exe --headless --path . --quit-after 60` should run with no `SCRIPT ERROR` output. Setting env var `DIGGER_DEBUG_GEN=1` before that command prints a cell-count/cluster/item breakdown to confirm generation is producing the expected depth-ordered, clustered distribution.
- Setting env var `DIGGER_DEBUG_IMG=<path>.png` before that command dumps a top-down material-color PNG of the whole generated grid to `<path>.png`, plus a 4x-upscaled crop of the first 200 rows to `<path>_zoom.png` — useful for visually eyeballing layer blobbiness against a reference image without opening the editor.
- Note: after adding new `class_name` scripts, Godot's global class cache (`.godot/global_script_class_cache.cfg`) needs a rescan before headless runs will resolve them — run `Godot...console.exe --headless --path . --editor --quit` once to force the rescan if you see "Could not find type X in the current scope" errors.
