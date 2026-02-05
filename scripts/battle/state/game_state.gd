class_name GameState
extends RefCounted

## GameState - The single source of truth for the entire battle
## Contains all game data, fully serializable for network sync

# Battle phases
enum BattlePhase {
	INITIALIZING,
	MULLIGAN,
	PLAYING,
	GAME_OVER
}

# Battle identity
var battle_id: String = ""
var random_seed: int = 0  # For deterministic randomness

# Game mode
var is_multiplayer: bool = false
var is_ai_battle: bool = true  # true = vs AI, false = vs player

# Turn management
var turn_number: int = 1
var current_player_index: int = 0  # 0 = host/player1, 1 = guest/player2
var phase: BattlePhase = BattlePhase.INITIALIZING

# Players (always 2 players: index 0 and index 1)
var players: Array[PlayerState] = []

# Action history (for replays and reconnection)
var action_history: Array = []  # Array of serialized actions

# Win condition
var winner_index: int = -1  # -1 = no winner yet, 0 or 1 = winner
var game_over_reason: String = ""

# ============================================
# INITIALIZATION
# ============================================

static func create_new_battle(multiplayer: bool = false) -> GameState:
	var state = GameState.new()
	state.battle_id = _generate_battle_id()
	state.random_seed = randi()
	state.is_multiplayer = multiplayer
	state.is_ai_battle = not multiplayer
	state.turn_number = 1
	state.current_player_index = 0
	state.phase = BattlePhase.INITIALIZING
	return state

static func _generate_battle_id() -> String:
	return "battle_%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000]

func setup_players(player1_team: Array, player2_team: Array, player1_name: String = "Player", player2_name: String = "Opponent") -> void:
	## Setup both players with their teams
	players.clear()
	
	# Player 1 (host in multiplayer)
	var p1 = PlayerState.create_from_team(0, player1_team, player1_name, true)
	players.append(p1)
	
	# Player 2 (guest in multiplayer, AI in single player)
	var p2 = PlayerState.create_from_team(1, player2_team, player2_name, false)
	players.append(p2)

func setup_multiplayer_players(host_team: Array, guest_team: Array, host_name: String, guest_name: String, host_client_id: int, guest_client_id: int) -> void:
	## Setup players for multiplayer with client IDs
	players.clear()
	
	# Host (player index 0)
	var host = PlayerState.create_from_team(0, host_team, host_name, true)
	host.client_id = host_client_id
	players.append(host)
	
	# Guest (player index 1)
	var guest = PlayerState.create_from_team(1, guest_team, guest_name, false)
	guest.client_id = guest_client_id
	players.append(guest)

# ============================================
# PLAYER ACCESS
# ============================================

func get_current_player() -> PlayerState:
	if current_player_index < 0 or current_player_index >= players.size():
		return null
	return players[current_player_index]

func get_opponent_player() -> PlayerState:
	var opponent_index = 1 - current_player_index
	if opponent_index < 0 or opponent_index >= players.size():
		return null
	return players[opponent_index]

func get_player(index: int) -> PlayerState:
	if index < 0 or index >= players.size():
		return null
	return players[index]

func get_player_by_client_id(client_id: int) -> PlayerState:
	for player in players:
		if player.client_id == client_id:
			return player
	return null

func get_host() -> PlayerState:
	for player in players:
		if player.is_host:
			return player
	return players[0] if players.size() > 0 else null

func get_guest() -> PlayerState:
	for player in players:
		if not player.is_host:
			return player
	return players[1] if players.size() > 1 else null

# ============================================
# HERO ACCESS
# ============================================

func get_hero(hero_id: String, owner_index: int) -> HeroState:
	## Get a specific hero by ID and owner
	var player = get_player(owner_index)
	if player:
		return player.get_hero(hero_id)
	return null

func get_all_heroes() -> Array[HeroState]:
	## Get all heroes from both players
	var all_heroes: Array[HeroState] = []
	for player in players:
		for hero in player.heroes:
			all_heroes.append(hero)
	return all_heroes

func get_all_alive_heroes() -> Array[HeroState]:
	## Get all living heroes from both players
	var alive: Array[HeroState] = []
	for player in players:
		for hero in player.get_alive_heroes():
			alive.append(hero)
	return alive

func find_hero_by_id_any_player(hero_id: String) -> HeroState:
	## Find hero by ID across all players (use with caution - prefer get_hero with owner)
	for player in players:
		var hero = player.get_hero(hero_id)
		if hero:
			return hero
	return null

# ============================================
# TURN MANAGEMENT
# ============================================

func start_battle() -> void:
	## Start the battle (after mulligan phase)
	phase = BattlePhase.PLAYING
	turn_number = 1
	current_player_index = 0  # Host goes first
	
	# Start first player's turn
	var current = get_current_player()
	if current:
		current.start_turn()

func start_mulligan_phase() -> void:
	phase = BattlePhase.MULLIGAN

func end_mulligan_phase() -> void:
	start_battle()

func switch_turn() -> void:
	## Switch to the other player's turn
	# End current player's turn
	var current = get_current_player()
	if current:
		current.end_turn()
	
	# Switch player
	current_player_index = 1 - current_player_index
	
	# If back to player 0, increment turn number
	if current_player_index == 0:
		turn_number += 1
	
	# Increase max mana for new current player
	var new_current = get_current_player()
	if new_current:
		new_current.increase_max_mana()
		new_current.start_turn()

