class_name BattleController
extends RefCounted

## BattleController - Main orchestrator for the battle system
## Ties together State, Actions, Effects, Events, and Network

# Core systems
var game_state: GameState = null
var event_bus: BattleEventBus = null
var effect_pipeline: EffectPipeline = null
var network_manager = null  # BattleNetworkManager (optional, for multiplayer)

# Local player info
var local_player_index: int = 0
var local_client_id: int = -1

# Deck managers (for local player only)
var player_deck_manager = null  # Reference to existing DeckManager

# Callbacks for UI
var on_action_executed: Callable = Callable()
var on_state_changed: Callable = Callable()

# ============================================
# INITIALIZATION
# ============================================

static func create(bus: BattleEventBus = null) -> BattleController:
	var controller = BattleController.new()
	controller.event_bus = bus if bus else BattleEventBus.new()
	controller.effect_pipeline = EffectPipeline.create(controller.event_bus)
	controller.game_state = GameState.create_new_battle(false)
	return controller

static func create_multiplayer(bus: BattleEventBus, is_host: bool, my_client_id: int) -> BattleController:
	var controller = BattleController.new()
	controller.event_bus = bus if bus else BattleEventBus.new()
	controller.effect_pipeline = EffectPipeline.create(controller.event_bus)
	controller.game_state = GameState.create_new_battle(true)
	controller.local_player_index = 0 if is_host else 1
	controller.local_client_id = my_client_id
	return controller

func set_network_manager(manager) -> void:
	network_manager = manager

func set_deck_manager(manager) -> void:
	player_deck_manager = manager

# ============================================
# BATTLE SETUP
# ============================================

func setup_single_player_battle(player_team: Array, enemy_team: Array, player_name: String = "Player") -> void:
	## Setup a single player (vs AI) battle
	game_state.is_multiplayer = false
	game_state.is_ai_battle = true
	game_state.setup_players(player_team, enemy_team, player_name, "AI Opponent")
	local_player_index = 0

func setup_multiplayer_battle(host_team: Array, guest_team: Array, host_name: String, guest_name: String, host_client_id: int, guest_client_id: int) -> void:
	## Setup a multiplayer (PVP) battle
	game_state.is_multiplayer = true
	game_state.is_ai_battle = false
	game_state.setup_multiplayer_players(host_team, guest_team, host_name, guest_name, host_client_id, guest_client_id)

func start_battle() -> void:
	## Start the battle after setup
	game_state.start_battle()
	
	if event_bus:
		event_bus.emit_battle_start(game_state)
		event_bus.emit_turn_start(game_state.current_player_index, game_state.turn_number)
		
		# Emit initial mana for both players
		for player in game_state.players:
			event_bus.emit_mana_change(player.player_index, player.mana, player.max_mana)

# ============================================
# ACTION EXECUTION (Local Player)
# ============================================

func execute_action(action: BaseAction) -> BaseAction.ActionResult:
	## Execute an action locally and sync to network if multiplayer
	
	# Validate action
	var validation = action.validate(game_state)
	if not validation.is_valid:
		print("BattleController: Action validation failed - ", validation.error_message)
		if event_bus:
			event_bus.action_validated.emit(action.get_action_name(), false, validation.error_message)
		var failed_result = BaseAction.ActionResult.new()
		failed_result.success = false
		return failed_result
	
	# Execute action
	var result = action.execute(game_state, effect_pipeline, event_bus)
	
	if result.success:
		# Record action in history
		game_state.record_action(action.serialize())
		
		# Emit action executed event
		if event_bus:
			event_bus.action_executed.emit(action.get_action_name(), action.player_index, result.serialize())
		
		# Send to network if multiplayer
		if game_state.is_multiplayer and network_manager:
			_send_action_to_network(action, result)
		
		# Callback
		if on_action_executed.is_valid():
			on_action_executed.call(action, result)
	
	return result

func play_card(card_data: Dictionary, source_hero_id: String, target_hero_id: String, target_owner: int, hand_index: int = -1) -> BaseAction.ActionResult:
	## Convenience method to play a card
	var action = ActionFactory.create_play_card(local_player_index, card_data, source_hero_id, target_hero_id, target_owner, hand_index)
	return execute_action(action)

func use_ex_skill(source_hero_id: String, target_hero_id: String = "", target_owner: int = 0) -> BaseAction.ActionResult:
	## Convenience method to use EX skill
	var action = ActionFactory.create_use_ex_skill(local_player_index, source_hero_id, target_hero_id, target_owner)
	return execute_action(action)

