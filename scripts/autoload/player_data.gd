extends Node

# PlayerData Autoload
# Manages player profile, stats, settings, and saved teams
# Saves locally to user:// folder

signal data_loaded()
signal data_saved()
signal stats_updated()
signal profile_updated()

const SAVE_PATH = "user://player_data.save"
const VERSION = 1  # For future data migration

# ============================================
# PLAYER PROFILE
# ============================================
var player_id: String = ""  # Unique identifier
var username: String = "Player"  # Display name
var avatar_id: int = 0  # Avatar selection (0 = default)
var created_at: int = 0  # Unix timestamp of account creation
var last_login: int = 0  # Unix timestamp of last login

# ============================================
# PLAYER STATS
# ============================================
var total_wins: int = 0
var total_losses: int = 0
var total_games: int = 0
var current_win_streak: int = 0
var best_win_streak: int = 0
var pvp_wins: int = 0
var pvp_losses: int = 0
var ai_wins: int = 0
var ai_losses: int = 0

# ============================================
# SAVED TEAM LOADOUTS (up to 3 slots)
# ============================================
var saved_teams: Array = []  # Array of {name, heroes, equipment}

# ============================================
# SETTINGS
# ============================================
var settings: Dictionary = {
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"ui_volume": 1.0,
	"screen_shake": true,
	"show_damage_numbers": true,
	"auto_end_turn": false,
	"confirm_card_play": false,
	"language": "en"
}

# ============================================
# ONLINE STATUS
# ============================================
var is_logged_in: bool = false
var is_guest: bool = true  # True if playing without account
var user_id: String = ""  # User ID when logged in

# ============================================
# INITIALIZATION
# ============================================
func _ready() -> void:
	load_data()
	
	# Generate player_id if first time
	if player_id.is_empty():
		player_id = _generate_player_id()
		created_at = int(Time.get_unix_time_from_system())
		save_data()
	
	# Update last login
	last_login = int(Time.get_unix_time_from_system())
	save_data()
	
	print("PlayerData: Initialized - ID: ", player_id, " Username: ", username)

func _generate_player_id() -> String:
	# Generate a unique local player ID
	var chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	var result = "local_"
	for i in range(12):
		result += chars[randi() % chars.length()]
	return result

# ============================================
# PROFILE FUNCTIONS
# ============================================
func set_username(new_username: String) -> void:
	username = new_username.strip_edges()
	if username.is_empty():
		username = "Player"
	save_data()
	profile_updated.emit()

func get_display_name() -> String:
	return username

func set_avatar(avatar_index: int) -> void:
	avatar_id = avatar_index
	save_data()
	profile_updated.emit()

# ============================================
# STATS FUNCTIONS
# ============================================
func record_win(is_pvp: bool = false) -> void:
	total_wins += 1
	total_games += 1
	current_win_streak += 1
	
	if current_win_streak > best_win_streak:
		best_win_streak = current_win_streak
	
	if is_pvp:
		pvp_wins += 1
	else:
		ai_wins += 1
	
	save_data()
	stats_updated.emit()

func record_loss(is_pvp: bool = false) -> void:
	total_losses += 1
	total_games += 1
	current_win_streak = 0
	
	if is_pvp:
		pvp_losses += 1
	else:
		ai_losses += 1
	
	save_data()
	stats_updated.emit()

func get_win_rate() -> float:
	if total_games == 0:
		return 0.0
	return float(total_wins) / float(total_games) * 100.0

func get_pvp_win_rate() -> float:
	var pvp_total = pvp_wins + pvp_losses
	if pvp_total == 0:
		return 0.0
	return float(pvp_wins) / float(pvp_total) * 100.0

func get_stats_summary() -> Dictionary:
	return {
		"total_wins": total_wins,
		"total_losses": total_losses,
		"total_games": total_games,
		"win_rate": get_win_rate(),
		"current_streak": current_win_streak,
		"best_streak": best_win_streak,
		"pvp_wins": pvp_wins,
		"pvp_losses": pvp_losses,
		"ai_wins": ai_wins,
		"ai_losses": ai_losses
	}

# ============================================
# SAVED TEAMS FUNCTIONS
# ============================================
func save_team_loadout(slot_index: int, name: String, heroes: Array, equipment: Array) -> bool:
	if slot_index < 0 or slot_index > 2:
		return false
	
	var loadout = {
		"name": name,
		"heroes": heroes.duplicate(),
		"equipment": equipment.duplicate(),
		"saved_at": int(Time.get_unix_time_from_system())
	}
	
	# Expand array if needed
	while saved_teams.size() <= slot_index:
		saved_teams.append(null)
	
	saved_teams[slot_index] = loadout
	save_data()
	return true

