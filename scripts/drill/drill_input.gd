extends Node
class_name DrillInput

## Click/touch-and-drag input. Emits the drag vector (screen pixels, origin to pointer)
## continuously while held, and resets to ZERO on release so the drill eases to a stop
## rather than snapping (handled by the damping in DrillController).

signal drag_changed(vector: Vector2)

var _dragging := false
var _origin := Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag(event.position)
		else:
			_end_drag()
	elif event is InputEventMouseMotion and _dragging:
		drag_changed.emit(event.position - _origin)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_start_drag(event.position)
		else:
			_end_drag()
	elif event is InputEventScreenDrag and _dragging:
		drag_changed.emit(event.position - _origin)

func _start_drag(pos: Vector2) -> void:
	_dragging = true
	_origin = pos
	drag_changed.emit(Vector2.ZERO)

func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	drag_changed.emit(Vector2.ZERO)
