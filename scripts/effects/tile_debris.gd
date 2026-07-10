## TileDebris.gd
## Small physics fragment spawned when a cell is excavated. Falls under gravity,
## collides with solid terrain cells and the drill, then frees itself. Some fragments
## (see `collectible` in setup()) instead fly to the drill and shrink away partway through,
## as a visual "getting collected" moment -- see SUCK_DELAY/SUCK_DURATION below.
##
## Adapted from the FeverDiggerPetru prototype's TileDebris to this project's TerrainGrid
## (grid lookups via world_to_cell / is_empty) and DrillController (footprint radius).
## Runs in world/global space -- spawn it under a node at the world origin (Main).
class_name TileDebris
extends Node2D

const LIFETIME: float        = 8.0
const GRAVITY: float         = 520.0
const RESTITUTION: float     = 0.35
const FRICTION: float        = 0.65
const REST_THRESHOLD: float  = 2.0    ## speed below which the debris is considered at rest
const ANGULAR_MAX: float     = 8.0    ## max initial angular velocity (rad/s)
const ANGULAR_DAMPING: float = 0.80   ## spin multiplier applied on each bounce
const GHOST_DURATION: float  = 0.18   ## seconds of free-fall with no collision after spawn

## "Collectible" fragments (see `collectible` param of setup()) pop out normally for
## SUCK_DELAY seconds, then fly to the drill and shrink away over SUCK_DURATION -- a small
## bit of juice suggesting the material got picked up. Regular fragments just fall/bounce
## until LIFETIME runs out; not every piece needs to fly home for this to read well.
const SUCK_DELAY: float    = 0.25
const SUCK_DURATION: float = 0.3

var _color: Color
var _half: float
var _velocity: Vector2
var _angular_velocity: float
var _ghost_time: float = 0.0
var _grid: TerrainGrid
var _drill: Node2D = null
var _drill_radius: float = 0.0
var _resting: bool = false
var _timer: SceneTreeTimer

var _collectible: bool = false
var _suck_delay_left: float = 0.0
var _being_sucked: bool = false
var _suck_elapsed: float = 0.0
var _suck_start_half: float = 0.0


func setup(color: Color, size: float, grid: TerrainGrid, impulse: Vector2, drill: Node2D = null, drill_radius: float = 0.0, collectible: bool = false) -> void:
	_color        = color
	_half         = size * 0.5
	_grid         = grid
	_drill        = drill
	_drill_radius = drill_radius
	_velocity     = impulse
	_ghost_time   = GHOST_DURATION
	_collectible  = collectible
	_suck_delay_left = SUCK_DELAY
	var spin_sign: float = signf(impulse.x) if impulse.x != 0.0 else (1.0 if randf() > 0.5 else -1.0)
	_angular_velocity = spin_sign * randf_range(ANGULAR_MAX * 0.4, ANGULAR_MAX)
	queue_redraw()
	_timer = get_tree().create_timer(LIFETIME)
	_timer.timeout.connect(queue_free)


func _exit_tree() -> void:
	if _timer != null:
		_timer.timeout.disconnect(queue_free)


func _cell_solid(cell: Vector2i) -> bool:
	return not _grid.is_empty(cell.x, cell.y)


