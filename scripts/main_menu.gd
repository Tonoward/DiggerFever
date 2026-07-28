extends Control

## Main menu -- shown on startup. "Play" goes to the planet selection screen (which then
## starts the game); "Settings" opens the settings screen. Menu music is owned by the
## AudioManager autoload so it keeps playing (and stays adjustable) across all of those
## scene changes.

func _ready() -> void:
	$VBoxContainer/PlayButton.pressed.connect(_on_play_pressed)
	$VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	AudioManager.play_music()

func _on_play_pressed() -> void:
	AudioManager.play_blip()
	# The music keeps playing through the planet selection; that screen stops it on Confirm.
	get_tree().change_scene_to_file("res://scenes/planet_select.tscn")

func _on_settings_pressed() -> void:
	AudioManager.play_blip()
	get_tree().change_scene_to_file("res://scenes/settings.tscn")
