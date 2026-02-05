class_name CardEffects
extends RefCounted

# Card effect application logic
# Extracted from battle.gd to reduce file size and improve maintainability

static func apply_effects(effects: Array, source: Node, target: Node, base_atk: int, card_data: Dictionary = {}, battle_context: Dictionary = {}) -> void:
	var player_heroes = battle_context.get("player_heroes", [])
	var enemy_heroes = battle_context.get("enemy_heroes", [])
	
	for effect in effects:
		match effect:
			"stun":
				if target and not target.is_dead:
					target.apply_debuff("stun", 1, base_atk)
			"weak":
				if target and not target.is_dead:
					target.apply_debuff("weak", 2, base_atk)
			"break":
				if target and not target.is_dead:
					target.apply_debuff("break", 2, base_atk)
			"taunt":
				if target and not target.is_dead:
					target.apply_buff("taunt", 2, base_atk)
				elif source and not source.is_dead:
					source.apply_buff("taunt", 2, base_atk)
			"empower":
				if source and not source.is_dead:
					source.apply_buff("empower", 2, base_atk)
			"empower_target":
				if target and not target.is_dead:
					target.apply_buff("empower", 2, base_atk)
			"empower_all":
				var allies = player_heroes if source and source.is_player_hero else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						ally.apply_buff("empower", 1, base_atk)
			"regen":
				if target and not target.is_dead:
					target.apply_buff("regen", 3, base_atk)
			"cleanse":
				if target and not target.is_dead:
					target.clear_all_debuffs()
			"thunder":
				if target and not target.is_dead:
					target.add_thunder_stacks(1, base_atk)
			"thunder_stack_2":
				if target and not target.is_dead and target.get_thunder_stacks() > 0:
					target.add_thunder_stacks(2, base_atk)
			"thunder_all":
				var targets = player_heroes if source and source.is_player_hero else enemy_heroes
				if source and not source.is_player_hero:
					targets = player_heroes
				else:
					targets = enemy_heroes
				for enemy in targets:
					if not enemy.is_dead:
						enemy.add_thunder_stacks(1, base_atk)
			"penetrate":
				# Handled separately in battle.gd due to position logic
				pass
			"shield_current_hp":
				if source and not source.is_dead:
					source.add_block(source.current_hp)
			"draw_1":
				# Signal to battle to draw a card
				if battle_context.has("draw_callback"):
					battle_context.draw_callback.call(1)
			"mana_surge":
				# Handled in play_card - damage scales with mana spent
				pass

static func calculate_damage(base_atk: int, atk_multiplier: float, damage_multiplier: float) -> int:
	var damage = int(base_atk * atk_multiplier * damage_multiplier)
	if damage == 0:
		damage = GameConstants.DEFAULT_BASE_ATTACK
	return damage

static func calculate_heal(base_atk: int, heal_multiplier: float) -> int:
	return int(base_atk * heal_multiplier)

static func calculate_shield(base_atk: int, shield_multiplier: float) -> int:
	return int(base_atk * shield_multiplier)
