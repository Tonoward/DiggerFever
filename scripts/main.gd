extends Node2D

## Main scene root -- the "conductor" that wires the pieces together. On start it builds a
## world (WorldGenerator), hands the shared TerrainGrid to the terrain renderer and the
## drill, spawns debris whenever a cell is dug, and regenerates on the R key. The actual
## logic lives in the other scripts; this file mostly just connects them.

## Debris (little fragments that pop out when a cell is dug).
## Impulse magnitudes are expressed in cell-widths/second (not raw px) so the "pop" stays
## proportionate to the hole size regardless of cell_size_px -- important since the grid
## scale is meant to be freely tunable for experiments.
const MAX_DEBRIS: int = 48
const DEBRIS_SIZE_FACTOR: float = 0.5      ## debris side = cell_size_px * this
const DEBRIS_IMPULSE_SIDE_CELLS: float = 3.0  ## +/- sideways scatter, in cells/sec
const DEBRIS_IMPULSE_MIN_CELLS: float = 3.0   ## kick toward the drill/hole, in cells/sec
const DEBRIS_IMPULSE_MAX_CELLS: float = 7.0

## Chance that a given spawned fragment plays the "sucked up" collection animation instead
## of just falling/bouncing like ordinary debris (see TileDebris.setup's `collectible` arg).
## Purely visual -- the material count below always increases, regardless of this roll.
const DEBRIS_COLLECT_CHANCE: float = 0.35

@export var world_config: WorldGenConfig

var grid: TerrainGrid

var _debris: Array[TileDebris] = []

## Materials collected so far this run, keyed by MaterialData.id -> count. Drives the
## color-block + counter row in the HUD.
var _material_counts: Dictionary = {}
## MaterialData.id -> the Label showing that material's count, so updates are O(1).
var _material_labels: Dictionary = {}

@onready var terrain: TerrainController = $Terrain
@onready var drill: DrillController = $Drill
@onready var _hud: Label = $HUD/Label
@onready var _materials_hud: GridContainer = $HUD/MaterialsRow

func _ready() -> void:
	drill.resource_collected.connect(_on_resource_collected)
	_generate_world()

func _generate_world() -> void:
	_clear_debris()
	_clear_material_hud()
	grid = WorldGenerator.generate(world_config)
	grid.cell_excavated.connect(_on_cell_excavated)
	terrain.setup(grid)
	drill.setup(grid)
	# Spawn at the top edge of row 0 (not its center) so the drill sits on top of the
	# grass "starting line" rather than half-buried in it.
	var spawn_x := grid.cell_to_world_center(grid.width / 2, 0).x
	drill.global_position = Vector2(spawn_x, 0.0)
	drill.velocity = Vector2.ZERO
	drill.target_velocity = Vector2.ZERO

	if OS.get_environment("DIGGER_DEBUG_GEN") == "1":
		_print_gen_debug()
	var debug_img_path := OS.get_environment("DIGGER_DEBUG_IMG")
	if debug_img_path != "":
		_save_debug_image(debug_img_path)


# --- Dev-only debug helpers (safe to ignore) ------------------------------------
# These only run when you set an environment variable before launching, e.g.
# DIGGER_DEBUG_GEN=1. They print stats / dump a PNG of the generated world and have
# no effect on the actual game. Handy while tuning generation.

func _print_gen_debug() -> void:
	var counts := {}
	for y in range(grid.depth):
		for x in range(grid.width):
			var mat := grid.get_material(x, y)
			var key: String = mat.id if mat else "empty"
			counts[key] = counts.get(key, 0) + 1
	print("Cell counts: ", counts)
	var sample := {}
	for item in grid.items.values():
		sample[item.id] = sample.get(item.id, 0) + 1
	print("Item breakdown: ", sample, " total=", grid.items.size())
	var profile := []
	for y in range(0, grid.depth, 20):
		var m := grid.get_material(40, y)
		profile.append("%d:%s" % [y, m.id if m else "empty"])
	print("Column profile @x=40: ", profile)

