extends Resource
class_name WorldGenConfig

## All the knobs for building a world, as a data-only resource (data/world_gen_config.tres).
## WorldGenerator reads this to decide grid size, cell size, the seed, and how ore clusters
## are scattered. Same seed_value -> identical world every run.

@export var seed_value: int = 12345
@export var grid_width: int = 80
@export var grid_depth: int = 400
@export var cell_size_px: int = 16

## Controls the Perlin noise field that shapes the base terrain layers into blobs.
@export var noise_settings: NoiseSettings

## Cluster pass tuning: expected number of cluster seeds per this many cells, per material.
@export var cluster_seed_density: float = 0.0015
