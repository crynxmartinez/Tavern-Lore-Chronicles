extends Node

# MatchmakingManager Autoload
# Stub - using ENet multiplayer lobby instead

signal matchmaking_started()
signal matchmaking_cancelled()
signal matchmaking_failed(error: String)
signal match_found(opponent_name: String, is_host: bool)
signal opponent_joined(opponent_name: String)
signal opponent_left()

enum MatchmakingState { IDLE, SEARCHING, FOUND, IN_BATTLE }

var state: MatchmakingState = MatchmakingState.IDLE
var is_host: bool = false

func _ready() -> void:
	print("MatchmakingManager: Using ENet multiplayer")

# Stub functions for compatibility
func start_matchmaking(_mode: String) -> void:
	# Redirect to ENet multiplayer lobby
	matchmaking_failed.emit("Use ENet Multiplayer Lobby instead")

func cancel_matchmaking() -> void:
	state = MatchmakingState.IDLE
	matchmaking_cancelled.emit()

func get_search_time() -> float:
	return 0.0

func get_state() -> MatchmakingState:
	return state

func is_searching() -> bool:
	return state == MatchmakingState.SEARCHING

func is_in_match() -> bool:
	return state == MatchmakingState.FOUND or state == MatchmakingState.IN_BATTLE

func is_connected_to_server() -> bool:
	return false

func is_connecting() -> bool:
	return false

func start_battle() -> void:
	state = MatchmakingState.IN_BATTLE

func leave_battle() -> void:
	state = MatchmakingState.IDLE
