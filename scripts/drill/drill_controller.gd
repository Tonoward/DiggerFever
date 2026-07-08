extends Node2D
class_name DrillController

## Manual movement + digging against a TerrainGrid (no Godot physics bodies involved --
## collision and digging are both resolved via grid lookups, which keeps this cheap
## regardless of world size).

signal resource_collected(resource_type: StringName, amount: int)

@export var stats: DrillStats
@export var footprint_radius_px: float = 10.0:
	set(value):
		footprint_radius_px = value
		_sync_collision_shape()

## Rotation offset (degrees) to apply if the sprite's frame 0 doesn't already
## point in the +X direction -- tune this if the art faces a different way.
@export var sprite_angle_offset_deg: float = 0.0

enum CellOutcome { CLEAR, DIGGING, HARD_BLOCKED }

var terrain_grid: TerrainGrid
var velocity := Vector2.ZERO
var target_velocity := Vector2.ZERO

var _drag_vector := Vector2.ZERO

## While > 0, the drill is bouncing back from hitting indestructible material --
## normal drag control and digging are suspended until it expires.
var _knockback_timer := 0.0
var _knockback_velocity := Vector2.ZERO
var _hit_flash_timer := 0.0

## True on frames the drill is actively boring through solid material; drives the sprite shake.
var _is_drilling_solid := false

@onready var _drag_line: Line2D = get_node_or_null("DragLine")
@onready var _input: DrillInput = get_node_or_null("DrillInput")
@onready var _sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var _collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

const MOVING_ANIM_SPEED_THRESHOLD := 5.0

func _ready() -> void:
	if _input:
		_input.drag_changed.connect(_on_drag_changed)
	_sync_collision_shape()

## Keeps the visual CollisionShape2D (a circle, purely for seeing the dig radius
## in-editor/in-game) matched to footprint_radius_px, which is the value that
## actually drives digging/blocking in _get_overlapped_cells.
func _sync_collision_shape() -> void:
	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionShape2D")
	if _collision_shape and _collision_shape.shape is CircleShape2D:
		(_collision_shape.shape as CircleShape2D).radius = footprint_radius_px

func setup(grid: TerrainGrid) -> void:
	terrain_grid = grid

func _on_drag_changed(v: Vector2) -> void:
	if v.y < 0.0:
		v.y = 0.0
	_drag_vector = v
	if _drag_line:
		_drag_line.points = [Vector2.ZERO, v]
		_drag_line.visible = v.length() > 1.0

func _physics_process(delta: float) -> void:
	if terrain_grid == null or stats == null:
		return

	if _knockback_timer > 0.0:
		_is_drilling_solid = false
		_process_knockback(delta)
		return

	_update_target_velocity()
	var ease := clampf(stats.maneuverability * delta, 0.0, 1.0)
	velocity = velocity.lerp(target_velocity, ease)

	var delta_pos := velocity * delta
	var tentative_position := global_position + delta_pos

	# Only cells the drill would newly enter this frame take damage/block movement --
	# cells it's already sitting inside of are by definition already cleared. This is
	# what stops both the "glide through unbroken terrain" and "idle digging carves a
	# hole" issues: if velocity is ~0, no new cells are entered, so nothing gets dug.
	var current_cells := _get_overlapped_cells(global_position)
	var entering_cells := _get_overlapped_cells(tentative_position).filter(
		func(c): return not current_cells.has(c)
	)

	var hard_blocked := false
	var digging := false
	for cell in entering_cells:
		match _resolve_entering_cell(cell, delta):
			CellOutcome.HARD_BLOCKED:
				hard_blocked = true
			CellOutcome.DIGGING:
				digging = true

	if hard_blocked:
		_start_knockback(delta_pos)
		return

	_is_drilling_solid = digging
	var move_velocity := Vector2.ZERO if digging else velocity

	_update_animation(move_velocity, digging)
	_update_facing(ease)

	global_position += move_velocity * delta
	_clamp_to_world_bounds()

