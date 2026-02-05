class_name EffectFactory
extends RefCounted

## EffectFactory - Creates effects from card data and other sources
## Centralizes effect creation logic

# ============================================
# CREATE FROM CARD DATA
# ============================================

static func create_effects_from_card(card_data: Dictionary, source: HeroState, target: HeroState) -> Array:
	## Create all effects from a card's data
	var effects: Array = []
	
	var card_type = card_data.get("type", "")
	
	match card_type:
		"basic_attack":
			effects.append(_create_basic_attack_effect(card_data, source, target))
		"damage":
			effects.append(_create_damage_effect(card_data, source, target))
		"heal":
			effects.append(_create_heal_effect(card_data, source, target))
		"buff":
			effects.append(_create_buff_effect(card_data, source, target))
		"debuff":
			effects.append(_create_debuff_effect(card_data, source, target))
		"shield":
			effects.append(_create_shield_effect(card_data, source, target))
		"equipment":
			effects.append_array(_create_equipment_effects(card_data, source, target))
		_:
			# Try to infer from card data
			effects.append_array(_create_effects_from_data(card_data, source, target))
	
	return effects

static func _create_basic_attack_effect(card_data: Dictionary, source: HeroState, target: HeroState) -> DamageEffect:
	## Create effect for basic attack card
	var damage = source.attack if source else 10
	var mult = card_data.get("atk_multiplier", 1.0)
	damage = int(damage * mult)
	
	return DamageEffect.create(damage, source.hero_id, source.owner_index, target.hero_id, target.owner_index)

static func _create_damage_effect(card_data: Dictionary, source: HeroState, target: HeroState) -> DamageEffect:
	## Create damage effect from card data
	var damage = card_data.get("damage", card_data.get("value", 0))
	
	# Check for ATK scaling
	if card_data.has("atk_multiplier"):
		var base_atk = source.attack if source else 10
		damage = int(base_atk * card_data.get("atk_multiplier", 1.0))
	
	var effect = DamageEffect.create(damage, source.hero_id, source.owner_index, target.hero_id, target.owner_index)
	effect.damage_type = card_data.get("damage_type", "physical")
	effect.lifesteal_percent = card_data.get("lifesteal", 0.0)
	
	return effect

static func _create_heal_effect(card_data: Dictionary, source: HeroState, target: HeroState) -> HealEffect:
	## Create heal effect from card data
	var heal = card_data.get("heal", card_data.get("value", 0))
	
	# Check for ATK scaling
	if card_data.has("atk_multiplier"):
		var base_atk = source.attack if source else 10
		heal = int(base_atk * card_data.get("atk_multiplier", 1.0))
	
	return HealEffect.create(heal, source.hero_id, source.owner_index, target.hero_id, target.owner_index)

static func _create_buff_effect(card_data: Dictionary, source: HeroState, target: HeroState) -> BuffEffect:
	## Create buff effect from card data
	var buff_type = card_data.get("buff_type", card_data.get("buff", ""))
	var duration = card_data.get("duration", 1)
	var source_atk = source.attack if source else 10
	
	return BuffEffect.create_buff(buff_type, duration, source.hero_id, source.owner_index, target.hero_id, target.owner_index, source_atk)

static func _create_debuff_effect(card_data: Dictionary, source: HeroState, target: HeroState) -> BuffEffect:
	## Create debuff effect from card data
	var debuff_type = card_data.get("debuff_type", card_data.get("debuff", ""))
	var duration = card_data.get("duration", 1)
	var source_atk = source.attack if source else 10
	
	# Special handling for Thunder
	if debuff_type == "thunder":
		var stacks = card_data.get("stacks", 1)
		return BuffEffect.create_thunder(stacks, source.hero_id, source.owner_index, target.hero_id, target.owner_index, source_atk)
	
	return BuffEffect.create_debuff(debuff_type, duration, source.hero_id, source.owner_index, target.hero_id, target.owner_index, source_atk)

static func _create_shield_effect(card_data: Dictionary, source: HeroState, target: HeroState) -> ShieldEffect:
	## Create shield effect from card data
	var shield = card_data.get("shield", card_data.get("block", card_data.get("value", 0)))
	
	# Check for ATK scaling
	if card_data.has("atk_multiplier"):
		var base_atk = source.attack if source else 10
		shield = int(base_atk * card_data.get("atk_multiplier", 1.0))
	
	return ShieldEffect.create(shield, source.hero_id, source.owner_index, target.hero_id, target.owner_index)

