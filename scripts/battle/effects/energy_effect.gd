class_name EnergyEffect
extends BaseEffect

## EnergyEffect - Adds energy to a target hero

# ============================================
# INITIALIZATION
# ============================================

static func create(value: int, source_id: String, source_owner: int, target_id: String, target_owner: int) -> EnergyEffect:
	var effect = EnergyEffect.new()
	effect.effect_type = EffectType.ENERGY
	effect.base_value = value
	effect.source_hero_id = source_id
	effect.source_owner_index = source_owner
	effect.target_hero_id = target_id
	effect.target_owner_index = target_owner
	return effect

static func create_from_card(card_data: Dictionary, source: HeroState, target: HeroState) -> EnergyEffect:
	var effect = EnergyEffect.new()
	effect.effect_type = EffectType.ENERGY
	effect.base_value = card_data.get("energy", card_data.get("value", 0))
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
	return true

func apply(game_state: GameState, source: HeroState, target: HeroState, event_bus: BattleEventBus) -> BaseEffect.EffectResult:
	var result = BaseEffect.EffectResult.new()
	result.effect_type = EffectType.ENERGY
	result.source_hero_id = source_hero_id
	result.source_owner_index = source_owner_index
	result.target_hero_id = target_hero_id
	result.target_owner_index = target_owner_index
	result.base_value = base_value
	
	if not can_apply(game_state, source, target):
		result.success = false
		return result
	
	# Store before value
	var energy_before = target.energy
	
	# Apply energy
	var energy_result = target.add_energy(base_value)
	
	result.final_value = energy_result.get("energy_added", 0)
	result.success = true
	
	# Emit event
	if event_bus:
		event_bus.emit_hero_energy_change(target_hero_id, target_owner_index, energy_before, target.energy)
	
	return result
