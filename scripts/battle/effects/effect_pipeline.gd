class_name EffectPipeline
extends RefCounted

## EffectPipeline - Processes effects through a standardized pipeline
## Handles pre-checks, modifiers, application, and post-triggers

var event_bus: BattleEventBus = null

# ============================================
# INITIALIZATION
# ============================================

static func create(bus: BattleEventBus = null) -> EffectPipeline:
	var pipeline = EffectPipeline.new()
	pipeline.event_bus = bus
	return pipeline

# ============================================
# MAIN PIPELINE
# ============================================

func process_effect(effect: BaseEffect, game_state: GameState, source: HeroState, target: HeroState) -> BaseEffect.EffectResult:
	## Process a single effect through the pipeline
	
	# Step 1: Pre-effect checks
	if not _pre_effect_check(effect, game_state, source, target):
		var result = BaseEffect.EffectResult.new()
		result.success = false
		return result
	
	# Step 2: Apply the effect (effect handles its own modifiers)
	var result = effect.apply(game_state, source, target, event_bus)
	
	# Step 3: Post-effect processing
	_post_effect_process(effect, game_state, source, target, result)
	
	return result

func process_effects(effects: Array, game_state: GameState, source: HeroState, target: HeroState) -> Array:
	## Process multiple effects in sequence
	var results: Array = []
	
	for effect in effects:
		var result = process_effect(effect, game_state, source, target)
		results.append(result)
		
		# Check if target died - stop processing further effects on this target
		if result.caused_death:
			break
	
	return results

func process_aoe_effect(effect: BaseEffect, game_state: GameState, source: HeroState, targets: Array) -> Array:
	## Process an AOE effect on multiple targets
	var results: Array = []
	
	for target in targets:
		if target is HeroState and not target.is_dead:
			# Create a copy of the effect for each target
			var target_effect = _clone_effect_for_target(effect, target)
			var result = process_effect(target_effect, game_state, source, target)
			results.append(result)
	
	return results

# ============================================
# PIPELINE STEPS
# ============================================

func _pre_effect_check(effect: BaseEffect, game_state: GameState, source: HeroState, target: HeroState) -> bool:
	## Pre-effect validation
	
	# Check if effect can be applied
	if not effect.can_apply(game_state, source, target):
		return false
	
	# Check for immunity (future feature)
	# if target.has_buff("immune"):
	#     return false
	
	return true

func _post_effect_process(effect: BaseEffect, game_state: GameState, source: HeroState, target: HeroState, result: BaseEffect.EffectResult) -> void:
	## Post-effect processing
	
	if not result.success:
		return
	
	# Check win condition after damage
	if effect.effect_type == BaseEffect.EffectType.DAMAGE:
		game_state.check_win_condition()

func _clone_effect_for_target(effect: BaseEffect, target: HeroState) -> BaseEffect:
	## Create a copy of an effect with a new target
	# For now, just update the target info
	effect.target_hero_id = target.hero_id
	effect.target_owner_index = target.owner_index
	return effect

# ============================================
# CONVENIENCE METHODS
# ============================================

func deal_damage(game_state: GameState, source: HeroState, target: HeroState, amount: int) -> BaseEffect.EffectResult:
	## Quick method to deal damage
	var effect = DamageEffect.create(amount, source.hero_id, source.owner_index, target.hero_id, target.owner_index)
	return process_effect(effect, game_state, source, target)

func heal_target(game_state: GameState, source: HeroState, target: HeroState, amount: int) -> BaseEffect.EffectResult:
	## Quick method to heal
	var effect = HealEffect.create(amount, source.hero_id, source.owner_index, target.hero_id, target.owner_index)
	return process_effect(effect, game_state, source, target)

func apply_buff(game_state: GameState, source: HeroState, target: HeroState, buff_type: String, duration: int) -> BaseEffect.EffectResult:
	## Quick method to apply buff
	var effect = BuffEffect.create_buff(buff_type, duration, source.hero_id, source.owner_index, target.hero_id, target.owner_index, source.attack)
	return process_effect(effect, game_state, source, target)

func apply_debuff(game_state: GameState, source: HeroState, target: HeroState, debuff_type: String, duration: int) -> BaseEffect.EffectResult:
	## Quick method to apply debuff
	var effect = BuffEffect.create_debuff(debuff_type, duration, source.hero_id, source.owner_index, target.hero_id, target.owner_index, source.attack)
	return process_effect(effect, game_state, source, target)

func add_shield(game_state: GameState, source: HeroState, target: HeroState, amount: int) -> BaseEffect.EffectResult:
	## Quick method to add shield
	var effect = ShieldEffect.create(amount, source.hero_id, source.owner_index, target.hero_id, target.owner_index)
	return process_effect(effect, game_state, source, target)

func add_energy(game_state: GameState, source: HeroState, target: HeroState, amount: int) -> BaseEffect.EffectResult:
	## Quick method to add energy
	var effect = EnergyEffect.create(amount, source.hero_id, source.owner_index, target.hero_id, target.owner_index)
	return process_effect(effect, game_state, source, target)
