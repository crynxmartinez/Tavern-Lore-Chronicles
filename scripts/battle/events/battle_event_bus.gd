class_name BattleEventBus
extends Node

## BattleEventBus - Central event dispatcher for battle events
## Decouples game logic from UI - UI subscribes to events and reacts
## Can be used as autoload or instantiated per battle

# ============================================
# GAME EVENTS
# ============================================

signal battle_started(game_state: GameState)
signal battle_ended(winner_index: int, reason: String)
signal turn_started(player_index: int, turn_number: int)
signal turn_ended(player_index: int)
signal phase_changed(new_phase: int)

# ============================================
# ACTION EVENTS
# ============================================

signal action_validated(action_type: String, is_valid: bool, reason: String)
signal action_executed(action_type: String, player_index: int, result: Dictionary)
signal action_received(action_type: String, from_player_index: int, action_data: Dictionary)

# ============================================
# CARD EVENTS
# ============================================

signal card_played(player_index: int, card_data: Dictionary, source_hero_id: String, target_hero_id: String)
signal card_drawn(player_index: int, count: int)
signal card_discarded(player_index: int, card_data: Dictionary)
signal hand_changed(player_index: int, hand_count: int)
signal deck_changed(player_index: int, deck_count: int)

# ============================================
# EFFECT EVENTS
# ============================================

signal damage_dealt(source_hero_id: String, target_hero_id: String, amount: int, is_critical: bool)
signal heal_applied(source_hero_id: String, target_hero_id: String, amount: int)
signal buff_applied(target_hero_id: String, buff_type: String, duration: int)
signal buff_removed(target_hero_id: String, buff_type: String)
signal debuff_applied(target_hero_id: String, debuff_type: String, duration: int)
signal debuff_removed(target_hero_id: String, debuff_type: String)
signal shield_gained(target_hero_id: String, amount: int)
signal shield_broken(target_hero_id: String)
signal shield_absorbed(target_hero_id: String, amount: int)

# ============================================
# HERO EVENTS
# ============================================

signal hero_hp_changed(hero_id: String, owner_index: int, old_hp: int, new_hp: int, max_hp: int)
signal hero_energy_changed(hero_id: String, owner_index: int, old_energy: int, new_energy: int)
signal hero_energy_full(hero_id: String, owner_index: int)
signal hero_died(hero_id: String, owner_index: int, killer_hero_id: String)
signal hero_ex_used(hero_id: String, owner_index: int, target_hero_id: String)
signal hero_attacked(source_hero_id: String, target_hero_id: String)

# ============================================
# MANA EVENTS
# ============================================

signal mana_changed(player_index: int, current_mana: int, max_mana: int)
signal mana_spent(player_index: int, amount: int)

# ============================================
# NETWORK EVENTS
# ============================================

signal opponent_connected(player_info: Dictionary)
signal opponent_disconnected(reason: String)
signal sync_started()
signal sync_completed()
signal sync_failed(reason: String)
signal network_action_received(action_data: Dictionary)

# ============================================
# MULLIGAN EVENTS
# ============================================

signal mulligan_started(player_index: int)
signal mulligan_completed(player_index: int, cards_replaced: int)
signal mulligan_phase_ended()

# ============================================
# ANIMATION EVENTS (for UI to know when to animate)
# ============================================

signal request_damage_animation(target_hero_id: String, owner_index: int, amount: int)
signal request_heal_animation(target_hero_id: String, owner_index: int, amount: int)
signal request_buff_animation(target_hero_id: String, owner_index: int, buff_type: String)
signal request_debuff_animation(target_hero_id: String, owner_index: int, debuff_type: String)
signal request_death_animation(hero_id: String, owner_index: int)
signal request_card_play_animation(card_data: Dictionary, source_hero_id: String, target_hero_id: String)
signal request_ex_skill_animation(hero_id: String, owner_index: int, skill_type: String)

# ============================================
# EMIT HELPERS
# ============================================

func emit_damage(source_id: String, target_id: String, amount: int, is_crit: bool = false) -> void:
	damage_dealt.emit(source_id, target_id, amount, is_crit)

func emit_heal(source_id: String, target_id: String, amount: int) -> void:
	heal_applied.emit(source_id, target_id, amount)

func emit_hero_hp_change(hero_id: String, owner: int, old_hp: int, new_hp: int, max_hp: int) -> void:
	hero_hp_changed.emit(hero_id, owner, old_hp, new_hp, max_hp)
	
	# Also request animation
	if new_hp < old_hp:
		request_damage_animation.emit(hero_id, owner, old_hp - new_hp)
	elif new_hp > old_hp:
		request_heal_animation.emit(hero_id, owner, new_hp - old_hp)

func emit_hero_energy_change(hero_id: String, owner: int, old_energy: int, new_energy: int) -> void:
	hero_energy_changed.emit(hero_id, owner, old_energy, new_energy)
	
	# Check if energy is now full
	if new_energy >= GameConstants.MAX_ENERGY and old_energy < GameConstants.MAX_ENERGY:
		hero_energy_full.emit(hero_id, owner)

func emit_buff(target_id: String, owner: int, buff_type: String, duration: int) -> void:
	buff_applied.emit(target_id, buff_type, duration)
	request_buff_animation.emit(target_id, owner, buff_type)

func emit_debuff(target_id: String, owner: int, debuff_type: String, duration: int) -> void:
	debuff_applied.emit(target_id, debuff_type, duration)
	request_debuff_animation.emit(target_id, owner, debuff_type)

func emit_hero_death(hero_id: String, owner: int, killer_id: String = "") -> void:
	hero_died.emit(hero_id, owner, killer_id)
	request_death_animation.emit(hero_id, owner)

func emit_card_played(player: int, card: Dictionary, source_id: String, target_id: String) -> void:
	card_played.emit(player, card, source_id, target_id)
	request_card_play_animation.emit(card, source_id, target_id)

func emit_turn_start(player: int, turn: int) -> void:
	turn_started.emit(player, turn)

func emit_turn_end(player: int) -> void:
	turn_ended.emit(player)

func emit_battle_start(state: GameState) -> void:
	battle_started.emit(state)

func emit_battle_end(winner: int, reason: String) -> void:
	battle_ended.emit(winner, reason)

func emit_mana_change(player: int, current: int, max_val: int) -> void:
	mana_changed.emit(player, current, max_val)

# ============================================
# DEBUG
# ============================================

var _debug_mode: bool = false

func enable_debug() -> void:
	_debug_mode = true
	_connect_debug_listeners()

func _connect_debug_listeners() -> void:
	battle_started.connect(_debug_log.bind("battle_started"))
	battle_ended.connect(_debug_log.bind("battle_ended"))
	turn_started.connect(_debug_log.bind("turn_started"))
	turn_ended.connect(_debug_log.bind("turn_ended"))
	damage_dealt.connect(_debug_log.bind("damage_dealt"))
	heal_applied.connect(_debug_log.bind("heal_applied"))
	hero_died.connect(_debug_log.bind("hero_died"))
	card_played.connect(_debug_log.bind("card_played"))

func _debug_log(args, event_name: String) -> void:
	if _debug_mode:
		print("[BattleEventBus] %s: %s" % [event_name, str(args)])
