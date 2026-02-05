class_name ActionFactory
extends RefCounted

## ActionFactory - Creates actions from various sources
## Centralizes action creation and deserialization

# ============================================
# CREATE FROM USER INPUT
# ============================================

static func create_play_card(player_index: int, card_data: Dictionary, source_hero_id: String, target_hero_id: String, target_owner: int, hand_index: int = -1) -> PlayCardAction:
	return PlayCardAction.create(player_index, card_data, source_hero_id, target_hero_id, target_owner, hand_index)

static func create_use_ex_skill(player_index: int, source_hero_id: String, target_hero_id: String = "", target_owner: int = 0) -> UseEXSkillAction:
	return UseEXSkillAction.create(player_index, source_hero_id, target_hero_id, target_owner)

static func create_end_turn(player_index: int) -> EndTurnAction:
	return EndTurnAction.create(player_index)

# ============================================
# CREATE FROM NETWORK DATA
# ============================================

static func create_from_data(data: Dictionary) -> BaseAction:
	## Create an action from serialized data (received from network)
	var action_type = data.get("action_type", 0)
	
	# Handle string action types (from sync_data)
	if action_type is String:
		match action_type:
			"play_card":
				return _create_play_card_from_data(data)
			"use_ex_skill":
				return _create_ex_skill_from_data(data)
			"end_turn":
				return _create_end_turn_from_data(data)
			"mulligan":
				return _create_mulligan_from_data(data)
			_:
				push_error("Unknown action type string: " + action_type)
				return null
	
	# Handle enum action types
	match action_type:
		BaseAction.ActionType.PLAY_CARD:
			return _create_play_card_from_data(data)
		BaseAction.ActionType.USE_EX_SKILL:
			return _create_ex_skill_from_data(data)
		BaseAction.ActionType.END_TURN:
			return _create_end_turn_from_data(data)
		BaseAction.ActionType.MULLIGAN:
			return _create_mulligan_from_data(data)
		_:
			push_error("Unknown action type: " + str(action_type))
			return null

static func _create_play_card_from_data(data: Dictionary) -> PlayCardAction:
	var action = PlayCardAction.new()
	action.action_type = BaseAction.ActionType.PLAY_CARD
	action.player_index = data.get("player_index", 0)
	action.timestamp = data.get("timestamp", 0)
	action.card_data = data.get("card_data", {}).duplicate(true)
	action.card_index = data.get("card_index", -1)
	action.source_hero_id = data.get("source_hero_id", "")
	action.target_hero_id = data.get("target_hero_id", "")
	action.target_owner_index = data.get("target_owner_index", 0)
	return action

static func _create_ex_skill_from_data(data: Dictionary) -> UseEXSkillAction:
	var action = UseEXSkillAction.new()
	action.action_type = BaseAction.ActionType.USE_EX_SKILL
	action.player_index = data.get("player_index", 0)
	action.timestamp = data.get("timestamp", 0)
	action.source_hero_id = data.get("source_hero_id", "")
	action.target_hero_id = data.get("target_hero_id", "")
	action.target_owner_index = data.get("target_owner_index", 0)
	return action

static func _create_end_turn_from_data(data: Dictionary) -> EndTurnAction:
	var action = EndTurnAction.new()
	action.action_type = BaseAction.ActionType.END_TURN
	action.player_index = data.get("player_index", 0)
	action.timestamp = data.get("timestamp", 0)
	return action

static func _create_mulligan_from_data(data: Dictionary) -> BaseAction:
	# TODO: Implement MulliganAction
	push_error("MulliganAction not yet implemented")
	return null

# ============================================
# CREATE FROM SYNC DATA (for applying results)
# ============================================

static func create_from_sync_data(sync_data: Dictionary) -> BaseAction:
	## Create action from sync_data (contains action + results)
	return create_from_data(sync_data)

# ============================================
# VALIDATION HELPERS
# ============================================

static func validate_action(action: BaseAction, game_state: GameState) -> BaseAction.ValidationResult:
	## Validate an action against game state
	if action == null:
		return BaseAction.ValidationResult.failure("Action is null")
	return action.validate(game_state)

static func is_valid_action_type(action_type) -> bool:
	if action_type is String:
		return action_type in ["play_card", "use_ex_skill", "end_turn", "mulligan", "surrender"]
	if action_type is int:
		return action_type >= 0 and action_type <= BaseAction.ActionType.SURRENDER
	return false
