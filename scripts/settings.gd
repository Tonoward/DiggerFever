extends Control

## Settings screen -- toggle and adjust the Music and Sound Effects volumes. Every
## change is applied live through the AudioManager autoload (so the menu music you can
## hear reacts immediately) and persisted between runs. "Back" returns to the main menu.

@onready var _music_toggle: CheckButton = $VBoxContainer/MusicRow/MusicToggle
@onready var _music_slider: HSlider = $VBoxContainer/MusicSlider
@onready var _sfx_toggle: CheckButton = $VBoxContainer/SfxRow/SfxToggle
@onready var _sfx_slider: HSlider = $VBoxContainer/SfxSlider
@onready var _back_button: Button = $VBoxContainer/BackButton

func _ready() -> void:
	# Seed the controls from the currently active settings.
	_music_toggle.button_pressed = AudioManager.music_enabled
	_music_slider.value = AudioManager.music_volume
	_music_slider.editable = AudioManager.music_enabled
	_sfx_toggle.button_pressed = AudioManager.sfx_enabled
	_sfx_slider.value = AudioManager.sfx_volume
	_sfx_slider.editable = AudioManager.sfx_enabled

	_music_toggle.toggled.connect(_on_music_toggled)
	_music_slider.value_changed.connect(AudioManager.set_music_volume)
	_sfx_toggle.toggled.connect(_on_sfx_toggled)
	_sfx_slider.value_changed.connect(AudioManager.set_sfx_volume)
	_back_button.pressed.connect(_on_back_pressed)

	# UI blip feedback on every button press. The SFX toggle applies its new mute
	# state (via toggled) before pressed fires, so turning SFX off stays silent.
	_music_toggle.pressed.connect(AudioManager.play_blip)
	_sfx_toggle.pressed.connect(AudioManager.play_blip)
	_back_button.pressed.connect(AudioManager.play_blip)

func _on_music_toggled(on: bool) -> void:
	AudioManager.set_music_enabled(on)
	_music_slider.editable = on

func _on_sfx_toggled(on: bool) -> void:
	AudioManager.set_sfx_enabled(on)
	_sfx_slider.editable = on

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
