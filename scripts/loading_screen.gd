extends CanvasLayer

## Shown while the game world is being generated (see main_menu.gd's Play button).
##
## How it works: this screen instantiates Main itself and adds it to the tree as a second
## top-level scene, hidden underneath -- Main's own _ready() runs normally and generates the
## world exactly as it always has (see Main.generation_progress / generation_finished).
## Since this CanvasLayer's `layer` is higher than Main's HUD, it fully covers Main the whole
## time regardless of node order, so nothing shows through until generation is done. Once
## `generation_finished` fires, Main is promoted to the active scene and this one frees itself.

const MAIN_SCENE_PATH := "res://scenes/main.tscn"

@onready var _progress_bar: ProgressBar = $VBoxContainer/ProgressBar
@onready var _percent_label: Label = $VBoxContainer/PercentLabel

func _ready() -> void:
	var main_instance: Node = load(MAIN_SCENE_PATH).instantiate()
	main_instance.generation_progress.connect(_on_progress)
	main_instance.generation_finished.connect(_on_generation_finished.bind(main_instance))
	# Deferred: the tree root is still busy finishing this scene's own setup during _ready(),
	# and add_child() on it synchronously here would fail.
	get_tree().root.add_child.call_deferred(main_instance)

func _on_progress(fraction: float) -> void:
	var percent := roundi(clampf(fraction, 0.0, 1.0) * 100.0)
	_progress_bar.value = percent
	_percent_label.text = "%d%%" % percent

func _on_generation_finished(main_instance: Node) -> void:
	get_tree().current_scene = main_instance
	queue_free()