## Dumps a top-down material-color map of the generated grid to a PNG for visual
## inspection (e.g. comparing layer blobbiness against a reference image).
func _save_debug_image(path: String) -> void:
	var img := Image.create(grid.width, grid.depth, false, Image.FORMAT_RGB8)
	for y in range(grid.depth):
		for x in range(grid.width):
			var color := Color.BLACK
			var item := grid.get_item(x, y)
			if item:
				color = item.color
			else:
				var mat := grid.get_material(x, y)
				if mat:
					color = mat.color
			img.set_pixel(x, y, color)
	img.save_png(path)

	var zoom_rows := mini(200, grid.depth)
	var crop := img.get_region(Rect2i(0, 0, grid.width, zoom_rows))
	crop.resize(grid.width * 4, zoom_rows * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png(path.get_basename() + "_zoom.png")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		world_config.seed_value = randi()
		_generate_world()

func _on_resource_collected(resource_type: StringName, amount: int) -> void:
	if resource_type == &"":
		return
	_hud.text = "Collected: %d x %s" % [amount, resource_type]

# --- Debris ---------------------------------------------------------------------

func _on_cell_excavated(x: int, y: int, mat: MaterialData) -> void:
	if mat == null:
		return
	_spawn_debris(x, y, mat)
	_collect_material(mat)

func _spawn_debris(x: int, y: int, mat: MaterialData) -> void:
	# Drop stale refs (freed by their own lifetime timer), then evict oldest if at cap.
	while not _debris.is_empty() and not is_instance_valid(_debris[0]):
		_debris.pop_front()
	if _debris.size() >= MAX_DEBRIS:
		var oldest: TileDebris = _debris.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var cell_center := grid.cell_to_world_center(x, y)
	# Kick the fragment back toward the drill -- i.e. into the hole/tunnel it just carved --
	# with some sideways spread. Gravity then settles it on the tunnel floor. Kicking it
	# the other way (away from the drill) would launch it straight into unexcavated ground.
	var cs := float(grid.cell_size_px)
	var toward_hole := (drill.global_position - cell_center)
	toward_hole = toward_hole.normalized() if toward_hole.length() > 0.01 else Vector2.UP
	var side := toward_hole.orthogonal()
	var impulse := toward_hole * randf_range(DEBRIS_IMPULSE_MIN_CELLS, DEBRIS_IMPULSE_MAX_CELLS) * cs \
		+ side * randf_range(-DEBRIS_IMPULSE_SIDE_CELLS, DEBRIS_IMPULSE_SIDE_CELLS) * cs

	var debris := TileDebris.new()
	add_child(debris)
	debris.global_position = cell_center
	var collectible := randf() < DEBRIS_COLLECT_CHANCE
	debris.setup(mat.color, grid.cell_size_px * DEBRIS_SIZE_FACTOR, grid, impulse, drill, drill.footprint_radius_px, collectible)
	_debris.append(debris)

func _clear_debris() -> void:
	for d in _debris:
		if is_instance_valid(d):
			d.queue_free()
	_debris.clear()

# --- Materials HUD ----------------------------------------------------------------
# A row of "color block + xN" entries, one per material that's been dug at least once.
# The count always increases the instant a cell is cleared -- independent of whether that
# cell's debris fragment happens to play the "sucked up" animation, so the number is never
# wrong or delayed by chance/visual timing.

func _collect_material(mat: MaterialData) -> void:
	var count: int = _material_counts.get(mat.id, 0) + 1
	_material_counts[mat.id] = count

	var label: Label = _material_labels.get(mat.id)
	if label == null:
		label = _add_material_entry(mat)
		_material_labels[mat.id] = label
	label.text = "x%d" % count

## Builds one "color swatch + count label" entry and adds it to the HUD row.
func _add_material_entry(mat: MaterialData) -> Label:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.color = mat.color
	entry.add_child(swatch)

	var label := Label.new()
	entry.add_child(label)

	_materials_hud.add_child(entry)
	return label

func _clear_material_hud() -> void:
	_material_counts.clear()
	_material_labels.clear()
	for child in _materials_hud.get_children():
		child.queue_free()
