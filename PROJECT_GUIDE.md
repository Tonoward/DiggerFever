# Project Guide — Digger Fever (prototype)

A map of the codebase for a programmer (new to Godot) who wants to work on any feature.
For the *why* and the game's vision, see [PLAN.md](PLAN.md); this file is the *where* and *how*.

---

## 1. Running it

1. Open `project.godot` in **Godot 4.7+**.
2. Press **F5** (or the ▶ button) to play.
3. **Controls:** click-and-drag to aim/thrust the drill (it can't go straight up); press **R** to regenerate the world with a new random layout.

---

## 2. The one big idea: data vs. logic

Almost everything tunable in this game is a **Resource** — a plain data file (`.tres`) with no code, edited in Godot's Inspector. Scripts read those numbers; they don't hard-code them. So "make stone harder" or "add a new ore" is usually a data edit, not a code edit.

- **Data** lives in `data/` (the `.tres` files) and is *described* by the small classes in `scripts/data/`.
- **Logic** lives in the other `scripts/` folders.

The second big idea is a clean split in the terrain:

- **`TerrainGrid`** = the *data* of the world (what material is in each cell). It's a plain object, not a scene node.
- **`TerrainController`** = the *picture* of the world (draws the grid on screen).
- **`DrillController`** = *reads and edits* the grid as it digs.

All three share **one** `TerrainGrid` object. The grid emits signals ("this cell changed", "this cell was dug out") and the others react. Collision and digging are done with plain grid math (which cell is here?), **not** Godot's physics engine — that keeps it fast even for a huge world.

---

## 3. Directory layout

```
digger-fever-test/
├── project.godot            # Godot project settings (autoloads, main scene, sky color)
├── PLAN.md                  # Vision, design decisions, feature history
├── PROJECT_GUIDE.md         # (this file) code map
│
├── scenes/                  # The .tscn scene files (node trees you can open visually)
│   ├── main.tscn            #   Root scene: Terrain + Drill + HUD
│   ├── terrain.tscn         #   The terrain renderer node
│   └── drill.tscn           #   The drill: sprite, camera, input, collision
│
├── data/                    # The tunable .tres resources (edit these in the Inspector)
│   ├── world_gen_config.tres
│   ├── noise_settings.tres
│   ├── drill_stats.tres
│   ├── materials/           #   One .tres per terrain material (grass, dirt, stone, ores...)
│   └── items/               #   One .tres per collectible (treasure_box, diamond_gem)
│
├── assets/                  # Textures (terrain ground textures, drill sprite sheets)
│
└── scripts/                 # All the code (GDScript)
    ├── main.gd              #   Conductor: ties everything together
    ├── autoload/            #   Global singletons (always loaded)
    ├── data/                #   The Resource classes that define .tres fields
    ├── terrain/             #   World data, generation, and rendering
    ├── drill/               #   Player drill: input + movement + digging
    └── effects/             #   Debris fragments
```

---

## 4. File-by-file reference

### Entry point

| File | What it does |
|------|--------------|
| [scripts/main.gd](scripts/main.gd) | The "conductor". Generates a world, gives the shared `TerrainGrid` to the terrain and drill, spawns debris when cells are dug, handles the **R**-to-regenerate key. Read this first — it shows how the pieces connect. Also holds *dev-only* debug helpers (clearly marked; safe to ignore). |
| [scenes/main.tscn](scenes/main.tscn) | The scene that actually runs. Node tree: `Main` → `Terrain`, `Drill` (with a `Camera2D`), `HUD`. |

### `scripts/autoload/` — global singletons

| File | What it does |
|------|--------------|
| [scripts/autoload/material_database.gd](scripts/autoload/material_database.gd) | Registered as `MaterialDatabase` in `project.godot`, so it's reachable from anywhere. At startup it loads every material/item `.tres` into `materials` / `items` arrays. Add a new material file and it appears automatically — no code change. |

### `scripts/data/` — Resource definitions (the "shape" of the .tres files)

These are pure data classes. Each `@export` field becomes an editable row in the Inspector.

| File | Defines |
|------|---------|
| [scripts/data/material_data.gd](scripts/data/material_data.gd) | `MaterialData`: a terrain material — color/texture, `hardness`, `friction`, `max_integrity` (HP), what depth it appears at, whether it forms ore-style clusters, and `render_priority` (draw order). |
| [scripts/data/item_data.gd](scripts/data/item_data.gd) | `ItemData`: a collectible broken open in one hit if drill `power ≥ required_power`. |
| [scripts/data/drill_stats.gd](scripts/data/drill_stats.gd) | `DrillStats`: drill `power`, speed, steering feel, knockback, vibration. |
| [scripts/data/world_gen_config.gd](scripts/data/world_gen_config.gd) | `WorldGenConfig`: grid size, cell size in pixels, random `seed_value`, cluster density, and a link to the noise settings. |
| [scripts/data/noise_settings.gd](scripts/data/noise_settings.gd) | `NoiseSettings`: Perlin-noise knobs that bend flat material layers into organic blobs. |

### `scripts/terrain/` — the world

| File | What it does |
|------|--------------|
| [scripts/terrain/terrain_grid.gd](scripts/terrain/terrain_grid.gd) | `TerrainGrid` — the **world data**. A flat array of which material is in each cell, plus each cell's current integrity (HP). Methods to read cells, damage/clear them, and convert between world pixels and grid cells. Emits `cell_changed` (redraw me) and `cell_excavated` (a cell was fully dug — spawn debris). Not a scene node. |
| [scripts/terrain/world_generator.gd](scripts/terrain/world_generator.gd) | `WorldGenerator` — builds a fresh `TerrainGrid` in ordered passes: (1) fill base layers using noise-warped depth, (2) grow ore clusters, (3) scatter items, (4) force the top row to grass. All driven by the seed, so the same seed = the same world. |
| [scripts/terrain/terrain_noise.gd](scripts/terrain/terrain_noise.gd) | `TerrainNoise` — a thin wrapper over Godot's `FastNoiseLite`, configured from `NoiseSettings`. Gives generation a "warped depth" so layer edges wobble instead of being flat lines. |
| [scripts/terrain/terrain_controller.gd](scripts/terrain/terrain_controller.gd) | `TerrainController` — **draws** the grid using the *dual-grid* technique: a display grid offset by half a cell picks 1 of 16 transition tiles per cell, giving smooth rounded edges instead of blocky squares. One draw layer per material, stacked by `render_priority`, so materials blend nicely where they meet. Tiles are generated in code from each material's color/texture. |

### `scripts/drill/` — the player

| File | What it does |
|------|--------------|
| [scripts/drill/drill_input.gd](scripts/drill/drill_input.gd) | `DrillInput` — turns mouse/touch drags into a single `drag_changed` signal (a vector from where you pressed to where the pointer is now). |
| [scripts/drill/drill_controller.gd](scripts/drill/drill_controller.gd) | `DrillController` — the drill's brain. Eases toward the drag direction (never straight up), figures out which cells it's entering, digs them (damaging integrity via `power` vs `hardness`), bounces back off material too hard to break, drives the sprite animation/rotation, and shakes while boring. The most involved script; the header comment and per-function comments walk through it. |
| [scenes/drill.tscn](scenes/drill.tscn) | The drill scene: `AnimatedSprite2D` (idle/drill/hit/dead animations), `DragLine`, `DrillInput`, `CollisionShape2D` (a *visual* dig-radius guide only), and the `Camera2D` that follows the drill. |

### `scripts/effects/` — juice

| File | What it does |
|------|--------------|
| [scripts/effects/tile_debris.gd](scripts/effects/tile_debris.gd) | `TileDebris` — a little square fragment spawned when a cell is dug. It falls with gravity, bounces off solid cells and the drill, settles into the tunnel floor, then removes itself. Uses the same grid-math collision as the drill (no physics bodies). |

---

## 5. How a frame flows

**On startup / regenerate** (`main.gd → _generate_world`):
1. `WorldGenerator.generate(config)` builds a new `TerrainGrid`.
2. `terrain.setup(grid)` builds the tile layers and draws everything.
3. `drill.setup(grid)` and the drill is placed on top of the grass line.

**While digging** (each physics frame):
1. `DrillInput` emits the current drag vector → `DrillController` eases its velocity toward it.
2. `DrillController` checks the cells it's about to enter and calls `grid.damage_cell(...)`.
3. When a cell's integrity hits 0, `TerrainGrid` clears it and emits `cell_changed` **and** `cell_excavated`.
4. `TerrainController` hears `cell_changed` and repaints the affected display tiles.
5. `main.gd` hears `cell_excavated` and spawns a `TileDebris` fragment.

---

## 6. "I want to change X" cookbook

| Goal | Where to go |
|------|-------------|
| Make a material harder/softer, change its color, its yield | its file in [data/materials/](data/materials/) (Inspector) |
| Add a brand-new material or ore | copy an existing `data/materials/*.tres`, give it a unique `id` — it auto-loads |
| Change how deep/rare a material is | that material's `depth_min/max/peak`, `rarity_weight`, cluster fields |
| Change world size, cell size, or seed | [data/world_gen_config.tres](data/world_gen_config.tres) |
| Change the blobby-ness of terrain layers | [data/noise_settings.tres](data/noise_settings.tres) (`frequency`, `warp_amount`) |
| Tune drill power, speed, steering, knockback, shake | [data/drill_stats.tres](data/drill_stats.tres) |
| Change the order/logic of world generation | [scripts/terrain/world_generator.gd](scripts/terrain/world_generator.gd) |
| Change how digging/collision feels | [scripts/drill/drill_controller.gd](scripts/drill/drill_controller.gd) |
| Change how terrain looks (dual-grid, textures vs flat color) | [scripts/terrain/terrain_controller.gd](scripts/terrain/terrain_controller.gd) + `use_material_textures` on the `Terrain` node in [scenes/main.tscn](scenes/main.tscn) |
| Change the debris behaviour | [scripts/effects/tile_debris.gd](scripts/effects/tile_debris.gd) (constants at the top) and the `DEBRIS_*` constants in [scripts/main.gd](scripts/main.gd) |
| Change the sky color | `project.godot` → `rendering/environment/defaults/default_clear_color` |
| Swap the camera zoom | the `Camera2D` node under `Drill` in [scenes/main.tscn](scenes/main.tscn) |

---

## 7. Dev-only debug switches

Set these environment variables **before** launching Godot to get generation diagnostics (they don't affect the game):

- `DIGGER_DEBUG_GEN=1` — prints cell counts, item counts, and a depth profile to the console.
- `DIGGER_DEBUG_IMG=<path>.png` — saves a top-down color map of the generated world (plus a zoomed crop) to that path.

Both are handled in the "Dev-only debug helpers" section of [scripts/main.gd](scripts/main.gd).
