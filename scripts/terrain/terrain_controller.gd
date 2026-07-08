extends Node2D
class_name TerrainController

## Dual-grid renderer for a TerrainGrid.
##
## Technique (from the pablogila/TileMapDual approach): a *display* grid is offset by
## half a cell from the world grid, so each display cell sits on the corner shared by
## four world cells. That display cell picks one of 16 transition tiles based on which
## of those 4 corners are "solid" -- giving smooth/organic edges instead of hard squares,
## from only 16 tiles per material instead of 47.
##
## Multi-material transitions are done with one display layer per material, stacked by
## `render_priority`. Each layer treats every cell of equal-or-higher priority as solid,
## so higher-priority materials draw their rounded edge on top of the lower ones. This
## mirrors how the addon layers terrains, but stays fully procedural/runtime-driven.

## When on, materials with a `texture` fill the tiles with that texture; otherwise `color`.
@export var use_material_textures: bool = false

var grid: TerrainGrid

## One TileMapLayer per material, ordered low -> high render_priority (draw order).
var _material_layers: Array[TileMapLayer] = []
var _layer_materials: Array[MaterialData] = []
var _items_layer: TileMapLayer

## mask (bit0=top-left, bit1=top-right, bit2=bottom-left, bit3=bottom-right) -> atlas coord.
## This is the standard dual-grid 4x4 layout, so a hand-drawn standard sheet drops in as-is.
const MASK_TO_COORD: Array[Vector2i] = [
	Vector2i(0, 3), # 0000
	Vector2i(3, 3), # 0001 TL
	Vector2i(0, 2), # 0010 TR
	Vector2i(1, 2), # 0011 TL TR
	Vector2i(0, 0), # 0100 BL
	Vector2i(3, 2), # 0101 TL BL
	Vector2i(2, 3), # 0110 TR BL
	Vector2i(3, 1), # 0111 TL TR BL
	Vector2i(1, 3), # 1000 BR
	Vector2i(0, 1), # 1001 TL BR
	Vector2i(1, 0), # 1010 TR BR
	Vector2i(2, 2), # 1011 TL TR BR
	Vector2i(3, 0), # 1100 BL BR
	Vector2i(2, 0), # 1101 TL BL BR
	Vector2i(1, 1), # 1110 TR BL BR
	Vector2i(2, 1), # 1111 all
]

func setup(p_grid: TerrainGrid) -> void:
	grid = p_grid
	_build_layers()
	if not grid.cell_changed.is_connected(_on_cell_changed):
		grid.cell_changed.connect(_on_cell_changed)
	_redraw_all()

func _build_layers() -> void:
	for c in get_children():
		c.queue_free()
	_material_layers.clear()
	_layer_materials.clear()

	# Sort materials low -> high priority; ties broken by load order for determinism.
	var mats := MaterialDatabase.materials.duplicate()
	mats.sort_custom(func(a, b): return a.render_priority < b.render_priority)

	var half := Vector2(grid.cell_size_px, grid.cell_size_px) * 0.5
	for mat in mats:
		var layer := TileMapLayer.new()
		layer.tile_set = _build_material_tileset(mat)
		layer.position = -half  # shift the display grid onto the world corners
		add_child(layer)
		_material_layers.append(layer)
		_layer_materials.append(mat)

	_items_layer = TileMapLayer.new()
	_items_layer.tile_set = _build_items_tileset()
	add_child(_items_layer)  # added last -> drawn on top of terrain

func _on_cell_changed(x: int, y: int) -> void:
	# A world cell is a corner of the 4 display cells around it; refresh those.
	for d in [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]:
		_update_display_cell(d.x, d.y)
	_update_item_cell(x, y)

func _redraw_all() -> void:
	for layer in _material_layers:
		layer.clear()
	_items_layer.clear()
	for dy in range(grid.depth + 1):
		for dx in range(grid.width + 1):
			_update_display_cell(dx, dy)
	for y in range(grid.depth):
		for x in range(grid.width):
			_update_item_cell(x, y)

## Refreshes one display cell across every material layer.
func _update_display_cell(dx: int, dy: int) -> void:
	for i in range(_material_layers.size()):
		var priority := _layer_materials[i].render_priority
		var mask := 0
		if _corner_solid(dx - 1, dy - 1, priority): mask |= 1
		if _corner_solid(dx, dy - 1, priority): mask |= 2
		if _corner_solid(dx - 1, dy, priority): mask |= 4
		if _corner_solid(dx, dy, priority): mask |= 8
		if mask == 0:
			_material_layers[i].erase_cell(Vector2i(dx, dy))
		else:
			_material_layers[i].set_cell(Vector2i(dx, dy), 0, MASK_TO_COORD[mask])