func is_player_turn(player_index: int) -> bool:
	return current_player_index == player_index

func is_current_player_host() -> bool:
	var current = get_current_player()
	return current != null and current.is_host

# ============================================
# WIN CONDITION
# ============================================

func check_win_condition() -> int:
	## Check if someone has won. Returns winner index or -1 if no winner.
	for i in range(players.size()):
		if not players[i].has_alive_heroes():
			# This player has no alive heroes - they lose
			winner_index = 1 - i
			phase = BattlePhase.GAME_OVER
			game_over_reason = "All heroes defeated"
			return winner_index
	return -1

func set_winner(index: int, reason: String = "") -> void:
	winner_index = index
	phase = BattlePhase.GAME_OVER
	game_over_reason = reason

func is_game_over() -> bool:
	return phase == BattlePhase.GAME_OVER

func get_winner() -> PlayerState:
	if winner_index < 0 or winner_index >= players.size():
		return null
	return players[winner_index]

# ============================================
# ACTION HISTORY
# ============================================

func record_action(action_data: Dictionary) -> void:
	## Record an action for history/replay
	action_history.append({
		"turn": turn_number,
		"player": current_player_index,
		"timestamp": Time.get_unix_time_from_system(),
		"action": action_data
	})

func get_action_history() -> Array:
	return action_history.duplicate(true)

func clear_action_history() -> void:
	action_history.clear()

# ============================================
# PERSPECTIVE HELPERS
# ============================================

func get_my_player_index(client_id: int) -> int:
	## Get player index for a given client ID
	for i in range(players.size()):
		if players[i].client_id == client_id:
			return i
	return -1

func get_opponent_index(my_index: int) -> int:
	return 1 - my_index

func is_my_hero(hero: HeroState, my_player_index: int) -> bool:
	return hero.owner_index == my_player_index

func is_enemy_hero(hero: HeroState, my_player_index: int) -> bool:
	return hero.owner_index != my_player_index

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	## Convert to Dictionary for network transmission
	var serialized_players = []
	for player in players:
		serialized_players.append(player.serialize())
	
	return {
		"battle_id": battle_id,
		"random_seed": random_seed,
		"is_multiplayer": is_multiplayer,
		"is_ai_battle": is_ai_battle,
		"turn_number": turn_number,
		"current_player_index": current_player_index,
		"phase": phase,
		"players": serialized_players,
		"action_history": action_history.duplicate(true),
		"winner_index": winner_index,
		"game_over_reason": game_over_reason
	}

func serialize_for_player(player_index: int) -> Dictionary:
	## Serialize with hidden info for opponent
	var serialized_players = []
	for i in range(players.size()):
		if i == player_index:
			serialized_players.append(players[i].serialize())
		else:
			serialized_players.append(players[i].serialize_for_opponent())
	
	return {
		"battle_id": battle_id,
		"random_seed": random_seed,
		"is_multiplayer": is_multiplayer,
		"is_ai_battle": is_ai_battle,
		"turn_number": turn_number,
		"current_player_index": current_player_index,
		"phase": phase,
		"players": serialized_players,
		"action_history": [],  # Don't send full history
		"winner_index": winner_index,
		"game_over_reason": game_over_reason
	}

static func deserialize(data: Dictionary) -> GameState:
	## Create GameState from Dictionary (received from network)
	var state = GameState.new()
	state.battle_id = data.get("battle_id", "")
	state.random_seed = data.get("random_seed", 0)
	state.is_multiplayer = data.get("is_multiplayer", false)
	state.is_ai_battle = data.get("is_ai_battle", true)
	state.turn_number = data.get("turn_number", 1)
	state.current_player_index = data.get("current_player_index", 0)
	state.phase = data.get("phase", BattlePhase.INITIALIZING)
	state.action_history = data.get("action_history", []).duplicate(true)
	state.winner_index = data.get("winner_index", -1)
	state.game_over_reason = data.get("game_over_reason", "")
	
	# Deserialize players
	state.players = []
	for player_data in data.get("players", []):
		state.players.append(PlayerState.deserialize(player_data))
	
	return state

func duplicate_state() -> GameState:
	## Create a deep copy of this game state
	return GameState.deserialize(serialize())

# ============================================
# DEBUG
# ============================================

func _to_string() -> String:
	var phase_names = ["INITIALIZING", "MULLIGAN", "PLAYING", "GAME_OVER"]
	var phase_str = phase_names[phase] if phase < phase_names.size() else "UNKNOWN"
	return "[GameState] Turn:%d Phase:%s CurrentPlayer:%d Winner:%d Players:%d" % [
		turn_number, phase_str, current_player_index, winner_index, players.size()
	]

func print_state() -> void:
	## Print detailed state for debugging
	print("=== GAME STATE ===")
	print("Battle ID: ", battle_id)
	print("Turn: ", turn_number)
	print("Phase: ", phase)
	print("Current Player: ", current_player_index)
	print("Multiplayer: ", is_multiplayer)
	print("")
	for player in players:
		print(player)
		for hero in player.heroes:
			print("  ", hero)
	print("==================")
