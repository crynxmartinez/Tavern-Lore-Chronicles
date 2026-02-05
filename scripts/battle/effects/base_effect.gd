class_name BaseEffect
extends RefCounted

## BaseEffect - Abstract base class for all effects
## Effects are the building blocks of card abilities and skills

# Effect types
enum EffectType {
	DAMAGE,
	HEAL,
	BUFF,
	DEBUFF,
	SHIELD,
	ENERGY,
	DRAW,
	DISPEL
}

# Core properties
var effect_type: EffectType = EffectType.DAMAGE
var base_value: int = 0
var source_hero_id: String = ""
var source_owner_index: int = 0
var target_hero_id: String = ""
var target_owner_index: int = 0

# Optional modifiers
var is_aoe: bool = false  # Affects all enemies/allies
var ignore_shield: bool = false  # Bypass shield
var ignore_modifiers: bool = false  # True damage

# ============================================
# ABSTRACT METHODS (override in subclasses)
# ============================================

func can_apply(game_state: GameState, source: HeroState, target: HeroState) -> bool:
	## Check if this effect can be applied
	if target == null:
		return false
	if target.is_dead:
		return false
	return true

func get_modified_value(game_state: GameState, source: HeroState, target: HeroState) -> int:
	## Calculate final value after modifiers
	return base_value

func apply(game_state: GameState, source: HeroState, target: HeroState, event_bus: BattleEventBus) -> EffectResult:
	## Apply the effect and return result
	## Override in subclasses
	push_error("BaseEffect.apply() called - should be overridden in subclass")
	return EffectResult.new()

func get_triggered_effects(game_state: GameState, source: HeroState, target: HeroState, result: EffectResult) -> Array:
	## Get any effects triggered by this effect (thorns, lifesteal, etc.)
	## Override in subclasses if needed
	return []

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	return {
		"effect_type": effect_type,
		"base_value": base_value,
		"source_hero_id": source_hero_id,
		"source_owner_index": source_owner_index,
		"target_hero_id": target_hero_id,
		"target_owner_index": target_owner_index,
		"is_aoe": is_aoe,
		"ignore_shield": ignore_shield,
		"ignore_modifiers": ignore_modifiers
	}

func _to_string() -> String:
	var type_names = ["DAMAGE", "HEAL", "BUFF", "DEBUFF", "SHIELD", "ENERGY", "DRAW", "DISPEL"]
	return "[Effect %s] value=%d source=%s target=%s" % [
		type_names[effect_type], base_value, source_hero_id, target_hero_id
	]


# ============================================
# EFFECT RESULT CLASS
# ============================================

class EffectResult extends RefCounted:
	## Result of applying an effect
	
	var success: bool = false
	var effect_type: int = EffectType.DAMAGE
	
	# Source and target
	var source_hero_id: String = ""
	var source_owner_index: int = 0
	var target_hero_id: String = ""
	var target_owner_index: int = 0
	
	# Values
	var base_value: int = 0
	var final_value: int = 0
	var modifiers: Array = []  # Array of {type, value}
	
	# HP changes
	var target_hp_before: int = 0
	var target_hp_after: int = 0
	var target_max_hp: int = 0
	
	# Shield changes
	var target_block_before: int = 0
	var target_block_after: int = 0
	var shield_absorbed: int = 0
	
	# Flags
	var was_critical: bool = false
	var was_blocked: bool = false
	var caused_death: bool = false
	var shield_broken: bool = false
	
	# Triggered effects
	var triggered_results: Array = []  # Array of EffectResult
	
	# Buff/Debuff specific
	var buff_type: String = ""
	var buff_duration: int = 0
	
	func serialize() -> Dictionary:
		var triggered_serialized = []
		for tr in triggered_results:
			triggered_serialized.append(tr.serialize())
		
		return {
			"success": success,
			"effect_type": effect_type,
			"source_hero_id": source_hero_id,
			"source_owner_index": source_owner_index,
			"target_hero_id": target_hero_id,
			"target_owner_index": target_owner_index,
			"base_value": base_value,
			"final_value": final_value,
			"modifiers": modifiers.duplicate(),
			"target_hp_before": target_hp_before,
			"target_hp_after": target_hp_after,
			"target_max_hp": target_max_hp,
			"target_block_before": target_block_before,
			"target_block_after": target_block_after,
			"shield_absorbed": shield_absorbed,
			"was_critical": was_critical,
			"was_blocked": was_blocked,
			"caused_death": caused_death,
			"shield_broken": shield_broken,
			"triggered_results": triggered_serialized,
			"buff_type": buff_type,
			"buff_duration": buff_duration
		}
	
	static func deserialize(data: Dictionary) -> EffectResult:
		var result = EffectResult.new()
		result.success = data.get("success", false)
		result.effect_type = data.get("effect_type", EffectType.DAMAGE)
		result.source_hero_id = data.get("source_hero_id", "")
		result.source_owner_index = data.get("source_owner_index", 0)
		result.target_hero_id = data.get("target_hero_id", "")
		result.target_owner_index = data.get("target_owner_index", 0)
		result.base_value = data.get("base_value", 0)
		result.final_value = data.get("final_value", 0)
		result.modifiers = data.get("modifiers", []).duplicate()
		result.target_hp_before = data.get("target_hp_before", 0)
		result.target_hp_after = data.get("target_hp_after", 0)
		result.target_max_hp = data.get("target_max_hp", 0)
		result.target_block_before = data.get("target_block_before", 0)
		result.target_block_after = data.get("target_block_after", 0)
		result.shield_absorbed = data.get("shield_absorbed", 0)
		result.was_critical = data.get("was_critical", false)
		result.was_blocked = data.get("was_blocked", false)
		result.caused_death = data.get("caused_death", false)
		result.shield_broken = data.get("shield_broken", false)
		result.buff_type = data.get("buff_type", "")
		result.buff_duration = data.get("buff_duration", 0)
		
		# Deserialize triggered results
		result.triggered_results = []
		for tr_data in data.get("triggered_results", []):
			result.triggered_results.append(EffectResult.deserialize(tr_data))
		
		return result
	
	func _to_string() -> String:
		var type_names = ["DAMAGE", "HEAL", "BUFF", "DEBUFF", "SHIELD", "ENERGY", "DRAW", "DISPEL"]
		return "[EffectResult %s] %d→%d HP:%d→%d death:%s" % [
			type_names[effect_type], base_value, final_value, 
			target_hp_before, target_hp_after, caused_death
		]
