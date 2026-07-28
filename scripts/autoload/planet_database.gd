extends Node

## Autoload singleton (registered in project.godot under [autoload]), reachable anywhere
## as `PlanetDatabase`. Same idea as MaterialDatabase: at startup it loads every
## PlanetData resource from data/planets/ into an array, so the selection screen never
## hard-codes planet paths.
##
## It also remembers which planet the player picked (`selected_planet`), because that
## outlives the selection scene -- the game scene will read it once planets actually
## change the world generation.

const PLANETS_DIR := "res://data/planets/"

## Every planet definition, ordered by file name (01_..., 02_...). That order is the
## carousel order, so renaming files reorders the wheel. Treat as read-only.
var planets: Array[PlanetData] = []

## The planet the player confirmed (defaults to the first one).
var selected_planet: PlanetData

func _ready() -> void:
	for path in _tres_files_in(PLANETS_DIR):
		var res: Resource = load(path)
		if res is PlanetData:
			planets.append(res)
	if not planets.is_empty():
		selected_planet = planets[0]

## Index of `selected_planet` in `planets`, or 0 if it isn't in the list.
func selected_index() -> int:
	var idx := planets.find(selected_planet)
	return idx if idx >= 0 else 0

## Returns the res:// paths of every .tres file directly inside `dir_path`, sorted by
## name so the carousel order is stable across platforms.
func _tres_files_in(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("PlanetDatabase: could not open %s" % dir_path)
		return result
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			result.append(dir_path + file_name)
	result.sort()
	return result