## Sprite-only shake perpendicular to the drill axis while boring, eased back to rest
## otherwise. Runs in _process so the jitter is smooth and independent of physics ticks.
func _process(_delta: float) -> void:
	if _sprite == null or stats == null:
		return
	if _is_drilling_solid:
		var facing := _drag_vector.angle() if _drag_vector.length() > 1.0 else _sprite.rotation
		var perp := Vector2.from_angle(facing + PI * 0.5)
		_sprite.position = perp * randf_range(-stats.vibration_amp, stats.vibration_amp)
	else:
		_sprite.position = _sprite.position.lerp(Vector2.ZERO, 0.4)

## Handles one cell the drill is trying to enter this frame.
func _resolve_entering_cell(cell: Vector2i, delta: float) -> CellOutcome:
	var item := terrain_grid.get_item(cell.x, cell.y)
	if item:
		if stats.power >= item.required_power:
			terrain_grid.set_item(cell.x, cell.y, null)
			resource_collected.emit(item.reward_type, item.reward_amount)
		else:
			return CellOutcome.HARD_BLOCKED

	var mat := terrain_grid.get_material(cell.x, cell.y)
	if mat == null:
		return CellOutcome.CLEAR
	if stats.power < mat.hardness:
		return CellOutcome.HARD_BLOCKED

	var damage := (stats.power / maxf(mat.friction, 0.01)) * delta
	if terrain_grid.damage_cell(cell.x, cell.y, damage):
		resource_collected.emit(mat.resource_type, mat.resource_amount)
		return CellOutcome.CLEAR
	return CellOutcome.DIGGING

## Triggered the instant the drill runs into material/an item it can't break.
## Cancels normal control for a short window and pushes it back the way it came.
func _start_knockback(delta_pos: Vector2) -> void:
	var dir := delta_pos.normalized() if delta_pos.length() > 0.001 else Vector2.RIGHT
	_knockback_velocity = -dir * stats.knockback_force
	_knockback_timer = stats.knockback_duration
	_hit_flash_timer = stats.hit_flash_duration
	velocity = Vector2.ZERO
	target_velocity = Vector2.ZERO
	if _drag_line:
		_drag_line.visible = false
	if _sprite:
		_sprite.play(&"hit")

func _process_knockback(delta: float) -> void:
	_knockback_timer -= delta
	_hit_flash_timer -= delta

	var t := clampf(_knockback_timer / stats.knockback_duration, 0.0, 1.0)
	var move_velocity := _knockback_velocity * t

	if _sprite:
		_sprite.play(&"hit")

	global_position += move_velocity * delta
	_clamp_to_world_bounds()

	if _knockback_timer <= 0.0:
		velocity = Vector2.ZERO

func _update_animation(move_velocity: Vector2, digging: bool) -> void:
	if _sprite == null:
		return
	if digging or move_velocity.length() > MOVING_ANIM_SPEED_THRESHOLD:
		_sprite.play(&"drill")
	else:
		_sprite.play(&"idle")

## Eases the sprite's rotation toward the drag vector's direction -- same easing
## factor as movement, so turning has the same "weight" as accelerating.
func _update_facing(ease: float) -> void:
	if _sprite == null or _drag_vector.length() <= 1.0:
		return
	var target_angle := _drag_vector.angle() + deg_to_rad(sprite_angle_offset_deg - 90)
	_sprite.rotation = lerp_angle(_sprite.rotation, target_angle, ease)

func _update_target_velocity() -> void:
	var clamped := _drag_vector.limit_length(stats.max_drag_force)
	if stats.max_drag_force > 0.0:
		target_velocity = (clamped / stats.max_drag_force) * stats.max_speed
	else:
		target_velocity = Vector2.ZERO

func _get_overlapped_cells(at_position: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var r := footprint_radius_px
	var min_cell := terrain_grid.world_to_cell(at_position - Vector2(r, r))
	var max_cell := terrain_grid.world_to_cell(at_position + Vector2(r, r))
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			if not terrain_grid.in_bounds(x, y):
				continue
			var cell_center := terrain_grid.cell_to_world_center(x, y)
			if cell_center.distance_to(at_position) <= r + terrain_grid.cell_size_px * 0.5:
				result.append(Vector2i(x, y))
	return result

func _clamp_to_world_bounds() -> void:
	var max_x := terrain_grid.width * terrain_grid.cell_size_px
	var max_y := terrain_grid.depth * terrain_grid.cell_size_px
	global_position.x = clampf(global_position.x, 0.0, max_x)
	global_position.y = clampf(global_position.y, 0.0, max_y)