static func _create_equipment_effects(card_data: Dictionary, source: HeroState, target: HeroState) -> Array:
	## Create effects for equipment card
	var effects: Array = []
	
	# Equipment typically applies buffs
	if card_data.has("buff_type"):
		effects.append(_create_buff_effect(card_data, source, target))
	
	# Equipment might also have stat bonuses
	if card_data.has("shield") or card_data.has("block"):
		effects.append(_create_shield_effect(card_data, source, target))
	
	if card_data.has("heal"):
		effects.append(_create_heal_effect(card_data, source, target))
	
	return effects

static func _create_effects_from_data(card_data: Dictionary, source: HeroState, target: HeroState) -> Array:
	## Infer effects from card data when type is not specified
	var effects: Array = []
	
	# Check for damage
	if card_data.has("damage") or (card_data.has("atk_multiplier") and card_data.get("type", "") != "heal"):
		effects.append(_create_damage_effect(card_data, source, target))
	
	# Check for heal
	if card_data.has("heal"):
		effects.append(_create_heal_effect(card_data, source, target))
	
	# Check for shield
	if card_data.has("shield") or card_data.has("block"):
		effects.append(_create_shield_effect(card_data, source, target))
	
	# Check for buff
	if card_data.has("buff_type") or card_data.has("buff"):
		effects.append(_create_buff_effect(card_data, source, target))
	
	# Check for debuff
	if card_data.has("debuff_type") or card_data.has("debuff"):
		effects.append(_create_debuff_effect(card_data, source, target))
	
	return effects

# ============================================
# CREATE FROM EX SKILL DATA
# ============================================

static func create_effects_from_ex_skill(hero_data: Dictionary, source: HeroState, target: HeroState) -> Array:
	## Create effects from a hero's EX skill
	var effects: Array = []
	
	var ex_skill = hero_data.get("ex_skill", {})
	if ex_skill.is_empty():
		return effects
	
	var skill_type = ex_skill.get("type", "damage")
	var value = ex_skill.get("value", 0)
	var atk_mult = ex_skill.get("atk_multiplier", 1.0)
	
	# Calculate value from ATK multiplier if specified
	if atk_mult > 0:
		value = int(source.attack * atk_mult)
	
	match skill_type:
		"damage":
			effects.append(DamageEffect.create(value, source.hero_id, source.owner_index, target.hero_id, target.owner_index))
		"heal":
			effects.append(HealEffect.create(value, source.hero_id, source.owner_index, target.hero_id, target.owner_index))
		"buff":
			var buff_type = ex_skill.get("buff_type", "empower")
			var duration = ex_skill.get("duration", 2)
			effects.append(BuffEffect.create_buff(buff_type, duration, source.hero_id, source.owner_index, target.hero_id, target.owner_index, source.attack))
		"debuff":
			var debuff_type = ex_skill.get("debuff_type", "stun")
			var duration = ex_skill.get("duration", 1)
			effects.append(BuffEffect.create_debuff(debuff_type, duration, source.hero_id, source.owner_index, target.hero_id, target.owner_index, source.attack))
		"shield":
			effects.append(ShieldEffect.create(value, source.hero_id, source.owner_index, target.hero_id, target.owner_index))
	
	# Check for secondary effects
	if ex_skill.has("secondary_effect"):
		var secondary = ex_skill.get("secondary_effect", {})
		var secondary_effects = _create_effects_from_data(secondary, source, target)
		effects.append_array(secondary_effects)
	
	return effects

# ============================================
# CREATE TURN EFFECTS
# ============================================

static func create_turn_start_effects(hero: HeroState) -> Array:
	## Create effects that trigger at turn start (regen, etc.)
	var effects: Array = []
	
	# Regeneration
	if hero.has_buff("regen"):
		var regen = hero.get_buff("regen")
		var heal_amount = int(regen.source_atk * GameConstants.REGEN_HEAL_MULT)
		effects.append(HealEffect.create(heal_amount, hero.hero_id, hero.owner_index, hero.hero_id, hero.owner_index))
	
	# Poison damage at turn start
	if hero.has_debuff("poison"):
		var poison = hero.get_debuff("poison")
		var damage = int(poison.source_atk * 0.5)
		var effect = DamageEffect.create(damage, poison.source_hero_id, 1 - hero.owner_index, hero.hero_id, hero.owner_index)
		effect.ignore_shield = true  # Poison bypasses shield
		effects.append(effect)
	
	return effects

static func create_turn_end_effects(hero: HeroState) -> Array:
	## Create effects that trigger at turn end (burn, thunder, etc.)
	var effects: Array = []
	
	# Burn damage
	if hero.has_debuff("burn"):
		var burn = hero.get_debuff("burn")
		var damage = int(burn.source_atk * 0.5)
		var effect = DamageEffect.create(damage, burn.source_hero_id, 1 - hero.owner_index, hero.hero_id, hero.owner_index)
		effects.append(effect)
	
	# Thunder is handled separately via tick_thunder()
	
	return effects
