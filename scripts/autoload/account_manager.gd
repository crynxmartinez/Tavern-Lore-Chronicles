extends Node

# AccountManager Autoload
# Handles local authentication

signal login_started()
signal login_success(username: String)
signal login_failed(error: String)
signal registration_started()
signal registration_success(username: String)
signal registration_failed(error: String)
signal logout_completed()
signal connected()

enum AuthState { LOGGED_OUT, LOGGING_IN, LOGGED_IN, REGISTERING }

var auth_state: AuthState = AuthState.LOGGED_OUT

func _ready() -> void:
	call_deferred("_deferred_init")

func _deferred_init() -> void:
	_restore_session()
	print("AccountManager: Using local mode")

func _restore_session() -> void:
	if has_node("/root/PlayerData"):
		var player_data = get_node("/root/PlayerData")
		if not player_data.is_guest and not player_data.user_id.is_empty():
			auth_state = AuthState.LOGGED_IN
			print("AccountManager: Local session restored for ", player_data.username)

# ============================================
# AUTHENTICATION
# ============================================

func login(username: String, _password: String) -> void:
	if auth_state == AuthState.LOGGING_IN:
		return
	
	auth_state = AuthState.LOGGING_IN
	login_started.emit()
	
	await get_tree().create_timer(0.3).timeout
	
	auth_state = AuthState.LOGGED_IN
	
	if has_node("/root/PlayerData"):
		var player_data = get_node("/root/PlayerData")
		player_data.username = username
		player_data.is_guest = false
		player_data.user_id = "local_" + username.to_lower()
		player_data.save_data()
	
	login_success.emit(username)
	print("AccountManager: Login successful - ", username)

func register(username: String, _password: String, _email: String = "") -> void:
	if auth_state == AuthState.REGISTERING:
		return
	
	auth_state = AuthState.REGISTERING
	registration_started.emit()
	
	await get_tree().create_timer(0.3).timeout
	
	auth_state = AuthState.LOGGED_IN
	
	if has_node("/root/PlayerData"):
		var player_data = get_node("/root/PlayerData")
		player_data.username = username
		player_data.is_guest = false
		player_data.user_id = "local_" + username.to_lower()
		player_data.reset_stats()
		player_data.save_data()
	
	registration_success.emit(username)
	print("AccountManager: Registration successful - ", username)

func logout() -> void:
	auth_state = AuthState.LOGGED_OUT
	
	if has_node("/root/PlayerData"):
		var player_data = get_node("/root/PlayerData")
		player_data.is_guest = true
		player_data.user_id = ""
		player_data.save_data()
	
	logout_completed.emit()
	print("AccountManager: Logged out")

func play_as_guest() -> void:
	auth_state = AuthState.LOGGED_IN
	
	if has_node("/root/PlayerData"):
		var player_data = get_node("/root/PlayerData")
		player_data.is_guest = true
		player_data.username = "Guest"
		player_data.save_data()
	
	login_success.emit("Guest")

# ============================================
# UTILITY
# ============================================

func is_logged_in() -> bool:
	return auth_state == AuthState.LOGGED_IN

func is_guest() -> bool:
	if has_node("/root/PlayerData"):
		return get_node("/root/PlayerData").is_guest
	return true

func get_username() -> String:
	if has_node("/root/PlayerData"):
		return get_node("/root/PlayerData").username
	return "Guest"
