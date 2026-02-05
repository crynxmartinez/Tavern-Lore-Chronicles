class_name EndTurnAction
extends BaseAction

## EndTurnAction - Action for ending the current player's turn

# ============================================
# INITIALIZATION
# ============================================

static func create(player: int) -> EndTurnAction:
	var action = EndTurnAction.new()
	action.action_type = ActionType.END_TURN
	action.player_index = player
	return action

# ============================================
# VALIDATION
# ============================================

func validate(game_state: GameState) -> ValidationResult:
	# Check if it's this player's turn
	if not game_state.is_player_turn(player_index):
		return ValidationResult.failure("Not your turn")
	
	# Check game phase
	if game_state.phase != GameState.BattlePhase.PLAYING:
		return ValidationResult.failure("Cannot end turn in this phase")
	
	is_validated = true
	return ValidationResult.success()

# ============================================
# EXECUTION
# ============================================

func execute(game_state: GameState, effect_pipeline: EffectPipeline, event_bus: BattleEventBus) -> ActionResult:
	var result = ActionResult.new()
	result.action_type = ActionType.END_TURN
	result.player_index = player_index
	result.turn_ended = true
	
	# Validate first if not already validated
	if not is_validated:
		var validation = validate(game_state)
		if not validation.is_valid:
			result.success = false
			return result
	
	# Get current player
	var current_player = game_state.get_current_player()
	
	# Process end-of-turn effects for current player's heroes
	for hero in current_player.heroes:
		if hero.is_dead:
			continue
		
		# Get turn end effects (burn, thunder, etc.)
		var turn_effects = EffectFactory.create_turn_end_effects(hero)
		for effect in turn_effects:
			var effect_result = effect_pipeline.process_effect(effect, game_state, null, hero)
			result.effect_results.append(effect_result)
		
		# Tick Thunder
		var thunder_damage = hero.tick_thunder()
		if thunder_damage > 0:
			var thunder_result = hero.take_damage(thunder_damage)
			if event_bus:
				event_bus.emit_damage("thunder", hero.hero_id, thunder_damage, false)
				event_bus.emit_hero_hp_change(hero.hero_id, hero.owner_index, 
					thunder_result.get("hp_before", hero.hp + thunder_damage), hero.hp, hero.max_hp)
				if thunder_result.get("caused_death", false):
					event_bus.emit_hero_death(hero.hero_id, hero.owner_index, "thunder")
	
	# Emit turn end event
	if event_bus:
		event_bus.emit_turn_end(player_index)
	
	# Check win condition after turn end effects
	var winner = game_state.check_win_condition()
	if winner >= 0:
		result.game_ended = true
		result.winner_index = winner
		if event_bus:
			event_bus.emit_battle_end(winner, "All heroes defeated")
		result.success = true
		return result
	
	# Switch turn
	game_state.switch_turn()
	
	# Get new current player
	var new_player = game_state.get_current_player()
	
	# Process start-of-turn effects for new player's heroes
	for hero in new_player.heroes:
		if hero.is_dead:
			continue
		
		# Get turn start effects (regen, poison, etc.)
		var turn_effects = EffectFactory.create_turn_start_effects(hero)
		for effect in turn_effects:
			var effect_result = effect_pipeline.process_effect(effect, game_state, null, hero)
			result.effect_results.append(effect_result)
	
	# Emit turn start event
	if event_bus:
		event_bus.emit_turn_start(game_state.current_player_index, game_state.turn_number)
		event_bus.emit_mana_change(game_state.current_player_index, new_player.mana, new_player.max_mana)
	
	# Check win condition again after turn start effects
	winner = game_state.check_win_condition()
	if winner >= 0:
		result.game_ended = true
		result.winner_index = winner
		if event_bus:
			event_bus.emit_battle_end(winner, "All heroes defeated")
	
	# Build sync data
	result.sync_data = _build_sync_data(game_state)
	
	result.success = true
	return result

func _build_sync_data(game_state: GameState) -> Dictionary:
	return {
		"action_type": "end_turn",
		"player_index": player_index,
		"new_current_player": game_state.current_player_index,
		"turn_number": game_state.turn_number
	}

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	return super.serialize()

static func deserialize_action(data: Dictionary) -> EndTurnAction:
	var action = EndTurnAction.new()
	action.action_type = data.get("action_type", ActionType.END_TURN)
	action.player_index = data.get("player_index", 0)
	action.timestamp = data.get("timestamp", 0)
	return action