## A world corner counts as solid for a layer if its material's priority is at least the
## layer's -- so higher materials read as filled underneath lower layers (no gaps/leaks).
func _corner_solid(x: int, y: int, layer_priority: int) -> bool:
	var mat := grid.get_material(x, y)
	return mat != null and mat.render_priority >= layer_priority

func _update_item_cell(x: int, y: int) -> void:
	var item := grid.get_item(x, y)
	if item:
		_items_layer.set_cell(Vector2i(x, y), 0, item.tile_atlas_coords)
	else:
		_items_layer.erase_cell(Vector2i(x, y))

# --- Tileset construction ------------------------------------------------------

func _build_material_tileset(mat: MaterialData) -> TileSet:
	var cs := grid.cell_size_px
	var image: Image
	if mat.dual_grid_texture:
		# Hand-drawn standard 4x4 sheet -> use as-is (resized to our cell size).
		image = mat.dual_grid_texture.get_image().duplicate()
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		image.resize(cs * 4, cs * 4, Image.INTERPOLATE_LANCZOS)
	else:
		image = _generate_dual_atlas(mat, cs)
	return _tileset_from_atlas(image, cs)

## Procedurally paints the 16 transition tiles into a 4x4 atlas. Foreground pixels get
## the material's color/texture; background pixels are transparent so lower layers show.
func _generate_dual_atlas(mat: MaterialData, cs: int) -> Image:
	var image := Image.create(cs * 4, cs * 4, false, Image.FORMAT_RGBA8)
	var fill := _material_fill_image(mat, cs)
	for mask in range(16):
		var origin := MASK_TO_COORD[mask] * cs
		for py in range(cs):
			for px in range(cs):
				var u := (px + 0.5) / cs
				var v := (py + 0.5) / cs
				if _mask_is_foreground(mask, u, v):
					image.set_pixel(origin.x + px, origin.y + py, fill.get_pixel(px, py))
	return image

## Bilinear "marching squares" test: interpolate the 4 corner solidities and threshold
## at 0.5. Gives clean diagonal transitions that are complementary between materials
## (no gaps or overlaps at boundaries).
func _mask_is_foreground(mask: int, u: float, v: float) -> bool:
	var tl := 1.0 if (mask & 1) else 0.0
	var tr := 1.0 if (mask & 2) else 0.0
	var bl := 1.0 if (mask & 4) else 0.0
	var br := 1.0 if (mask & 8) else 0.0
	var f := tl * (1.0 - u) * (1.0 - v) + tr * u * (1.0 - v) + bl * (1.0 - u) * v + br * u * v
	return f >= 0.5

## One cell-sized image of the material's appearance (texture sample or flat color).
func _material_fill_image(mat: MaterialData, cs: int) -> Image:
	if use_material_textures and mat.texture:
		var src := mat.texture.get_image().duplicate()
		if src.get_format() != Image.FORMAT_RGBA8:
			src.convert(Image.FORMAT_RGBA8)
		src.resize(cs, cs, Image.INTERPOLATE_LANCZOS)
		return src
	var flat := Image.create(cs, cs, false, Image.FORMAT_RGBA8)
	flat.fill(mat.color)
	return flat

func _build_items_tileset() -> TileSet:
	var items := MaterialDatabase.items
	var cs := grid.cell_size_px
	var cols := 1
	for it in items:
		cols = maxi(cols, it.tile_atlas_coords.x + 1)
	var image := Image.create(cols * cs, cs, false, Image.FORMAT_RGBA8)
	for it in items:
		var rect := Rect2i(it.tile_atlas_coords.x * cs, 0, cs, cs)
		image.fill_rect(rect, it.color)
	return _tileset_from_atlas(image, cs)

func _tileset_from_atlas(image: Image, cs: int) -> TileSet:
	var texture := ImageTexture.create_from_image(image)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(cs, cs)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(cs, cs)
	var cols := image.get_width() / cs
	var rows := image.get_height() / cs
	for ty in range(rows):
		for tx in range(cols):
			source.create_tile(Vector2i(tx, ty))
	tile_set.add_source(source, 0)
	return tile_set
