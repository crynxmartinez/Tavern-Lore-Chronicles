class_name BuffEffect
extends BaseEffect

## BuffEffect - Applies a buff or debuff to a target hero

# Buff-specific properties
var buff_name: String = ""  # e.g., "shield", "empower", "poison"
var duration: int = 1  # Turns the buff lasts (-1 = permanent)
var is_debuff: bool = false  # true = debuff, false = buff
var stacks: int = 1  # For stackable effects like Thunder

# ============================================
# INITIALIZATION
# ============================================

static func create_buff(buff_type: String, dur: int, source_id: String, source_owner: int, target_id: String, target_owner: int, source_atk: int = 10) -> BuffEffect:
	var effect = BuffEffect.new()
	effect.effect_type = EffectType.BUFF
	effect.buff_name = buff_type
	effect.duration = dur
	effect.base_value = source_atk
	effect.source_hero_id = source_id
	effect.source_owner_index = source_owner
	effect.target_hero_id = target_id
	effect.target_owner_index = target_owner
	effect.is_debuff = false
	return effect

static func create_debuff(debuff_type: String, dur: int, source_id: String, source_owner: int, target_id: String, target_owner: int, source_atk: int = 10) -> BuffEffect:
	var effect = BuffEffect.new()
	effect.effect_type = EffectType.DEBUFF
	effect.buff_name = debuff_type
	effect.duration = dur
	effect.base_value = source_atk
	effect.source_hero_id = source_id
	effect.source_owner_index = source_owner
	effect.target_hero_id = target_id
	effect.target_owner_index = target_owner
	effect.is_debuff = true
	return effect

static func create_thunder(stack_count: int, source_id: String, source_owner: int, target_id: String, target_owner: int, source_atk: int = 10) -> BuffEffect:
	var effect = BuffEffect.new()
	effect.effect_type = EffectType.DEBUFF
	effect.buff_name = "thunder"
	effect.duration = -1  # Thunder doesn't expire by duration
	effect.base_value = source_atk
	effect.source_hero_id = source_id
	effect.source_owner_index = source_owner
	effect.target_hero_id = target_id
	effect.target_owner_index = target_owner
	effect.is_debuff = true
	effect.stacks = stack_count
	return effect

static func create_from_card(card_data: Dictionary, source: HeroState, target: HeroState) -> BuffEffect:
	var effect = BuffEffect.new()
	
	var buff_type = card_data.get("buff_type", card_data.get("debuff_type", ""))
	effect.buff_name = buff_type
	effect.duration = card_data.get("duration", 1)
	effect.base_value = source.attack if source else 10
	effect.source_hero_id = source.hero_id if source else ""
	effect.source_owner_index = source.owner_index if source else 0
	effect.target_hero_id = target.hero_id
	effect.target_owner_index = target.owner_index
	
	# Determine if buff or debuff
	if buff_type in BuffState.DEBUFF_TYPES:
		effect.effect_type = EffectType.DEBUFF
		effect.is_debuff = true
	else:
		effect.effect_type = EffectType.BUFF
		effect.is_debuff = false
	
	# Handle Thunder stacks
	if buff_type == "thunder":
		effect.stacks = card_data.get("stacks", 1)
	
	return effect

# ============================================
# EFFECT IMPLEMENTATION
# ============================================

func can_apply(game_state: GameState, source: HeroState, target: HeroState) -> bool:
	if not super.can_apply(game_state, source, target):
		return false
	# Can apply buffs/debuffs to living targets
	return buff_name != ""

func apply(game_state: GameState, source: HeroState, target: HeroState, event_bus: BattleEventBus) -> BaseEffect.EffectResult:
	var result = BaseEffect.EffectResult.new()
	result.effect_type = effect_type
	result.source_hero_id = source_hero_id
	result.source_owner_index = source_owner_index
	result.target_hero_id = target_hero_id
	result.target_owner_index = target_owner_index
	result.base_value = base_value
	result.buff_type = buff_name
	result.buff_duration = duration
	
	if not can_apply(game_state, source, target):
		result.success = false
		return result
	
	# Apply buff or debuff
	if is_debuff:
		if buff_name == "thunder":
			target.apply_thunder(stacks, base_value, source_hero_id)
		else:
			target.apply_debuff(buff_name, duration, base_value, source_hero_id)
		
		# Emit event
		if event_bus:
			event_bus.emit_debuff(target_hero_id, target_owner_index, buff_name, duration)
	else:
		target.apply_buff(buff_name, duration, base_value, source_hero_id)
		
		# Emit event
		if event_bus:
			event_bus.emit_buff(target_hero_id, target_owner_index, buff_name, duration)
	
	result.success = true
	result.final_value = stacks if buff_name == "thunder" else duration
	
	return result

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	var data = super.serialize()
	data["buff_name"] = buff_name
	data["duration"] = duration
	data["is_debuff"] = is_debuff
	data["stacks"] = stacks
	return data