func end_turn() -> BaseAction.ActionResult:
	## Convenience method to end turn
	var action = ActionFactory.create_end_turn(local_player_index)
	return execute_action(action)

# ============================================
# ACTION EXECUTION (From Network)
# ============================================

func apply_remote_action(action_data: Dictionary, result_data: Dictionary) -> void:
	## Apply an action received from the network
	## Uses the result data directly instead of re-executing
	
	print("BattleController: Applying remote action: ", action_data.get("action_type", "unknown"))
	
	# Create action from data
	var action = ActionFactory.create_from_data(action_data)
	if action == null:
		push_error("BattleController: Failed to create action from network data")
		return
	
	# Apply the results directly to game state
	_apply_action_results(action, result_data)
	
	# Record in history
	game_state.record_action(action_data)
	
	# Emit events for UI
	if event_bus:
		event_bus.action_received.emit(action.get_action_name(), action.player_index, action_data)
		event_bus.action_executed.emit(action.get_action_name(), action.player_index, result_data)

func _apply_action_results(action: BaseAction, result_data: Dictionary) -> void:
	## Apply action results to game state without re-executing
	
	match action.action_type:
		BaseAction.ActionType.PLAY_CARD:
			_apply_play_card_results(action as PlayCardAction, result_data)
		BaseAction.ActionType.USE_EX_SKILL:
			_apply_ex_skill_results(action as UseEXSkillAction, result_data)
		BaseAction.ActionType.END_TURN:
			_apply_end_turn_results(action as EndTurnAction, result_data)

func _apply_play_card_results(action: PlayCardAction, result_data: Dictionary) -> void:
	## Apply play card results from network
	var sync_data = result_data.get("sync_data", result_data)
	
	# Update opponent's mana
	var player = game_state.get_player(action.player_index)
	if player:
		player.mana = sync_data.get("mana_after", player.mana)
		player.hand_count = sync_data.get("hand_count_after", player.hand_count)
	
	# Apply effect results
	_apply_effect_results(result_data.get("effect_results", sync_data.get("effect_results", [])))
	
	# Emit card played event for UI
	if event_bus:
		event_bus.emit_card_played(action.player_index, action.card_data, action.source_hero_id, action.target_hero_id)
		if player:
			event_bus.emit_mana_change(action.player_index, player.mana, player.max_mana)
			event_bus.hand_changed.emit(action.player_index, player.hand_count)
	
	# Check win condition
	var winner = game_state.check_win_condition()
	if winner >= 0 and event_bus:
		event_bus.emit_battle_end(winner, "All heroes defeated")

func _apply_ex_skill_results(action: UseEXSkillAction, result_data: Dictionary) -> void:
	## Apply EX skill results from network
	var sync_data = result_data.get("sync_data", result_data)
	
	# Reset source hero energy
	var player = game_state.get_player(action.player_index)
	if player:
		var source = player.get_hero(action.source_hero_id)
		if source:
			source.energy = 0
	
	# Apply effect results
	_apply_effect_results(result_data.get("effect_results", sync_data.get("effect_results", [])))
	
	# Emit EX skill event for UI
	if event_bus:
		event_bus.hero_ex_used.emit(action.source_hero_id, action.player_index, action.target_hero_id)
	
	# Check win condition
	var winner = game_state.check_win_condition()
	if winner >= 0 and event_bus:
		event_bus.emit_battle_end(winner, "All heroes defeated")

func _apply_end_turn_results(action: EndTurnAction, result_data: Dictionary) -> void:
	## Apply end turn results from network
	var sync_data = result_data.get("sync_data", result_data)
	
	# Apply effect results (burn, thunder, etc.)
	_apply_effect_results(result_data.get("effect_results", sync_data.get("effect_results", [])))
	
	# Switch turn
	game_state.current_player_index = sync_data.get("new_current_player", 1 - game_state.current_player_index)
	game_state.turn_number = sync_data.get("turn_number", game_state.turn_number)
	
	# Update new current player's mana
	var new_player = game_state.get_current_player()
	if new_player:
		new_player.increase_max_mana()
		new_player.restore_mana()
	
	# Emit events
	if event_bus:
		event_bus.emit_turn_end(action.player_index)
		event_bus.emit_turn_start(game_state.current_player_index, game_state.turn_number)
		if new_player:
			event_bus.emit_mana_change(game_state.current_player_index, new_player.mana, new_player.max_mana)
	
	# Check win condition
	var winner = game_state.check_win_condition()
	if winner >= 0 and event_bus:
		event_bus.emit_battle_end(winner, "All heroes defeated")

