extends Node

# Audio Manager - Handles all game audio
# Add to autoload as "AudioManager"

# Audio buses
const MASTER_BUS = "Master"
const MUSIC_BUS = "Music"
const SFX_BUS = "SFX"
const UI_BUS = "UI"

# Music players
var music_player: AudioStreamPlayer
var music_crossfade_player: AudioStreamPlayer

# SFX pools for overlapping sounds
var sfx_pool: Array[AudioStreamPlayer] = []
var ui_pool: Array[AudioStreamPlayer] = []
const POOL_SIZE = 8

# Volume settings (0.0 to 1.0)
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 1.0
var ui_volume: float = 0.8

# Preloaded sounds - add your sound files here
var sounds: Dictionary = {
	# UI Sounds
	"ui_click": null,
	"ui_hover": null,
	"ui_back": null,
	
	# Card Sounds
	"card_draw": null,
	"card_play": null,
	"card_discard": null,
	"card_shuffle": null,
	
	# Battle Sounds
	"attack_hit": null,
	"attack_miss": null,
	"heal": null,
	"buff": null,
	"debuff": null,
	"shield": null,
	"critical": null,
	
	# Hero Sounds
	"hero_death": null,
	"hero_revive": null,
	
	# Turn Sounds
	"turn_start": null,
	"turn_end": null,
	"victory": null,
	"defeat": null,
}

func _ready() -> void:
	_setup_audio_buses()
	_setup_players()
	_preload_sounds()

func _setup_audio_buses() -> void:
	# Create audio buses if they don't exist
	# Note: You should set these up in Project Settings > Audio > Buses
	pass

func _setup_players() -> void:
	# Music players
	music_player = AudioStreamPlayer.new()
	music_player.bus = MUSIC_BUS
	add_child(music_player)
	
	music_crossfade_player = AudioStreamPlayer.new()
	music_crossfade_player.bus = MUSIC_BUS
	add_child(music_crossfade_player)
	
	# SFX pool
	for i in range(POOL_SIZE):
		var sfx = AudioStreamPlayer.new()
		sfx.bus = SFX_BUS
		add_child(sfx)
		sfx_pool.append(sfx)
	
	# UI pool
	for i in range(POOL_SIZE):
		var ui = AudioStreamPlayer.new()
		ui.bus = UI_BUS
		add_child(ui)
		ui_pool.append(ui)

func _preload_sounds() -> void:
	# Preload sound files if they exist
	var sound_paths = {
		"ui_click": "res://audio/sfx/ui_click.wav",
		"ui_hover": "res://audio/sfx/ui_hover.wav",
		"card_draw": "res://audio/sfx/card_draw.wav",
		"card_play": "res://audio/sfx/card_play.wav",
		"attack_hit": "res://audio/sfx/attack_hit.wav",
		"heal": "res://audio/sfx/heal.wav",
		"buff": "res://audio/sfx/buff.wav",
		"debuff": "res://audio/sfx/debuff.wav",
		"critical": "res://audio/sfx/critical.wav",
		"victory": "res://audio/sfx/victory.wav",
		"defeat": "res://audio/sfx/defeat.wav",
	}
	
	for key in sound_paths:
		var path = sound_paths[key]
		if ResourceLoader.exists(path):
			sounds[key] = load(path)

# ============================================
# MUSIC FUNCTIONS
# ============================================

func play_music(stream: AudioStream, fade_duration: float = 1.0) -> void:
	if music_player.playing:
		# Crossfade
		music_crossfade_player.stream = stream
		music_crossfade_player.volume_db = -80
		music_crossfade_player.play()
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(music_player, "volume_db", -80, fade_duration)
		tween.tween_property(music_crossfade_player, "volume_db", linear_to_db(music_volume), fade_duration)
		
		await tween.finished
		music_player.stop()
		
		# Swap players
		var temp = music_player
		music_player = music_crossfade_player
		music_crossfade_player = temp
	else:
		music_player.stream = stream
		music_player.volume_db = linear_to_db(music_volume)
		music_player.play()

func stop_music(fade_duration: float = 1.0) -> void:
	if music_player.playing:
		var tween = create_tween()
		tween.tween_property(music_player, "volume_db", -80, fade_duration)
		await tween.finished
		music_player.stop()

func pause_music() -> void:
	music_player.stream_paused = true

func resume_music() -> void:
	music_player.stream_paused = false

# ============================================
# SFX FUNCTIONS
# ============================================

func play_sfx(sound_name: String, pitch_variation: float = 0.0) -> void:
	var stream = sounds.get(sound_name)
	if stream == null:
		return
	
	var player = _get_available_player(sfx_pool)
	if player:
		player.stream = stream
		player.volume_db = linear_to_db(sfx_volume)
		if pitch_variation > 0:
			player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
		else:
			player.pitch_scale = 1.0
		player.play()

func play_ui(sound_name: String) -> void:
	var stream = sounds.get(sound_name)
	if stream == null:
		return
	
	var player = _get_available_player(ui_pool)
	if player:
		player.stream = stream
		player.volume_db = linear_to_db(ui_volume)
		player.pitch_scale = 1.0
		player.play()

func _get_available_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for player in pool:
		if not player.playing:
			return player
	# All busy, return first one (will interrupt)
	return pool[0]

# ============================================
# VOLUME CONTROL
# ============================================

func set_master_volume(value: float) -> void:
	master_volume = clamp(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER_BUS), linear_to_db(master_volume))

func set_music_volume(value: float) -> void:
	music_volume = clamp(value, 0.0, 1.0)
	music_player.volume_db = linear_to_db(music_volume)
	music_crossfade_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(value: float) -> void:
	sfx_volume = clamp(value, 0.0, 1.0)

func set_ui_volume(value: float) -> void:
	ui_volume = clamp(value, 0.0, 1.0)

# ============================================
# CONVENIENCE FUNCTIONS
# ============================================

func play_card_draw() -> void:
	play_sfx("card_draw", 0.1)

func play_card_play() -> void:
	play_sfx("card_play", 0.05)

func play_attack(is_critical: bool = false) -> void:
	if is_critical:
		play_sfx("critical")
	else:
		play_sfx("attack_hit", 0.1)

func play_heal() -> void:
	play_sfx("heal")

func play_buff() -> void:
	play_sfx("buff")

func play_debuff() -> void:
	play_sfx("debuff")

func play_victory() -> void:
	play_sfx("victory")

func play_defeat() -> void:
	play_sfx("defeat")

func play_button_click() -> void:
	play_ui("ui_click")

func play_button_hover() -> void:
	play_ui("ui_hover")
