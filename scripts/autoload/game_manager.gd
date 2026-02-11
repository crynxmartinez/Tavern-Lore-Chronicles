extends Node

signal turn_started(is_player_turn: bool)
signal turn_ended(is_player_turn: bool)
signal mana_changed(current: int, max_mana: int)
signal game_over(player_won: bool)
signal phase_changed(phase: GamePhase)
signal hero_died(hero_id: String)
signal hero_revived(hero_id: String)
signal deck_shuffled()

enum GamePhase { MULLIGAN, PLAYER_TURN, ENEMY_TURN, GAME_OVER }

var current_phase: GamePhase = GamePhase.MULLIGAN
var is_player_turn: bool = true
var turn_number: int = 1

var current_mana: int = 3
var max_mana: int = 3

# Enemy mana (used in practice mode when player controls enemy team)
var enemy_current_mana: int = 3
var enemy_max_mana: int = 3

var last_rps_choice: int = 0  # 0=Rock, 1=Scissors, 2=Paper (persists across battles)
const MANA_CAP: int = 10

# Multiplayer flags
var is_multiplayer: bool = false
var is_host: bool = false
var opponent_client_id: int = -1

var player_heroes: Array = []
var enemy_heroes: Array = []

# Deck managers for player and enemy
var player_deck_manager: DeckManager
var enemy_deck_manager: DeckManager

# Legacy accessors for backwards compatibility
var deck: Array:
	get: return player_deck_manager.deck if player_deck_manager else []
var hand: Array:
	get: return player_deck_manager.hand if player_deck_manager else []
var discard_pile: Array:
	get: return player_deck_manager.discard_pile if player_deck_manager else []
var dead_hero_cards: Dictionary:
	get: return player_deck_manager.dead_hero_cards if player_deck_manager else {}

var enemy_deck: Array:
	get: return enemy_deck_manager.deck if enemy_deck_manager else []
var enemy_hand: Array:
	get: return enemy_deck_manager.hand if enemy_deck_manager else []
var enemy_discard_pile: Array:
	get: return enemy_deck_manager.discard_pile if enemy_deck_manager else []
var enemy_dead_hero_cards: Dictionary:
	get: return enemy_deck_manager.dead_hero_cards if enemy_deck_manager else {}

# Use GameConstants for these values
const HAND_SIZE: int = GameConstants.HAND_SIZE
const CARDS_PER_TURN: int = GameConstants.CARDS_PER_TURN
const STARTING_MANA: int = GameConstants.STARTING_MANA

func _ready() -> void:
	player_deck_manager = DeckManager.new("")
	enemy_deck_manager = DeckManager.new("enemy_")
	player_deck_manager.deck_shuffled.connect(_on_player_deck_shuffled)

func start_game() -> void:
	turn_number = 1
	current_mana = STARTING_MANA
	max_mana = STARTING_MANA
	current_phase = GamePhase.MULLIGAN
	phase_changed.emit(current_phase)

func start_mulligan() -> void:
	current_phase = GamePhase.MULLIGAN
	phase_changed.emit(current_phase)
	player_deck_manager.draw_cards(HAND_SIZE)

func finish_mulligan(cards_to_replace: Array) -> void:
	player_deck_manager.mulligan(cards_to_replace)
	# Don't auto-start player turn here - battle.gd handles who goes first based on RPS

func start_player_turn() -> void:
	is_player_turn = true
	current_phase = GamePhase.PLAYER_TURN
	
	if turn_number > 1:
		if max_mana < MANA_CAP:
			max_mana += 1
		current_mana = max_mana
		# Draw 3 cards per turn, up to max hand size
		var cards_to_draw = min(CARDS_PER_TURN, HAND_SIZE - player_deck_manager.get_hand_size())
		if cards_to_draw > 0:
			player_deck_manager.draw_cards(cards_to_draw)
	
	mana_changed.emit(current_mana, max_mana)
	turn_started.emit(true)
	phase_changed.emit(current_phase)
	# NOTE: hero.on_turn_start() is called by battle.gd in _on_turn_started()
	# to avoid double-calling regen/regen_draw and to handle regen_draw_triggered routing.

