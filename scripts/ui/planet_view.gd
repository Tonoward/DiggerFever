extends Control
class_name PlanetView

## One planet inside the selection carousel. Placeholder art for now: a flat circle in the
## planet's color with a soft highlight and a darker rim, so it reads as a sphere. The
## moment a PlanetData gets a `texture`, that image is drawn instead -- same size, same
## scaling, so swapping in real artwork is a data edit, not a code change.
##
## The node is always BASE_RADIUS*2 square with its pivot at the center; the carousel
## resizes it purely through `scale`, which keeps the visual center exactly on the slot.

const BASE_RADIUS: float = 52.0

var planet: PlanetData:
	set(value):
		planet = value
		queue_redraw()

func _init() -> void:
	size = Vector2(BASE_RADIUS * 2.0, BASE_RADIUS * 2.0)
	pivot_offset = size * 0.5
	# The carousel owns all pointer handling (drag + tap), so the planets must not eat it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if planet == null:
		return
	var center := size * 0.5
	if planet.texture:
		draw_texture_rect(planet.texture, Rect2(Vector2.ZERO, size), false)
		return
	draw_circle(center, BASE_RADIUS, planet.color, true, -1.0, true)
	# Light coming from the upper left: a soft blob highlight...
	draw_circle(center - Vector2(BASE_RADIUS * 0.28, BASE_RADIUS * 0.3), BASE_RADIUS * 0.45,
		planet.color.lightened(0.28), true, -1.0, true)
	# ...and a darker rim to close the sphere off against the background.
	draw_arc(center, BASE_RADIUS - 1.5, 0.0, TAU, 64, planet.color.darkened(0.45), 3.0, true)
