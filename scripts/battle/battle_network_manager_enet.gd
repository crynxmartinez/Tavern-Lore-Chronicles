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

func _get_enet_manager():
	if has_node("/root/ENetMultiplayerManager"):
		return get_node("/root/ENetMultiplayerManager")
	return null

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
	
	# Stamp with match_id and action_id
	var enet = _get_enet_manager()
	if enet:
		request["match_id"] = enet.match_id
		request["action_id"] = enet.next_action_id()
	
	var action = request.get("action_type", "unknown")
	print("\n=== NET [GUEST→HOST] ACTION REQUEST ===")
	print("  action_type: ", action)
	if action == "play_card":
		print("  card_name: ", request.get("card_data", {}).get("name", "?"))
		print("  card_type: ", request.get("card_data", {}).get("type", "?"))
		print("  source_hero_id: ", request.get("source_hero_id", "?"))
		print("  target_hero_id: ", request.get("target_hero_id", "?"))
		print("  target_is_enemy: ", request.get("target_is_enemy", "?"))
	elif action == "use_ex_skill":
		print("  source_hero_id: ", request.get("source_hero_id", "?"))
		print("  target_hero_id: ", request.get("target_hero_id", "?"))
		print("  target_is_enemy: ", request.get("target_is_enemy", "?"))
	print("==================================\n")
	
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
		print("BattleNetworkManagerENet: [HOST] ERROR - Failed to parse action request JSON!")
		print("  Raw JSON: ", json_str.substr(0, 200))
		request = {}
		return
	
	var action = request.get("action_type", "unknown")
	print("\n=== NET [HOST←GUEST] ACTION REQUEST RECEIVED ===")
	print("  action_type: ", action)
	if action == "play_card":
		print("  card_name: ", request.get("card_data", {}).get("name", "?"))
		print("  card_type: ", request.get("card_data", {}).get("type", "?"))
		print("  source_hero_id: ", request.get("source_hero_id", "?"))
		print("  target_hero_id: ", request.get("target_hero_id", "?"))
		print("  target_is_enemy: ", request.get("target_is_enemy", "?"))
	elif action == "use_ex_skill":
		print("  source_hero_id: ", request.get("source_hero_id", "?"))
		print("  target_hero_id: ", request.get("target_hero_id", "?"))
	print("================================================\n")
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
	
	# Stamp with match_id and action_id
	var enet = _get_enet_manager()
	if enet:
		result["match_id"] = enet.match_id
		result["action_id"] = enet.next_action_id()
	
	var action = result.get("action_type", "unknown")
	var effects = result.get("effects", [])
	print("\n=== NET [HOST→GUEST] ACTION RESULT ===")
	print("  action_type: ", action)
	print("  success: ", result.get("success", "?"))
	if action == "play_card":
		print("  card_name: ", result.get("card_name", "MISSING!"))
		print("  card_type: ", result.get("card_type", "MISSING!"))
		print("  source_hero_id: ", result.get("source_hero_id", "MISSING!"))
		print("  target_hero_id: ", result.get("target_hero_id", "MISSING!"))
		print("  target_is_enemy: ", result.get("target_is_enemy", "MISSING!"))
	print("  effects_count: ", effects.size())
	for i in range(effects.size()):
		var e = effects[i]
		print("    effect[", i, "]: type=", e.get("type", "?"), " hero_id=", e.get("hero_id", "?"), " is_host_hero=", e.get("is_host_hero", "MISSING!"))
		if e.get("type", "") == "damage":
			print("      amount=", e.get("amount", "?"), " new_hp=", e.get("new_hp", "?"))
		elif e.get("type", "") == "heal":
			print("      amount=", e.get("amount", "?"), " new_hp=", e.get("new_hp", "?"))
	print("======================================\n")
	
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
		print("BattleNetworkManagerENet: [GUEST] ERROR - Failed to parse action result JSON!")
		print("  Raw JSON: ", json_str.substr(0, 200))
		result = {}
		return
	
	var action = result.get("action_type", "unknown")
	var effects = result.get("effects", [])
	print("\n=== NET [GUEST←HOST] ACTION RESULT RECEIVED ===")
	print("  action_type: ", action)
	print("  success: ", result.get("success", "?"))
	if action == "play_card":
		print("  card_name: ", result.get("card_name", "MISSING!"))
		print("  card_type: ", result.get("card_type", "MISSING!"))
		print("  source_hero_id: ", result.get("source_hero_id", "MISSING!"))
		print("  target_hero_id: ", result.get("target_hero_id", "MISSING!"))
		print("  target_is_enemy: ", result.get("target_is_enemy", "MISSING!"))
	print("  effects_count: ", effects.size())
	for i in range(effects.size()):
		var e = effects[i]
		print("    effect[", i, "]: type=", e.get("type", "?"), " hero_id=", e.get("hero_id", "?"), " is_host_hero=", e.get("is_host_hero", "MISSING!"))
		if e.get("type", "") == "damage":
			print("      amount=", e.get("amount", "?"), " new_hp=", e.get("new_hp", "?"))
		elif e.get("type", "") == "heal":
			print("      amount=", e.get("amount", "?"), " new_hp=", e.get("new_hp", "?"))
	print("================================================\n")
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
