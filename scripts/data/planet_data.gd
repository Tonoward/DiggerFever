extends Resource
class_name PlanetData

## One selectable planet. Data-only resource -- no behaviour, just identity + looks.
## Create/edit them as .tres files in data/planets/; PlanetDatabase loads them all at
## startup, sorted by file name (that's also the carousel order, hence the 01_, 02_...
## prefixes). Adding a planet = dropping a new .tres in that folder, no code change.

## Identity
@export var id: StringName
@export var display_name: String = ""

## Looks. While there's no artwork yet the carousel draws a flat circle in `color`;
## as soon as `texture` is set it draws that image instead (same size/scale rules).
@export var color: Color = Color.WHITE
@export var texture: Texture2D
