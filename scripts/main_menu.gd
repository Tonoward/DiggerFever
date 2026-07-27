extends Control

## Main menu -- shown on startup. "Play" launches the game; "Settings" opens the
## settings screen. Menu music is owned by the AudioManager autoload so it keeps
## playing (and stays adjustable) across the menu <-> settings scene changes.

func _ready() -> void:
	$VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	$VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	AudioManager.play_music()

func _on_play_pressed() -> void:
	AudioManager.play_blip()
	AudioManager.stop_music()
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")

func _on_settings_pressed() -> void:
	AudioManager.play_blip()
	get_tree().change_scene_to_file("res://scenes/settings.tscn")
