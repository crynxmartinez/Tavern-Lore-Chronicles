class_name DamageEffect
extends BaseEffect

## DamageEffect - Deals damage to a target hero
## Handles shield absorption, damage modifiers, and death

# Damage-specific properties
var damage_type: String = "physical"  # physical, magical, true
var can_crit: bool = false
var crit_chance: float = 0.0
var crit_multiplier: float = 1.5
var lifesteal_percent: float = 0.0  # 0.0 to 1.0

# ============================================
# INITIALIZATION
# ============================================

static func create(value: int, source_id: String, source_owner: int, target_id: String, target_owner: int) -> DamageEffect:
	var effect = DamageEffect.new()
	effect.effect_type = EffectType.DAMAGE
	effect.base_value = value
	effect.source_hero_id = source_id
	effect.source_owner_index = source_owner
	effect.target_hero_id = target_id
	effect.target_owner_index = target_owner
	return effect

static func create_from_card(card_data: Dictionary, source: HeroState, target: HeroState) -> DamageEffect:
	var effect = DamageEffect.new()
	effect.effect_type = EffectType.DAMAGE
	effect.base_value = card_data.get("damage", card_data.get("value", 0))
	effect.source_hero_id = source.hero_id
	effect.source_owner_index = source.owner_index
	effect.target_hero_id = target.hero_id
	effect.target_owner_index = target.owner_index
	effect.damage_type = card_data.get("damage_type", "physical")
	effect.lifesteal_percent = card_data.get("lifesteal", 0.0)
	return effect

# ============================================
# EFFECT IMPLEMENTATION
# ============================================

func can_apply(game_state: GameState, source: HeroState, target: HeroState) -> bool:
	if not super.can_apply(game_state, source, target):
		return false
	# Can always deal damage to living targets
	return true

func get_modified_value(game_state: GameState, source: HeroState, target: HeroState) -> int:
	if ignore_modifiers:
		return base_value
	
	var value = float(base_value)
	var modifiers_applied: Array = []
	
	# Source damage multiplier (empower, weak)
	if source:
		var source_mult = source.get_damage_dealt_multiplier()
		if source_mult != 1.0:
			value *= source_mult
			modifiers_applied.append({"type": "source_mult", "value": source_mult})
	
	# Target damage taken multiplier (break, marked)
	if target and not ignore_shield:
		var target_mult = target.get_damage_taken_multiplier()
		if target_mult != 1.0:
			value *= target_mult
			modifiers_applied.append({"type": "target_mult", "value": target_mult})
	
	# Critical hit
	if can_crit and randf() < crit_chance:
		value *= crit_multiplier
		modifiers_applied.append({"type": "critical", "value": crit_multiplier})
	
	return int(value)

func apply(game_state: GameState, source: HeroState, target: HeroState, event_bus: BattleEventBus) -> BaseEffect.EffectResult:
	var result = BaseEffect.EffectResult.new()
	result.effect_type = EffectType.DAMAGE
	result.source_hero_id = source_hero_id
	result.source_owner_index = source_owner_index
	result.target_hero_id = target_hero_id
	result.target_owner_index = target_owner_index
	result.base_value = base_value
	
	if not can_apply(game_state, source, target):
		result.success = false
		return result
	
	# Calculate final damage
	var final_damage = get_modified_value(game_state, source, target)
	result.final_value = final_damage
	
	# Store before values
	result.target_hp_before = target.hp
	result.target_max_hp = target.max_hp
	result.target_block_before = target.block
	
	# Apply damage to target
	var damage_result = target.take_damage(final_damage)
	
	# Store after values
	result.target_hp_after = target.hp
	result.target_block_after = target.block
	result.shield_absorbed = damage_result.get("shield_absorbed", 0)
	result.was_blocked = result.shield_absorbed > 0
	result.shield_broken = damage_result.get("shield_broken", false)
	result.caused_death = damage_result.get("caused_death", false)
	result.success = true
	
	# Emit events
	if event_bus:
		event_bus.emit_damage(source_hero_id, target_hero_id, damage_result.get("actual_damage", 0), result.was_critical)
		event_bus.emit_hero_hp_change(target_hero_id, target_owner_index, result.target_hp_before, result.target_hp_after, result.target_max_hp)
		
		if result.shield_absorbed > 0:
			event_bus.shield_absorbed.emit(target_hero_id, result.shield_absorbed)
		
		if result.shield_broken:
			event_bus.shield_broken.emit(target_hero_id)
		
		if result.caused_death:
			event_bus.emit_hero_death(target_hero_id, target_owner_index, source_hero_id)
	
	# Handle triggered effects
	var triggered = get_triggered_effects(game_state, source, target, result)
	for triggered_effect in triggered:
		var triggered_result = triggered_effect.apply(game_state, source, target, event_bus)
		result.triggered_results.append(triggered_result)
	
	return result

func get_triggered_effects(game_state: GameState, source: HeroState, target: HeroState, result: BaseEffect.EffectResult) -> Array:
	var triggered: Array = []
	
	# Lifesteal
	if lifesteal_percent > 0 and result.final_value > 0 and source and not source.is_dead:
		var heal_amount = int(result.final_value * lifesteal_percent)
		if heal_amount > 0:
			var lifesteal_heal = HealEffect.create(heal_amount, source_hero_id, source_owner_index, source_hero_id, source_owner_index)
			triggered.append(lifesteal_heal)
	
	# Thorns (if target has thorns buff - future feature)
	# TODO: Add thorns handling when buff system supports it
	
	return triggered

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	var data = super.serialize()
	data["damage_type"] = damage_type
	data["can_crit"] = can_crit
	data["crit_chance"] = crit_chance
	data["crit_multiplier"] = crit_multiplier
	data["lifesteal_percent"] = lifesteal_percent
	return data
