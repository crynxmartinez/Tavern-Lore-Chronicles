class_name BattleUIAdapter
extends RefCounted

## BattleUIAdapter - Bridges the new OOP battle system with the existing battle.gd UI
## Subscribes to EventBus events and calls appropriate UI methods

var battle_ui: Node = null  # Reference to battle.gd
var event_bus: BattleEventBus = null
var battle_controller: BattleController = null

# ============================================
# INITIALIZATION
# ============================================

static func create(ui: Node, bus: BattleEventBus, controller: BattleController) -> BattleUIAdapter:
	var adapter = BattleUIAdapter.new()
	adapter.battle_ui = ui
	adapter.event_bus = bus
	adapter.battle_controller = controller
	adapter._connect_events()
	return adapter

func _connect_events() -> void:
	if event_bus == null:
		return
	
	# Game events
	event_bus.battle_started.connect(_on_battle_started)
	event_bus.battle_ended.connect(_on_battle_ended)
	event_bus.turn_started.connect(_on_turn_started)
	event_bus.turn_ended.connect(_on_turn_ended)
	
	# Effect events
	event_bus.damage_dealt.connect(_on_damage_dealt)
	event_bus.heal_applied.connect(_on_heal_applied)
	event_bus.buff_applied.connect(_on_buff_applied)
	event_bus.debuff_applied.connect(_on_debuff_applied)
	event_bus.shield_gained.connect(_on_shield_gained)
	event_bus.shield_broken.connect(_on_shield_broken)
	
	# Hero events
	event_bus.hero_hp_changed.connect(_on_hero_hp_changed)
	event_bus.hero_energy_changed.connect(_on_hero_energy_changed)
	event_bus.hero_died.connect(_on_hero_died)
	event_bus.hero_ex_used.connect(_on_hero_ex_used)
	
	# Card events
	event_bus.card_played.connect(_on_card_played)
	event_bus.hand_changed.connect(_on_hand_changed)
	
	# Mana events
	event_bus.mana_changed.connect(_on_mana_changed)
	
	# Animation requests
	event_bus.request_damage_animation.connect(_on_request_damage_animation)
	event_bus.request_heal_animation.connect(_on_request_heal_animation)
	event_bus.request_death_animation.connect(_on_request_death_animation)
	event_bus.request_card_play_animation.connect(_on_request_card_play_animation)

func disconnect_events() -> void:
	if event_bus == null:
		return
	
	# Disconnect all signals
	if event_bus.battle_started.is_connected(_on_battle_started):
		event_bus.battle_started.disconnect(_on_battle_started)
	if event_bus.battle_ended.is_connected(_on_battle_ended):
		event_bus.battle_ended.disconnect(_on_battle_ended)
	# ... (disconnect others as needed)

# ============================================
# GAME EVENT HANDLERS
# ============================================

func _on_battle_started(game_state: GameState) -> void:
	print("BattleUIAdapter: Battle started")
	# UI initialization is handled by battle.gd directly

func _on_battle_ended(winner_index: int, reason: String) -> void:
	print("BattleUIAdapter: Battle ended - Winner: ", winner_index, " Reason: ", reason)
	if battle_ui and battle_ui.has_method("_show_game_over"):
		var we_won = (winner_index == battle_controller.local_player_index)
		battle_ui._show_game_over(we_won)

func _on_turn_started(player_index: int, turn_number: int) -> void:
	print("BattleUIAdapter: Turn started - Player: ", player_index, " Turn: ", turn_number)
	if battle_ui:
		# Update turn indicator
		var is_my_turn = (player_index == battle_controller.local_player_index)
		if battle_ui.has_method("_update_turn_indicator"):
			battle_ui._update_turn_indicator(is_my_turn)
		
		# Enable/disable controls
		if battle_ui.has_method("_set_controls_enabled"):
			battle_ui._set_controls_enabled(is_my_turn)

func _on_turn_ended(player_index: int) -> void:
	print("BattleUIAdapter: Turn ended - Player: ", player_index)

# ============================================
# EFFECT EVENT HANDLERS
# ============================================

func _on_damage_dealt(source_hero_id: String, target_hero_id: String, amount: int, is_critical: bool) -> void:
	print("BattleUIAdapter: Damage dealt - ", source_hero_id, " -> ", target_hero_id, " for ", amount)
	# Damage animation is handled by request_damage_animation

func _on_heal_applied(source_hero_id: String, target_hero_id: String, amount: int) -> void:
	print("BattleUIAdapter: Heal applied - ", target_hero_id, " for ", amount)
	# Heal animation is handled by request_heal_animation

func _on_buff_applied(target_hero_id: String, buff_type: String, duration: int) -> void:
	print("BattleUIAdapter: Buff applied - ", target_hero_id, " got ", buff_type)
	_update_hero_buffs(target_hero_id)

func _on_debuff_applied(target_hero_id: String, debuff_type: String, duration: int) -> void:
	print("BattleUIAdapter: Debuff applied - ", target_hero_id, " got ", debuff_type)
	_update_hero_buffs(target_hero_id)

func _on_shield_gained(target_hero_id: String, amount: int) -> void:
	print("BattleUIAdapter: Shield gained - ", target_hero_id, " got ", amount)
	_update_hero_ui(target_hero_id)

func _on_shield_broken(target_hero_id: String) -> void:
	print("BattleUIAdapter: Shield broken - ", target_hero_id)
	_update_hero_ui(target_hero_id)

# ============================================
# HERO EVENT HANDLERS
# ============================================

func _on_hero_hp_changed(hero_id: String, owner_index: int, old_hp: int, new_hp: int, max_hp: int) -> void:
	_update_hero_ui(hero_id, owner_index)