func end_player_turn() -> void:
	# NOTE: on_own_turn_end() is called by battle.gd before this function.
	# Only add energy here to avoid double buff/debuff expiry.
	for hero in player_heroes:
		if hero.has_method("add_energy"):
			hero.add_energy(GameConstants.ENERGY_ON_TURN_END)
	
	turn_ended.emit(true)
	start_enemy_turn()

func start_enemy_turn() -> void:
	is_player_turn = false
	current_phase = GamePhase.ENEMY_TURN
	# Update enemy mana (mirrors player mana logic)
	if turn_number > 1:
		if enemy_max_mana < MANA_CAP:
			enemy_max_mana += 1
		enemy_current_mana = enemy_max_mana
	turn_started.emit(false)
	phase_changed.emit(current_phase)

func practice_play_enemy_card(card_data: Dictionary, source_hero, target) -> bool:
	var cost = card_data.get("cost", 0)
	if cost == -1:
		if enemy_current_mana < 1:
			return false
		card_data["mana_spent"] = enemy_current_mana
		cost = enemy_current_mana
	if enemy_current_mana < cost:
		return false
	enemy_current_mana -= cost
	mana_changed.emit(enemy_current_mana, enemy_max_mana)
	if source_hero and source_hero.has_method("add_energy"):
		if card_data.get("type", "") == "attack":
			source_hero.add_energy(GameConstants.ENERGY_ON_ATTACK)
	enemy_deck_manager.play_card(card_data)
	return true

func end_enemy_turn() -> void:
	# NOTE: on_own_turn_end() is called by battle.gd before this function.
	# Only add energy here to avoid double buff/debuff expiry.
	for hero in enemy_heroes:
		if hero.has_method("add_energy"):
			hero.add_energy(GameConstants.ENERGY_ON_TURN_END)
	
	turn_ended.emit(false)
	turn_number += 1
	start_player_turn()

func draw_cards(count: int) -> Array:
	return player_deck_manager.draw_cards(count)

func reshuffle_discard_into_deck() -> void:
	player_deck_manager.reshuffle_discard_into_deck()

func _on_player_deck_shuffled() -> void:
	deck_shuffled.emit()

func play_card(card_data: Dictionary, source_hero, target) -> bool:
	var cost = card_data.get("cost", 0)
	
	# Handle Mana Surge (cost = -1 means use ALL mana)
	if cost == -1:
		if current_mana < 1:
			return false  # Need at least 1 mana
		# Store mana spent for damage calculation
		card_data["mana_spent"] = current_mana
		cost = current_mana
	
	if current_mana < cost:
		return false
	
	current_mana -= cost
	mana_changed.emit(current_mana, max_mana)
	
	if source_hero and source_hero.has_method("add_energy"):
		if card_data.get("type", "") == "attack":
			source_hero.add_energy(GameConstants.ENERGY_ON_ATTACK)
	
	player_deck_manager.play_card(card_data)
	return true

func spend_mana(amount: int) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		mana_changed.emit(current_mana, max_mana)
		return true
	return false

func check_game_over() -> void:
	var player_alive = false
	var enemy_alive = false
	
	for hero in player_heroes:
		if hero.current_hp > 0:
			player_alive = true
			break
	
	for hero in enemy_heroes:
		if hero.current_hp > 0:
			enemy_alive = true
			break
	
	if not player_alive:
		current_phase = GamePhase.GAME_OVER
		phase_changed.emit(current_phase)
		game_over.emit(false)
	elif not enemy_alive:
		current_phase = GamePhase.GAME_OVER
		phase_changed.emit(current_phase)
		game_over.emit(true)

func on_hero_died(hero_id: String, hero_color: String) -> void:
	player_deck_manager.on_hero_died(hero_id, hero_color)
	hero_died.emit(hero_id)

