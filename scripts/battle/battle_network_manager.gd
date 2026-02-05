extends Node
class_name BattleNetworkManager

# BattleNetworkManager
# Handles multiplayer synchronization for battles
# Uses HOST-AUTHORITATIVE model:
#   - Host executes ALL game logic
#   - Guest sends ACTION REQUESTS to Host
#   - Host broadcasts ACTION RESULTS to Guest
#   - Both clients apply results identically

# Signals (Legacy - kept for backwards compatibility)
signal opponent_action_received(action: Dictionary)  # Legacy - not used in Host-Authoritative
signal opponent_mulligan_done(discarded_indices: Array)
signal opponent_turn_ended()
signal opponent_disconnected()
signal sync_complete()
signal opponent_team_received(team: Array)
signal opponent_ready()

# HOST-AUTHORITATIVE signals
signal action_request_received(request: Dictionary)  # Host receives from Guest
signal action_result_received(result: Dictionary)    # Guest receives from Host

var _gdsync = null
var battle_scene = null
var battle_controller: BattleController = null  # NEW: Reference to battle controller
var is_multiplayer: bool = false
var is_host: bool = false
var opponent_client_id: int = -1

# Shared random seed for deterministic shuffling
var battle_seed: int = 0
var opponent_team: Array = []  # Opponent's hero team
var my_team_sent: bool = false
var opponent_team_received_flag: bool = false

func _ready() -> void:
	if has_node("/root/GDSync"):
		_gdsync = get_node("/root/GDSync")
		_setup_gdsync()

func _setup_gdsync() -> void:
	if _gdsync == null:
		return
	
	# Debug: Print our NodePath so we can verify it matches on both clients
	print("BattleNetworkManager: My NodePath is: ", get_path())
	
	# Expose functions for remote calls
	if _gdsync.has_method("expose_func"):
		_gdsync.expose_func(_receive_action)
		_gdsync.expose_func(_receive_mulligan)
		_gdsync.expose_func(_receive_turn_end)
		_gdsync.expose_func(_receive_initial_state)
		_gdsync.expose_func(_receive_game_over)
		_gdsync.expose_func(_receive_team)
		_gdsync.expose_func(_receive_ready)
		_gdsync.expose_func(_receive_action_request)  # HOST-AUTHORITATIVE: Guest -> Host
		_gdsync.expose_func(_receive_action_result)   # HOST-AUTHORITATIVE: Host -> Guest
		_gdsync.expose_func(_receive_rps_choice)      # RPS minigame sync
		print("BattleNetworkManager: Exposed all receive functions")
	
	# Connect disconnect signal
	if _gdsync.has_signal("client_left"):
		_gdsync.client_left.connect(_on_client_left)

func set_battle_controller(controller: BattleController) -> void:
	## NEW: Set reference to battle controller for applying remote actions
	battle_controller = controller

func initialize(battle: Node, multiplayer: bool, host: bool, opponent_id: int) -> void:
	battle_scene = battle
	is_multiplayer = multiplayer
	is_host = host
	opponent_client_id = opponent_id
	
	if is_multiplayer:
		print("BattleNetworkManager: Initialized - Host: ", is_host, " Opponent: ", opponent_id)

func set_battle_seed(seed_value: int) -> void:
	battle_seed = seed_value

# ============================================
# SENDING ACTIONS TO OPPONENT
# ============================================

func send_action(action: Dictionary) -> void:
	if not is_multiplayer or _gdsync == null:
		return
	
	print("BattleNetworkManager: Sending action: ", action.get("type", "unknown"))
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_action, [action])

# ============================================
# RPS (Rock Paper Scissors) SYNC
# ============================================

signal opponent_rps_choice_received(choice: int)

func send_rps_choice(choice: int) -> void:
	if not is_multiplayer or _gdsync == null:
		return
	
	print("BattleNetworkManager: Sending RPS choice: ", choice)
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_rps_choice, [choice])

func _receive_rps_choice(choice) -> void:
	var actual_choice = choice
	if choice is Array and choice.size() == 1:
		actual_choice = choice[0]
	
	print("BattleNetworkManager: Received opponent RPS choice: ", actual_choice)
	opponent_rps_choice_received.emit(actual_choice)

