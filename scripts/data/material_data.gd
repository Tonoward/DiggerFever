extends Resource
class_name MaterialData

## One type of terrain material (grass, dirt, stone, an ore vein...). This is a data-only
## resource -- no behaviour, just numbers. Create/edit them as .tres files in
## data/materials/; MaterialDatabase loads them all at startup. Every @export field below
## shows up in the Inspector, so tuning the game means editing values here, not code.

## Identity
@export var id: StringName
@export var display_name: String = ""
@export var color: Color = Color.WHITE

## Dig stats
@export var hardness: float = 1.0          ## Drill needs power >= hardness to dig at all.
@export var friction: float = 1.0          ## Higher friction = slower drill movement while digging this material.
@export var max_integrity: float = 10.0    ## "HP" of a cell of this material.

## Resource yield (dropped when a cell is cleared)
@export var resource_type: StringName = &""
@export var resource_amount: int = 0

## Depth distribution (in cells). Used by the base-fill pass.
@export var depth_min: int = 0
@export var depth_max: int = 9999
@export var depth_peak: int = 0            ## Depth at which this material is most likely to appear.
@export var depth_falloff: float = 50.0    ## How quickly probability drops off away from depth_peak.
@export var rarity_weight: float = 1.0     ## Relative weight against other materials valid at a given depth.

## Cluster generation (vein-style materials instead of uniform fill)
@export var is_cluster: bool = false
@export var cluster_size_min: int = 4
@export var cluster_size_max: int = 12

## Visual mapping into the terrain TileSet's atlas.
@export var tile_atlas_coords: Vector2i = Vector2i.ZERO

## Optional ground texture for this material. Only used when
## TerrainController.use_material_textures is enabled; otherwise falls back to `color`.
@export var texture: Texture2D

## Dual-grid rendering.
## Higher priority draws on top: at a boundary between two materials, the higher-priority
## one gets the rounded/organic edge overlaid on the lower one. Ties broken by load order.
@export var render_priority: int = 0

## Optional hand-drawn dual-grid sheet, in the standard 4x4 (16-tile) layout. When set,
## it is used verbatim instead of the procedurally-generated transition tiles -- this is
## the "bring your own art" path. Leave null to auto-generate from `color`/`texture`.
@export var dual_grid_texture: Texture2D
