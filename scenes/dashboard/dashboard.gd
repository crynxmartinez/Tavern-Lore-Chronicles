@tool
extends Control

enum GameMode { VS_AI, VS_NORMAL, VS_RANK }

var current_mode: GameMode = GameMode.VS_AI
var is_rotating: bool = false

@onready var background: TextureRect = $Background
@onready var top_navigation: TextureRect = $TopNavigation
@onready var mode_diamond: TextureButton = $ModeDiamond
@onready var mode_label: Label = $FindMatchButton/ModeLabel
@onready var find_match_button: TextureButton = $FindMatchButton
@onready var shop_button: TextureButton = $LeftMenu/ShopButton
@onready var team_button: TextureButton = $LeftMenu/TeamButton
@onready var collection_button: TextureButton = $LeftMenu/CollectionButton
@onready var username_label: Label = $UsernameLabel
@onready var stats_label: Label = $StatsLabel
@onready var profile_container: Control = $ProfileContainer
@onready var profile_pic: TextureRect = $ProfileContainer/ProfilePic
@onready var logout_button: Button = $LogoutButton
@onready var matchmaking_overlay: ColorRect = $MatchmakingOverlay
@onready var searching_label: Label = $MatchmakingOverlay/CenterContainer/Panel/VBoxContainer/SearchingLabel
@onready var timer_label: Label = $MatchmakingOverlay/CenterContainer/Panel/VBoxContainer/TimerLabel
@onready var status_label: Label = $MatchmakingOverlay/CenterContainer/Panel/VBoxContainer/StatusLabel
@onready var cancel_matchmaking_button: Button = $MatchmakingOverlay/CenterContainer/Panel/VBoxContainer/CancelButton

var vs_ai_texture: Texture2D
var vs_normal_texture: Texture2D
var vs_rank_texture: Texture2D