func send_mulligan(discarded_indices: Array) -> void:
	if not is_multiplayer or _gdsync == null:
		return
	
	print("BattleNetworkManager: Sending mulligan: ", discarded_indices)
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_mulligan, [discarded_indices])

func send_turn_end() -> void:
	if not is_multiplayer or _gdsync == null:
		return
	
	print("BattleNetworkManager: Sending turn end")
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_turn_end, [])

func send_initial_state(state: Dictionary) -> void:
	if not is_multiplayer or _gdsync == null:
		return
	
	print("BattleNetworkManager: Sending initial state")
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_initial_state, [state])

func send_game_over(winner_is_host: bool) -> void:
	if not is_multiplayer or _gdsync == null:
		return
	
	print("BattleNetworkManager: Sending game over - Host won: ", winner_is_host)
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_game_over, [winner_is_host])

func send_team(team: Array) -> void:
	if not is_multiplayer or _gdsync == null:
		return
	
	print("BattleNetworkManager: Sending my team: ", team)
	my_team_sent = true
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_team, [team])

func send_ready() -> void:
	if not is_multiplayer or _gdsync == null:
		return
	
	print("BattleNetworkManager: Sending ready signal")
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_ready, [])

# ============================================
# HOST-AUTHORITATIVE SYSTEM
# ============================================

func send_action_request(request: Dictionary) -> void:
	## GUEST ONLY: Send action request to Host for execution
	if not is_multiplayer or _gdsync == null:
		return
	
	if is_host:
		push_warning("BattleNetworkManager: Host should not send action requests!")
		return
	
	print("BattleNetworkManager: [GUEST] Sending action request: ", request.get("action_type", "unknown"))
	
	# FLATTEN the request to avoid nested dictionary serialization issues
	# Convert card_data to JSON string for safe transmission
	var card_data = request.get("card_data", {})
	var card_data_json = JSON.stringify(card_data)
	
	var flat_request = {
		"action_type": request.get("action_type", ""),
		"card_data_json": card_data_json,  # Card data as JSON string
		"source_hero_id": request.get("source_hero_id", ""),
		"target_hero_id": request.get("target_hero_id", ""),
		"target_is_enemy": request.get("target_is_enemy", false),
		"timestamp": request.get("timestamp", 0)
	}
	
	print("BattleNetworkManager: [GUEST] Flat request - card_data_json length: ", card_data_json.length())
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_action_request, [flat_request])

func send_action_result(result: Dictionary) -> void:
	## HOST ONLY: Send action result to Guest after execution
	if not is_multiplayer or _gdsync == null:
		print("BattleNetworkManager: Cannot send - multiplayer:", is_multiplayer, " gdsync:", _gdsync != null)
		return
	
	if not is_host:
		push_warning("BattleNetworkManager: Guest should not send action results!")
		return
	
	print("BattleNetworkManager: [HOST] Sending action result: ", result.get("action_type", "unknown"), " to opponent: ", opponent_client_id)
	
	# FLATTEN the result to avoid nested dictionary serialization issues
	# Convert effects array to JSON string for safe transmission
	var effects = result.get("effects", [])
	var effects_json = JSON.stringify(effects)
	
	var flat_result = {
		"type": "action_result",
		"action_type": result.get("action_type", ""),
		"card_name": result.get("card_name", ""),
		"card_type": result.get("card_type", ""),
		"source_hero_id": result.get("source_hero_id", ""),
		"target_hero_id": result.get("target_hero_id", ""),
		"target_is_enemy": result.get("target_is_enemy", false),
		"whose_turn_ended": result.get("whose_turn_ended", ""),
		"success": result.get("success", true),
		"effects_json": effects_json  # Effects as JSON string to avoid serialization issues
	}
	
	print("BattleNetworkManager: [HOST] Flat result keys: ", flat_result.keys())
	print("BattleNetworkManager: [HOST] Effects JSON: ", effects_json)
	
	if _gdsync.has_method("call_func_on"):
		_gdsync.call_func_on(opponent_client_id, _receive_action, [flat_result])
		print("BattleNetworkManager: [HOST] Sent flat result via _receive_action")

