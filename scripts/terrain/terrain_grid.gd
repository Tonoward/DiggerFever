extends RefCounted
class_name TerrainGrid

## Plain data grid for the terrain. Decoupled from rendering: TerrainController
## listens to `cell_changed` and keeps the TileMapLayer in sync.

signal cell_changed(x: int, y: int)

## Emitted when a cell is fully dug out by damage (not on generation/plain clears).
## Carries the material that was removed so listeners can spawn matching debris, etc.
signal cell_excavated(x: int, y: int, material: MaterialData)

const EMPTY := -1

var width: int
var depth: int
var cell_size_px: int

## Index into `material_palette`, or EMPTY if the cell has been dug out.
var material_ids: PackedInt32Array
var integrity: PackedFloat32Array

## Built once by WorldGenerator; shared lookup so we don't store StringNames per-cell.
var material_palette: Array[MaterialData] = []

## Sparse: cell index -> ItemData, for special collectibles embedded in terrain.
var items: Dictionary = {}

func _init(p_width: int, p_depth: int, p_cell_size_px: int, p_palette: Array[MaterialData]) -> void:
	width = p_width
	depth = p_depth
	cell_size_px = p_cell_size_px
	material_palette = p_palette
	var count := width * depth
	material_ids = PackedInt32Array()
	material_ids.resize(count)
	material_ids.fill(EMPTY)
	integrity = PackedFloat32Array()
	integrity.resize(count)

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < depth

func _index(x: int, y: int) -> int:
	return y * width + x

func get_material_index(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return EMPTY
	return material_ids[_index(x, y)]

func get_material(x: int, y: int) -> MaterialData:
	var idx := get_material_index(x, y)
	if idx == EMPTY or idx < 0 or idx >= material_palette.size():
		return null
	return material_palette[idx]

func get_item(x: int, y: int) -> ItemData:
	return items.get(_index(x, y))

func get_integrity(x: int, y: int) -> float:
	if not in_bounds(x, y):
		return 0.0
	return integrity[_index(x, y)]

func is_empty(x: int, y: int) -> bool:
	return get_material_index(x, y) == EMPTY

## Used by WorldGenerator to lay down initial terrain.
func set_cell(x: int, y: int, material_index: int) -> void:
	if not in_bounds(x, y):
		return
	var i := _index(x, y)
	material_ids[i] = material_index
	var mat := material_palette[material_index] if material_index >= 0 else null
	integrity[i] = mat.max_integrity if mat else 0.0
	cell_changed.emit(x, y)

func set_item(x: int, y: int, item: ItemData) -> void:
	if not in_bounds(x, y):
		return
	items[_index(x, y)] = item
	cell_changed.emit(x, y)

## Returns true if the cell was fully cleared this call.
func damage_cell(x: int, y: int, amount: float) -> bool:
	if not in_bounds(x, y) or is_empty(x, y):
		return false
	var i := _index(x, y)
	integrity[i] -= amount
	if integrity[i] <= 0.0:
		var mat := get_material(x, y)
		clear_cell(x, y)
		cell_excavated.emit(x, y, mat)
		return true
	return false

func clear_cell(x: int, y: int) -> void:
	if not in_bounds(x, y):
		return
	var i := _index(x, y)
	material_ids[i] = EMPTY
	integrity[i] = 0.0
	items.erase(i)
	cell_changed.emit(x, y)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / cell_size_px), floori(world_pos.y / cell_size_px))

func cell_to_world_center(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * cell_size_px, (y + 0.5) * cell_size_px)
