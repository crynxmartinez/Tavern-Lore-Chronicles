extends Node

# ENetMultiplayerManager
# Handles multiplayer connections using Godot's built-in ENet
# For testing on same PC with 2 instances

signal connection_succeeded()
signal connection_failed()
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal match_ready(is_host: bool, opponent_id: int)

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 1  # 1v1 game

var is_multiplayer: bool = false
var is_host: bool = false
var opponent_id: int = -1
var my_id: int = -1

# Player identity (from PlayerData)
var my_player_id: String = ""  # My account UID
var my_username: String = ""  # My display name
var opponent_player_id: String = ""  # Opponent's account UID
var opponent_username: String = ""  # Opponent's display name
var _match_ready_emitted: bool = false  # Guard against double-fire

func _ready() -> void:
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _load_my_identity() -> void:
	if has_node("/root/PlayerData"):
		var pd = get_node("/root/PlayerData")
		my_player_id = pd.player_id
		my_username = pd.username
	else:
		my_player_id = "unknown_" + str(randi())
		my_username = "Player"
	# When testing locally (2 instances on same PC), both share the same PlayerData save.
	# Append peer role to make player_id unique per session.
	# This will be overwritten once we have proper separate accounts.
	if is_host:
		my_player_id = my_player_id + "_host"
		if my_username == "Player" or my_username == "Guest":
			my_username = my_username + " (Host)"
	else:
		my_player_id = my_player_id + "_client"
		if my_username == "Player" or my_username == "Guest":
			my_username = my_username + " (Client)"
	print("ENetMultiplayer: My identity - player_id: ", my_player_id, " username: ", my_username)

func host_game(port: int = DEFAULT_PORT) -> Error:
	"""Host a game server"""
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	
	if error != OK:
		print("ENetMultiplayer: Failed to create server: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	is_host = true
	my_id = multiplayer.get_unique_id()
	_load_my_identity()
	
	print("ENetMultiplayer: Server started on port ", port)
	print("ENetMultiplayer: My ID: ", my_id, " (Host)")
	
	return OK

func join_game(ip: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	"""Join an existing game"""
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	
	if error != OK:
		print("ENetMultiplayer: Failed to create client: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	is_host = false
	_load_my_identity()
	
	print("ENetMultiplayer: Connecting to ", ip, ":", port)
	
	return OK

func disconnect_game() -> void:
	"""Disconnect from current game"""
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	
	is_multiplayer = false
	is_host = false
	opponent_id = -1
	my_id = -1
	_match_ready_emitted = false
	
	print("ENetMultiplayer: Disconnected")

func _on_peer_connected(id: int) -> void:
	print("ENetMultiplayer: Peer connected: ", id)
	
	if is_host:
		# Host: the connected peer is our opponent
		opponent_id = id
		print("ENetMultiplayer: Opponent joined! ID: ", opponent_id)
	
	# Exchange player identity with the new peer
	_send_identity.rpc_id(id, my_player_id, my_username)
	
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("ENetMultiplayer: Peer disconnected: ", id)
	
	if id == opponent_id:
		opponent_id = -1
	
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	opponent_id = 1  # Server is always ID 1
	
	print("ENetMultiplayer: Connected to server!")
	print("ENetMultiplayer: My ID: ", my_id, " (Client)")
	print("ENetMultiplayer: Opponent (Host) ID: ", opponent_id)
	
	connection_succeeded.emit()
	
	# Send our identity to the host
	_send_identity.rpc_id(opponent_id, my_player_id, my_username)

@rpc("any_peer", "reliable")
func _send_identity(player_id: String, username: String) -> void:
	opponent_player_id = player_id
	opponent_username = username
	print("ENetMultiplayer: Received opponent identity - player_id: ", opponent_player_id, " username: ", opponent_username)
	
	# Defer the signal emit so listeners run in a clean frame context (not inside RPC)
	_emit_match_ready.call_deferred()

func _emit_match_ready() -> void:
	if _match_ready_emitted:
		print("ENetMultiplayer: match_ready already emitted, skipping")
		return
	_match_ready_emitted = true
	print("ENetMultiplayer: Emitting match_ready (deferred) - is_host: ", is_host, " opponent_id: ", opponent_id)
	match_ready.emit(is_host, opponent_id)

func _on_connection_failed() -> void:
	print("ENetMultiplayer: Connection failed!")
	is_multiplayer = false
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("ENetMultiplayer: Server disconnected!")
	is_multiplayer = false
	opponent_id = -1
	server_disconnected.emit()

func get_opponent_id() -> int:
	return opponent_id

func get_my_id() -> int:
	return my_id