func _on_hero_energy_changed(hero_id: String, owner_index: int, old_energy: int, new_energy: int) -> void:
	_update_hero_ui(hero_id, owner_index)

func _on_hero_died(hero_id: String, owner_index: int, killer_hero_id: String) -> void:
	print("BattleUIAdapter: Hero died - ", hero_id)
	_update_hero_ui(hero_id, owner_index)

func _on_hero_ex_used(hero_id: String, owner_index: int, target_hero_id: String) -> void:
	print("BattleUIAdapter: EX skill used - ", hero_id, " -> ", target_hero_id)

# ============================================
# CARD EVENT HANDLERS
# ============================================

func _on_card_played(player_index: int, card_data: Dictionary, source_hero_id: String, target_hero_id: String) -> void:
	print("BattleUIAdapter: Card played - ", card_data.get("name", "Unknown"))
	# Card animation is handled by request_card_play_animation

func _on_hand_changed(player_index: int, hand_count: int) -> void:
	print("BattleUIAdapter: Hand changed - Player: ", player_index, " Count: ", hand_count)
	if player_index == battle_controller.local_player_index:
		# Refresh local hand display
		if battle_ui and battle_ui.has_method("_refresh_hand_display"):
			battle_ui._refresh_hand_display()
	else:
		# Update enemy hand count display
		if battle_ui and battle_ui.has_method("_refresh_enemy_hand_display"):
			battle_ui._refresh_enemy_hand_display()

# ============================================
# MANA EVENT HANDLERS
# ============================================

func _on_mana_changed(player_index: int, current_mana: int, max_mana: int) -> void:
	if battle_ui and battle_ui.has_method("_update_mana_display"):
		battle_ui._update_mana_display(player_index, current_mana, max_mana)

# ============================================
# ANIMATION REQUEST HANDLERS
# ============================================

func _on_request_damage_animation(target_hero_id: String, owner_index: int, amount: int) -> void:
	var hero_node = _find_hero_node(target_hero_id, owner_index)
	if hero_node and hero_node.has_method("_spawn_floating_number"):
		hero_node._spawn_floating_number(amount, Color(1.0, 0.2, 0.2))
	if hero_node and hero_node.has_method("_play_hit_animation"):
		hero_node._play_hit_animation()

func _on_request_heal_animation(target_hero_id: String, owner_index: int, amount: int) -> void:
	var hero_node = _find_hero_node(target_hero_id, owner_index)
	if hero_node and hero_node.has_method("_show_heal_effect"):
		hero_node._show_heal_effect(amount)

func _on_request_death_animation(hero_id: String, owner_index: int) -> void:
	var hero_node = _find_hero_node(hero_id, owner_index)
	if hero_node and hero_node.has_method("die"):
		hero_node.die()

func _on_request_card_play_animation(card_data: Dictionary, source_hero_id: String, target_hero_id: String) -> void:
	if battle_ui and battle_ui.has_method("_show_card_display"):
		battle_ui._show_card_display(card_data)

# ============================================
# UI UPDATE HELPERS
# ============================================

func _find_hero_node(hero_id: String, owner_index: int) -> Node:
	## Find the Hero UI node for a given hero
	if battle_ui == null:
		return null
	
	var is_my_hero = (owner_index == battle_controller.local_player_index)
	var hero_array_name = "player_heroes" if is_my_hero else "enemy_heroes"
	
	if battle_ui.has(hero_array_name):
		var heroes = battle_ui.get(hero_array_name)
		for hero in heroes:
			if hero.hero_id == hero_id:
				return hero
	
	return null

func _update_hero_ui(hero_id: String, owner_index: int = -1) -> void:
	## Update a hero's UI to reflect current state
	if owner_index < 0:
		# Try to find owner from game state
		var hero_state = battle_controller.game_state.find_hero_by_id_any_player(hero_id)
		if hero_state:
			owner_index = hero_state.owner_index
		else:
			return
	
	var hero_node = _find_hero_node(hero_id, owner_index)
	if hero_node == null:
		return
	
	# Get hero state
	var hero_state = battle_controller.get_hero(hero_id, owner_index)
	if hero_state == null:
		return
	
	# Update HP
	if hero_node.has_method("_update_ui"):
		# Sync state to UI node
		hero_node.current_hp = hero_state.hp
		hero_node.max_hp = hero_state.max_hp
		hero_node.energy = hero_state.energy
		hero_node.block = hero_state.block
		hero_node.is_dead = hero_state.is_dead
		hero_node._update_ui()

func _update_hero_buffs(hero_id: String) -> void:
	## Update buff icons for a hero
	# This would sync BuffState to the Hero UI node's active_buffs/active_debuffs
	pass

# ============================================
# ACTION HELPERS (for UI to call)
# ============================================

func play_card(card_data: Dictionary, source_hero_id: String, target_hero_id: String, target_owner: int, hand_index: int = -1) -> bool:
	## Called by UI when player plays a card
	var result = battle_controller.play_card(card_data, source_hero_id, target_hero_id, target_owner, hand_index)
	return result.success

func use_ex_skill(source_hero_id: String, target_hero_id: String = "", target_owner: int = 0) -> bool:
	## Called by UI when player uses EX skill
	var result = battle_controller.use_ex_skill(source_hero_id, target_hero_id, target_owner)
	return result.success

func end_turn() -> bool:
	## Called by UI when player ends turn
	var result = battle_controller.end_turn()
	return result.success

func is_my_turn() -> bool:
	return battle_controller.is_my_turn()

func can_afford_card(card_data: Dictionary) -> bool:
	var player = battle_controller.get_local_player()
	if player == null:
		return false
	return player.can_afford(card_data.get("cost", 0))
