extends Node

## Persistent audio controller (autoload singleton). Owns the looping menu music so it
## survives scene changes, and routes music/SFX through dedicated audio buses so the
## Settings screen can adjust or mute each independently -- live, while the music plays.
## Preferences persist to user://settings.cfg between runs.

const SETTINGS_PATH: String = "user://settings.cfg"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"
const MENU_MUSIC: AudioStream = preload("res://assets/music/main_menu.wav")
const BLIP_SFX: AudioStream = preload("res://assets/sounds/blip.wav")

## Current preferences. Volumes are 0..1 linear; the "enabled" flags map to bus mute.
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var music_enabled: bool = true
var sfx_enabled: bool = true

var _music_bus_idx: int
var _sfx_bus_idx: int
var _music_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer

func _ready() -> void:
	_music_bus_idx = _ensure_bus(MUSIC_BUS)
	_sfx_bus_idx = _ensure_bus(SFX_BUS)

	_music_player = AudioStreamPlayer.new()
	_music_player.stream = MENU_MUSIC
	_music_player.bus = MUSIC_BUS
	# The .wav isn't marked as looping on import, so re-play it when it ends.
	_music_player.finished.connect(_music_player.play)
	add_child(_music_player)

	# One-shot UI sound effect, routed through the SFX bus so the Settings screen's
	# SFX volume/mute controls it. Lives on the autoload so it keeps playing across
	# the scene change a button press may trigger (e.g. Play).
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.stream = BLIP_SFX
	_sfx_player.bus = SFX_BUS
	add_child(_sfx_player)

	_load_settings()
	_apply_bus(_music_bus_idx, music_volume, music_enabled)
	_apply_bus(_sfx_bus_idx, sfx_volume, sfx_enabled)
	play_music()

## Returns the index of the named bus, creating it (routed to Master) if it doesn't exist.
## Done in code so the project works without a hand-authored default_bus_layout.tres.
func _ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
	return idx

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_bus(_music_bus_idx, music_volume, music_enabled)
	_save_settings()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus(_sfx_bus_idx, sfx_volume, sfx_enabled)
	_save_settings()

func set_music_enabled(on: bool) -> void:
	music_enabled = on
	_apply_bus(_music_bus_idx, music_volume, music_enabled)
	_save_settings()

func set_sfx_enabled(on: bool) -> void:
	sfx_enabled = on
	_apply_bus(_sfx_bus_idx, sfx_volume, sfx_enabled)
	_save_settings()

func play_music() -> void:
	if not _music_player.playing:
		_music_player.play()

func stop_music() -> void:
	_music_player.stop()

## Plays the UI "blip" sound. Obeys the SFX bus volume/mute automatically.
func play_blip() -> void:
	_sfx_player.play()

## Maps a 0..1 linear volume onto the bus dB level and applies the mute toggle.
func _apply_bus(idx: int, volume: float, enabled: bool) -> void:
	AudioServer.set_bus_volume_db(idx, linear_to_db(volume))
	AudioServer.set_bus_mute(idx, not enabled)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # No saved settings yet -- keep defaults.
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	music_enabled = cfg.get_value("audio", "music_enabled", music_enabled)
	sfx_enabled = cfg.get_value("audio", "sfx_enabled", sfx_enabled)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.set_value("audio", "sfx_enabled", sfx_enabled)
	cfg.save(SETTINGS_PATH)
