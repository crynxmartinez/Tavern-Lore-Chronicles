class_name EnemyAI
extends RefCounted

# AI decision-making for enemy turns
# Extracted from battle.gd to reduce file size and improve maintainability

var battle_ref: Node  # Reference to battle scene for callbacks

func _init(battle: Node) -> void:
	battle_ref = battle

func get_card_priority(card: Dictionary, players: Array, enemies: Array) -> int:
	var card_type = card.get("type", "attack")
	var cost = card.get("cost", 0)
	var priority = 0
	
	if card_type == "attack":
		var atk_mult = card.get("atk_multiplier", 1.0)
		priority = int(atk_mult * 10)
		var target_type = card.get("target", "single")
		if target_type == "all_enemy":
			priority += players.size() * 2
	elif card_type == "heal":
		for enemy in enemies:
			if enemy.current_hp < enemy.max_hp * GameConstants.AI_HEAL_HP_THRESHOLD:
				priority += GameConstants.AI_HEAL_PRIORITY
	elif card_type == "buff":
		priority += GameConstants.AI_BUFF_PRIORITY
	elif card_type == "energy":
		priority += 2
	
	if cost == 0:
		priority += 1
	
	return priority

func get_best_target(targets: Array, action_type: String, get_taunt_func: Callable) -> Node:
	if targets.is_empty():
		return null
	
	if action_type == "damage":
		# Check for taunt - if any target has taunt, must target them
		var taunt_target = get_taunt_func.call(targets)
		if taunt_target:
			return taunt_target
		# Otherwise target the nearest player (last in array = position 4, closest to enemy)
		return targets[targets.size() - 1]
	elif action_type == "heal":
		var most_damaged = targets[0]
		for target in targets:
			var hp_percent = float(target.current_hp) / float(target.max_hp)
			var most_damaged_percent = float(most_damaged.current_hp) / float(most_damaged.max_hp)
			if hp_percent < most_damaged_percent:
				most_damaged = target
		return most_damaged
	elif action_type == "buff":
		return targets[randi() % targets.size()]
	
	return targets[0]

func select_action(alive_enemies: Array, alive_players: Array, mana: int, enemy_hand: Array, get_taunt_func: Callable) -> Dictionary:
	var result = {"action": null, "card": null, "attacker": null, "target": null, "cost": 0}
	
	# Filter out stunned enemies - they cannot act
	var non_stunned_enemies = alive_enemies.filter(func(e): return not e.has_debuff("stun"))
	
	if non_stunned_enemies.is_empty():
		return result  # All enemies are stunned, skip turn
	
	# Check for EX skills first (these don't use cards from hand)
	for enemy in non_stunned_enemies:
		if enemy.energy >= enemy.max_energy:
			var target = get_best_target(alive_players, "damage", get_taunt_func)
			if target:
				result.action = "ex_skill"
				result.attacker = enemy
				result.target = target
				result.cost = 0
				return result
	
	# Build possible actions from actual enemy hand
	var possible_actions = []
	
	for card in enemy_hand:
		var cost = card.get("cost", 0)
		if cost <= mana:
			# Find the enemy hero that matches this card's color (and is not stunned)
			var card_color = card.get("hero_color", "")
			var matching_enemy = null
			for enemy in non_stunned_enemies:
				if enemy.get_color() == card_color:
					matching_enemy = enemy
					break
			
			# If no matching hero found (dead or stunned), use any non-stunned enemy
			if matching_enemy == null and not non_stunned_enemies.is_empty():
				matching_enemy = non_stunned_enemies[0]
			
			if matching_enemy:
				possible_actions.append({
					"enemy": matching_enemy, 
					"card": card, 
					"priority": get_card_priority(card, alive_players, alive_enemies)
				})
	
	if possible_actions.is_empty():
		return result
	
	# Sort by priority and add some randomness
	possible_actions.sort_custom(func(a, b): return a.priority > b.priority)
	
	var chosen = possible_actions[0]
	if randf() < 0.3 and possible_actions.size() > 1:
		chosen = possible_actions[randi() % mini(3, possible_actions.size())]
	
	var card = chosen.card
	var attacker = chosen.enemy
	var card_type = card.get("type", "attack")
	
	result.card = card
	result.attacker = attacker
	result.cost = card.get("cost", 0)
	
	if card_type == "mana":
		result.action = "mana"
		result.cost = 0
	elif card_type == "energy":
		result.action = "energy"
	elif card_type == "attack":
		result.action = "attack"
		result.target = get_best_target(alive_players, "damage", get_taunt_func)
	elif card_type == "heal":
		result.action = "heal"
		result.target = get_best_target(alive_enemies, "heal", get_taunt_func)
	elif card_type == "buff":
		result.action = "buff"
		result.target = get_best_target(alive_enemies, "buff", get_taunt_func)
	
	return result