func _ready() -> void:
	vs_ai_texture = preload("res://asset/Others/Dashboard/VS AI.png")
	vs_normal_texture = preload("res://asset/Others/Dashboard/VS Normal.png")
	vs_rank_texture = preload("res://asset/Others/Dashboard/VS Rank.png")
	
	_update_mode_display()
	_update_player_profile()
	
	mode_diamond.pressed.connect(_on_mode_diamond_pressed)
	find_match_button.pressed.connect(_on_find_match_pressed)
	shop_button.pressed.connect(_on_shop_pressed)
	team_button.pressed.connect(_on_team_pressed)
	collection_button.pressed.connect(_on_collection_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	cancel_matchmaking_button.pressed.connect(_on_cancel_matchmaking_pressed)
	
	# Connect matchmaking signals
	if has_node("/root/MatchmakingManager"):
		var mm = get_node("/root/MatchmakingManager")
		mm.matchmaking_started.connect(_on_matchmaking_started)
		mm.matchmaking_cancelled.connect(_on_matchmaking_cancelled)
		mm.matchmaking_failed.connect(_on_matchmaking_failed)
		mm.match_found.connect(_on_match_found)

func _update_mode_display() -> void:
	match current_mode:
		GameMode.VS_AI:
			mode_diamond.texture_normal = vs_ai_texture
			mode_label.text = "TRAIN"
		GameMode.VS_NORMAL:
			mode_diamond.texture_normal = vs_normal_texture
			mode_label.text = "NORMAL"
		GameMode.VS_RANK:
			mode_diamond.texture_normal = vs_rank_texture
			mode_label.text = "RANKED"

func _on_mode_diamond_pressed() -> void:
	if Engine.is_editor_hint():
		return
	if is_rotating:
		return
	
	is_rotating = true
	
	# Set pivot to center of the diamond for proper rotation
	var diamond_size = mode_diamond.size
	mode_diamond.pivot_offset = diamond_size / 2
	
	# Rotate with Y-axis flip effect (scale X to 0, change texture, scale back)
	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(mode_diamond, "scale:x", 0.0, 0.15)
	await tween.finished
	
	# Change mode
	match current_mode:
		GameMode.VS_AI:
			current_mode = GameMode.VS_NORMAL
		GameMode.VS_NORMAL:
			current_mode = GameMode.VS_RANK
		GameMode.VS_RANK:
			current_mode = GameMode.VS_AI
	
	_update_mode_display()
	
	# Scale back
	var tween2 = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween2.tween_property(mode_diamond, "scale:x", 1.0, 0.2)
	await tween2.finished
	
	is_rotating = false

func _on_find_match_pressed() -> void:
	if Engine.is_editor_hint():
		return
	match current_mode:
		GameMode.VS_AI:
			SceneTransition.change_scene("res://scenes/battle/battle.tscn")
		GameMode.VS_NORMAL:
			# Use ENet multiplayer lobby for testing
			SceneTransition.change_scene("res://scenes/ui/multiplayer_lobby.tscn")
		GameMode.VS_RANK:
			_start_matchmaking("ranked")

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	# Update matchmaking timer display
	if matchmaking_overlay.visible and has_node("/root/MatchmakingManager"):
		var mm = get_node("/root/MatchmakingManager")
		if mm.is_searching():
			var elapsed = mm.get_search_time()
			var minutes = int(elapsed) / 60
			var seconds = int(elapsed) % 60
			timer_label.text = "%d:%02d" % [minutes, seconds]

# ============================================
# MATCHMAKING
# ============================================

func _start_matchmaking(mode: String) -> void:
	if not has_node("/root/MatchmakingManager"):
		_show_matchmaking_error("Matchmaking not available")
		return
	
	var mm = get_node("/root/MatchmakingManager")
	
	# Check connection status
	if mm.is_connecting():
		_show_matchmaking_error("Connecting to server... Please wait a moment and try again.")
		return
	
	if not mm.is_connected_to_server():
		_show_matchmaking_error("Not connected to server. Please check your internet connection and restart the game.")
		return
	
	mm.start_matchmaking(mode)

func _on_cancel_matchmaking_pressed() -> void:
	if has_node("/root/MatchmakingManager"):
		get_node("/root/MatchmakingManager").cancel_matchmaking()

func _on_matchmaking_started() -> void:
	matchmaking_overlay.visible = true
	searching_label.text = "Searching for opponent..."
	status_label.text = "Looking for available matches..."
	timer_label.text = "0:00"

func _on_matchmaking_cancelled() -> void:
	matchmaking_overlay.visible = false

func _on_matchmaking_failed(error: String) -> void:
	matchmaking_overlay.visible = false
	_show_matchmaking_error(error)

func _on_match_found(opponent_name: String, is_host: bool) -> void:
	searching_label.text = "Match Found!"
	status_label.text = "Opponent: " + opponent_name
	
	# Wait a moment then transition to battle
	await get_tree().create_timer(1.5).timeout
	
	matchmaking_overlay.visible = false
	
	# Start battle with multiplayer flag
	if has_node("/root/MatchmakingManager"):
		get_node("/root/MatchmakingManager").start_battle()
	
	# Pass multiplayer info to battle scene
	if has_node("/root/GameManager"):
		var gm = get_node("/root/GameManager")
		gm.is_multiplayer = true
		gm.is_host = is_host
	
	SceneTransition.change_scene("res://scenes/battle/battle.tscn")

func _show_matchmaking_error(error: String) -> void:
	# Create error popup
	var popup = Panel.new()
	popup.custom_minimum_size = Vector2(400, 80)
	popup.position = Vector2(get_viewport_rect().size.x / 2 - 200, 100)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.7, 0.2, 0.2, 0.9)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	popup.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.text = error
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(400, 80)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup.add_child(label)
	
	add_child(popup)
	
	var tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(popup, "modulate:a", 0.0, 0.5)
	tween.tween_callback(popup.queue_free)

func _on_shop_pressed() -> void:
	print("Shop pressed - Not implemented yet")

func _on_team_pressed() -> void:
	SceneTransition.change_scene("res://scenes/team_editor/team_editor.tscn")

func _on_collection_pressed() -> void:
	SceneTransition.change_scene("res://scenes/collection/collection_new.tscn")

func _update_player_profile() -> void:
	if Engine.is_editor_hint():
		return
	
	if not has_node("/root/PlayerData"):
		return
	
	var player_data = get_node("/root/PlayerData")
	
	# Update username
	if username_label:
		var display_name = player_data.username
		if player_data.is_guest:
			display_name += " (Guest)"
		username_label.text = display_name
	
	# Update stats
	if stats_label:
		var stats = player_data.get_stats_summary()
		var wins = stats.get("total_wins", 0)
		var losses = stats.get("total_losses", 0)
		var rate = stats.get("win_rate", 0.0)
		stats_label.text = "W: " + str(wins) + " | L: " + str(losses) + " | " + str(int(rate)) + "%"

func _on_logout_pressed() -> void:
	if Engine.is_editor_hint():
		return
	# Clear saved login credentials
	_clear_saved_login()
	# Logout and go to login screen
	if has_node("/root/AccountManager"):
		get_node("/root/AccountManager").logout()
	SceneTransition.change_scene("res://scenes/account/login.tscn")

func _clear_saved_login() -> void:
	var saved_login_path = "user://saved_login.dat"
	if FileAccess.file_exists(saved_login_path):
		DirAccess.remove_absolute(saved_login_path)
