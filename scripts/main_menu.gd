extends Control

## Main menu -- shown on startup. "Play" launches the game; "Settings" is a
## placeholder for a future settings screen.

func _ready() -> void:
	$VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	$VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$MusicPlayer.finished.connect($MusicPlayer.play)

func _on_play_pressed() -> void:
	$MusicPlayer.stop()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_settings_pressed() -> void:
	pass  # Not yet implemented.