func _process(delta: float) -> void:
	if _being_sucked:
		_process_suck(delta)
		return

	# Countdown runs regardless of resting/falling state, so a collectible fragment gets
	# pulled in on schedule whether it's still tumbling or already settled.
	if _collectible:
		_suck_delay_left -= delta
		if _suck_delay_left <= 0.0:
			_being_sucked = true
			_suck_elapsed = 0.0
			_suck_start_half = _half
			return

	if _resting:
		return

	_velocity.y += GRAVITY * delta

	# Ghost phase: pass freely through cells for a moment after spawn so the debris
	# sinks into the freshly excavated space before it starts colliding.
	if _ghost_time > 0.0:
		_ghost_time -= delta
		position += _velocity * delta
		rotation += _angular_velocity * delta
		return

	var ts: float = float(_grid.cell_size_px)

	# Rescue at the start of the frame, before moving (e.g. it drifted into a wall during
	# the ghost phase, or the narrow dig footprint left a gap it slipped into).
	_rescue_if_embedded()

	var next_pos := position + _velocity * delta

	# Drill collision -- bounce off its circular footprint.
	if _drill != null and is_instance_valid(_drill) and _drill_radius > 0.0:
		var to_debris := next_pos - _drill.global_position
		var dist := to_debris.length()
		var min_dist := _drill_radius + _half
		if dist < min_dist:
			var normal := to_debris.normalized() if dist > 0.01 else Vector2.UP
			next_pos = _drill.global_position + normal * (min_dist + 1.0)
			_velocity = _velocity.bounce(normal) * RESTITUTION
			_angular_velocity *= ANGULAR_DAMPING
			_resting = false

	# Vertical collision -- snap to the cell surface.
	var bottom := _grid.world_to_cell(next_pos + Vector2(0.0, _half))
	if _cell_solid(bottom):
		next_pos.y = float(bottom.y) * ts - _half - 0.5
		_velocity.y = -absf(_velocity.y) * RESTITUTION
		_velocity.x *= FRICTION
		_angular_velocity *= ANGULAR_DAMPING

	# Horizontal collision -- snap to the cell edge.
	if _velocity.x != 0.0:
		var sx: float = signf(_velocity.x)
		var side := _grid.world_to_cell(next_pos + Vector2(_half * sx, 0.0))
		if _cell_solid(side):
			if sx > 0.0:
				next_pos.x = float(side.x) * ts - _half - 0.5
			else:
				next_pos.x = float(side.x + 1) * ts + _half + 0.5
			_velocity.x = -_velocity.x * RESTITUTION
			_angular_velocity *= ANGULAR_DAMPING

	position = next_pos
	rotation += _angular_velocity * delta

	# Rescue again after moving, in case the edge-snaps above squeezed it into a corner.
	# Must run before the resting check: once _resting is true _process early-returns
	# forever, so a bad position latched here would freeze the fragment inside rock.
	_rescue_if_embedded()

	# Only rest when a solid cell is directly below -- prevents freezing mid-air.
	if _velocity.length_squared() < REST_THRESHOLD * REST_THRESHOLD:
		var ground := _grid.world_to_cell(position + Vector2(0.0, _half + 2.0))
		if _cell_solid(ground):
			_resting = true


## Flies toward the drill's current position and shrinks to nothing over SUCK_DURATION,
## then frees itself -- the visual "getting collected" moment. No collision here; it's
## purely cosmetic and rides on top of the instant, guaranteed material count in Main.
func _process_suck(delta: float) -> void:
	_suck_elapsed += delta
	var t := clampf(_suck_elapsed / SUCK_DURATION, 0.0, 1.0)
	if _drill != null and is_instance_valid(_drill):
		position = position.lerp(_drill.global_position, 0.25)
	_half = _suck_start_half * (1.0 - t)
	queue_redraw()
	if t >= 1.0:
		queue_free()


## If the fragment's center is inside a solid cell, teleport it to the nearest open cell
## and stop it. This guarantees a fragment can never stay permanently buried in rock (which
## would look broken); ordinary edge-snap collision only blocks *future* motion, so it can't
## rescue something that is already stuck.
func _rescue_if_embedded() -> void:
	if _cell_solid(_grid.world_to_cell(position)):
		position = _nearest_open_position(position)
		_velocity = Vector2.ZERO


## Searches outward ring-by-ring (up to 4 cells) for the nearest non-solid cell and
## returns its world-center. Falls back to the original position if none is found
## (shouldn't happen in practice -- every dig carves at least one open cell).
func _nearest_open_position(pos: Vector2) -> Vector2:
	var origin := _grid.world_to_cell(pos)
	if not _cell_solid(origin):
		return pos
	for radius in range(1, 5):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := origin + Vector2i(dx, dy)
				if not _cell_solid(c):
					return _grid.cell_to_world_center(c.x, c.y)
	return pos


func _draw() -> void:
	draw_rect(Rect2(-_half, -_half, _half * 2.0, _half * 2.0), _color)