func on_hero_revived(hero_id: String) -> void:
	player_deck_manager.on_hero_revived(hero_id)
	hero_revived.emit(hero_id)

func play_mana_card() -> void:
	current_mana += 1
	mana_changed.emit(current_mana, max_mana)

func build_deck(heroes: Array, include_equipment: bool = true) -> void:
	player_deck_manager.build_from_heroes(heroes, include_equipment)

func build_deck_from_instances(hero_instances: Array, include_equipment: bool = false) -> void:
	player_deck_manager.build_from_hero_instances(hero_instances, include_equipment)

func build_enemy_deck(heroes: Array) -> void:
	enemy_deck_manager.build_from_heroes(heroes, false)  # false = no equipment

func build_enemy_deck_from_instances(hero_instances: Array) -> void:
	enemy_deck_manager.build_from_hero_instances(hero_instances, false)

func enemy_draw_cards(count: int) -> Array:
	return enemy_deck_manager.draw_cards(count)

func enemy_reshuffle_discard_into_deck() -> void:
	enemy_deck_manager.reshuffle_discard_into_deck()

func enemy_play_card(card_data: Dictionary, source_hero, target) -> bool:
	return enemy_deck_manager.play_card(card_data)

func enemy_mulligan(cards_to_replace_count: int) -> void:
	enemy_deck_manager.random_mulligan(cards_to_replace_count)

func enemy_smart_mulligan() -> int:
	# AI evaluates each card in hand and replaces bad ones
	var cards_to_replace = []
	for card in enemy_hand:
		var dominated = false
		var cost = card.get("cost", 0)
		var card_type = card.get("type", "attack")
		# Replace expensive cards (cost 3+) — want cheap openers
		if cost >= 3:
			dominated = true
		# Keep buffs/debuffs (setup cards) and mana/energy cards
		if card_type in ["buff", "mana", "energy"]:
			dominated = false
		# Keep 0-cost attacks always
		if card_type == "basic_attack" or cost == 0:
			dominated = false
		if dominated:
			cards_to_replace.append(card)
	# Cap at 2 replacements max
	if cards_to_replace.size() > 2:
		cards_to_replace.resize(2)
	if not cards_to_replace.is_empty():
		enemy_deck_manager.mulligan(cards_to_replace)
	return cards_to_replace.size()

func on_enemy_hero_died(hero_id: String, hero_color: String) -> void:
	enemy_deck_manager.on_hero_died(hero_id, hero_color)

func get_enemy_hand_size() -> int:
	return enemy_deck_manager.get_hand_size()

func get_enemy_deck_size() -> int:
	return enemy_deck_manager.get_deck_size()

# ============================================
# BATTLE STATS TRACKING
# ============================================

var battle_stats: Dictionary = {}

func reset_battle_stats() -> void:
	battle_stats.clear()

func init_hero_stats(hero_id: String, is_player: bool, portrait_path: String, hero_name: String) -> void:
	battle_stats[hero_id] = {
		"damage_dealt": 0,
		"shield_given": 0,
		"healing_done": 0,
		"ex_skills_used": 0,
		"is_player": is_player,
		"portrait": portrait_path,
		"name": hero_name
	}

func add_damage_dealt(hero_id: String, amount: int) -> void:
	if battle_stats.has(hero_id):
		battle_stats[hero_id]["damage_dealt"] += amount

func add_shield_given(hero_id: String, amount: int) -> void:
	if battle_stats.has(hero_id):
		battle_stats[hero_id]["shield_given"] += amount

func add_healing_done(hero_id: String, amount: int) -> void:
	if battle_stats.has(hero_id):
		battle_stats[hero_id]["healing_done"] += amount

func add_ex_skill_used(hero_id: String) -> void:
	if battle_stats.has(hero_id):
		battle_stats[hero_id]["ex_skills_used"] += 1

func get_battle_stats() -> Dictionary:
	return battle_stats
