class_name ShieldEffect
extends BaseEffect

## ShieldEffect - Adds block/shield to a target hero

# ============================================
# INITIALIZATION
# ============================================

static func create(value: int, source_id: String, source_owner: int, target_id: String, target_owner: int) -> ShieldEffect:
	var effect = ShieldEffect.new()
	effect.effect_type = EffectType.SHIELD
	effect.base_value = value
	effect.source_hero_id = source_id
	effect.source_owner_index = source_owner
	effect.target_hero_id = target_id
	effect.target_owner_index = target_owner
	return effect

static func create_from_card(card_data: Dictionary, source: HeroState, target: HeroState) -> ShieldEffect:
	var effect = ShieldEffect.new()
	effect.effect_type = EffectType.SHIELD
	effect.base_value = card_data.get("shield", card_data.get("block", card_data.get("value", 0)))
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

func get_modified_value(game_state: GameState, source: HeroState, target: HeroState) -> int:
	if ignore_modifiers:
		return base_value
	
	var value = float(base_value)
	# Future: Add shield modifiers
	return int(value)

func apply(game_state: GameState, source: HeroState, target: HeroState, event_bus: BattleEventBus) -> BaseEffect.EffectResult:
	var result = BaseEffect.EffectResult.new()
	result.effect_type = EffectType.SHIELD
	result.source_hero_id = source_hero_id
	result.source_owner_index = source_owner_index
	result.target_hero_id = target_hero_id
	result.target_owner_index = target_owner_index
	result.base_value = base_value
	
	if not can_apply(game_state, source, target):
		result.success = false
		return result
	
	# Calculate final shield
	var final_shield = get_modified_value(game_state, source, target)
	result.final_value = final_shield
	
	# Store before value
	result.target_block_before = target.block
	
	# Apply shield
	target.add_block(final_shield)
	
	# Store after value
	result.target_block_after = target.block
	result.success = true
	
	# Emit event
	if event_bus:
		event_bus.shield_gained.emit(target_hero_id, final_shield)
	
	return result
