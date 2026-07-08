extends Node

## Autoload singleton (registered in project.godot under [autoload]), so it exists for the
## whole game and is reachable anywhere as `MaterialDatabase`.
##
## Its whole job: at startup, load every MaterialData and ItemData resource from the data/
## folders into two arrays. The rest of the game reads these lists instead of hard-coding
## material paths -- so "adding a new material" just means dropping a new .tres in
## data/materials/, with no code changes.

const MATERIALS_DIR := "res://data/materials/"
const ITEMS_DIR := "res://data/items/"

## Every material / item definition, in no particular order. Treat as read-only.
var materials: Array[MaterialData] = []
var items: Array[ItemData] = []

func _ready() -> void:
	for path in _tres_files_in(MATERIALS_DIR):
		var res: Resource = load(path)
		if res is MaterialData:
			materials.append(res)
	for path in _tres_files_in(ITEMS_DIR):
		var res: Resource = load(path)
		if res is ItemData:
			items.append(res)

## Returns the res:// paths of every .tres file directly inside `dir_path`.
func _tres_files_in(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("MaterialDatabase: could not open %s" % dir_path)
		return result
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			result.append(dir_path + file_name)
	return result
