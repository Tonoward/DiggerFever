extends Control

## Planet selection screen -- sits between the main menu and the game. An infinite
## (wrap-around) carousel: the planet in the middle is the selected one and is drawn
## bigger than its neighbours. You can swipe/drag the wheel with a finger, tap a side
## planet to bring it to the center, or use the < / > buttons. "Confirm" stores the
## choice in PlanetDatabase and starts the game.
##
## How the wheel works
## -------------------
## Everything is driven by one number: `_scroll`, the (fractional) index sitting in the
## center slot. Planet i is drawn at slot offset `d = i - _scroll`, wrapped into
## [-n/2, n/2) -- that wrap is what makes the list endless for free: pass the last planet
## and the first one simply comes around from the other side. `_target` is where the
## wheel wants to settle (always a whole index); `_scroll` eases toward it every frame.
## While a finger is down, `_scroll` follows the drag directly and `_target` tags along.

## --- Wheel geometry -----------------------------------------------------------------
const SLOT_SPACING: float = 96.0    ## px between the centers of two neighbouring planets
const CENTER_SCALE: float = 1.0     ## scale of the planet in the middle (the selected one)
const SIDE_SCALE: float = 0.55      ## scale of its immediate neighbours
const FAR_SCALE: float = 0.4        ## scale two slots out, where they fade away
const VISIBLE_SLOTS: float = 2.0    ## planets further out than this aren't drawn at all
const ARC_DROP: float = 10.0        ## px the side planets sit lower, for a subtle arc

## --- Feel ---------------------------------------------------------------------------
const SNAP_SPEED: float = 14.0      ## how briskly the wheel eases into its target slot
const TAP_MAX_DRAG: float = 12.0    ## px of movement still counted as a tap, not a swipe
const TAP_PADDING: float = 10.0     ## extra px around a planet that still counts as hitting it
const FLICK_LOOKAHEAD: float = 0.12 ## seconds of "throw" carried over when you let go
const MAX_FLICK_SLOTS: float = 2.0  ## cap so a hard flick can't spin the wheel wildly

@onready var _carousel: Control = $VBox/Carousel
@onready var _name_label: Label = $VBox/NavRow/PlanetName
@onready var _prev_button: Button = $VBox/NavRow/PrevButton
@onready var _next_button: Button = $VBox/NavRow/NextButton
@onready var _confirm_button: Button = $VBox/ConfirmButton
@onready var _back_button: Button = $VBox/BackButton

var _views: Array[PlanetView] = []
var _scroll: float = 0.0
var _target: float = 0.0
var _dragging: bool = false
var _drag_moved: float = 0.0        ## total px travelled this drag (tap vs swipe test)
var _drag_velocity: float = 0.0     ## slots/sec, for the flick on release
var _shown_index: int = -1          ## index the name label currently shows

func _ready() -> void:
	_build_planets()
	_carousel.gui_input.connect(_on_carousel_gui_input)
	_carousel.resized.connect(_layout_planets)
	_prev_button.pressed.connect(_step.bind(-1))
	_next_button.pressed.connect(_step.bind(1))
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	AudioManager.play_music()

	# Start on whatever was picked last (first planet on a fresh run).
	_target = float(PlanetDatabase.selected_index())
	_scroll = _target
	_refresh_selection()
	_layout_planets()

func _build_planets() -> void:
	for planet in PlanetDatabase.planets:
		var view := PlanetView.new()
		view.planet = planet
		_carousel.add_child(view)
		_views.append(view)
	if _views.is_empty():
		push_warning("PlanetSelect: no planets found in data/planets/")
		_confirm_button.disabled = true
		_prev_button.disabled = true
		_next_button.disabled = true

func _process(delta: float) -> void:
	if _views.is_empty():
		return
	if not _dragging:
		# Frame-rate independent easing toward the target slot.
		_scroll = lerpf(_scroll, _target, 1.0 - exp(-SNAP_SPEED * delta))
		if absf(_target - _scroll) < 0.0005:
			_scroll = _target
			_normalize()
	# The label follows the planet nearest the center, so it updates live mid-swipe.
	var nearest := wrapi(int(round(_scroll)), 0, _views.size())
	if nearest != _shown_index:
		_refresh_selection()
		if _dragging:
			AudioManager.play_blip()  # button/tap changes blip on press instead
	_layout_planets()

# --- Drawing the wheel ----------------------------------------------------------------