# ============================================
# RECEIVING ACTIONS FROM OPPONENT
# ============================================

func _receive_action(action) -> void:
	# GD-Sync may wrap parameters - handle both Dictionary and Array
	var actual_action = action
	if action is Array and action.size() == 1:
		actual_action = action[0]
	
	var action_type = actual_action.get("type", "unknown")
	print("BattleNetworkManager: Received action: ", action_type)
	
	# HOST-AUTHORITATIVE: Check if this is a wrapped action_result
	if action_type == "action_result":
		var result = actual_action.get("result", {})
		print("BattleNetworkManager: Unwrapped action_result, forwarding to handler")
		_handle_action_result(result)
		return
	
	# Legacy: emit for old system
	opponent_action_received.emit(actual_action)

func _handle_action_result(result: Dictionary) -> void:
	## Process action result received from Host (via _receive_action wrapper)
	print("BattleNetworkManager: _handle_action_result called, is_host=", is_host)
	
	if is_host:
		push_warning("BattleNetworkManager: Host received action result - ignoring")
		return
	
	# Parse effects from JSON string back to array
	var effects_json = result.get("effects_json", "[]")
	var effects = JSON.parse_string(effects_json)
	if effects == null:
		effects = []
	
	# Reconstruct the result with parsed effects
	var parsed_result = {
		"action_type": result.get("action_type", ""),
		"card_name": result.get("card_name", ""),
		"card_type": result.get("card_type", ""),
		"source_hero_id": result.get("source_hero_id", ""),
		"target_hero_id": result.get("target_hero_id", ""),
		"target_is_enemy": result.get("target_is_enemy", false),
		"whose_turn_ended": result.get("whose_turn_ended", ""),
		"success": result.get("success", true),
		"effects": effects
	}
	
	print("BattleNetworkManager: [GUEST] Processing action result: ", parsed_result.get("action_type", "unknown"))
	print("BattleNetworkManager: [GUEST] Parsed effects count: ", effects.size())
	
	action_result_received.emit(parsed_result)

func _receive_mulligan(discarded_indices) -> void:
	# GD-Sync may wrap parameters - unwrap if necessary
	var actual_indices = discarded_indices
	if discarded_indices is Array and discarded_indices.size() == 1 and discarded_indices[0] is Array:
		actual_indices = discarded_indices[0]
	print("BattleNetworkManager: Received mulligan: ", actual_indices)
	opponent_mulligan_done.emit(actual_indices)

func _receive_turn_end() -> void:
	print("BattleNetworkManager: Received turn end")
	opponent_turn_ended.emit()

func _receive_initial_state(state) -> void:
	# GD-Sync may wrap parameters - handle both Dictionary and Array
	var actual_state = state
	if state is Array and state.size() == 1:
		actual_state = state[0]
	print("BattleNetworkManager: Received initial state")
	battle_seed = actual_state.get("seed", 0)
	sync_complete.emit()

func _receive_game_over(winner_is_host) -> void:
	# GD-Sync may wrap parameters - unwrap if necessary
	var actual_winner_is_host = winner_is_host
	if winner_is_host is Array and winner_is_host.size() == 1:
		actual_winner_is_host = winner_is_host[0]
	print("BattleNetworkManager: Received game over - Host won: ", actual_winner_is_host)
	# Determine if we won based on whether we're host
	var we_won = (is_host == actual_winner_is_host)
	if battle_scene and battle_scene.has_method("_on_network_game_over"):
		battle_scene._on_network_game_over(we_won)

func _receive_team(team: Array) -> void:
	print("BattleNetworkManager: Received opponent team (raw): ", team)
	
	# GD-Sync wraps parameters in an array, so we may receive [[...]] instead of [...]
	# Unwrap if necessary
	var actual_team = team
	if team.size() == 1 and team[0] is Array:
		actual_team = team[0]
		print("BattleNetworkManager: Unwrapped nested array to: ", actual_team)
	
	opponent_team = actual_team
	opponent_team_received_flag = true
	opponent_team_received.emit(actual_team)

