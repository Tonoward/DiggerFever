extends RefCounted
class_name WorldGenerator

## Procedural terrain generation, seeded for reproducibility.
## Pass 1 fills the grid with base materials (dirt/clay/stone), picking whichever
## material's depth band wins at a noise-warped depth -- this is what turns flat
## per-row bands into the big organic blobs/patches look (see TerrainNoise).
## Pass 2 scatters vein/cluster materials (ores, gems) as grown blobs, overwriting the base fill.
## Pass 3 scatters standalone items (treasure boxes, diamonds) embedded in existing terrain.
## Pass 4 forces the very top row to the "grass" material (if defined), so the world always
## has a clean, deterministic starting line regardless of noise warp -- overrides whatever
## the depth-based passes picked there.
##
## The base-fill pass is by far the most expensive part (one iteration per cell, so it scales
## with grid_width * grid_depth), so `generate` optionally reports progress through it and
## yields a frame every so often -- this is what lets a loading screen show a real, moving
## percentage instead of freezing the game for however long generation takes.

## How many progress updates (and frame-yields) to spread the base-fill pass across,
## regardless of grid size -- bigger grids just do more rows per update.
const PROGRESS_STEPS: int = 40

static func generate(config: WorldGenConfig, progress: Callable = Callable()) -> TerrainGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed_value

	var palette: Array[MaterialData] = MaterialDatabase.materials
	var grid := TerrainGrid.new(config.grid_width, config.grid_depth, config.cell_size_px, palette)
	var noise := TerrainNoise.new(config.noise_settings, config.seed_value)

	await _base_fill_pass(grid, palette, noise, progress)
	_cluster_pass(grid, palette, config, rng)
	_item_pass(grid, MaterialDatabase.items, config, rng)
	_surface_pass(grid, palette)
	if progress.is_valid():
		progress.call(1.0)

	return grid

## Forces row 0 to the "grass" material across every column, if one is defined in the
## palette. Runs last so nothing else (noise-warped base fill, clusters) can override it.
static func _surface_pass(grid: TerrainGrid, palette: Array[MaterialData]) -> void:
	if grid.depth <= 0:
		return
	var surface_index := -1
	for i in range(palette.size()):
		if palette[i].id == &"grass":
			surface_index = i
			break
	if surface_index == -1:
		return
	for x in range(grid.width):
		grid.set_cell(x, 0, surface_index)

static func _weight_at_depth(depth_min: int, depth_max: int, depth_peak: int, depth_falloff: float, rarity_weight: float, y: float) -> float:
	if y < depth_min or y > depth_max:
		return 0.0
	var falloff := maxf(depth_falloff, 1.0)
	var d := y - depth_peak
	return rarity_weight * exp(-(d * d) / (2.0 * falloff * falloff))

static func _base_fill_pass(grid: TerrainGrid, palette: Array[MaterialData], noise: TerrainNoise, progress: Callable) -> void:
	var base_indices: Array[int] = []
	for i in range(palette.size()):
		if not palette[i].is_cluster:
			base_indices.append(i)
	if base_indices.is_empty():
		return

	var rows_per_step := maxi(1, grid.depth / PROGRESS_STEPS)

	for y in range(grid.depth):
		for x in range(grid.width):
			var warped_y := noise.warped_depth(x, y)
			var best_index := base_indices[0]
			var best_weight := -1.0
			for i in base_indices:
				var m := palette[i]
				var w := _weight_at_depth(m.depth_min, m.depth_max, m.depth_peak, m.depth_falloff, m.rarity_weight, warped_y)
				if w > best_weight:
					best_weight = w
					best_index = i
			grid.set_cell(x, y, best_index)

		# Yield to the engine periodically so a loading screen can actually redraw with the
		# updated percentage -- without this, the whole pass runs in one uninterrupted frame
		# and the game would just freeze until it's done, no matter what we report.
		if y % rows_per_step == 0:
			if progress.is_valid():
				# Base fill is the dominant cost; leave the rest of the bar (0.9-1.0) for
				# the comparatively cheap cluster/item/surface passes that follow.
				progress.call(float(y) / grid.depth * 0.9)
			await Engine.get_main_loop().process_frame

static func _cluster_pass(grid: TerrainGrid, palette: Array[MaterialData], config: WorldGenConfig, rng: RandomNumberGenerator) -> void:
	for i in range(palette.size()):
		var m := palette[i]
		if not m.is_cluster:
			continue
		for y in range(grid.depth):
			var w := _weight_at_depth(m.depth_min, m.depth_max, m.depth_peak, m.depth_falloff, m.rarity_weight, y)
			if w <= 0.0:
				continue
			var expected := config.cluster_seed_density * w * grid.width
			var seed_count := int(expected)
			if rng.randf() < fmod(expected, 1.0):
				seed_count += 1
			for s in range(seed_count):
				var x := rng.randi_range(0, grid.width - 1)
				_grow_cluster(grid, i, m, x, y, rng)

static func _grow_cluster(grid: TerrainGrid, material_index: int, mat: MaterialData, start_x: int, start_y: int, rng: RandomNumberGenerator) -> void:
	var target_size := rng.randi_range(mat.cluster_size_min, mat.cluster_size_max)
	var claimed: Dictionary = {}
	var frontier: Array[Vector2i] = [Vector2i(start_x, start_y)]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while claimed.size() < target_size and not frontier.is_empty():
		var idx := rng.randi_range(0, frontier.size() - 1)
		var cell: Vector2i = frontier[idx]
		frontier.remove_at(idx)
		if not grid.in_bounds(cell.x, cell.y) or claimed.has(cell):
			continue
		claimed[cell] = true
		for d in dirs:
			var n: Vector2i = cell + d
			if grid.in_bounds(n.x, n.y) and not claimed.has(n) and rng.randf() < 0.65:
				frontier.append(n)
	for cell in claimed.keys():
		grid.set_cell(cell.x, cell.y, material_index)

static func _item_pass(grid: TerrainGrid, items: Array[ItemData], config: WorldGenConfig, rng: RandomNumberGenerator) -> void:
	for item in items:
		for y in range(grid.depth):
			var w := _weight_at_depth(item.depth_min, item.depth_max, item.depth_peak, item.depth_falloff, item.rarity_weight, y)
			if w <= 0.0:
				continue
			var expected := config.cluster_seed_density * w * grid.width
			var count := int(expected)
			if rng.randf() < fmod(expected, 1.0):
				count += 1
			for c in range(count):
				var x := rng.randi_range(0, grid.width - 1)
				if grid.is_empty(x, y) or grid.get_item(x, y):
					continue
				grid.set_item(x, y, item)
