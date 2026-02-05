class_name HealEffect
extends BaseEffect

## HealEffect - Restores HP to a target hero

# Heal-specific properties
var can_overheal: bool = false  # Allow healing above max HP (future feature)

# ============================================
# INITIALIZATION
# ============================================

static func create(value: int, source_id: String, source_owner: int, target_id: String, target_owner: int) -> HealEffect:
	var effect = HealEffect.new()
	effect.effect_type = EffectType.HEAL
	effect.base_value = value
	effect.source_hero_id = source_id
	effect.source_owner_index = source_owner
	effect.target_hero_id = target_id
	effect.target_owner_index = target_owner
	return effect

static func create_from_card(card_data: Dictionary, source: HeroState, target: HeroState) -> HealEffect:
	var effect = HealEffect.new()
	effect.effect_type = EffectType.HEAL
	effect.base_value = card_data.get("heal", card_data.get("value", 0))
	effect.source_hero_id = source.hero_id
	effect.source_owner_index = source.owner_index
	effect.target_hero_id = target.hero_id
	effect.target_owner_index = target.owner_index
	return effect

# ============================================
# EFFECT IMPLEMENTATION
# ============================================

func can_apply(game_state: GameState, source: HeroState, target: HeroState) -> bool:
	if not super.can_apply(game_state, source, target):
		return false
	# Can heal living targets (even at full HP - just won't do anything)
	return true

func get_modified_value(game_state: GameState, source: HeroState, target: HeroState) -> int:
	if ignore_modifiers:
		return base_value
	
	var value = float(base_value)
	
	# Future: Add heal modifiers (heal boost buffs, etc.)
	
	return int(value)

func apply(game_state: GameState, source: HeroState, target: HeroState, event_bus: BattleEventBus) -> BaseEffect.EffectResult:
	var result = BaseEffect.EffectResult.new()
	result.effect_type = EffectType.HEAL
	result.source_hero_id = source_hero_id
	result.source_owner_index = source_owner_index
	result.target_hero_id = target_hero_id
	result.target_owner_index = target_owner_index
	result.base_value = base_value
	
	if not can_apply(game_state, source, target):
		result.success = false
		return result
	
	# Calculate final heal
	var final_heal = get_modified_value(game_state, source, target)
	result.final_value = final_heal
	
	# Store before values
	result.target_hp_before = target.hp
	result.target_max_hp = target.max_hp
	
	# Apply heal to target
	var heal_result = target.heal(final_heal)
	
	# Store after values
	result.target_hp_after = target.hp
	result.final_value = heal_result.get("actual_heal", 0)
	result.success = true
	
	# Emit events
	if event_bus and result.final_value > 0:
		event_bus.emit_heal(source_hero_id, target_hero_id, result.final_value)
		event_bus.emit_hero_hp_change(target_hero_id, target_owner_index, result.target_hp_before, result.target_hp_after, result.target_max_hp)
	
	return result

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	var data = super.serialize()
	data["can_overheal"] = can_overheal
	return data