func _receive_ready() -> void:
	print("BattleNetworkManager: Opponent is ready")
	opponent_ready.emit()

func _receive_action_request(request) -> void:
	## HOST ONLY: Receive action request from Guest
	## Host will execute the action and send results back
	
	# GD-Sync may wrap parameters - unwrap if necessary
	var actual_request = request
	if request is Array and request.size() == 1:
		actual_request = request[0]
	
	print("BattleNetworkManager: [HOST] Received action request: ", actual_request.get("action_type", "unknown"))
	
	if not is_host:
		push_warning("BattleNetworkManager: Guest received action request - this should not happen!")
		return
	
	# Parse card_data from JSON string back to dictionary
	var card_data_json = actual_request.get("card_data_json", "{}")
	var card_data = JSON.parse_string(card_data_json)
	if card_data == null:
		card_data = {}
	
	# Reconstruct the request with parsed card_data
	var parsed_request = {
		"action_type": actual_request.get("action_type", ""),
		"card_data": card_data,
		"source_hero_id": actual_request.get("source_hero_id", ""),
		"target_hero_id": actual_request.get("target_hero_id", ""),
		"target_is_enemy": actual_request.get("target_is_enemy", false),
		"timestamp": actual_request.get("timestamp", 0)
	}
	
	print("BattleNetworkManager: [HOST] Parsed request - card_data keys: ", card_data.keys())
	
	# Emit signal for battle.gd to handle
	action_request_received.emit(parsed_request)

func _receive_action_result(result) -> void:
	## GUEST ONLY: Receive action result from Host
	## Guest will apply the results directly (no game logic execution)
	
	print("BattleNetworkManager: _receive_action_result CALLED! is_host=", is_host, " raw result type=", typeof(result))
	
	# GD-Sync may wrap parameters - unwrap if necessary
	var actual_result = result
	if result is Array and result.size() == 1:
		actual_result = result[0]
	elif result is Array and result.size() > 1:
		# GD-Sync might double-wrap, try to get the dictionary
		print("BattleNetworkManager: Result is array with ", result.size(), " elements")
		for i in range(result.size()):
			if result[i] is Dictionary:
				actual_result = result[i]
				break
	
	print("BattleNetworkManager: [GUEST] Received action result: ", actual_result.get("action_type", "unknown") if actual_result is Dictionary else "NOT A DICT")
	
	if is_host:
		push_warning("BattleNetworkManager: Host received action result - this should not happen!")
		return
	
	# Emit signal for battle.gd to apply results
	action_result_received.emit(actual_result)

func _on_client_left(client_id: int) -> void:
	if client_id == opponent_client_id:
		print("BattleNetworkManager: Opponent disconnected!")
		opponent_disconnected.emit()

# ============================================
# ACTION TYPES
# ============================================

func create_card_play_action(card_id: String, target_hero_id: String = "") -> Dictionary:
	return {
		"type": "play_card",
		"card_id": card_id,
		"target_hero_id": target_hero_id,
		"timestamp": Time.get_unix_time_from_system()
	}

func create_ex_skill_action(hero_id: String, target_hero_id: String = "") -> Dictionary:
	return {
		"type": "ex_skill",
		"hero_id": hero_id,
		"target_hero_id": target_hero_id,
		"timestamp": Time.get_unix_time_from_system()
	}

# ============================================
# INITIAL STATE SYNC (Host generates, sends to guest)
# ============================================

func generate_initial_state(player_team: Array, enemy_team: Array) -> Dictionary:
	# Generate a random seed for deterministic shuffling
	battle_seed = randi()
	
	return {
		"seed": battle_seed,
		"host_team": player_team,
		"guest_team": enemy_team,
		"timestamp": Time.get_unix_time_from_system()
	}

func get_deterministic_shuffle(array: Array) -> Array:
	# Use the battle seed for deterministic shuffling
	var rng = RandomNumberGenerator.new()
	rng.seed = battle_seed
	
	var shuffled = array.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var temp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = temp
	
	return shuffled
