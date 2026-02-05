class_name PlayCardAction
extends BaseAction

## PlayCardAction - Action for playing a card from hand

# Card-specific properties
var card_data: Dictionary = {}  # Full card data
var card_index: int = -1  # Index in hand (for local validation)
var source_hero_id: String = ""  # Hero playing the card
var target_hero_id: String = ""  # Target hero (if applicable)
var target_owner_index: int = 0  # Owner of target hero

# ============================================
# INITIALIZATION
# ============================================

static func create(player: int, card: Dictionary, source_id: String, target_id: String, target_owner: int, hand_index: int = -1) -> PlayCardAction:
	var action = PlayCardAction.new()
	action.action_type = ActionType.PLAY_CARD
	action.player_index = player
	action.card_data = card.duplicate(true)
	action.source_hero_id = source_id
	action.target_hero_id = target_id
	action.target_owner_index = target_owner
	action.card_index = hand_index
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
		return ValidationResult.failure("Cannot play cards in this phase")
	
	# Get player state
	var player = game_state.get_player(player_index)
	if player == null:
		return ValidationResult.failure("Player not found")
	
	# Check mana cost
	var cost = card_data.get("cost", 0)
	if not player.can_afford(cost):
		return ValidationResult.failure("Not enough mana (need %d, have %d)" % [cost, player.mana])
	
	# Check if card exists in hand (if index provided)
	if card_index >= 0:
		if card_index >= player.hand.size():
			return ValidationResult.failure("Card index out of range")
	
	# Check source hero
	var source = player.get_hero(source_hero_id)
	if source == null:
		# Source might be any alive hero for some cards
		source = player.get_alive_heroes()[0] if player.has_alive_heroes() else null
	if source != null and source.is_dead:
		return ValidationResult.failure("Source hero is dead")
	
	# Check target if required
	var card_type = card_data.get("type", "")
	var needs_target = _card_needs_target(card_type)
	
	if needs_target and target_hero_id.is_empty():
		return ValidationResult.failure("This card requires a target")
	
	if not target_hero_id.is_empty():
		var target = game_state.get_hero(target_hero_id, target_owner_index)
		if target == null:
			return ValidationResult.failure("Target hero not found")
		if target.is_dead:
			return ValidationResult.failure("Target hero is dead")
		
		# Check if target is valid for this card type
		if not _is_valid_target(card_type, player_index, target_owner_index):
			return ValidationResult.failure("Invalid target for this card")
	
	is_validated = true
	return ValidationResult.success()

func _card_needs_target(card_type: String) -> bool:
	# Cards that need a target
	match card_type:
		"basic_attack", "damage", "debuff":
			return true
		"heal", "buff", "shield":
			return true  # Usually target an ally
		"equipment":
			return true  # Target ally to equip
		_:
			return false

func _is_valid_target(card_type: String, my_index: int, target_index: int) -> bool:
	# Check if target is valid for card type
	match card_type:
		"basic_attack", "damage", "debuff":
			# Must target enemy
			return target_index != my_index
		"heal", "buff", "shield", "equipment":
			# Must target ally
			return target_index == my_index
		_:
			return true

# ============================================
# EXECUTION
# ============================================

func execute(game_state: GameState, effect_pipeline: EffectPipeline, event_bus: BattleEventBus) -> ActionResult:
	var result = ActionResult.new()
	result.action_type = ActionType.PLAY_CARD
	result.player_index = player_index
	result.card_data = card_data.duplicate(true)
	result.source_hero_id = source_hero_id
	result.target_hero_id = target_hero_id
	
	# Validate first if not already validated
	if not is_validated:
		var validation = validate(game_state)
		if not validation.is_valid:
			result.success = false
			return result
	
	# Get player and heroes
	var player = game_state.get_player(player_index)
	var source = player.get_hero(source_hero_id)
	if source == null and player.has_alive_heroes():
		source = player.get_alive_heroes()[0]
	
	var target: HeroState = null
	if not target_hero_id.is_empty():
		target = game_state.get_hero(target_hero_id, target_owner_index)
	
	# Spend mana
	var cost = card_data.get("cost", 0)
	player.spend_mana(cost)
	result.mana_spent = cost
	
	# Remove card from hand
	if card_index >= 0:
		player.remove_card_from_hand(card_index)
	else:
		# Try to find by ID
		var card_id = card_data.get("id", "")
		if not card_id.is_empty():
			player.remove_card_by_id(card_id)
	
	# Emit card played event
	if event_bus:
		event_bus.emit_card_played(player_index, card_data, source_hero_id, target_hero_id)
		event_bus.emit_mana_change(player_index, player.mana, player.max_mana)
		event_bus.hand_changed.emit(player_index, player.hand.size())
	
	# Create and execute effects
	var effects = EffectFactory.create_effects_from_card(card_data, source, target)
	
	for effect in effects:
		if target != null:
			var effect_result = effect_pipeline.process_effect(effect, game_state, source, target)
			result.effect_results.append(effect_result)
	
	# Add energy to source hero for playing a card
	if source and not source.is_dead:
		source.add_energy(GameConstants.ENERGY_ON_ATTACK)
		if event_bus:
			event_bus.emit_hero_energy_change(source.hero_id, source.owner_index, source.energy - GameConstants.ENERGY_ON_ATTACK, source.energy)
	
	# Check win condition
	var winner = game_state.check_win_condition()
	if winner >= 0:
		result.game_ended = true
		result.winner_index = winner
		if event_bus:
			event_bus.emit_battle_end(winner, "All heroes defeated")
	
	# Build sync data for network
	result.sync_data = _build_sync_data(result, player)
	
	result.success = true
	return result

func _build_sync_data(result: ActionResult, player: PlayerState) -> Dictionary:
	## Build data needed to sync this action to opponent
	return {
		"action_type": "play_card",
		"player_index": player_index,
		"card_data": card_data.duplicate(true),
		"source_hero_id": source_hero_id,
		"target_hero_id": target_hero_id,
		"target_owner_index": target_owner_index,
		"mana_after": player.mana,
		"hand_count_after": player.hand.size(),
		"effect_results": result.serialize().get("effect_results", [])
	}

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	var data = super.serialize()
	data["card_data"] = card_data.duplicate(true)
	data["card_index"] = card_index
	data["source_hero_id"] = source_hero_id
	data["target_hero_id"] = target_hero_id
	data["target_owner_index"] = target_owner_index
	return data

static func deserialize_action(data: Dictionary) -> PlayCardAction:
	var action = PlayCardAction.new()
	action.action_type = data.get("action_type", ActionType.PLAY_CARD)
	action.player_index = data.get("player_index", 0)
	action.timestamp = data.get("timestamp", 0)
	action.card_data = data.get("card_data", {}).duplicate(true)
	action.card_index = data.get("card_index", -1)
	action.source_hero_id = data.get("source_hero_id", "")
	action.target_hero_id = data.get("target_hero_id", "")
	action.target_owner_index = data.get("target_owner_index", 0)
	return action
