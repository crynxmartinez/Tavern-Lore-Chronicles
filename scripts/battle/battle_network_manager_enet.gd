extends Node
class_name BattleNetworkManagerENet

# BattleNetworkManager using Godot's built-in ENet
# Uses HOST-AUTHORITATIVE model:
#   - Host executes ALL game logic
#   - Guest sends ACTION REQUESTS to Host
#   - Host broadcasts ACTION RESULTS to Guest
#   - Both clients apply results identically

# Signals
signal opponent_team_received(team: Array)
signal opponent_rps_choice_received(choice: int)
signal action_request_received(request: Dictionary)
signal action_result_received(result: Dictionary)
signal opponent_mulligan_done(discarded_indices: Array)
signal opponent_turn_ended()
signal opponent_disconnected()
signal opponent_conceded()

var battle_scene = null
var is_multiplayer: bool = false
var is_host: bool = false
var opponent_id: int = -1
var my_id: int = -1

var opponent_team: Array = []
var my_team_sent: bool = false
var opponent_team_received_flag: bool = false

func _ready() -> void:
	# Connect to multiplayer signals
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func initialize(battle: Node, mp: bool, host: bool, opp_id: int) -> void:
	battle_scene = battle
	is_multiplayer = mp
	is_host = host
	opponent_id = opp_id
	my_id = multiplayer.get_unique_id()
	
	print("BattleNetworkManagerENet: Initialized")
	print("  - Is Multiplayer: ", is_multiplayer)
	print("  - Is Host: ", is_host)
	print("  - My ID: ", my_id)
	print("  - Opponent ID: ", opponent_id)

func _on_peer_disconnected(id: int) -> void:
	if id == opponent_id:
		print("BattleNetworkManagerENet: Opponent disconnected!")
		opponent_disconnected.emit()

# ============================================
# TEAM EXCHANGE
# ============================================

func send_team(team: Array) -> void:
	if not is_multiplayer:
		return
	
	print("BattleNetworkManagerENet: Sending team: ", team)
	my_team_sent = true
	
	_receive_team.rpc_id(opponent_id, team)

@rpc("any_peer", "reliable")
func _receive_team(team: Array) -> void:
	print("BattleNetworkManagerENet: Received opponent team: ", team)
	opponent_team = team
	opponent_team_received_flag = true
	opponent_team_received.emit(team)

# ============================================
# RPS (Rock Paper Scissors)
# ============================================

func send_rps_choice(choice: int) -> void:
	if not is_multiplayer:
		return
	
	print("BattleNetworkManagerENet: Sending RPS choice: ", choice)
	_receive_rps_choice.rpc_id(opponent_id, choice)

@rpc("any_peer", "reliable")
func _receive_rps_choice(choice: int) -> void:
	print("BattleNetworkManagerENet: Received opponent RPS choice: ", choice)
	opponent_rps_choice_received.emit(choice)

# ============================================
# HOST-AUTHORITATIVE: Action Requests (Guest -> Host)
# ============================================

func send_action_request(request: Dictionary) -> void:
	## GUEST ONLY: Send action request to Host
	if not is_multiplayer:
		return
	
	if is_host:
		push_warning("BattleNetworkManagerENet: Host should not send action requests!")
		return
	
	print("BattleNetworkManagerENet: [GUEST] Sending action request: ", request.get("action_type", "unknown"))
	
	# Convert to JSON for reliable serialization
	var json_str = JSON.stringify(request)
	_receive_action_request.rpc_id(opponent_id, json_str)

@rpc("any_peer", "reliable")
func _receive_action_request(json_str: String) -> void:
	## HOST ONLY: Receive action request from Guest
	if not is_host:
		push_warning("BattleNetworkManagerENet: Guest received action request!")
		return
	
	var request = JSON.parse_string(json_str)
	if request == null:
		request = {}
	
	print("BattleNetworkManagerENet: [HOST] Received action request: ", request.get("action_type", "unknown"))
	action_request_received.emit(request)

# ============================================
# HOST-AUTHORITATIVE: Action Results (Host -> Guest)
# ============================================

func send_action_result(result: Dictionary) -> void:
	## HOST ONLY: Send action result to Guest
	if not is_multiplayer:
		return
	
	if not is_host:
		push_warning("BattleNetworkManagerENet: Guest should not send action results!")
		return
	
	print("BattleNetworkManagerENet: [HOST] Sending action result: ", result.get("action_type", "unknown"))
	
	# Convert to JSON for reliable serialization
	var json_str = JSON.stringify(result)
	_receive_action_result.rpc_id(opponent_id, json_str)

@rpc("any_peer", "reliable")
func _receive_action_result(json_str: String) -> void:
	## GUEST ONLY: Receive action result from Host
	if is_host:
		push_warning("BattleNetworkManagerENet: Host received action result!")
		return
	
	var result = JSON.parse_string(json_str)
	if result == null:
		result = {}
	
	print("BattleNetworkManagerENet: [GUEST] Received action result: ", result.get("action_type", "unknown"))
	action_result_received.emit(result)

# ============================================
# MULLIGAN
# ============================================

func send_mulligan(discarded_indices: Array) -> void:
	if not is_multiplayer:
		return
	
	print("BattleNetworkManagerENet: Sending mulligan: ", discarded_indices)
	_receive_mulligan.rpc_id(opponent_id, discarded_indices)

@rpc("any_peer", "reliable")
func _receive_mulligan(discarded_indices: Array) -> void:
	print("BattleNetworkManagerENet: Received opponent mulligan: ", discarded_indices)
	opponent_mulligan_done.emit(discarded_indices)

# ============================================
# TURN END (Legacy - for non-host-authoritative)
# ============================================

func send_turn_end() -> void:
	if not is_multiplayer:
		return
	
	print("BattleNetworkManagerENet: Sending turn end")
	_receive_turn_end.rpc_id(opponent_id)

@rpc("any_peer", "reliable")
func _receive_turn_end() -> void:
	print("BattleNetworkManagerENet: Received turn end")
	opponent_turn_ended.emit()

# ============================================
# CONCEDE / GAME OVER
# ============================================

func send_concede() -> void:
	if not is_multiplayer:
		return
	
	print("BattleNetworkManagerENet: Sending concede to opponent")
	_receive_concede.rpc_id(opponent_id)

@rpc("any_peer", "reliable")
func _receive_concede() -> void:
	print("BattleNetworkManagerENet: Opponent conceded!")
	opponent_conceded.emit()