func get_team_loadout(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= saved_teams.size():
		return {}
	if saved_teams[slot_index] == null:
		return {}
	return saved_teams[slot_index]

func delete_team_loadout(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < saved_teams.size():
		saved_teams[slot_index] = null
		save_data()

func get_all_team_loadouts() -> Array:
	return saved_teams

# ============================================
# SETTINGS FUNCTIONS
# ============================================
func get_setting(key: String, default_value = null):
	return settings.get(key, default_value)

func set_setting(key: String, value) -> void:
	settings[key] = value
	save_data()
	
	# Apply audio settings immediately
	if key in ["master_volume", "music_volume", "sfx_volume", "ui_volume"]:
		_apply_audio_settings()

func _apply_audio_settings() -> void:
	# Apply to AudioManager if it exists
	if has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		if audio.has_method("set_master_volume"):
			audio.set_master_volume(settings.get("master_volume", 1.0))
		if audio.has_method("set_music_volume"):
			audio.set_music_volume(settings.get("music_volume", 0.8))
		if audio.has_method("set_sfx_volume"):
			audio.set_sfx_volume(settings.get("sfx_volume", 1.0))

# ============================================
# SAVE / LOAD
# ============================================
func save_data() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"version": VERSION,
			"player_id": player_id,
			"username": username,
			"avatar_id": avatar_id,
			"created_at": created_at,
			"last_login": last_login,
			"total_wins": total_wins,
			"total_losses": total_losses,
			"total_games": total_games,
			"current_win_streak": current_win_streak,
			"best_win_streak": best_win_streak,
			"pvp_wins": pvp_wins,
			"pvp_losses": pvp_losses,
			"ai_wins": ai_wins,
			"ai_losses": ai_losses,
			"saved_teams": saved_teams,
			"settings": settings,
			"is_guest": is_guest,
			"user_id": user_id
		}
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		data_saved.emit()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("PlayerData: No save file found, using defaults")
		return
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			var data = json.get_data()
			_load_from_dict(data)
			print("PlayerData: Loaded from ", SAVE_PATH)
			data_loaded.emit()
		else:
			push_error("PlayerData: Failed to parse save file - " + json.get_error_message())

func _load_from_dict(data: Dictionary) -> void:
	# Profile
	player_id = data.get("player_id", "")
	username = data.get("username", "Player")
	avatar_id = data.get("avatar_id", 0)
	created_at = data.get("created_at", 0)
	last_login = data.get("last_login", 0)
	
	# Stats
	total_wins = data.get("total_wins", 0)
	total_losses = data.get("total_losses", 0)
	total_games = data.get("total_games", 0)
	current_win_streak = data.get("current_win_streak", 0)
	best_win_streak = data.get("best_win_streak", 0)
	pvp_wins = data.get("pvp_wins", 0)
	pvp_losses = data.get("pvp_losses", 0)
	ai_wins = data.get("ai_wins", 0)
	ai_losses = data.get("ai_losses", 0)
	
	# Saved teams
	saved_teams = data.get("saved_teams", [])
	
	# Settings (merge with defaults to handle new settings)
	var loaded_settings = data.get("settings", {})
	for key in loaded_settings:
		settings[key] = loaded_settings[key]
	
	# Online status
	is_guest = data.get("is_guest", true)
	user_id = data.get("user_id", data.get("gdsync_user_id", ""))

# ============================================
# DATA EXPORT
# ============================================
func export_to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"player_id": player_id,
		"username": username,
		"avatar_id": avatar_id,
		"created_at": created_at,
		"total_wins": total_wins,
		"total_losses": total_losses,
		"total_games": total_games,
		"current_win_streak": current_win_streak,
		"best_win_streak": best_win_streak,
		"pvp_wins": pvp_wins,
		"pvp_losses": pvp_losses,
		"ai_wins": ai_wins,
		"ai_losses": ai_losses,
		"saved_teams": saved_teams,
		"settings": settings
	}

func import_from_dict(data: Dictionary) -> void:
	_load_from_dict(data)
	save_data()
	data_loaded.emit()

# ============================================
# RESET (for testing or new account)
# ============================================
func reset_stats() -> void:
	total_wins = 0
	total_losses = 0
	total_games = 0
	current_win_streak = 0
	best_win_streak = 0
	pvp_wins = 0
	pvp_losses = 0
	ai_wins = 0
	ai_losses = 0
	save_data()
	stats_updated.emit()

func reset_all() -> void:
	player_id = _generate_player_id()
	username = "Player"
	avatar_id = 0
	created_at = int(Time.get_unix_time_from_system())
	last_login = created_at
	reset_stats()
	saved_teams = []
	settings = {
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 1.0,
		"ui_volume": 1.0,
		"screen_shake": true,
		"show_damage_numbers": true,
		"auto_end_turn": false,
		"confirm_card_play": false,
		"language": "en"
	}
	is_guest = true
	user_id = ""
	save_data()
	profile_updated.emit()
