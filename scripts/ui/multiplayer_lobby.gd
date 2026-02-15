extends Control

# Multiplayer Lobby UI
# Simple Host/Join interface for testing

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinContainer/JoinButton
@onready var ip_input: LineEdit = $VBoxContainer/JoinContainer/IPInput
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var back_button: Button = $VBoxContainer/BackButton

var enet_manager: Node = null

func _ready() -> void:
	# Get ENetMultiplayerManager autoload
	enet_manager = get_node_or_null("/root/ENetMultiplayerManager")
	
	if enet_manager == null:
		status_label.text = "ERROR: ENetMultiplayerManager not found!"
		return
	
	# Connect buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Connect ENet signals
	enet_manager.match_ready.connect(_on_match_ready)
	enet_manager.connection_failed.connect(_on_connection_failed)
	enet_manager.server_disconnected.connect(_on_server_disconnected)
	
	status_label.text = "Ready to connect..."

func _on_host_pressed() -> void:
	status_label.text = "Starting server..."
	host_button.disabled = true
	join_button.disabled = true
	
	var error = enet_manager.host_game()
	
	if error == OK:
		status_label.text = "Waiting for opponent to join...\nPort: 7777"
	else:
		status_label.text = "Failed to start server!"
		host_button.disabled = false
		join_button.disabled = false

func _on_join_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Please enter the host's IP address."
		return
	
	status_label.text = "Connecting to " + ip + "..."
	host_button.disabled = true
	join_button.disabled = true
	
	var error = enet_manager.join_game(ip)
	
	if error != OK:
		status_label.text = "Failed to connect!"
		host_button.disabled = false
		join_button.disabled = false

func _on_match_ready(is_host: bool, opponent_id: int) -> void:
	var role = "HOST" if is_host else "CLIENT"
	status_label.text = "Match ready! You are: " + role + "\nStarting battle..."
	
	# Wait a moment then start battle
	await get_tree().create_timer(1.0).timeout
	_start_battle()

func _start_battle() -> void:
	# Load battle scene
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

func _on_connection_failed() -> void:
	status_label.text = "Connection failed! Check IP and try again."
	host_button.disabled = false
	join_button.disabled = false

func _on_server_disconnected() -> void:
	status_label.text = "Server disconnected!"
	host_button.disabled = false
	join_button.disabled = false

func _on_back_pressed() -> void:
	enet_manager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/dashboard/dashboard.tscn")
