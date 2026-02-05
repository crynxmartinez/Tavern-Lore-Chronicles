class_name BaseAction
extends RefCounted

## BaseAction - Abstract base class for all player actions
## Actions are serializable commands that modify game state

# Action types
enum ActionType {
	PLAY_CARD,
	USE_EX_SKILL,
	END_TURN,
	MULLIGAN,
	SURRENDER
}

# Core properties
var action_type: ActionType = ActionType.PLAY_CARD
var player_index: int = 0  # Who performed the action
var timestamp: int = 0  # When the action was created

# Validation
var is_validated: bool = false
var validation_error: String = ""

# ============================================
# INITIALIZATION
# ============================================

func _init() -> void:
	timestamp = Time.get_unix_time_from_system()

# ============================================
# ABSTRACT METHODS (override in subclasses)
# ============================================

func validate(game_state: GameState) -> ValidationResult:
	## Check if this action is valid given the current game state
	## Override in subclasses
	push_error("BaseAction.validate() called - should be overridden in subclass")
	return ValidationResult.new(false, "Not implemented")

func execute(game_state: GameState, effect_pipeline: EffectPipeline, event_bus: BattleEventBus) -> ActionResult:
	## Execute this action and return the result
	## Override in subclasses
	push_error("BaseAction.execute() called - should be overridden in subclass")
	return ActionResult.new()

func get_action_name() -> String:
	## Get human-readable action name
	var names = ["Play Card", "Use EX Skill", "End Turn", "Mulligan", "Surrender"]
	return names[action_type] if action_type < names.size() else "Unknown"

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	## Convert to Dictionary for network transmission
	return {
		"action_type": action_type,
		"player_index": player_index,
		"timestamp": timestamp
	}

static func deserialize(data: Dictionary) -> BaseAction:
	## Create action from Dictionary - use ActionFactory instead
	push_error("Use ActionFactory.create_from_data() instead of BaseAction.deserialize()")
	return null

func _to_string() -> String:
	return "[Action %s] player=%d" % [get_action_name(), player_index]


# ============================================
# VALIDATION RESULT CLASS
# ============================================

class ValidationResult extends RefCounted:
	var is_valid: bool = false
	var error_message: String = ""
	
	func _init(valid: bool = false, error: String = "") -> void:
		is_valid = valid
		error_message = error
	
	static func success() -> ValidationResult:
		return ValidationResult.new(true, "")
	
	static func failure(error: String) -> ValidationResult:
		return ValidationResult.new(false, error)
	
	func _to_string() -> String:
		if is_valid:
			return "[Valid]"
		return "[Invalid: %s]" % error_message


# ============================================
# ACTION RESULT CLASS
# ============================================

class ActionResult extends RefCounted:
	var success: bool = false
	var action_type: int = ActionType.PLAY_CARD
	var player_index: int = 0
	
	# Effect results from this action
	var effect_results: Array = []  # Array of BaseEffect.EffectResult
	
	# State changes
	var mana_spent: int = 0
	var cards_drawn: int = 0
	var turn_ended: bool = false
	var game_ended: bool = false
	var winner_index: int = -1
	
	# For card plays
	var card_data: Dictionary = {}
	var source_hero_id: String = ""
	var target_hero_id: String = ""
	
	# For network sync - contains all info needed to replicate on other client
	var sync_data: Dictionary = {}
	
	func serialize() -> Dictionary:
		var serialized_effects = []
		for effect_result in effect_results:
			serialized_effects.append(effect_result.serialize())
		
		return {
			"success": success,
			"action_type": action_type,
			"player_index": player_index,
			"effect_results": serialized_effects,
			"mana_spent": mana_spent,
			"cards_drawn": cards_drawn,
			"turn_ended": turn_ended,
			"game_ended": game_ended,
			"winner_index": winner_index,
			"card_data": card_data.duplicate(true),
			"source_hero_id": source_hero_id,
			"target_hero_id": target_hero_id,
			"sync_data": sync_data.duplicate(true)
		}
	
	static func deserialize(data: Dictionary) -> ActionResult:
		var result = ActionResult.new()
		result.success = data.get("success", false)
		result.action_type = data.get("action_type", ActionType.PLAY_CARD)
		result.player_index = data.get("player_index", 0)
		result.mana_spent = data.get("mana_spent", 0)
		result.cards_drawn = data.get("cards_drawn", 0)
		result.turn_ended = data.get("turn_ended", false)
		result.game_ended = data.get("game_ended", false)
		result.winner_index = data.get("winner_index", -1)
		result.card_data = data.get("card_data", {}).duplicate(true)
		result.source_hero_id = data.get("source_hero_id", "")
		result.target_hero_id = data.get("target_hero_id", "")
		result.sync_data = data.get("sync_data", {}).duplicate(true)
		
		# Deserialize effect results
		result.effect_results = []
		for effect_data in data.get("effect_results", []):
			result.effect_results.append(BaseEffect.EffectResult.deserialize(effect_data))
		
		return result
	
	func _to_string() -> String:
		var type_names = ["PLAY_CARD", "USE_EX_SKILL", "END_TURN", "MULLIGAN", "SURRENDER"]
		return "[ActionResult %s] success=%s effects=%d" % [
			type_names[action_type], success, effect_results.size()
		]
