class_name UseEXSkillAction
extends BaseAction

## UseEXSkillAction - Action for using a hero's EX skill

# EX skill properties
var source_hero_id: String = ""  # Hero using the skill
var target_hero_id: String = ""  # Target hero (if applicable)
var target_owner_index: int = 0  # Owner of target hero

# ============================================
# INITIALIZATION
# ============================================

static func create(player: int, source_id: String, target_id: String = "", target_owner: int = 0) -> UseEXSkillAction:
	var action = UseEXSkillAction.new()
	action.action_type = ActionType.USE_EX_SKILL
	action.player_index = player
	action.source_hero_id = source_id
	action.target_hero_id = target_id
	action.target_owner_index = target_owner
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
		return ValidationResult.failure("Cannot use EX skill in this phase")
	
	# Get player state
	var player = game_state.get_player(player_index)
	if player == null:
		return ValidationResult.failure("Player not found")
	
	# Check source hero
	var source = player.get_hero(source_hero_id)
	if source == null:
		return ValidationResult.failure("Source hero not found")
	if source.is_dead:
		return ValidationResult.failure("Source hero is dead")
	if not source.is_ex_ready():
		return ValidationResult.failure("EX skill not ready (need %d energy, have %d)" % [source.max_energy, source.energy])
	
	# Check target if provided
	if not target_hero_id.is_empty():
		var target = game_state.get_hero(target_hero_id, target_owner_index)
		if target == null:
			return ValidationResult.failure("Target hero not found")
		if target.is_dead:
			return ValidationResult.failure("Target hero is dead")
	
	is_validated = true
	return ValidationResult.success()

# ============================================
# EXECUTION
# ============================================

func execute(game_state: GameState, effect_pipeline: EffectPipeline, event_bus: BattleEventBus) -> ActionResult:
	var result = ActionResult.new()
	result.action_type = ActionType.USE_EX_SKILL
	result.player_index = player_index
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
	
	var target: HeroState = null
	if not target_hero_id.is_empty():
		target = game_state.get_hero(target_hero_id, target_owner_index)
	
	# Use energy
	var energy_before = source.energy
	source.use_energy()
	
	# Emit EX skill event
	if event_bus:
		event_bus.hero_ex_used.emit(source_hero_id, source.owner_index, target_hero_id)
		event_bus.emit_hero_energy_change(source_hero_id, source.owner_index, energy_before, source.energy)
		event_bus.request_ex_skill_animation.emit(source_hero_id, source.owner_index, _get_skill_type(source))
	
	# Get hero data for EX skill effects
	var hero_data = {}
	if HeroDatabase:
		hero_data = HeroDatabase.get_hero(source_hero_id)
	
	# Create and execute EX skill effects
	var effects = EffectFactory.create_effects_from_ex_skill(hero_data, source, target)
	
	for effect in effects:
		var effect_target = target if target else source  # Default to self if no target
		var effect_result = effect_pipeline.process_effect(effect, game_state, source, effect_target)
		result.effect_results.append(effect_result)
	
	# Check win condition
	var winner = game_state.check_win_condition()
	if winner >= 0:
		result.game_ended = true
		result.winner_index = winner
		if event_bus:
			event_bus.emit_battle_end(winner, "All heroes defeated")
	
	# Build sync data
	result.sync_data = _build_sync_data(result)
	
	result.success = true
	return result

func _get_skill_type(source: HeroState) -> String:
	var hero_data = {}
	if HeroDatabase:
		hero_data = HeroDatabase.get_hero(source.hero_id)
	var ex_skill = hero_data.get("ex_skill", {})
	return ex_skill.get("type", "damage")

func _build_sync_data(result: ActionResult) -> Dictionary:
	return {
		"action_type": "use_ex_skill",
		"player_index": player_index,
		"source_hero_id": source_hero_id,
		"target_hero_id": target_hero_id,
		"target_owner_index": target_owner_index,
		"effect_results": result.serialize().get("effect_results", [])
	}

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	var data = super.serialize()
	data["source_hero_id"] = source_hero_id
	data["target_hero_id"] = target_hero_id
	data["target_owner_index"] = target_owner_index
	return data

static func deserialize_action(data: Dictionary) -> UseEXSkillAction:
	var action = UseEXSkillAction.new()
	action.action_type = data.get("action_type", ActionType.USE_EX_SKILL)
	action.player_index = data.get("player_index", 0)
	action.timestamp = data.get("timestamp", 0)
	action.source_hero_id = data.get("source_hero_id", "")
	action.target_hero_id = data.get("target_hero_id", "")
	action.target_owner_index = data.get("target_owner_index", 0)
	return action
