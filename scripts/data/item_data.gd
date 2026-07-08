extends Resource
class_name ItemData

## One collectible embedded in the terrain (treasure box, loose gem). Data-only resource,
## edited as .tres files in data/items/. Similar to MaterialData, but an item is a single
## cell that the drill breaks open in one go if its `power` meets `required_power` --
## it isn't dug down tile-by-tile like a material.

@export var id: StringName
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var required_power: float = 5.0   ## Drill power needed to break this item open.

@export var reward_type: StringName = &""
@export var reward_amount: int = 0

## Depth distribution + rarity, same shape as MaterialData so generation code can share logic.
@export var depth_min: int = 0
@export var depth_max: int = 9999
@export var depth_peak: int = 0
@export var depth_falloff: float = 50.0
@export var rarity_weight: float = 1.0

@export var cluster_size_min: int = 1
@export var cluster_size_max: int = 1

@export var tile_atlas_coords: Vector2i = Vector2i.ZERO

## Optional texture for this item. Only used when TerrainController.use_material_textures
## is enabled; otherwise falls back to `color`.
@export var texture: Texture2D