## Places every planet according to its distance from the center slot: bigger and fully
## opaque in the middle, smaller/dimmer toward the edges, and drawn front-to-back so the
## selected one overlaps its neighbours.
func _layout_planets() -> void:
	if _views.is_empty():
		return
	var center := _carousel.size * 0.5
	var n := _views.size()
	for i in n:
		var view := _views[i]
		var d := _slot_offset(i)
		var ad := absf(d)
		if ad > VISIBLE_SLOTS:
			view.visible = false
			continue
		var scale_factor: float
		var alpha: float
		if ad <= 1.0:
			scale_factor = lerpf(CENTER_SCALE, SIDE_SCALE, smoothstep(0.0, 1.0, ad))
			alpha = 1.0
		else:
			var t := ad - 1.0
			scale_factor = lerpf(SIDE_SCALE, FAR_SCALE, t)
			alpha = 1.0 - t * t  # fades out before it reaches the screen edge
		view.visible = true
		view.scale = Vector2(scale_factor, scale_factor)
		view.modulate.a = alpha
		view.z_index = 10 - int(ad * 4.0)
		var slot_center := center + Vector2(d * SLOT_SPACING, ad * ARC_DROP)
		view.position = slot_center - view.size * 0.5

## Signed distance (in slots) from planet `i` to the center, wrapped into [-n/2, n/2).
## The wrap is what makes the carousel endless.
func _slot_offset(i: int) -> float:
	var n := float(_views.size())
	return fposmod(float(i) - _scroll + n * 0.5, n) - n * 0.5

# --- Input ----------------------------------------------------------------------------

## Drag/tap on the carousel area. Touch arrives here as mouse events (Godot's
## "emulate mouse from touch" is on by default), so one code path covers both.
func _on_carousel_gui_input(event: InputEvent) -> void:
	if _views.is_empty():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_dragging = true
			_drag_moved = 0.0
			_drag_velocity = 0.0
		elif _dragging:
			_dragging = false
			_end_drag(button.position)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var dx: float = motion.relative.x
		_drag_moved += absf(dx)
		# Drag right -> the wheel rolls right -> the planet on the left comes to the center.
		_scroll -= dx / SLOT_SPACING
		_target = _scroll
		_drag_velocity = -motion.velocity.x / SLOT_SPACING

## Released: either it was a tap on a side planet (select it), or a swipe (snap to the
## nearest slot, carrying a bit of the flick so a quick throw skips ahead).
func _end_drag(release_pos: Vector2) -> void:
	if _drag_moved <= TAP_MAX_DRAG:
		var tapped := _planet_at(release_pos)
		if tapped >= 0:
			AudioManager.play_blip()
			_select(tapped)
		else:
			_target = roundf(_scroll)
		return
	var predicted := _scroll + _drag_velocity * FLICK_LOOKAHEAD
	_target = roundf(clampf(predicted, _scroll - MAX_FLICK_SLOTS, _scroll + MAX_FLICK_SLOTS))

## Index of the planet under `local_pos` (carousel-local), or -1. Hit radius follows the
## current scale, so the big center planet has a big target and the small ones a small one.
func _planet_at(local_pos: Vector2) -> int:
	var best := -1
	var best_dist := INF
	for i in _views.size():
		var view := _views[i]
		if not view.visible:
			continue
		var hit_radius := PlanetView.BASE_RADIUS * view.scale.x + TAP_PADDING
		var dist := (view.position + view.size * 0.5).distance_to(local_pos)
		if dist <= hit_radius and dist < best_dist:
			best = i
			best_dist = dist
	return best

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)

# --- Moving the wheel -------------------------------------------------------------------

## One slot left (-1) or right (+1). `_target` keeps counting past the ends; `_normalize`
## folds it back once the wheel settles, so it never drifts into float trouble.
func _step(dir: int) -> void:
	if _views.is_empty():
		return
	AudioManager.play_blip()
	_target = roundf(_target) + float(dir)

## Brings planet `i` to the center, turning the shortest way around the wheel.
func _select(i: int) -> void:
	var n := float(_views.size())
	var delta := fposmod(float(i) - _target + n * 0.5, n) - n * 0.5
	_target += delta

## Folds `_scroll`/`_target` back into [0, n) once they agree, keeping them small.
func _normalize() -> void:
	var n := float(_views.size())
	var wrapped := fposmod(_target, n)
	_scroll += wrapped - _target
	_target = wrapped

func _refresh_selection() -> void:
	_shown_index = wrapi(int(round(_scroll)), 0, _views.size())
	_name_label.text = _views[_shown_index].planet.display_name

# --- Buttons ------------------------------------------------------------------------------

func _on_confirm_pressed() -> void:
	AudioManager.play_blip()
	# Confirm the planet the wheel is settling on, not the one it started from.
	PlanetDatabase.selected_planet = _views[wrapi(int(round(_target)), 0, _views.size())].planet
	AudioManager.stop_music()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_back_pressed() -> void:
	AudioManager.play_blip()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