func _apply_effect_results(effect_results: Array) -> void:
	## Apply effect results to game state and emit events
	for effect_data in effect_results:
		var effect_type = effect_data.get("effect_type", 0)
		var target_hero_id = effect_data.get("target_hero_id", "")
		var target_owner = effect_data.get("target_owner_index", 0)
		
		var target = game_state.get_hero(target_hero_id, target_owner)
		if target == null:
			continue
		
		# Apply HP changes
		var hp_after = effect_data.get("target_hp_after", -1)
		if hp_after >= 0:
			var hp_before = target.hp
			target.hp = hp_after
			
			if event_bus:
				event_bus.emit_hero_hp_change(target_hero_id, target_owner, hp_before, hp_after, target.max_hp)
		
		# Apply block changes
		var block_after = effect_data.get("target_block_after", -1)
		if block_after >= 0:
			target.block = block_after
		
		# Check for death
		if effect_data.get("caused_death", false):
			target.is_dead = true
			if event_bus:
				var killer_id = effect_data.get("source_hero_id", "")
				event_bus.emit_hero_death(target_hero_id, target_owner, killer_id)
		
		# Apply buff/debuff
		var buff_type = effect_data.get("buff_type", "")
		if not buff_type.is_empty():
			var duration = effect_data.get("buff_duration", 1)
			if effect_type == BaseEffect.EffectType.DEBUFF:
				if event_bus:
					event_bus.emit_debuff(target_hero_id, target_owner, buff_type, duration)
			else:
				if event_bus:
					event_bus.emit_buff(target_hero_id, target_owner, buff_type, duration)
		
		# Process triggered effects recursively
		var triggered = effect_data.get("triggered_results", [])
		if not triggered.is_empty():
			_apply_effect_results(triggered)

# ============================================
# NETWORK SYNC
# ============================================

func _send_action_to_network(action: BaseAction, result: BaseAction.ActionResult) -> void:
	## Send action and result to opponent via network
	if network_manager == null:
		return
	
	var message = {
		"action": action.serialize(),
		"result": result.serialize()
	}
	
	# Use the network manager to send
	if network_manager.has_method("send_action_result"):
		network_manager.send_action_result(message)
	elif network_manager.has_method("send_action"):
		# Fallback to old method
		network_manager.send_action(result.sync_data)

# ============================================
# GAME STATE QUERIES
# ============================================

func is_my_turn() -> bool:
	return game_state.is_player_turn(local_player_index)

func get_current_player() -> PlayerState:
	return game_state.get_current_player()

func get_local_player() -> PlayerState:
	return game_state.get_player(local_player_index)

func get_opponent_player() -> PlayerState:
	return game_state.get_player(1 - local_player_index)

func get_my_heroes() -> Array[HeroState]:
	var player = get_local_player()
	return player.heroes if player else []

func get_enemy_heroes() -> Array[HeroState]:
	var opponent = get_opponent_player()
	return opponent.heroes if opponent else []

func is_game_over() -> bool:
	return game_state.is_game_over()

func get_winner() -> PlayerState:
	return game_state.get_winner()

func did_i_win() -> bool:
	return game_state.winner_index == local_player_index

# ============================================
# HERO QUERIES
# ============================================

func get_hero(hero_id: String, owner_index: int) -> HeroState:
	return game_state.get_hero(hero_id, owner_index)

func get_valid_targets_for_card(card_data: Dictionary) -> Array[HeroState]:
	## Get valid targets for a card
	var targets: Array[HeroState] = []
	var card_type = card_data.get("type", "")
	
	match card_type:
		"basic_attack", "damage", "debuff":
			# Target enemies
			var opponent = get_opponent_player()
			if opponent:
				for hero in opponent.get_alive_heroes():
					# Check for taunt
					var taunt_hero = opponent.get_hero_with_taunt()
					if taunt_hero and hero != taunt_hero:
						continue
					targets.append(hero)
		"heal", "buff", "shield", "equipment":
			# Target allies
			var player = get_local_player()
			if player:
				targets.append_array(player.get_alive_heroes())
		_:
			# Default: can target any alive hero
			targets.append_array(game_state.get_all_alive_heroes())
	
	return targets

# ============================================
# DEBUG
# ============================================

func print_state() -> void:
	game_state.print_state()
