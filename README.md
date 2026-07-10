# DiggerFever

A mining/digging game prototype built in Godot 4. The player controls a drill to excavate procedurally generated terrain and collect resources.

## Project Structure

```
DiggerFever/
├── scenes/       # Scene files defining node hierarchies
├── scripts/      # GDScript logic
│   ├── autoload/ # Global singletons (loaded at startup)
│   ├── data/     # Resource class definitions
│   ├── terrain/  # World generation and rendering
│   ├── drill/    # Player input and movement
│   └── effects/  # Visual feedback (debris, particles)
├── data/         # Tunable game data (.tres Resource files)
└── assets/       # Textures and sprite sheets
```

## Architecture

**Entry point:** `main.gd` / `main.tscn` — ties all systems together, handles world generation and debris spawning.

### Terrain System (`scripts/terrain/`)
Procedural world built from noise-warped depth layers with ore clusters and item placement. The grid stores material and integrity data per cell, emitting signals on changes to decouple rendering from logic. Rendering uses a dual-grid technique for smooth tile transitions.

### Drill System (`scripts/drill/`)
Converts player input (mouse/touch drag) into directional movement. Handles digging mechanics, sprite animation, and camera shake feedback.

### Effects (`scripts/effects/`)
Debris fragments spawned when cells are excavated.

## Design Principles

- **Data-driven:** All tunable values (material hardness, depth ranges, drill power, noise parameters) live in `.tres` files under `data/` — no magic numbers in scripts.
- **Signal-based:** Systems communicate via Godot signals, keeping terrain logic, rendering, and effects decoupled.
- **Autoload singleton:** `material_database.gd` loads all material and item resources at startup, making them globally accessible.

## Materials & Items

Seven material types layer from surface to depth (grass, dirt, clay, stone, and ore variants), each configured with hardness, depth range, rarity, and appearance. Collectible items are scattered through the world during generation.

## Docs

See `PROJECT_GUIDE.md` for a detailed function-by-function walkthrough of the codebase.
