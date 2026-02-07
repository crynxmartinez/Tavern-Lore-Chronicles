extends Control

enum BattlePhase { MULLIGAN, PLAYING, TARGETING, EX_TARGETING, ENEMY_TURN, GAME_OVER }

# Safe audio/VFX helper functions
func _play_audio(method: String, args: Array = []) -> void:
	if Engine.has_singleton("AudioManager") or has_node("/root/AudioManager"):
		var audio = get_node_or_null("/root/AudioManager")
		if audio and audio.has_method(method):
			audio.callv(method, args)

func _play_vfx(method: String, args: Array = []) -> void:
	if Engine.has_singleton("VFXManager") or has_node("/root/VFXManager"):
		var vfx = get_node_or_null("/root/VFXManager")
		if vfx and vfx.has_method(method):
			vfx.callv(method, args)

var current_phase: BattlePhase = BattlePhase.MULLIGAN
var selected_card: Card = null
var mulligan_selections: Array = []

# Card queue system for rapid clicking
var card_queue: Array = []  # Array of {card: Card, target: Hero or null}
var is_casting: bool = false
var queued_card_visuals: Array = []  # Flying card visuals for queued cards

@onready var hand_container: HBoxContainer = $HandArea/HandContainer
@onready var mana_label: Label = $UI/ManaDisplay/ManaLabel
@onready var deck_label: Label = $UI/DeckDisplay/DeckLabel
@onready var deck_display: Control = $UI/DeckDisplay
@onready var turn_indicator: Label = $UI/TurnIndicator
@onready var turn_label: Label = $UI/TurnDisplay/TurnLabel
@onready var enemy_hand_container: HBoxContainer = $UI/EnemyInfoPanel/EnemyHandContainer
@onready var enemy_hand_label: Label = $UI/EnemyInfoPanel/EnemyHandLabel
@onready var enemy_deck_label: Label = $UI/EnemyInfoPanel/EnemyDeckLabel
@onready var enemy_name_label: Label = $UI/EnemyInfoPanel/EnemyNameLabel
@onready var end_turn_button: Button = $UI/EndTurnButton/EndTurnBtn
@onready var mulligan_panel: Panel = $MulliganPanel
@onready var mulligan_button: Button = $MulliganPanel/ConfirmMulligan
@onready var game_over_panel: Panel = $GameOverPanel
@onready var game_over_label: Label = $GameOverPanel/ResultLabel
@onready var card_display_container: Control = $CardDisplay
var _displayed_card_instance: Card = null  # Instantiated Card scene for display
@onready var deck_icon: TextureRect = $UI/DeckDisplay/DeckIcon
@onready var mana_display: Control = $UI/ManaDisplay
@onready var turn_icon: TextureRect = $UI/TurnDisplay/TurnIcon
@onready var end_turn_bg: TextureRect = $UI/EndTurnButton/EndTurnBG
@onready var end_turn_label: Label = $UI/EndTurnButton/EndTurnLabel
@onready var turn_display: Control = $UI/TurnDisplay
@onready var end_turn_container: Control = $UI/EndTurnButton
@onready var concede_button: Button = $UI/ConcedeButton

var cardback_texture = preload("res://asset/card template/cardback_Default.png")
var player_turn_diamond = preload("res://asset/Others/turn.png")
var opponent_turn_diamond = preload("res://asset/Others/opponents turn diamond.png")
var player_endturn_bg = preload("res://asset/Others/endturn.png")
var opponent_endturn_bg = preload("res://asset/Others/opponents turn.png")
var last_mana: int = 0

# Animation layer for flying cards
var animation_layer: CanvasLayer
var enemy_hand_count: int = 5
var enemy_deck_count: int = 0  # Will be set based on actual deck size

var card_scene = preload("res://scenes/components/card.tscn")
var hero_scene = preload("res://scenes/components/hero.tscn")
var card_selection_scene = preload("res://scenes/components/card_selection_ui.tscn")
# ENet-based network manager for multiplayer
var battle_network_manager_script = preload("res://scripts/battle/battle_network_manager_enet.gd")

var card_selection_ui: CardSelectionUI = null

var player_heroes: Array = []
var enemy_heroes: Array = []
var ex_skill_hero: Hero = null
var targeting_vignette: ColorRect = null

# Multiplayer
var is_multiplayer: bool = false
var is_host: bool = false
var network_manager = null  # BattleNetworkManager instance
var waiting_for_opponent: bool = false
var my_player_id: String = ""  # My account UID
var opponent_player_id: String = ""  # Opponent's account UID

func _ready() -> void:
	GameManager.mana_changed.connect(_on_mana_changed)
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.game_over.connect(_on_game_over)
	GameManager.deck_shuffled.connect(_on_deck_shuffled)
	
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	mulligan_button.pressed.connect(_on_mulligan_confirm)
	if concede_button:
		concede_button.pressed.connect(_on_concede_pressed)
	
	# Setup button hover effects
	_setup_button_hover(end_turn_button)
	_setup_button_hover(mulligan_button)
	if concede_button:
		_setup_button_hover(concede_button)
	
	game_over_panel.visible = false
	# Hide the old DisplayedCard node (we use instantiated Card scenes now)
	var old_displayed = card_display_container.get_node_or_null("DisplayedCard")
	if old_displayed:
		old_displayed.visible = false
	
	# Create animation layer for flying cards (above everything)
	animation_layer = CanvasLayer.new()
	animation_layer.layer = 10
	add_child(animation_layer)
	
	# Create card selection UI for dig/search/discard mechanics
	card_selection_ui = card_selection_scene.instantiate()
	add_child(card_selection_ui)
	card_selection_ui.visible = false
	
	_setup_battle()

func _setup_battle() -> void:
	# Check if this is a multiplayer battle
	_setup_multiplayer()
	
	var player_team = HeroDatabase.get_current_team()
	
	if is_multiplayer:
		# In multiplayer, we need to exchange teams with opponent
		await _setup_multiplayer_battle(player_team)
	else:
		# AI battle: enemy team is reversed player team
		var enemy_team = player_team.duplicate()
		enemy_team.reverse()
		_finalize_battle_setup(player_team, enemy_team)

func _setup_multiplayer_battle(player_team: Array) -> void:
	# Show waiting message
	if turn_indicator:
		turn_indicator.text = "Syncing with opponent..."
	
	# Wait a moment to ensure both clients have their BattleNetworkManager ready
	# This prevents RPC calls from arriving before the node exists
	await get_tree().create_timer(0.5).timeout
	
	print("Battle: _setup_multiplayer_battle - my team: ", player_team)
	
	# Send our team to opponent
	if network_manager:
		network_manager.send_team(player_team)
		
		# Connect to receive opponent team
		if not network_manager.opponent_team_received.is_connected(_on_opponent_team_received):
			network_manager.opponent_team_received.connect(_on_opponent_team_received)
	
	# Wait for opponent team (with timeout)
	var timeout = 10.0
	var elapsed = 0.0
	while network_manager and not network_manager.opponent_team_received_flag and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	
	if network_manager and network_manager.opponent_team_received_flag:
		var enemy_team = network_manager.opponent_team
		print("Battle: Received opponent team: ", enemy_team)
		_finalize_battle_setup(player_team, enemy_team)
	else:
		print("Battle: Timeout waiting for opponent team, using fallback")
		var enemy_team = player_team.duplicate()
		enemy_team.reverse()
		_finalize_battle_setup(player_team, enemy_team)

func _on_opponent_team_received(team: Array) -> void:
	print("Battle: Opponent team received via signal: ", team)

func _finalize_battle_setup(player_team: Array, enemy_team: Array) -> void:
	var role = "[HOST]" if is_host else "[GUEST]"
	print("Battle: ", role, " _finalize_battle_setup called")
	print("  player_team (MY heroes): ", player_team)
	print("  enemy_team (OPPONENT heroes): ", enemy_team)
	
	_spawn_heroes(player_team, true)
	_spawn_heroes(enemy_team, false)
	
	print("Battle: After spawning - player_heroes count: ", player_heroes.size())
	print("Battle: After spawning - enemy_heroes count: ", enemy_heroes.size())
	for h in player_heroes:
		print("  Player hero: ", h.hero_id, " at ", h.position)
	for h in enemy_heroes:
		print("  Enemy hero: ", h.hero_id, " at ", h.position)
	
	GameManager.player_heroes = player_heroes
	GameManager.enemy_heroes = enemy_heroes
	
	# Reset and initialize battle stats
	GameManager.reset_battle_stats()
	for hero in player_heroes:
		var hero_data = hero.hero_data
		GameManager.init_hero_stats(
			hero.hero_id,
			true,
			hero_data.get("portrait", ""),
			hero_data.get("name", "Hero")
		)
	for hero in enemy_heroes:
		var hero_data = hero.hero_data
		GameManager.init_hero_stats(
			"enemy_" + hero.hero_id,
			false,
			hero_data.get("portrait", ""),
			hero_data.get("name", "Hero")
		)
	
	# Build player deck
	var hero_data_list = []
	for hero_id in player_team:
		hero_data_list.append(HeroDatabase.get_hero(hero_id))
	GameManager.build_deck(hero_data_list)
	
	# Build enemy deck (only for AI battles - in multiplayer, opponent manages their own deck)
	if not is_multiplayer:
		var enemy_hero_data_list = []
		for hero_id in enemy_team:
			enemy_hero_data_list.append(HeroDatabase.get_hero(hero_id))
		GameManager.build_enemy_deck(enemy_hero_data_list)
		
		# Enemy draws initial hand (same as player starting hand)
		GameManager.enemy_draw_cards(5)
	
	_setup_enemy_hand_display()
	_start_rps_minigame()

const PLAYER_HERO_POSITIONS = [
	Vector2(120, 285),  # Position 1
	Vector2(320, 285),  # Position 2
	Vector2(520, 285),  # Position 3
	Vector2(720, 285),  # Position 4
]

const ENEMY_HERO_POSITIONS = [
	Vector2(1160, 285), # Position 5 - front enemy (closest to center)
	Vector2(1360, 285), # Position 6
	Vector2(1560, 285), # Position 7
	Vector2(1760, 285), # Position 8 - back enemy (furthest right)
]

const PLAYER_HERO_Z_INDEX = [0, 1, 2, 3]
const ENEMY_HERO_Z_INDEX = [3, 2, 1, 0]

func _spawn_heroes(team: Array, is_player: bool) -> void:
	print("Battle: _spawn_heroes called - is_player: ", is_player, " team: ", team)
	
	var positions = PLAYER_HERO_POSITIONS if is_player else ENEMY_HERO_POSITIONS
	var z_indices = PLAYER_HERO_Z_INDEX if is_player else ENEMY_HERO_Z_INDEX
	
	# In multiplayer, reverse enemy hero order so positions mirror correctly:
	# Opponent's hero[0] (their back) → our furthest enemy position
	# Opponent's hero[3] (their front/nearest) → our nearest enemy position
	var spawn_team = team.duplicate()
	if is_multiplayer and not is_player:
		spawn_team.reverse()
		print("Battle: Reversed enemy team order for multiplayer mirroring: ", spawn_team)
	
	# Clear the appropriate array directly (not via reference)
	if is_player:
		player_heroes.clear()
	else:
		enemy_heroes.clear()
	
	var hero_count = spawn_team.size()
	# Determine the owner's player_id for deterministic instance_id generation
	# Both sides compute the SAME instance_id for any hero using: owner_short_heroId_origPos
	var owner_pid = my_player_id if is_player else opponent_player_id
	# Use last 8 chars of player_id as short prefix for readability
	var owner_short = owner_pid.substr(max(0, owner_pid.length() - 8)) if not owner_pid.is_empty() else ("p" if is_player else "e")
	for i in range(hero_count):
		var hero_id = spawn_team[i]
		var hero_instance = hero_scene.instantiate()
		# Add directly to Board instead of HBoxContainer for absolute positioning
		$Board.add_child(hero_instance)
		hero_instance.setup(hero_id)
		hero_instance.is_player_hero = is_player
		# Generate deterministic instance_id: ownerShort_heroId_originalPosition
		# Note: i is the spawn position (may be reversed for enemy in MP), 
		# but we use the ORIGINAL team index for consistency.
		# For enemy in MP, spawn_team is reversed, so original index = (hero_count - 1 - i)
		var original_index = i
		if is_multiplayer and not is_player:
			original_index = hero_count - 1 - i  # Undo the reverse to get original team index
		hero_instance.instance_id = owner_short + "_" + hero_id + "_" + str(original_index)
		# Tag hero with owner's player_id
		if is_multiplayer:
			hero_instance.owner_id = owner_pid
		hero_instance.hero_clicked.connect(_on_hero_clicked)
		hero_instance.hero_died.connect(_on_hero_died)
		
		# Append to the correct array directly
		if is_player:
			player_heroes.append(hero_instance)
		else:
			enemy_heroes.append(hero_instance)
		
		# Position hero based on array index (order set by Position Editor)
		hero_instance.global_position = positions[i]
		hero_instance.z_index = z_indices[i]
		
		print("Battle: Spawned hero ", hero_id, " instance_id=", hero_instance.instance_id, " at position ", positions[i], " is_player: ", is_player)
		
		if not is_player:
			hero_instance.flip_sprite()
	

func _setup_enemy_hand_display() -> void:
	_refresh_enemy_hand_display()

func _refresh_enemy_hand_display() -> void:
	# Sync with actual GameManager values
	enemy_hand_count = GameManager.get_enemy_hand_size()
	enemy_deck_count = GameManager.get_enemy_deck_size()
	
	if not enemy_hand_container:
		return
	# Clear existing cards
	for child in enemy_hand_container.get_children():
		if is_instance_valid(child):
			child.queue_free()
	
	# Add card backs for enemy hand
	for i in range(enemy_hand_count):
		var card_back = TextureRect.new()
		card_back.texture = cardback_texture
		card_back.custom_minimum_size = Vector2(40, 55)
		card_back.expand_mode = 1
		card_back.stretch_mode = 5
		enemy_hand_container.add_child(card_back)
	
	if enemy_hand_label:
		enemy_hand_label.text = str(enemy_hand_count)
	if enemy_deck_label:
		enemy_deck_label.text = str(enemy_deck_count)

func _update_deck_display() -> void:
	if deck_label:
		deck_label.text = str(GameManager.deck.size())

func _update_turn_display() -> void:
	if turn_label:
		turn_label.text = str(GameManager.turn_number)

var rps_minigame_scene = preload("res://scenes/battle/rps_minigame.tscn")
var player_goes_first: bool = true

func _start_rps_minigame() -> void:
	# Both single player and multiplayer use RPS minigame
	var rps = rps_minigame_scene.instantiate()
	
	if is_multiplayer and network_manager:
		# Setup multiplayer mode for RPS
		rps.setup_multiplayer(network_manager, is_host)
		print("Battle: Starting multiplayer RPS minigame")
	
	add_child(rps)
	rps.rps_finished.connect(_on_rps_finished)

func _on_rps_finished(player_wins: bool) -> void:
	player_goes_first = player_wins
	GameManager.is_player_turn = player_wins
	_start_mulligan()

func _start_mulligan() -> void:
	current_phase = BattlePhase.MULLIGAN
	mulligan_panel.visible = true
	mulligan_selections.clear()
	
	GameManager.draw_cards(5)
	await _deal_hand_animated()
	
	if turn_indicator:
		turn_indicator.text = "MULLIGAN PHASE\nClick cards to replace"
	end_turn_button.visible = false

func _on_mulligan_confirm() -> void:
	var cards_to_replace = []
	var cards_to_animate_out = []
	
	for card in mulligan_selections:
		cards_to_replace.append(card.card_data)
		cards_to_animate_out.append(card)
	
	mulligan_selections.clear()
	mulligan_panel.visible = false
	
	for card in cards_to_animate_out:
		var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
		tween.tween_property(card, "position:y", card.position.y - 100, 0.15)
		tween.parallel().tween_property(card, "modulate:a", 0.0, 0.15)
	
	await get_tree().create_timer(0.2).timeout
	
	GameManager.finish_mulligan(cards_to_replace)
	await _deal_hand_animated()
	
	# Enemy mulligan
	await _do_enemy_mulligan()
	
	# Start the game based on RPS result
	if player_goes_first:
		GameManager.is_player_turn = true
		current_phase = BattlePhase.PLAYING
		end_turn_button.visible = true
		if turn_indicator:
			turn_indicator.text = "YOUR TURN"
	else:
		GameManager.is_player_turn = false
		current_phase = BattlePhase.ENEMY_TURN
		end_turn_button.visible = true
		end_turn_button.disabled = true
		if turn_indicator:
			turn_indicator.text = "ENEMY TURN"
		_flip_to_opponent_turn()
		await get_tree().create_timer(0.5).timeout
		_do_enemy_turn()

func _do_enemy_mulligan() -> void:
	if turn_indicator:
		turn_indicator.text = "ENEMY MULLIGAN..."
	await get_tree().create_timer(0.5).timeout
	
	# In multiplayer, opponent handles their own mulligan - skip AI logic
	if is_multiplayer:
		if turn_indicator:
			turn_indicator.text = "WAITING FOR OPPONENT..."
		# Just wait a moment and continue - opponent's mulligan is on their client
		await get_tree().create_timer(1.0).timeout
		return
	
	# AI randomly decides to replace 0-3 cards
	var cards_to_replace = randi() % 4  # 0, 1, 2, or 3 cards
	
	if cards_to_replace > 0:
		# Animate enemy hand changing (cards go down, new ones come up)
		for i in range(cards_to_replace):
			if enemy_hand_container.get_child_count() > i:
				var card_back = enemy_hand_container.get_child(i)
				var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
				tween.tween_property(card_back, "modulate:a", 0.0, 0.15)
		
		await get_tree().create_timer(0.3).timeout
		
		# Actually perform the mulligan in GameManager
		GameManager.enemy_mulligan(cards_to_replace)
		
		# Refresh enemy hand display with actual values
		_refresh_enemy_hand_display()
		
		# Fade in the new cards
		for i in range(enemy_hand_container.get_child_count()):
			var card_back = enemy_hand_container.get_child(i)
			card_back.modulate.a = 0
		
		for i in range(enemy_hand_container.get_child_count()):
			var card_back = enemy_hand_container.get_child(i)
			var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.tween_interval(i * 0.05)
			tween.tween_property(card_back, "modulate:a", 1.0, 0.15)
		
		await get_tree().create_timer(0.3).timeout
	
	if turn_indicator:
		turn_indicator.text = "YOUR TURN"
	_update_ui()

func _refresh_hand(animate: bool = false) -> void:
	for child in hand_container.get_children():
		if is_instance_valid(child):
			child.queue_free()
	
	var index = 0
	for card_data in GameManager.hand:
		var card_instance = card_scene.instantiate()
		hand_container.add_child(card_instance)
		card_instance.setup(card_data)
		card_instance.card_clicked.connect(_on_card_clicked)
		
		if current_phase == BattlePhase.MULLIGAN:
			card_instance.can_interact = true
		else:
			var can_play = card_instance.can_play(GameManager.current_mana)
			card_instance.set_playable(can_play)
		
		if animate:
			card_instance.modulate.a = 0
			card_instance.position.y = 50
			var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.set_parallel(false)
			tween.tween_interval(index * 0.08)
			tween.tween_property(card_instance, "modulate:a", 1.0, 0.2)
			tween.parallel().tween_property(card_instance, "position:y", 0, 0.25)
		index += 1

func _deal_hand_animated() -> void:
	for child in hand_container.get_children():
		if is_instance_valid(child):
			child.queue_free()
	
	_update_deck_display()
	
	# First add all cards to container (invisible)
	var cards_to_animate = []
	for card_data in GameManager.hand:
		var card_instance = card_scene.instantiate()
		hand_container.add_child(card_instance)
		card_instance.setup(card_data)
		card_instance.card_clicked.connect(_on_card_clicked)
		card_instance.modulate.a = 0
		
		if current_phase == BattlePhase.MULLIGAN:
			card_instance.can_interact = true
		else:
			var can_play = card_instance.can_play(GameManager.current_mana)
			card_instance.set_playable(can_play)
		cards_to_animate.append(card_instance)
	
	# Wait for layout to complete
	await get_tree().process_frame
	
	# Simple fade-in animation for cards
	var index = 0
	for card_instance in cards_to_animate:
		var final_y = card_instance.position.y
		card_instance.position.y = final_y + 50
		
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_interval(index * 0.08)
		tween.tween_property(card_instance, "modulate:a", 1.0, 0.2)
		tween.parallel().tween_property(card_instance, "position:y", final_y, 0.25)
		
		# Play card draw sound
		_play_audio("play_card_draw")
		
		index += 1
	
	await get_tree().create_timer(0.08 * cards_to_animate.size() + 0.3).timeout
	_update_deck_display()

func _on_deck_shuffled() -> void:
	# Play shuffle animation - multiple rapid shakes with rotation
	if not deck_icon:
		return
	var original_pos = deck_icon.position
	var original_rotation = deck_icon.rotation
	
	var shuffle_tween = create_tween()
	for i in range(6):
		var offset = Vector2(randf_range(-5, 5), randf_range(-3, 3))
		var rot = randf_range(-0.1, 0.1)
		shuffle_tween.tween_property(deck_icon, "position", original_pos + offset, 0.05)
		shuffle_tween.parallel().tween_property(deck_icon, "rotation", rot, 0.05)
	
	shuffle_tween.tween_property(deck_icon, "position", original_pos, 0.1)
	shuffle_tween.parallel().tween_property(deck_icon, "rotation", original_rotation, 0.1)
	
	# Update displays after shuffle
	shuffle_tween.tween_callback(_update_deck_display)

func _on_card_clicked(card: Card) -> void:
	if current_phase == BattlePhase.MULLIGAN:
		_toggle_mulligan_selection(card)
	elif current_phase == BattlePhase.PLAYING and GameManager.is_player_turn:
		# Only allow playing cards during player's turn
		if card.can_play(GameManager.current_mana):
			# Check if the source hero is stunned
			var source_hero = _get_source_hero(card.card_data)
			if source_hero and source_hero.is_stunned():
				print("Cannot play card - " + source_hero.hero_data.get("name", "Hero") + " is stunned!")
				return
			
			# Check if card requires targeting
			var card_data = card.card_data
			var card_type = card_data.get("type", "")
			var target_type = card_data.get("target", "single")
			
			# Cards that auto-cast (no targeting needed)
			var auto_cast = false
			if card_type == "mana":
				auto_cast = true
			elif card_type == "energy":
				auto_cast = true
			elif card_type == "attack" or card_type == "basic_attack":
				# ALL attack cards auto-target the front enemy (or taunted enemy)
				auto_cast = true
			elif card_type == "heal":
				if target_type == "all_ally":
					auto_cast = true
			elif card_type == "buff":
				if target_type == "all_ally" or target_type == "self":
					auto_cast = true
			elif card_type == "debuff":
				# Debuff cards that target all enemies auto-cast
				if target_type == "all_enemy":
					auto_cast = true
			
			if auto_cast:
				# UNIFIED STACK SYSTEM: Auto-cast cards go to the stack
				_add_card_to_stack(card)
			else:
				# Requires targeting - use the selection system
				_select_card(card)

func _toggle_mulligan_selection(card: Card) -> void:
	if card in mulligan_selections:
		mulligan_selections.erase(card)
		card.set_selected(false)
	else:
		mulligan_selections.append(card)
		card.set_selected(true)

func _add_card_to_stack(card: Card) -> void:
	var card_id = card.card_data.get("id", "")
	var this_cost = card.card_data.get("cost", 0)
	
	# Check if card is already in stack
	for queued in card_queue:
		if queued.card_id == card_id:
			return
	
	# Handle Mana Surge (cost = -1 means use ALL mana)
	if this_cost == -1:
		this_cost = GameManager.current_mana
		if this_cost < 1:
			return  # Need at least 1 mana
		# Store the mana spent for damage calculation
		card.card_data["mana_spent"] = this_cost
	else:
		# Frost debuff: +1 card cost for each frosted hero on the source's team
		var source_hero = _get_source_hero(card.card_data)
		if source_hero and source_hero.has_debuff("frost"):
			this_cost += 1
	
	# Check if we have enough mana
	if GameManager.current_mana < this_cost:
		return
	
	# Determine target for auto-cast cards
	var auto_target: Hero = null
	var auto_target_is_enemy: bool = false
	var card_type = card.card_data.get("type", "")
	
	if card_type == "attack" or card_type == "basic_attack":
		auto_target = _get_nearest_enemy()
		auto_target_is_enemy = true
	elif card_type == "heal":
		auto_target = _get_lowest_hp_ally()
		auto_target_is_enemy = false
	elif card_type == "buff":
		var target_type = card.card_data.get("target", "single")
		if target_type == "self":
			auto_target = _get_source_hero(card.card_data)
			auto_target_is_enemy = false
	
	# HOST-AUTHORITATIVE MULTIPLAYER
	if is_multiplayer and network_manager:
		var source_hero = _get_source_hero(card.card_data)
		var role = "[HOST]" if is_host else "[GUEST]"
		
		print("\n--- CARD PLAY: ", role, " _add_card_to_stack ---")
		print("  card_name: ", card.card_data.get("name", "?"))
		print("  card_type: ", card_type)
		print("  card_id: ", card_id)
		print("  cost: ", this_cost, " mana: ", GameManager.current_mana)
		print("  source_hero: ", source_hero.hero_id if source_hero else "null")
		print("  auto_target: ", auto_target.hero_id if auto_target else "null", " is_enemy: ", auto_target_is_enemy)
		
		if is_host:
			# HOST: Execute locally, then send RESULTS to Guest
			# (Results will be sent after execution in _play_queued_card_multiplayer)
			print("  → HOST will execute locally and send results")
			pass  # Continue to normal execution below
		else:
			# GUEST: Send REQUEST to Host, do NOT execute locally
			var request = {
				"action_type": "play_card",
				"card_data": card.card_data.duplicate(),
				"source_hero_id": source_hero.hero_id if source_hero else "",
				"source_instance_id": source_hero.instance_id if source_hero else "",
				"target_hero_id": auto_target.hero_id if auto_target else "",
				"target_instance_id": auto_target.instance_id if auto_target else "",
				"target_is_enemy": auto_target_is_enemy,
				"timestamp": Time.get_unix_time_from_system()
			}
			print("  → GUEST sending request to Host")
			network_manager.send_action_request(request)
			
			# Guest: Spend mana locally for UI feedback, remove card from hand
			GameManager.current_mana -= this_cost
			GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
			
			# Remove from hand
			for i in range(GameManager.hand.size() - 1, -1, -1):
				if GameManager.hand[i].get("id", "") == card_id:
					GameManager.hand.remove_at(i)
					break
			
			# Remove card visual
			card.queue_free()
			_refresh_hand()
			
			# Guest does NOT execute the card - wait for Host's result
			print("  → GUEST waiting for Host result...")
			print("---\n")
			return
	
	# SPEND MANA IMMEDIATELY (Host or single-player)
	GameManager.current_mana -= this_cost
	GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
	
	# Store card data
	var queued_data = {
		card_data = card.card_data.duplicate(),
		card_id = card_id,
		mana_spent = this_cost
	}
	card_queue.append(queued_data)
	
	# Remove from GameManager.hand
	for i in range(GameManager.hand.size() - 1, -1, -1):
		if GameManager.hand[i].get("id", "") == card_id:
			GameManager.hand.remove_at(i)
			break
	
	# Add to discard pile
	GameManager.discard_pile.append(card.card_data.duplicate())
	
	# Calculate stack position (0 = front, 1+ = behind)
	var stack_position = card_queue.size() - 1
	
	# Create visual and add to stack
	_create_stack_visual(card, stack_position)
	
	# If this is the first card (front of stack), start playing it
	if stack_position == 0:
		is_casting = true
		# Small delay to let the card fly to position first
		await get_tree().create_timer(0.3).timeout
		_play_front_card()

func _create_stack_visual(card: Card, stack_position: int) -> void:
	if not is_instance_valid(card):
		return
	
	var card_global_pos = card.global_position
	
	# Stack position at TOP center
	var viewport_size = get_viewport_rect().size
	var base_pos = Vector2(viewport_size.x / 2 - 100, 60)
	
	# Front card (position 0) has no offset, others peek from behind
	var stack_offset = Vector2(-8 * stack_position, -6 * stack_position)
	var target_pos = base_pos + stack_offset
	
	# Create flying card
	var flying_card = card_scene.instantiate()
	flying_card.setup(card.card_data)
	flying_card.can_interact = false
	flying_card.position = card_global_pos
	flying_card.scale = Vector2(0.9, 0.9)
	animation_layer.add_child(flying_card)
	
	# z_index: front card = 0, others go negative (behind)
	flying_card.z_index = -stack_position
	
	# Store visual reference
	var card_id = card.card_data.get("id", "")
	queued_card_visuals.append({visual = flying_card, card_id = card_id})
	
	# Remove original card from hand
	card.queue_free()
	
	# Animate to stack position
	var fly_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	fly_tween.tween_property(flying_card, "position", target_pos, 0.25)
	
	# Front card scales bigger, others stay smaller
	var target_scale = Vector2(1.3, 1.3) if stack_position == 0 else Vector2(1.1, 1.1)
	fly_tween.parallel().tween_property(flying_card, "scale", target_scale, 0.25)

func _play_front_card() -> void:
	if card_queue.is_empty():
		is_casting = false
		_refresh_hand()
		_update_ui()
		return
	
	var front = card_queue[0]
	var card_data = front.card_data
	var card_id = front.card_id
	
	# Find the front visual
	var front_visual: Card = null
	for visual_data in queued_card_visuals:
		if visual_data.card_id == card_id:
			front_visual = visual_data.visual
			break
	
	if not front_visual or not is_instance_valid(front_visual):
		# No visual, remove from queue and try next
		card_queue.pop_front()
		for i in range(queued_card_visuals.size() - 1, -1, -1):
			if queued_card_visuals[i].card_id == card_id:
				queued_card_visuals.remove_at(i)
				break
		_play_front_card()
		return
	
	# Execute the card effect
	await _play_queued_card(card_data, front_visual)

func _play_queued_card(card_data: Dictionary, visual: Card) -> void:
	var card_type = card_data.get("type", "")
	var target_type = card_data.get("target", "single")
	
	# Safety check
	if visual == null or not is_instance_valid(visual):
		_finish_card_play()
		return
	
	# Bring visual to front
	visual.z_index = 10
	
	# Scale up to casting size
	var scale_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	scale_tween.tween_property(visual, "scale", Vector2(1.3, 1.3), 0.15)
	await scale_tween.finished
	
	# Re-check validity after await
	if not is_instance_valid(visual):
		_finish_card_play()
		return
	
	# HOST-AUTHORITATIVE: If Host in multiplayer, use special execution that sends results
	if is_multiplayer and is_host and network_manager:
		await _play_queued_card_as_host(card_data, visual)
		return
	
	if card_type == "mana":
		GameManager.play_mana_card()
		await _fade_out_visual(visual)
		_finish_card_play()
	elif card_type == "energy":
		# Energy cards like Bull Rage - add energy to source hero
		var source_hero = _get_source_hero(card_data)
		await _show_card_display(card_data)
		# Play cast animation
		if source_hero:
			await _animate_cast_buff(source_hero, source_hero)
			var energy_gain = card_data.get("energy_gain", 0)
			source_hero.add_energy(energy_gain)
		await _hide_card_display()
		await _fade_out_visual(visual)
		_finish_card_play()
	elif card_type == "attack":
		# For queued attacks, auto-target nearest enemy
		var target = _get_nearest_enemy()
		if target:
			if target_type == "all_enemy":
				await _play_queued_attack_all(card_data, visual)
			else:
				# Single target, front_enemy, or nearest - attack nearest
				await _play_queued_attack(card_data, visual, target)
		else:
			await _fade_out_visual(visual)
			_finish_card_play()
	elif card_type == "heal":
		# For queued heals, auto-target lowest HP ally
		var target = _get_lowest_hp_ally()
		if target:
			if target_type == "all_ally":
				await _play_queued_heal_all(card_data, visual)
			else:
				await _play_queued_heal(card_data, visual, target)
		else:
			await _fade_out_visual(visual)
			_finish_card_play()
	elif card_type == "buff":
		if target_type == "all_ally":
			await _play_queued_buff_all(card_data, visual)
		elif target_type == "self":
			# Self-buff: target the source hero
			var source_hero = _get_source_hero(card_data)
			if source_hero and not source_hero.is_dead:
				await _play_queued_buff(card_data, visual, source_hero)
			else:
				await _fade_out_visual(visual)
				_finish_card_play()
		else:
			# Single ally target
			var target = _get_first_alive_ally()
			if target:
				await _play_queued_buff(card_data, visual, target)
			else:
				await _fade_out_visual(visual)
				_finish_card_play()
	elif card_type == "debuff":
		# Debuff cards targeting all enemies (like Thunder Punish)
		if target_type == "all_enemy":
			await _play_queued_debuff_all(card_data, visual)
		else:
			# Single-target debuffs should NOT be in queue - they require manual targeting
			# If somehow one ends up here, just fade out without applying effects
			await _fade_out_visual(visual)
			_finish_card_play()
	else:
		await _fade_out_visual(visual)
		_finish_card_play()

func _play_queued_card_as_host(card_data: Dictionary, visual: Card) -> void:
	## HOST ONLY: Execute card and send results to Guest
	var card_type = card_data.get("type", "")
	var target_type = card_data.get("target", "single")
	var source_hero = _get_source_hero(card_data)
	var target: Hero = null
	var target_is_enemy: bool = false
	
	print("Battle: [HOST] _play_queued_card_as_host - card: ", card_data.get("name", "?"), " type: ", card_type, " target_type: ", target_type)
	print("Battle: [HOST] source_hero: ", source_hero.hero_id if source_hero else "null")
	
	# Determine target based on card type and target_type
	if target_type == "all_ally":
		# Multi-target: target is null, _execute_card_and_collect_results resolves internally
		target = null
		target_is_enemy = false
		print("Battle: [HOST] all_ally card - multi-target resolved in execute")
	elif target_type == "all_enemy":
		target = null
		target_is_enemy = true
		print("Battle: [HOST] all_enemy card - multi-target resolved in execute")
	elif target_type == "self":
		target = source_hero
		target_is_enemy = false
		print("Battle: [HOST] self-target: ", target.hero_id if target else "null")
	elif card_type == "attack" or card_type == "basic_attack":
		target = _get_nearest_enemy()
		target_is_enemy = true
		print("Battle: [HOST] Attack target (nearest enemy): ", target.hero_id if target else "null")
	elif card_type == "heal":
		target = _get_lowest_hp_ally()
		target_is_enemy = false
	elif card_type == "buff":
		target = _get_first_alive_ally()
		target_is_enemy = false
	elif card_type == "debuff":
		target = _get_nearest_enemy()
		target_is_enemy = true
	elif card_type == "equipment":
		target = source_hero
		target_is_enemy = false
	elif card_type == "energy":
		target = source_hero
		target_is_enemy = false
		print("Battle: [HOST] energy card - self-target: ", target.hero_id if target else "null")
	
	# Build send callback that adds metadata and sends result before animations
	var _src_hero = source_hero
	var _tgt = target
	var _tgt_is_enemy = target_is_enemy
	var _nm = network_manager
	var _pid = my_player_id
	var _cd = card_data
	var send_cb = func(res: Dictionary) -> void:
		res["action_type"] = "play_card"
		res["played_by"] = _pid
		res["card_id"] = _cd.get("base_id", _cd.get("id", ""))
		res["card_name"] = _cd.get("name", "Unknown")
		res["card_type"] = _cd.get("type", "")
		res["source_hero_id"] = _src_hero.hero_id if _src_hero else ""
		res["source_instance_id"] = _src_hero.instance_id if _src_hero else ""
		res["target_hero_id"] = _tgt.hero_id if _tgt else ""
		res["target_instance_id"] = _tgt.instance_id if _tgt else ""
		res["target_is_enemy"] = _tgt_is_enemy
		print("Battle: [HOST] Sending result with ", res.get("effects", []).size(), " effects")
		_nm.send_action_result(res)
		print("Battle: [HOST] Sent results to Guest BEFORE animations")
	
	# Execute: pre-compute → send via callback → animate on Host
	var result = await _execute_card_and_collect_results(card_data, source_hero, target, send_cb)
	
	# Finish card play
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_attack(card_data: Dictionary, visual: Card, target: Hero) -> void:
	var source_hero = _get_source_hero(card_data)
	
	# Mana already spent when queued, just execute the effect
	if source_hero and source_hero.has_method("add_energy"):
		source_hero.add_energy(10)
	
	await _show_card_display(card_data)
	await _resolve_card_effect(card_data, source_hero, target)
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_attack_all(card_data: Dictionary, visual: Card) -> void:
	var source_hero = _get_source_hero(card_data)
	
	# Mana already spent when queued, just execute the effect
	if source_hero and source_hero.has_method("add_energy"):
		source_hero.add_energy(10)
	
	await _show_card_display(card_data)
	
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	var atk_mult = card_data.get("atk_multiplier", 1.0)
	var damage_mult = source_hero.get_damage_multiplier() if source_hero else 1.0
	var damage = int(base_atk * atk_mult * damage_mult)
	if damage == 0:
		damage = 10
	var alive_enemies = enemy_heroes.filter(func(h): return not h.is_dead)
	
	if source_hero:
		source_hero._play_attack_animation()
	
	await get_tree().create_timer(0.15).timeout
	
	var attacker_id = source_hero.hero_id if source_hero else ""
	var attacker_color = source_hero.get_color() if source_hero else ""
	var total_damage = 0
	for enemy in alive_enemies:
		enemy.spawn_attack_effect(attacker_id, attacker_color)
		enemy.take_damage(damage)
		enemy.play_hit_anim()
		total_damage += damage
		# Trigger on_damage_dealt for each enemy hit
		if source_hero:
			_trigger_equipment_effects(source_hero, "on_damage_dealt", {"damage": damage, "target": enemy})
		# Check if enemy died
		if enemy.is_dead and source_hero:
			_trigger_equipment_effects(source_hero, "on_kill", {"target": enemy})
	
	if source_hero:
		GameManager.add_damage_dealt(attacker_id, total_damage)
	
	# Process card effects (taunt, upgrade_shuffle, etc.)
	var effects = card_data.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, source_hero, null, base_atk, card_data)
	
	await get_tree().create_timer(0.3).timeout
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_heal_all(card_data: Dictionary, visual: Card) -> void:
	var source_hero = _get_source_hero(card_data)
	
	# Mana already spent when queued
	await _show_card_display(card_data)
	
	# Play cast animation
	if source_hero:
		await _animate_cast_heal(source_hero, source_hero)
	
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	var hp_mult = card_data.get("hp_multiplier", 0.0)
	var heal_amount: int
	if hp_mult > 0 and source_hero:
		heal_amount = source_hero.calculate_heal(hp_mult)
	else:
		var heal_mult = card_data.get("heal_multiplier", 1.0)
		heal_amount = int(base_atk * heal_mult)
	var alive_allies = player_heroes.filter(func(h): return not h.is_dead)
	var total_heal = 0
	
	for ally in alive_allies:
		ally.heal(heal_amount)
		total_heal += heal_amount
	
	if source_hero:
		GameManager.add_healing_done(source_hero.hero_id, total_heal)
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_heal(card_data: Dictionary, visual: Card, target: Hero) -> void:
	var source_hero = _get_source_hero(card_data)
	
	await _show_card_display(card_data)
	
	# Play cast animation
	if source_hero:
		await _animate_cast_heal(source_hero, target)
	
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	var hp_mult = card_data.get("hp_multiplier", 0.0)
	var heal_amount: int
	if hp_mult > 0 and source_hero:
		heal_amount = source_hero.calculate_heal(hp_mult)
	else:
		var heal_mult = card_data.get("heal_multiplier", 1.0)
		heal_amount = int(base_atk * heal_mult)
	target.heal(heal_amount)
	
	# Check if card also gives shield
	var card_base_shield = card_data.get("base_shield", 0)
	var def_mult = card_data.get("def_multiplier", 0.0)
	var shield_mult = card_data.get("shield_multiplier", 0.0)
	var shield_amount = 0
	if card_base_shield > 0 or def_mult > 0:
		shield_amount = source_hero.calculate_shield(card_base_shield, def_mult) if source_hero else card_base_shield
	elif shield_mult > 0:
		shield_amount = int(base_atk * shield_mult)
	if shield_amount > 0:
		target.add_block(shield_amount)
		if source_hero:
			GameManager.add_shield_given(source_hero.hero_id, shield_amount)
	
	if source_hero:
		GameManager.add_healing_done(source_hero.hero_id, heal_amount)
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_buff_all(card_data: Dictionary, visual: Card) -> void:
	var source_hero = _get_source_hero(card_data)
	
	# Mana already spent when queued
	await _show_card_display(card_data)
	
	# Play cast animation (target self for all_ally buffs)
	if source_hero:
		await _animate_cast_buff(source_hero, source_hero)
	
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	var card_base_shield = card_data.get("base_shield", 0)
	var def_mult = card_data.get("def_multiplier", 0.0)
	var shield_mult_legacy = card_data.get("shield_multiplier", 0.0)
	var shield_amount = 0
	if card_base_shield > 0 or def_mult > 0:
		shield_amount = source_hero.calculate_shield(card_base_shield, def_mult) if source_hero else card_base_shield
	elif shield_mult_legacy > 0:
		shield_amount = int(base_atk * shield_mult_legacy)
	var alive_allies = player_heroes.filter(func(h): return not h.is_dead)
	var total_shield = 0
	
	for ally in alive_allies:
		if shield_amount > 0:
			ally.add_block(shield_amount)
			total_shield += shield_amount
	
	if source_hero and total_shield > 0:
		GameManager.add_shield_given(source_hero.hero_id, total_shield)
	
	# Apply effects (empower_all, etc.)
	var effects = card_data.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, source_hero, null, base_atk, card_data)
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_debuff_single(card_data: Dictionary, visual: Card, target: Hero) -> void:
	var source_hero = _get_source_hero(card_data)
	
	await _show_card_display(card_data)
	
	# Play cast animation
	if source_hero:
		await _animate_cast_buff(source_hero, target)
	
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	
	# Apply effects to single target (thunder_stack_2, etc.)
	var effects = card_data.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, source_hero, target, base_atk, card_data)
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_debuff_all(card_data: Dictionary, visual: Card) -> void:
	var source_hero = _get_source_hero(card_data)
	
	await _show_card_display(card_data)
	
	# Play cast animation on self
	if source_hero:
		await _animate_cast_buff(source_hero, source_hero)
	
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	
	# Apply effects to all enemies (thunder_all, etc.)
	var effects = card_data.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, source_hero, null, base_atk, card_data)
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_buff(card_data: Dictionary, visual: Card, target: Hero) -> void:
	var source_hero = _get_source_hero(card_data)
	
	await _show_card_display(card_data)
	
	# Play cast animation
	if source_hero:
		await _animate_cast_buff(source_hero, target)
	
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	var card_base_shield = card_data.get("base_shield", 0)
	var def_mult = card_data.get("def_multiplier", 0.0)
	var shield_mult_legacy = card_data.get("shield_multiplier", 0.0)
	var shield_amount = 0
	if card_base_shield > 0 or def_mult > 0:
		shield_amount = source_hero.calculate_shield(card_base_shield, def_mult) if source_hero else card_base_shield
	elif shield_mult_legacy > 0:
		shield_amount = int(base_atk * shield_mult_legacy)
	if shield_amount > 0:
		target.add_block(shield_amount)
		if source_hero:
			GameManager.add_shield_given(source_hero.hero_id, shield_amount)
	
	# Apply effects (taunt, empower, etc.)
	var effects = card_data.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, source_hero, target, base_atk, card_data)
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _get_lowest_hp_ally() -> Hero:
	var alive_allies = player_heroes.filter(func(h): return not h.is_dead)
	if alive_allies.is_empty():
		return null
	var lowest = alive_allies[0]
	for ally in alive_allies:
		if ally.current_hp < lowest.current_hp:
			lowest = ally
	return lowest

func _get_first_alive_ally() -> Hero:
	var alive_allies = player_heroes.filter(func(h): return not h.is_dead)
	if alive_allies.is_empty():
		return null
	return alive_allies[0]

func _fade_out_visual(visual: Card) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var fade_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fade_tween.tween_property(visual, "scale", Vector2(0.5, 0.5), 0.2)
	fade_tween.parallel().tween_property(visual, "modulate:a", 0.0, 0.2)
	await fade_tween.finished
	if is_instance_valid(visual):
		visual.queue_free()

func _shift_stack_forward() -> void:
	# Shift all remaining cards forward in the stack
	# Card at index 0 becomes the new front (z_index 0, no offset, bigger scale)
	var viewport_size = get_viewport_rect().size
	var base_pos = Vector2(viewport_size.x / 2 - 100, 60)
	
	for i in range(queued_card_visuals.size()):
		var visual_data = queued_card_visuals[i]
		if is_instance_valid(visual_data.visual):
			# Position 0 = front (no offset), others peek behind
			var stack_offset = Vector2(-8 * i, -6 * i)
			var target_pos = base_pos + stack_offset
			visual_data.visual.z_index = -i
			
			# Front card scales up, others stay smaller
			var target_scale = Vector2(1.3, 1.3) if i == 0 else Vector2(1.1, 1.1)
			
			var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(visual_data.visual, "position", target_pos, 0.2)
			tween.parallel().tween_property(visual_data.visual, "scale", target_scale, 0.2)


func _clear_card_queue() -> void:
	card_queue.clear()
	for visual_data in queued_card_visuals:
		if is_instance_valid(visual_data.visual):
			visual_data.visual.queue_free()
	queued_card_visuals.clear()

func _select_card(card: Card) -> void:
	is_casting = true
	if selected_card:
		selected_card.set_selected(false)
	
	selected_card = card
	card.set_selected(true)
	
	var card_data = card.card_data
	var card_type = card.get_card_type()
	var target_type = card_data.get("target", "single")
	
	if card_type == "mana":
		await _play_mana_card(card)
		return
	elif card_type == "attack":
		if target_type == "nearest" or card_data.get("cost", 0) == 0:
			await _play_attack_on_nearest(card)
			return
		elif target_type == "all_enemy":
			await _play_attack_on_all_enemies(card)
			return
		else:
			# Targeting required - clear queue since user needs to pick target
			_clear_card_queue()
			is_casting = false
			current_phase = BattlePhase.TARGETING
			_highlight_valid_targets(false)
			if turn_indicator:
				turn_indicator.text = "SELECT ENEMY TARGET"
			return
	elif card_type == "heal":
		if target_type == "all_ally":
			await _play_heal_on_all_allies(card)
			return
		else:
			# Targeting required - clear queue since user needs to pick target
			_clear_card_queue()
			is_casting = false
			current_phase = BattlePhase.TARGETING
			_highlight_valid_targets(true)
			if turn_indicator:
				turn_indicator.text = "SELECT ALLY TARGET"
			return
	elif card_type == "buff":
		if target_type == "all_ally":
			await _play_buff_on_all_allies(card)
			return
		else:
			# Targeting required - clear queue since user needs to pick target
			_clear_card_queue()
			is_casting = false
			current_phase = BattlePhase.TARGETING
			_highlight_valid_targets(true)
			if turn_indicator:
				turn_indicator.text = "SELECT ALLY TARGET"
			return
	elif card_type == "debuff":
		# Single-target debuff cards target enemies
		if target_type == "single_enemy":
			_clear_card_queue()
			is_casting = false
			current_phase = BattlePhase.TARGETING
			_highlight_valid_targets(false)  # false = target enemies
			if turn_indicator:
				turn_indicator.text = "SELECT ENEMY TARGET"
			return
	elif card_type == "equipment":
		# Equipment cards target a single ally (that doesn't already have equipment)
		_clear_card_queue()
		is_casting = false
		current_phase = BattlePhase.TARGETING
		_highlight_valid_targets(true, true)  # Second true = is_equipment
		if turn_indicator:
			turn_indicator.text = "SELECT ALLY TO EQUIP"
		return

func _highlight_valid_targets(target_allies: bool, is_equipment: bool = false) -> void:
	# Show vignette overlay
	_show_targeting_vignette()
	
	var targets = player_heroes if target_allies else enemy_heroes
	var non_targets = enemy_heroes if target_allies else player_heroes
	
	# Dim non-targets (keep them under vignette)
	for hero in non_targets:
		hero.z_index = 0
		hero.modulate = Color(1.0, 1.0, 1.0)
	
	# Highlight valid targets with circle animation (bring above vignette)
	for hero in targets:
		if not hero.is_dead:
			# For equipment, check if hero already has one
			if is_equipment and hero.has_equipment():
				# Hero already has equipment - dim them
				hero.z_index = 0
				hero.modulate = Color(0.5, 0.5, 0.5)
			else:
				hero.z_index = 20
				hero.modulate = Color(1.0, 1.0, 1.0)
				hero.show_targeting_circle()
		else:
			hero.z_index = 0
			hero.modulate = Color(1.0, 1.0, 1.0)

func _clear_highlights() -> void:
	# Hide vignette
	_hide_targeting_vignette()
	
	# Reset all heroes and hide targeting circles
	for hero in player_heroes + enemy_heroes:
		hero.z_index = 0
		hero.modulate = Color(1, 1, 1) if not hero.is_dead else Color(0.8, 0.8, 0.8)
		hero.hide_targeting_circle()

func _show_targeting_vignette() -> void:
	if targeting_vignette:
		return
	
	targeting_vignette = ColorRect.new()
	targeting_vignette.color = Color(0, 0, 0, 0.5)
	targeting_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	targeting_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	targeting_vignette.z_index = 10
	add_child(targeting_vignette)
	
	# Fade in
	targeting_vignette.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(targeting_vignette, "modulate:a", 1.0, 0.15)

func _hide_targeting_vignette() -> void:
	if not targeting_vignette:
		return
	
	var vignette = targeting_vignette
	targeting_vignette = null
	
	# Fade out then remove
	var tween = create_tween()
	tween.tween_property(vignette, "modulate:a", 0.0, 0.15)
	tween.tween_callback(vignette.queue_free)

func _highlight_revive_targets() -> void:
	# Show vignette overlay
	_show_targeting_vignette()
	
	# Keep all enemies under vignette
	for hero in enemy_heroes:
		hero.z_index = 0
		hero.modulate = Color(1.0, 1.0, 1.0)
	
	# Highlight dead allies for revive (bring above vignette)
	for hero in player_heroes:
		if hero.is_dead:
			hero.z_index = 20
			hero.modulate = Color(1.0, 1.0, 1.0)
			hero.show_targeting_circle()
		else:
			hero.z_index = 0
			hero.modulate = Color(1.0, 1.0, 1.0)

func _on_hero_clicked(hero: Hero) -> void:
	if current_phase == BattlePhase.TARGETING and selected_card:
		var card_type = selected_card.get_card_type()
		var valid_target = false
		
		if card_type == "attack" and not hero.is_player_hero and not hero.is_dead:
			valid_target = true
		elif card_type == "debuff" and not hero.is_player_hero and not hero.is_dead:
			valid_target = true
		elif (card_type == "heal" or card_type == "buff") and hero.is_player_hero and not hero.is_dead:
			valid_target = true
		elif card_type == "equipment" and hero.is_player_hero and not hero.is_dead:
			# Check if hero already has equipment (limit: 1 per hero)
			if hero.has_equipment():
				print("[Equipment] " + hero.hero_data.get("name", "Hero") + " already has equipment!")
				return  # Don't allow targeting
			valid_target = true
		
		if valid_target:
			_play_card_on_target(selected_card, hero)
	elif current_phase == BattlePhase.EX_TARGETING and ex_skill_hero:
		var ex_data = ex_skill_hero.hero_data.get("ex_skill", {})
		var ex_type = ex_data.get("type", "damage")
		
		if ex_type == "revive":
			if hero.is_player_hero and hero.is_dead:
				if is_multiplayer and network_manager and not is_host:
					# GUEST: Send EX skill request to Host
					var request = {
						"action_type": "use_ex_skill",
						"source_hero_id": ex_skill_hero.hero_id,
						"source_instance_id": ex_skill_hero.instance_id,
						"target_hero_id": hero.hero_id,
						"target_instance_id": hero.instance_id,
						"target_is_enemy": false,
						"timestamp": Time.get_unix_time_from_system()
					}
					network_manager.send_action_request(request)
					ex_skill_hero = null
					current_phase = BattlePhase.PLAYING
					_clear_highlights()
					print("Battle: [GUEST] Sent EX skill request (revive)")
					return
				# HOST or single-player: execute locally
				if is_multiplayer and network_manager and is_host:
					var ex_result = await _execute_ex_skill_and_collect_results(ex_skill_hero, hero)
					ex_result["action_type"] = "use_ex_skill"
					ex_result["played_by"] = my_player_id
					ex_result["source_hero_id"] = ex_skill_hero.hero_id
					ex_result["source_instance_id"] = ex_skill_hero.instance_id
					ex_result["target_hero_id"] = hero.hero_id
					ex_result["target_instance_id"] = hero.instance_id
					network_manager.send_action_result(ex_result)
				else:
					_execute_ex_skill(ex_skill_hero, hero)
		else:
			if not hero.is_player_hero and not hero.is_dead:
				if is_multiplayer and network_manager and not is_host:
					# GUEST: Send EX skill request to Host
					var request = {
						"action_type": "use_ex_skill",
						"source_hero_id": ex_skill_hero.hero_id,
						"source_instance_id": ex_skill_hero.instance_id,
						"target_hero_id": hero.hero_id,
						"target_instance_id": hero.instance_id,
						"target_is_enemy": true,
						"timestamp": Time.get_unix_time_from_system()
					}
					network_manager.send_action_request(request)
					ex_skill_hero = null
					current_phase = BattlePhase.PLAYING
					_clear_highlights()
					print("Battle: [GUEST] Sent EX skill request (damage)")
					return
				# HOST or single-player: execute locally
				if is_multiplayer and network_manager and is_host:
					var ex_result = await _execute_ex_skill_and_collect_results(ex_skill_hero, hero)
					ex_result["action_type"] = "use_ex_skill"
					ex_result["played_by"] = my_player_id
					ex_result["source_hero_id"] = ex_skill_hero.hero_id
					ex_result["source_instance_id"] = ex_skill_hero.instance_id
					ex_result["target_hero_id"] = hero.hero_id
					ex_result["target_instance_id"] = hero.instance_id
					network_manager.send_action_result(ex_result)
				else:
					_execute_ex_skill(ex_skill_hero, hero)
	elif current_phase == BattlePhase.PLAYING:
		if hero.is_player_hero and hero.energy >= hero.max_energy:
			# Check if hero is stunned
			if hero.is_stunned():
				print("Cannot use EX skill - " + hero.hero_data.get("name", "Hero") + " is stunned!")
				return
			_use_ex_skill(hero)

func _play_card_on_target(card: Card, target: Hero) -> void:
	var source_hero = _get_source_hero(card.card_data)
	var card_data_copy = card.card_data.duplicate()
	
	# HOST-AUTHORITATIVE MULTIPLAYER: Route through request/result system
	if is_multiplayer and network_manager:
		if not is_host:
			# GUEST: Send request to Host, do NOT execute locally
			var request = {
				"action_type": "play_card",
				"card_data": card_data_copy,
				"source_hero_id": source_hero.hero_id if source_hero else "",
				"source_instance_id": source_hero.instance_id if source_hero else "",
				"target_hero_id": target.hero_id if target else "",
				"target_instance_id": target.instance_id if target else "",
				"target_is_enemy": not target.is_player_hero if target else false,
				"timestamp": Time.get_unix_time_from_system()
			}
			network_manager.send_action_request(request)
			
			# Spend mana locally for UI feedback
			var cost = card_data_copy.get("cost", 0)
			if cost == -1:
				cost = GameManager.current_mana
			GameManager.current_mana -= cost
			GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
			
			# Remove from hand
			var card_id = card_data_copy.get("id", "")
			for i in range(GameManager.hand.size() - 1, -1, -1):
				if GameManager.hand[i].get("id", "") == card_id:
					GameManager.hand.remove_at(i)
					break
			
			selected_card = null
			card.queue_free()
			_refresh_hand()
			_clear_highlights()
			current_phase = BattlePhase.PLAYING
			print("Battle: [GUEST] Sent targeted card request, waiting for Host result...")
			return
		# HOST: Execute via host-authoritative path and send results to Guest
		if is_host:
			selected_card = null
			_play_audio("play_card_play")
			
			if GameManager.play_card(card_data_copy, source_hero, target):
				# Build send callback
				var _sh = source_hero
				var _tg = target
				var _nm = network_manager
				var _pid = my_player_id
				var _cdc = card_data_copy
				var send_cb = func(res: Dictionary) -> void:
					res["action_type"] = "play_card"
					res["played_by"] = _pid
					res["card_id"] = _cdc.get("base_id", _cdc.get("id", ""))
					res["card_name"] = _cdc.get("name", "Unknown")
					res["card_type"] = _cdc.get("type", "")
					res["source_hero_id"] = _sh.hero_id if _sh else ""
					res["source_instance_id"] = _sh.instance_id if _sh else ""
					res["target_hero_id"] = _tg.hero_id if _tg else ""
					res["target_instance_id"] = _tg.instance_id if _tg else ""
					res["target_is_enemy"] = not _tg.is_player_hero if _tg else false
					_nm.send_action_result(res)
					print("Battle: [HOST] Sent targeted card results to Guest BEFORE animations")
				# Animate card to display, then execute (pre-compute → send → animate)
				await _animate_card_to_display(card)
				await _execute_card_and_collect_results(card_data_copy, source_hero, target, send_cb)
			else:
				await _animate_card_to_display(card)
			
			_finish_card_play()
			return
	
	# Single-player path
	selected_card = null
	_play_audio("play_card_play")
	await _animate_card_to_display(card)
	
	if GameManager.play_card(card_data_copy, source_hero, target):
		await _show_card_display(card_data_copy)
		await _resolve_card_effect(card_data_copy, source_hero, target)
		await _hide_card_display()
	else:
		await _hide_card_display()
	
	_finish_card_play()

func _resolve_card_effect(card_data: Dictionary, source: Hero, target: Hero) -> void:
	var card_type = card_data.get("type", "")
	var source_id = source.hero_id if source else ""
	var base_atk = source.hero_data.get("base_attack", 10) if source else 10
	
	# Apply damage multiplier from buffs/debuffs
	var damage_mult = source.get_damage_multiplier() if source else 1.0
	
	match card_type:
		"attack":
			# Attack cards deal damage - use attack animation
			var atk_mult = card_data.get("atk_multiplier", 1.0)
			
			# Handle Mana Surge: damage = mana_spent × 100% ATK
			var effects = card_data.get("effects", [])
			if effects.has("mana_surge"):
				var mana_spent = card_data.get("mana_spent", 1)
				atk_mult = float(mana_spent)  # X × 100% ATK
				print("[Mana Surge] Spent " + str(mana_spent) + " mana, dealing " + str(int(base_atk * atk_mult * damage_mult)) + " damage")
			
			var damage = int(base_atk * atk_mult * damage_mult)
			if damage == 0:
				damage = 10
			if source:
				await _animate_attack(source, target, damage)
				GameManager.add_damage_dealt(source_id, damage)
			else:
				target.take_damage(damage)
				target.play_hit_anim()
		"heal":
			# Play cast animation for heals
			if source:
				await _animate_cast_heal(source, target)
			var hp_mult = card_data.get("hp_multiplier", 0.0)
			var heal_amount: int
			if hp_mult > 0 and source:
				heal_amount = source.calculate_heal(hp_mult)
			else:
				var heal_mult = card_data.get("heal_multiplier", 1.0)
				heal_amount = int(base_atk * heal_mult)
			target.heal(heal_amount)
			GameManager.add_healing_done(source_id, heal_amount)
			# Check if card also gives shield
			var card_base_shield = card_data.get("base_shield", 0)
			var def_mult = card_data.get("def_multiplier", 0.0)
			var shield_mult = card_data.get("shield_multiplier", 0.0)
			var shield_amount = 0
			if card_base_shield > 0 or def_mult > 0:
				shield_amount = source.calculate_shield(card_base_shield, def_mult) if source else card_base_shield
			elif shield_mult > 0:
				shield_amount = int(base_atk * shield_mult)
			if shield_amount > 0:
				target.add_block(shield_amount)
				GameManager.add_shield_given(source_id, shield_amount)
			# Check for conditional empower if target has equipment (Repair card)
			var empower_if_equipped = card_data.get("empower_if_equipped", false)
			if empower_if_equipped and target.has_equipment():
				target.apply_buff("empower", 1, base_atk, "own_turn_end")
				print("[Repair] Target has equipment - applying Empower!")
		"buff":
			# Play cast animation for buffs
			if source:
				await _animate_cast_buff(source, target)
			var card_base_shield = card_data.get("base_shield", 0)
			var def_mult = card_data.get("def_multiplier", 0.0)
			var shield_mult_legacy = card_data.get("shield_multiplier", 0.0)
			var shield_amount = 0
			if card_base_shield > 0 or def_mult > 0:
				shield_amount = source.calculate_shield(card_base_shield, def_mult) if source else card_base_shield
			elif shield_mult_legacy > 0:
				shield_amount = int(base_atk * shield_mult_legacy)
			if shield_amount > 0:
				target.add_block(shield_amount)
				GameManager.add_shield_given(source_id, shield_amount)
		"debuff":
			# Play cast animation for debuffs targeting enemies
			if source:
				await _animate_cast_buff(source, target)
			# Apply debuff effects (thunder_stack_2, etc.)
			var effects = card_data.get("effects", [])
			if not effects.is_empty():
				_apply_effects(effects, source, target, base_atk, card_data)
			return  # Don't apply effects again at the end
		"equipment":
			# Play cast animation for equipping - use target as caster if no source
			var caster = source if source else target
			if caster:
				await _animate_cast_buff(caster, target)
			# Equip item to target hero - store equipment data on the hero
			var equip_effect = card_data.get("effect", "")
			var equip_trigger = card_data.get("trigger", "")
			var equip_value = card_data.get("effect_value", 0)
			var equip_name = card_data.get("name", "Equipment")
			
			# Check if hero already has equipment (limit: 1 per hero)
			if target.has_equipment():
				print("[Equipment] " + target.hero_data.get("name", "Hero") + " already has equipment! Cannot equip " + equip_name)
				return
			
			# Add equipment to hero using new equipment system
			target.add_equipment({
				"id": card_data.get("id", ""),
				"name": equip_name,
				"effect": equip_effect,
				"trigger": equip_trigger,
				"value": equip_value
			})
		"dig":
			# Dig: Reveal top X cards, pick one matching filter
			await _handle_dig_card(card_data, source)
			return  # Don't process effects at the end
		"search_deck":
			# Search entire deck for card type
			await _handle_search_deck_card(card_data, source)
			return
		"check_discard":
			# Check discard pile, pick one card
			await _handle_check_discard_card(card_data, source)
			return
	
	# Process card effects (cleanse, taunt, etc.)
	var effects = card_data.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, source, target, base_atk, card_data)

# ============================================
# EQUIPMENT TRIGGER SYSTEM
# ============================================

func _trigger_equipment_effects(hero: Hero, trigger_type: String, context: Dictionary = {}) -> void:
	if hero == null or not is_instance_valid(hero) or hero.is_dead:
		return
	
	if not hero.has_equipment():
		return
	
	var equipped = hero.get_equipped_items()
	for equip in equipped:
		if equip.get("trigger", "") != trigger_type:
			continue
		
		var effect = equip.get("effect", "")
		var value = equip.get("effect_value", equip.get("value", 0))
		var equip_name = equip.get("name", "Equipment")
		
		match effect:
			"lifesteal":
				# Vampiric Blade: Heal % of damage dealt
				var damage_dealt = context.get("damage", 0)
				var heal_amount = int(damage_dealt * value)
				if heal_amount > 0:
					hero.heal(heal_amount)
					print("[Equipment] " + equip_name + ": " + hero.hero_data.get("name", "") + " healed " + str(heal_amount) + " HP")
			
			"energy_gain":
				# Energy Pendant: Gain energy on dealing damage
				var energy_amount = int(value)
				hero.add_energy(energy_amount)
				print("[Equipment] " + equip_name + ": " + hero.hero_data.get("name", "") + " gained " + str(energy_amount) + " energy")
			
			"apply_frost":
				# Frost Gauntlet: Apply Frost to target (+1 card cost)
				var target = context.get("target", null)
				if target and is_instance_valid(target) and not target.is_dead:
					target.apply_debuff("frost", 1, 0, "own_turn_end")
					print("[Equipment] " + equip_name + ": Applied Frost to " + target.hero_data.get("name", ""))
			
			"reflect":
				# Thorned Armor: Reflect damage back to attacker
				var damage_taken = context.get("damage", 0)
				var attacker = context.get("attacker", null)
				var reflect_damage = int(damage_taken * value)
				if reflect_damage > 0 and attacker and is_instance_valid(attacker) and not attacker.is_dead:
					attacker.take_damage(reflect_damage)
					print("[Equipment] " + equip_name + ": Reflected " + str(reflect_damage) + " damage to " + attacker.hero_data.get("name", ""))
			
			"mana_gain":
				# Mana Siphon: Gain mana on kill
				var mana_amount = int(value)
				GameManager.current_mana = min(GameManager.current_mana + mana_amount, GameManager.max_mana)
				GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
				_update_ui()
				print("[Equipment] " + equip_name + ": Gained " + str(mana_amount) + " mana")
			
			"empower_all":
				# Battle Horn: Empower all allies on kill
				var allies = player_heroes if hero.is_player_hero else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						ally.apply_buff("empower", 1, 0, "own_turn_end")
				print("[Equipment] " + equip_name + ": Empowered all allies!")
			
			"auto_revive":
				# Phoenix Feather: Revive with % HP on death (one-time use)
				var max_hp = hero.hero_data.get("max_hp", 100)
				var revive_hp = int(max_hp * value)
				hero.is_dead = false
				hero.current_hp = revive_hp
				hero._update_hp_display()
				hero.modulate = Color(1, 1, 1, 1)
				# Remove the equipment after use (one-time)
				hero.remove_equipment(equip.get("id", ""))
				print("[Equipment] " + equip_name + ": " + hero.hero_data.get("name", "") + " revived with " + str(revive_hp) + " HP!")
				return  # Exit early since we modified the array
			
			"empower":
				# Berserker's Axe: Gain Empower when HP drops below threshold
				var hp_percent = float(hero.current_hp) / float(hero.hero_data.get("max_hp", 100))
				if hp_percent <= value:
					# Check if already has this buff to avoid stacking
					if not hero.has_buff("empower"):
						hero.apply_buff("empower", 1, 0, "own_turn_end")
						print("[Equipment] " + equip_name + ": " + hero.hero_data.get("name", "") + " gained Empower (low HP)!")
			
			"cleanse":
				# Cleansing Charm: Remove debuffs at turn start
				var cleanse_count = int(value)
				for i in range(cleanse_count):
					hero.remove_random_debuff()
				print("[Equipment] " + equip_name + ": Cleansed " + str(cleanse_count) + " debuff(s) from " + hero.hero_data.get("name", ""))
			
			"guardian":
				# Guardian's Shield: Passive -5 damage dealt / -5 damage received
				# Handled inline in _animate_attack and take_damage via _get_guardian_reduction
				pass

func _get_guardian_reduction(hero: Hero) -> int:
	## Returns the total Guardian's Shield reduction value for a hero.
	## Used for both damage dealt reduction and damage received reduction.
	if hero == null or not is_instance_valid(hero) or not hero.has_equipment():
		return 0
	var total_reduction = 0
	for equip in hero.get_equipped_items():
		if equip.get("effect", "") == "guardian":
			total_reduction += int(equip.get("effect_value", equip.get("value", 0)))
	return total_reduction

# ============================================
# DECK MANIPULATION CARD HANDLERS
# ============================================

func _handle_dig_card(card_data: Dictionary, source: Hero) -> void:
	# Dig: Reveal top X cards from deck, player picks one matching filter
	var dig_count = card_data.get("dig_count", 3)
	var dig_filter = card_data.get("dig_filter", "equipment")
	var card_name = card_data.get("name", "Dig")
	
	# Get top X cards from deck (without removing them yet)
	var deck = GameManager.deck
	var revealed_cards: Array = []
	
	for i in range(min(dig_count, deck.size())):
		revealed_cards.append(deck[deck.size() - 1 - i])  # Top of deck is end of array
	
	if revealed_cards.is_empty():
		print("[" + card_name + "] Deck is empty!")
		return
	
	print("[" + card_name + "] Revealing " + str(revealed_cards.size()) + " cards, filter: " + dig_filter)
	
	# Show card selection UI
	var selected_card = await _show_card_selection(revealed_cards, dig_filter, "Dig - Select a Card")
	
	if not selected_card.is_empty():
		# Remove selected card from deck
		for i in range(deck.size()):
			if deck[i].get("id", "") == selected_card.get("id", ""):
				deck.remove_at(i)
				break
		
		# Add to hand (or discard if hand full)
		if GameManager.hand.size() < GameManager.HAND_SIZE:
			GameManager.hand.append(selected_card)
			print("[" + card_name + "] Added " + selected_card.get("name", "card") + " to hand")
			_refresh_hand()
		else:
			GameManager.discard_pile.append(selected_card)
			print("[" + card_name + "] Hand full! " + selected_card.get("name", "card") + " goes to discard")
	
	# Shuffle remaining revealed cards back into deck
	deck.shuffle()
	_update_ui()

func _handle_search_deck_card(card_data: Dictionary, source: Hero) -> void:
	# Search entire deck for cards matching filter
	var search_filter = card_data.get("search_filter", "equipment")
	var card_name = card_data.get("name", "Search")
	
	var deck = GameManager.deck
	var matching_cards: Array = []
	
	for card in deck:
		if _card_matches_filter_type(card, search_filter):
			matching_cards.append(card)
	
	if matching_cards.is_empty():
		print("[" + card_name + "] No matching cards in deck!")
		return
	
	print("[" + card_name + "] Found " + str(matching_cards.size()) + " matching cards")
	
	# Show card selection UI
	var selected_card = await _show_card_selection(matching_cards, "any", "Search - Select a Card")
	
	if not selected_card.is_empty():
		# Remove from deck
		for i in range(deck.size()):
			if deck[i].get("id", "") == selected_card.get("id", ""):
				deck.remove_at(i)
				break
		
		# Add to hand (or discard if full)
		if GameManager.hand.size() < GameManager.HAND_SIZE:
			GameManager.hand.append(selected_card)
			print("[" + card_name + "] Added " + selected_card.get("name", "card") + " to hand")
			_refresh_hand()
		else:
			GameManager.discard_pile.append(selected_card)
			print("[" + card_name + "] Hand full! " + selected_card.get("name", "card") + " goes to discard")
	
	# Shuffle deck after searching
	deck.shuffle()
	_update_ui()

func _handle_check_discard_card(card_data: Dictionary, source: Hero) -> void:
	# Check discard pile, pick one card to return to hand
	var discard_filter = card_data.get("discard_filter", "any")
	var card_name = card_data.get("name", "Recycle")
	
	var discard = GameManager.discard_pile
	var matching_cards: Array = []
	
	for card in discard:
		if _card_matches_filter_type(card, discard_filter):
			matching_cards.append(card)
	
	if matching_cards.is_empty():
		print("[" + card_name + "] No matching cards in discard pile!")
		return
	
	print("[" + card_name + "] Found " + str(matching_cards.size()) + " cards in discard")
	
	# Show card selection UI
	var selected_card = await _show_card_selection(matching_cards, "any", "Discard Pile - Select a Card")
	
	if not selected_card.is_empty():
		# Remove from discard
		for i in range(discard.size()):
			if discard[i].get("id", "") == selected_card.get("id", ""):
				discard.remove_at(i)
				break
		
		# Add to hand (or back to discard if full)
		if GameManager.hand.size() < GameManager.HAND_SIZE:
			GameManager.hand.append(selected_card)
			print("[" + card_name + "] Returned " + selected_card.get("name", "card") + " to hand")
			_refresh_hand()
		else:
			discard.append(selected_card)
			print("[" + card_name + "] Hand full! Card stays in discard")
	
	_update_ui()

func _card_matches_filter_type(card: Dictionary, filter: String) -> bool:
	if filter == "any":
		return true
	var card_type = card.get("type", "")
	return card_type == filter

func _show_card_selection(cards: Array, filter: String, title: String) -> Dictionary:
	# Show the card selection UI and wait for player choice
	if not card_selection_ui:
		return {}
	
	var selected_card: Dictionary = {}
	var selection_done = false
	
	# Connect signals
	var on_selected = func(card: Dictionary):
		selected_card = card
		selection_done = true
	var on_cancelled = func():
		selection_done = true
	
	card_selection_ui.card_selected.connect(on_selected, CONNECT_ONE_SHOT)
	card_selection_ui.selection_cancelled.connect(on_cancelled, CONNECT_ONE_SHOT)
	
	# Show UI
	card_selection_ui.show_cards(cards, filter, title)
	
	# Wait for selection
	while not selection_done:
		await get_tree().process_frame
	
	return selected_card

func _trigger_thunder_damage(heroes: Array) -> void:
	# Tick Thunder debuff on all heroes - triggers after 2 turns
	var thunder_targets = heroes.filter(func(h): return not h.is_dead and h.get_thunder_stacks() > 0)
	
	if thunder_targets.is_empty():
		return
	
	# Tick down and check if any should trigger
	for hero in thunder_targets:
		var stacks = hero.get_thunder_stacks()
		print("[Thunder] Ticking " + hero.hero_data.get("name", "Hero") + " with " + str(stacks) + " stacks")
		var damage = hero.tick_thunder()  # Decrements turn counter, returns damage if ready
		print("[Thunder] tick_thunder returned damage: " + str(damage))
		
		if damage > 0:
			# Thunder is ready to strike!
			# Spawn lightning VFX
			if VFX:
				var sprite_center = hero.global_position
				if hero.sprite:
					sprite_center = hero.sprite.global_position + hero.sprite.size / 2
				VFX.spawn_lightning_strike(sprite_center)
			
			# Deal damage
			hero.take_damage(damage)
			hero.play_hit_anim()
			print("[Thunder] " + hero.hero_data.get("name", "Hero") + " struck by lightning for " + str(damage) + " damage (" + str(stacks) + " stacks)")
			
			await get_tree().create_timer(0.3).timeout
	
	await get_tree().create_timer(0.2).timeout

func _get_hero_by_id(hero_id: String) -> Hero:
	for hero in player_heroes:
		if hero.hero_id == hero_id:
			return hero
	return null

func _find_hero_by_instance_id(iid: String) -> Hero:
	## Find any hero (player or enemy) by their unique instance_id
	for hero in player_heroes:
		if hero.instance_id == iid:
			return hero
	for hero in enemy_heroes:
		if hero.instance_id == iid:
			return hero
	return null

func _get_hero_by_color(color: String) -> Hero:
	for hero in player_heroes:
		if hero.get_color() == color:
			return hero
	return null

func _get_source_hero(card_data: Dictionary) -> Hero:
	var hero_id = card_data.get("hero_id", "")
	if hero_id != "":
		var hero = _get_hero_by_id(hero_id)
		if hero:
			return hero
	return _get_hero_by_color(card_data.get("hero_color", ""))

func _get_nearest_enemy() -> Hero:
	var alive_enemies = enemy_heroes.filter(func(h): return not h.is_dead)
	if alive_enemies.is_empty():
		return null
	# Check for taunt - if any enemy has taunt, target them instead
	var taunt_target = _get_taunt_target(alive_enemies)
	if taunt_target:
		return taunt_target
	return alive_enemies[0]

func _play_attack_on_nearest(card: Card) -> void:
	var target = _get_nearest_enemy()
	if target:
		await _play_card_on_target(card, target)
	else:
		selected_card = null
		card.set_selected(false)
		_finish_card_play()

func _play_attack_on_all_enemies(card: Card) -> void:
	var source_hero = _get_source_hero(card.card_data)
	var card_data_copy = card.card_data.duplicate()
	
	selected_card = null
	await _animate_card_to_display(card)
	
	if GameManager.play_card(card_data_copy, source_hero, null):
		await _show_card_display(card_data_copy)
		
		var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
		var atk_mult = card_data_copy.get("atk_multiplier", 1.0)
		var damage_mult = source_hero.get_damage_multiplier() if source_hero else 1.0
		var damage = int(base_atk * atk_mult * damage_mult)
		if damage == 0:
			damage = 10
		var alive_enemies = enemy_heroes.filter(func(h): return not h.is_dead)
		
		# Play attack animation first
		if source_hero:
			source_hero._play_attack_animation()
		
		# Small delay before hits land
		await get_tree().create_timer(0.15).timeout
		
		# All enemies get hit simultaneously (no delay between them)
		var attacker_id = source_hero.hero_id if source_hero else ""
		var attacker_color = source_hero.get_color() if source_hero else ""
		var total_damage = 0
		for enemy in alive_enemies:
			enemy.spawn_attack_effect(attacker_id, attacker_color)
			enemy.take_damage(damage)
			enemy.play_hit_anim()
			total_damage += damage
		
		# Track total damage dealt
		if source_hero:
			GameManager.add_damage_dealt(attacker_id, total_damage)
		
		# Process card effects (taunt, upgrade_shuffle, etc.)
		var effects = card_data_copy.get("effects", [])
		if not effects.is_empty():
			_apply_effects(effects, source_hero, null, base_atk, card_data_copy)
		
		await get_tree().create_timer(0.3).timeout
		await _hide_card_display()
	
	_finish_card_play()

func _play_heal_on_all_allies(card: Card) -> void:
	var source_hero = _get_source_hero(card.card_data)
	var card_data_copy = card.card_data.duplicate()
	
	selected_card = null
	await _animate_card_to_display(card)
	
	if GameManager.play_card(card_data_copy, source_hero, null):
		await _show_card_display(card_data_copy)
		
		var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
		var hp_mult = card_data_copy.get("hp_multiplier", 0.0)
		var heal_amount: int
		if hp_mult > 0 and source_hero:
			heal_amount = source_hero.calculate_heal(hp_mult)
		else:
			var heal_mult = card_data_copy.get("heal_multiplier", 1.0)
			heal_amount = int(base_atk * heal_mult)
		var alive_allies = player_heroes.filter(func(h): return not h.is_dead)
		var total_heal = 0
		
		for ally in alive_allies:
			ally.heal(heal_amount)
			total_heal += heal_amount
		
		# Track total healing done
		if source_hero:
			GameManager.add_healing_done(source_hero.hero_id, total_heal)
		
		await _hide_card_display()
	
	_finish_card_play()

func _play_buff_on_all_allies(card: Card) -> void:
	var source_hero = _get_source_hero(card.card_data)
	var card_data_copy = card.card_data.duplicate()
	
	selected_card = null
	await _animate_card_to_display(card)
	
	if GameManager.play_card(card_data_copy, source_hero, null):
		await _show_card_display(card_data_copy)
		
		var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
		var card_base_shield = card_data_copy.get("base_shield", 0)
		var def_mult = card_data_copy.get("def_multiplier", 0.0)
		var shield_mult_legacy = card_data_copy.get("shield_multiplier", 0.0)
		var shield_amount = 0
		if card_base_shield > 0 or def_mult > 0:
			shield_amount = source_hero.calculate_shield(card_base_shield, def_mult) if source_hero else card_base_shield
		elif shield_mult_legacy > 0:
			shield_amount = int(base_atk * shield_mult_legacy)
		var alive_allies = player_heroes.filter(func(h): return not h.is_dead)
		var total_shield = 0
		
		for ally in alive_allies:
			if shield_amount > 0:
				ally.add_block(shield_amount)
				total_shield += shield_amount
		
		# Track total shield given
		if source_hero and total_shield > 0:
			GameManager.add_shield_given(source_hero.hero_id, total_shield)
		
		await _hide_card_display()
	
	_finish_card_play()

func _finish_card_play() -> void:
	_clear_highlights()
	selected_card = null
	current_phase = BattlePhase.PLAYING
	if turn_indicator:
		turn_indicator.text = "YOUR TURN"
	
	# Remove the front card from queue and visuals (it just finished playing)
	if not card_queue.is_empty():
		var finished_card = card_queue.pop_front()
		var finished_id = finished_card.card_id
		
		# Remove its visual
		for i in range(queued_card_visuals.size() - 1, -1, -1):
			if queued_card_visuals[i].card_id == finished_id:
				queued_card_visuals.remove_at(i)
				break
	
	# Process next card if any
	if not card_queue.is_empty():
		_update_ui()
		
		# 1 SECOND PAUSE - let player read and feel the next card
		await get_tree().create_timer(1.0).timeout
		
		# Shift remaining cards forward in the stack
		_shift_stack_forward()
		
		# Play the new front card
		_play_front_card()
	else:
		is_casting = false
		_refresh_hand()
		_update_ui()

func _play_mana_card(card: Card) -> void:
	selected_card = null
	await _animate_card_to_display(card)
	
	GameManager.play_mana_card()
	
	var card_index = -1
	for i in range(GameManager.hand.size()):
		if GameManager.hand[i].get("id", "") == card.card_data.get("id", ""):
			card_index = i
			break
	if card_index != -1:
		GameManager.hand.remove_at(card_index)
	
	_finish_card_play()

func _animate_card_to_display(card: Card) -> void:
	if not is_instance_valid(card):
		return
	
	# Get card's current global position
	var card_global_pos = card.global_position
	
	# Get the position of the CardDisplay node (TOP center of screen)
	# This matches where queued cards stack
	var viewport_size = get_viewport_rect().size
	var target_pos = Vector2(viewport_size.x / 2 - 100, 60)
	
	# Create a flying copy of the card
	var flying_card = card_scene.instantiate()
	flying_card.setup(card.card_data)
	flying_card.can_interact = false
	flying_card.position = card_global_pos
	flying_card.scale = Vector2(1.0, 1.0)
	flying_card.z_index = 10  # Always in front of queued cards (which have negative z_index)
	animation_layer.add_child(flying_card)
	
	# Hide original card
	card.modulate.a = 0
	
	# Spawn glow trail particles during flight with card's hero color
	var hero_color = card.card_data.get("hero_color", "")
	var trail_color = _get_trail_color_from_hero(hero_color)
	_spawn_card_trail(flying_card, card_global_pos, target_pos, trail_color)
	
	# Animate: fly to center, scale up
	var fly_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	fly_tween.tween_property(flying_card, "position", target_pos, 0.3)
	fly_tween.parallel().tween_property(flying_card, "scale", Vector2(1.3, 1.3), 0.3)
	await fly_tween.finished
	
	# Brief pause at center
	await get_tree().create_timer(0.15).timeout
	
	# Fade out and shrink
	var fade_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fade_tween.tween_property(flying_card, "scale", Vector2(0.5, 0.5), 0.25)
	fade_tween.parallel().tween_property(flying_card, "modulate:a", 0.0, 0.25)
	await fade_tween.finished
	
	flying_card.queue_free()
	if is_instance_valid(card):
		card.queue_free()

func _animate_attack(source: Hero, target: Hero, damage: int) -> void:
	if source == null or not is_instance_valid(source):
		target.take_damage(damage)
		target.play_hit_anim()
		return
	
	# Play attack animation first
	source.play_attack_anim_with_callback(func(): pass)
	
	# Delay before hit lands (let attack animation play)
	await get_tree().create_timer(0.35).timeout
	
	# Spawn attack effect on target based on attacker type
	var attacker_id = source.hero_id
	var attacker_color = source.get_color()
	target.spawn_attack_effect(attacker_id, attacker_color)
	
	# VFX Library: spawn sparks on target sprite
	if VFX and target.sprite:
		var sprite_center = target.sprite.global_position + target.sprite.size / 2
		VFX.spawn_particles(sprite_center, Color(1.0, 0.6, 0.2), 8)
	
	# Guardian's Shield: reduce damage dealt by source, reduce damage received by target
	var final_damage = damage
	var source_guardian = _get_guardian_reduction(source)
	if source_guardian > 0:
		final_damage = max(1, final_damage - source_guardian)
		print("[Guardian's Shield] " + source.hero_data.get("name", "") + " dealt " + str(source_guardian) + " less damage")
	var target_guardian = _get_guardian_reduction(target)
	if target_guardian > 0:
		final_damage = max(1, final_damage - target_guardian)
		print("[Guardian's Shield] " + target.hero_data.get("name", "") + " received " + str(target_guardian) + " less damage")
	
	# Then apply damage and hit animation
	target.take_damage(final_damage)
	target.play_hit_anim()
	
	# Play sound and flash (damage number already spawned by take_damage)
	if target.sprite:
		_play_vfx("flash_damage", [target.sprite])
	_play_audio("play_attack")
	
	# Trigger on_damage_dealt equipment effects (Vampiric Blade, Energy Pendant, Frost Gauntlet)
	_trigger_equipment_effects(source, "on_damage_dealt", {"damage": final_damage, "target": target})
	
	# Trigger on_damage_taken equipment effects (Thorned Armor)
	_trigger_equipment_effects(target, "on_damage_taken", {"damage": final_damage, "attacker": source})
	
	# Check for on_low_hp trigger (Berserker's Axe)
	_trigger_equipment_effects(target, "on_low_hp", {})
	
	# Check if target died - trigger on_kill and on_death
	if target.is_dead:
		_trigger_equipment_effects(source, "on_kill", {"target": target})
		_trigger_equipment_effects(target, "on_death", {})
	
	await get_tree().create_timer(0.5).timeout

func _guest_animate_attack(source: Hero, target: Hero, damage: int) -> void:
	## GUEST ONLY: Visual-only attack animation. Does NOT apply damage or trigger equipment.
	## _apply_effect will set authoritative HP values from Host afterward.
	print("Battle: [GUEST] _guest_animate_attack - source=", source.hero_id if source else "null", " target=", target.hero_id if target else "null", " damage=", damage)
	
	if source == null or not is_instance_valid(source):
		# No source — just play hit anim visually, no damage
		if target and is_instance_valid(target):
			target.play_hit_anim()
		return
	
	# Play attack animation first
	source.play_attack_anim_with_callback(func(): pass)
	
	# Delay before hit lands (let attack animation play)
	await get_tree().create_timer(0.35).timeout
	
	# Spawn attack effect on target based on attacker type
	if target and is_instance_valid(target):
		var attacker_id = source.hero_id
		var attacker_color = source.get_color()
		target.spawn_attack_effect(attacker_id, attacker_color)
		
		# VFX Library: spawn sparks on target sprite
		if VFX and target.sprite:
			var sprite_center = target.sprite.global_position + target.sprite.size / 2
			VFX.spawn_particles(sprite_center, Color(1.0, 0.6, 0.2), 8)
		
		# Play hit animation (visual only, no take_damage)
		target.play_hit_anim()
		
		# Spawn damage number and play sound
		if target.sprite:
			var sprite_center = target.sprite.global_position + target.sprite.size / 2
			_play_vfx("spawn_damage", [self, sprite_center, damage])
			_play_vfx("flash_damage", [target.sprite])
	
	_play_audio("play_attack")
	await get_tree().create_timer(0.5).timeout

func _animate_cast(source: Hero, target: Hero, damage: int) -> void:
	# Cast animation for spells that deal damage (like Turret Deploy)
	if source == null or not is_instance_valid(source):
		target.take_damage(damage)
		target.play_hit_anim()
		return
	
	# Play cast animation and wait for it
	await source.play_cast_anim_with_callback(func(): pass)
	
	# Spawn magic effect on target
	if VFX and target.sprite:
		var sprite_center = target.sprite.global_position + target.sprite.size / 2
		VFX.spawn_particles(sprite_center, Color(0.5, 0.3, 1.0), 10)
	
	# Guardian's Shield: reduce damage dealt by source, reduce damage received by target
	var final_damage = damage
	var source_guardian = _get_guardian_reduction(source)
	if source_guardian > 0:
		final_damage = max(1, final_damage - source_guardian)
		print("[Guardian's Shield] " + source.hero_data.get("name", "") + " dealt " + str(source_guardian) + " less damage")
	var target_guardian = _get_guardian_reduction(target)
	if target_guardian > 0:
		final_damage = max(1, final_damage - target_guardian)
		print("[Guardian's Shield] " + target.hero_data.get("name", "") + " received " + str(target_guardian) + " less damage")
	
	# Apply damage
	target.take_damage(final_damage)
	target.play_hit_anim()
	
	# Trigger on_damage_dealt equipment effects
	_trigger_equipment_effects(source, "on_damage_dealt", {"damage": final_damage, "target": target})
	
	# Trigger on_damage_taken equipment effects
	_trigger_equipment_effects(target, "on_damage_taken", {"damage": final_damage, "attacker": source})
	
	# Check for on_low_hp trigger
	_trigger_equipment_effects(target, "on_low_hp", {})
	
	# Check if target died
	if target.is_dead:
		_trigger_equipment_effects(source, "on_kill", {"target": target})
		_trigger_equipment_effects(target, "on_death", {})
	
	await get_tree().create_timer(0.3).timeout

func _animate_cast_heal(source: Hero, target: Hero, heal_amount: int = 0) -> void:
	# Cast animation for healing spells
	if source == null or not is_instance_valid(source):
		return
	
	# Play cast animation and wait for it
	await source.play_cast_anim_with_callback(func(): pass)
	
	# Spawn heal effect on target
	if VFX and target.sprite:
		var sprite_center = target.sprite.global_position + target.sprite.size / 2
		VFX.spawn_particles(sprite_center, Color(0.3, 1.0, 0.3), 8)
		_play_vfx("spawn_heal_particles", [self, sprite_center])
		if heal_amount > 0:
			_play_vfx("spawn_heal", [self, sprite_center, heal_amount])
		_play_vfx("flash_heal", [target.sprite])
	_play_audio("play_heal")
	
	await get_tree().create_timer(0.2).timeout

func _animate_cast_buff(source: Hero, target: Hero) -> void:
	# Cast animation for buffs/equipment
	if source == null or not is_instance_valid(source):
		return
	
	# Play cast animation and wait for it
	await source.play_cast_anim_with_callback(func(): pass)
	
	# Spawn buff effect on target
	if VFX and target.sprite:
		var sprite_center = target.sprite.global_position + target.sprite.size / 2
		VFX.spawn_particles(sprite_center, Color(1.0, 0.8, 0.2), 8)
		_play_vfx("spawn_buff_particles", [self, sprite_center, Color.GOLD])
	_play_audio("play_buff")
	
	await get_tree().create_timer(0.2).timeout

func _animate_cast_debuff(source: Hero, target: Hero) -> void:
	# Cast animation for debuffs
	if source == null or not is_instance_valid(source):
		return
	
	# Simple cast animation - source glows purple, target gets debuff effect
	var tween = create_tween()
	tween.tween_property(source, "modulate", Color(0.8, 0.3, 0.8), 0.15)
	tween.tween_property(source, "modulate", Color.WHITE, 0.15)
	
	await get_tree().create_timer(0.2).timeout

func _show_card_display(card_data: Dictionary) -> void:
	if not card_display_container:
		return
	# Clean up any previous displayed card
	if _displayed_card_instance and is_instance_valid(_displayed_card_instance):
		_displayed_card_instance.queue_free()
		_displayed_card_instance = null
	
	# Instantiate a real Card scene (with template frame, art, labels)
	_displayed_card_instance = card_scene.instantiate()
	_displayed_card_instance.can_interact = false
	# Center the card in the container
	_displayed_card_instance.position = Vector2(0, 0)
	_displayed_card_instance.scale = Vector2(1.3, 1.3)
	card_display_container.add_child(_displayed_card_instance)
	_displayed_card_instance.setup(card_data)
	
	# Fade in
	_displayed_card_instance.modulate.a = 0
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_displayed_card_instance, "modulate:a", 1.0, 0.2)
	await get_tree().create_timer(0.2).timeout

func _hide_card_display() -> void:
	if not _displayed_card_instance or not is_instance_valid(_displayed_card_instance):
		return
	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_displayed_card_instance, "modulate:a", 0.0, 0.15)
	await get_tree().create_timer(0.15).timeout
	if _displayed_card_instance and is_instance_valid(_displayed_card_instance):
		_displayed_card_instance.queue_free()
		_displayed_card_instance = null

func _force_hide_card_display() -> void:
	if _displayed_card_instance and is_instance_valid(_displayed_card_instance):
		_displayed_card_instance.queue_free()
		_displayed_card_instance = null

func _use_ex_skill(hero: Hero) -> void:
	if hero.energy < hero.max_energy:
		return
	
	ex_skill_hero = hero
	
	var ex_data = hero.hero_data.get("ex_skill", {})
	var ex_card_data = {
		"name": ex_data.get("name", "EX Skill"),
		"cost": 0,
		"description": ex_data.get("description", ""),
		"hero_color": hero.get_color(),
		"image": ex_data.get("image", ""),
		"is_ex": true
	}
	
	await _show_card_display(ex_card_data)
	
	var ex_type = ex_data.get("type", "damage")
	
	if ex_type == "self_buff":
		# Self-buff EX skills don't need targeting - execute immediately on self
		if is_multiplayer and network_manager and not is_host:
			# GUEST: Send EX skill request to Host
			var request = {
				"action_type": "use_ex_skill",
				"source_hero_id": hero.hero_id,
				"source_instance_id": hero.instance_id,
				"target_hero_id": hero.hero_id,
				"target_instance_id": hero.instance_id,
				"target_is_enemy": false,
				"timestamp": Time.get_unix_time_from_system()
			}
			network_manager.send_action_request(request)
			ex_skill_hero = null
			print("Battle: [GUEST] Sent EX skill request (self_buff)")
			return
		# HOST: Execute and send results to Guest
		if is_multiplayer and network_manager and is_host:
			var ex_result = await _execute_ex_skill_and_collect_results(hero, hero)
			ex_result["action_type"] = "use_ex_skill"
			ex_result["played_by"] = my_player_id
			ex_result["source_hero_id"] = hero.hero_id
			ex_result["source_instance_id"] = hero.instance_id
			ex_result["target_hero_id"] = hero.hero_id
			ex_result["target_instance_id"] = hero.instance_id
			network_manager.send_action_result(ex_result)
		else:
			_execute_ex_skill(hero, hero)
	elif ex_type == "thunder_all":
		# Raizel's Storm Judgment: Apply Thunder to ALL enemies - no targeting needed
		if is_multiplayer and network_manager and not is_host:
			# GUEST: Send EX skill request to Host
			var request = {
				"action_type": "use_ex_skill",
				"source_hero_id": hero.hero_id,
				"source_instance_id": hero.instance_id,
				"target_hero_id": hero.hero_id,
				"target_instance_id": hero.instance_id,
				"target_is_enemy": false,
				"timestamp": Time.get_unix_time_from_system()
			}
			network_manager.send_action_request(request)
			ex_skill_hero = null
			print("Battle: [GUEST] Sent EX skill request (thunder_all)")
			return
		# HOST: Execute and send results to Guest
		if is_multiplayer and network_manager and is_host:
			var ex_result = await _execute_ex_skill_and_collect_results(hero, hero)
			ex_result["action_type"] = "use_ex_skill"
			ex_result["played_by"] = my_player_id
			ex_result["source_hero_id"] = hero.hero_id
			ex_result["source_instance_id"] = hero.instance_id
			ex_result["target_hero_id"] = hero.hero_id
			ex_result["target_instance_id"] = hero.instance_id
			network_manager.send_action_result(ex_result)
		else:
			_execute_ex_skill(hero, hero)
	else:
		current_phase = BattlePhase.EX_TARGETING
		
		if ex_type == "revive":
			_highlight_revive_targets()
			if turn_indicator:
				turn_indicator.text = "SELECT ALLY TO REVIVE"
		else:
			_highlight_valid_targets(false)
			if turn_indicator:
				turn_indicator.text = "SELECT EX TARGET"

var ex_cutin_scene = preload("res://scenes/effects/ex_cutin.tscn")

func _play_ex_cutin(hero: Hero, from_left: bool) -> void:
	var cutin = ex_cutin_scene.instantiate()
	add_child(cutin)
	
	# Get hero splash art (fall back to portrait if no splash)
	var splash_path = hero.hero_data.get("splash", "")
	if splash_path.is_empty():
		splash_path = hero.hero_data.get("portrait", "")
	
	var splash_texture: Texture2D = null
	if not splash_path.is_empty() and ResourceLoader.exists(splash_path):
		splash_texture = load(splash_path)
	
	# Get hero color
	var hero_color = hero.get_hero_color()
	
	# Get skill name
	var ex_data = hero.hero_data.get("ex_skill", {})
	var skill_name = ex_data.get("name", "EX SKILL")
	
	cutin.play_cutin(splash_texture, hero_color, skill_name, from_left)
	await cutin.cutin_finished

func _execute_ex_skill(hero: Hero, target: Hero) -> void:
	hero.use_ex_skill()
	
	# Track EX skill usage
	GameManager.add_ex_skill_used(hero.hero_id)
	
	var ex_data = hero.hero_data.get("ex_skill", {})
	var ex_type = ex_data.get("type", "damage")
	
	# Play cut-in effect first
	await _play_ex_cutin(hero, true)
	
	var done = false
	var timeout = 2.0
	var elapsed = 0.0
	
	var base_atk = hero.hero_data.get("base_attack", 10)
	
	if ex_type == "revive":
		var hp_mult = ex_data.get("hp_multiplier", 0.0)
		var heal_amount: int
		if hp_mult > 0:
			heal_amount = hero.calculate_heal(hp_mult)
		else:
			var heal_mult = ex_data.get("heal_multiplier", 5.0)
			heal_amount = int(base_atk * heal_mult)
		hero.play_ex_skill_anim(func():
			if not done:
				target.revive(heal_amount)
				# VFX Library: revive effect with heal particles on target sprite
				if VFX and target.sprite:
					var sprite_center = target.sprite.global_position + target.sprite.size / 2
					VFX.spawn_heal_effect(sprite_center)
					VFX.spawn_energy_burst(sprite_center, Color(0.2, 1.0, 0.4))
				done = true
		)
	elif ex_type == "self_buff":
		# Self-buff EX skills (like Stony's Goliath Strength)
		var effects = ex_data.get("effects", [])
		hero.play_ex_skill_anim(func():
			if not done:
				# VFX Library: buff effect on self
				if VFX and hero.sprite:
					var sprite_center = hero.sprite.global_position + hero.sprite.size / 2
					VFX.spawn_energy_burst(sprite_center, Color(0.8, 0.8, 0.2))
				# Apply effects immediately (shield_current_hp, etc.)
				_apply_effects(effects, hero, hero, base_atk)
				done = true
		)
	elif ex_type == "thunder_all":
		# Raizel's Storm Judgment: Apply Thunder to ALL enemies
		var effects = ex_data.get("effects", [])
		hero.play_ex_skill_anim(func():
			if not done:
				# VFX Library: lightning effect
				if VFX and hero.sprite:
					var sprite_center = hero.sprite.global_position + hero.sprite.size / 2
					VFX.spawn_energy_burst(sprite_center, Color(0.6, 0.8, 1.0))
				# Apply thunder_all effect
				_apply_effects(effects, hero, null, base_atk)
				done = true
		)
	else:
		var atk_mult = ex_data.get("atk_multiplier", 2.0)
		var damage_mult = hero.get_damage_multiplier()  # Apply weak/empower
		var damage = int(base_atk * atk_mult * damage_mult)
		var effects = ex_data.get("effects", [])
		hero.play_ex_skill_anim(func():
			if not done:
				# VFX Library: energy burst for EX damage on target sprite
				if VFX and target.sprite:
					var sprite_center = target.sprite.global_position + target.sprite.size / 2
					VFX.spawn_energy_burst(sprite_center, Color(1.0, 0.5, 0.2))
				target.take_damage(damage)
				target.play_hit_anim()
				# Apply effects immediately with damage (weak, penetrate, etc.)
				_apply_effects(effects, hero, target, base_atk)
				done = true
		)
	
	while not done and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	
	await get_tree().create_timer(0.3).timeout
	_force_hide_card_display()
	
	ex_skill_hero = null
	_clear_highlights()
	current_phase = BattlePhase.PLAYING
	if turn_indicator:
		turn_indicator.text = "YOUR TURN"
	_update_ui()

# ============================================
# BUFF/DEBUFF EFFECT PROCESSING
# ============================================

func _get_buff_expire_on(buff_type: String) -> String:
	## Returns the correct expire_on for a given buff type.
	match buff_type:
		"empower":
			return "own_turn_end"
		"taunt":
			return "opponent_turn_end"
		"regen":
			return "permanent"  # Self-consumes at turn start (delayed heal)
		"equipped":
			return "permanent"
		_:
			return "own_turn_end"  # Default: expires at end of own turn

func _get_debuff_expire_on(debuff_type: String) -> String:
	## Returns the correct expire_on for a given debuff type.
	match debuff_type:
		"stun":
			return "own_turn_end"
		"weak":
			return "own_turn_end"
		"frost":
			return "own_turn_end"
		"break":
			return "own_turn_end"
		"burn":
			return "own_turn_end"
		"poison":
			return "own_turn_end"
		"bleed":
			return "own_turn_end"
		"chain":
			return "own_turn_end"
		"entangle":
			return "own_turn_end"
		"marked":
			return "own_turn_end"
		"bomb":
			return "own_turn_end"
		_:
			return "own_turn_end"  # Default: expires at end of own turn

func _apply_effects(effects: Array, source: Hero, target: Hero, source_atk: int, card_data: Dictionary = {}) -> void:
	for effect in effects:
		match effect:
			"stun":
				if target and not target.is_dead:
					target.apply_debuff("stun", 1, source_atk, "own_turn_end")
			"weak":
				if target and not target.is_dead:
					target.apply_debuff("weak", 1, source_atk, "own_turn_end")
			"empower":
				if source and not source.is_dead:
					source.apply_buff("empower", 1, source_atk, "own_turn_end")
			"empower_target":
				if target and not target.is_dead:
					target.apply_buff("empower", 1, source_atk, "own_turn_end")
			"empower_all":
				var allies = player_heroes if source.is_player_hero else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						ally.apply_buff("empower", 1, source_atk, "own_turn_end")
			"taunt":
				if source and not source.is_dead:
					# Remove taunt from all other allies first
					var allies = player_heroes if source.is_player_hero else enemy_heroes
					for ally in allies:
						if ally != source:
							ally.remove_buff("taunt")
					source.apply_buff("taunt", 1, source_atk, "opponent_turn_end")
			"regen":
				if target and not target.is_dead:
					target.apply_buff("regen", -1, source_atk, "permanent")
			"cleanse":
				if target and not target.is_dead:
					target.clear_all_debuffs()
			"penetrate":
				# Penetrate hits the hero behind the target (further from attacker)
				# For player heroes: behind = lower index (pos 3 -> pos 2)
				# For enemy heroes: behind = higher index (pos 5 -> pos 6)
				if target and not target.is_dead:
					var target_team = player_heroes if target.is_player_hero else enemy_heroes
					var target_index = target_team.find(target)
					# Behind = lower index for players, higher index for enemies
					var behind_index = target_index - 1 if target.is_player_hero else target_index + 1
					if behind_index >= 0 and behind_index < target_team.size():
						var behind_target = target_team[behind_index]
						if not behind_target.is_dead:
							var damage = int(source_atk * 1.0)  # Same damage as main hit
							behind_target.take_damage(damage)
							behind_target.play_hit_anim()
							# Apply weak to behind target too
							behind_target.apply_debuff("weak", 1, source_atk, "own_turn_end")
			"upgrade_shuffle":
				if not card_data.is_empty():
					_apply_upgrade_shuffle(card_data)
			"shield_current_hp":
				# Stony's EX: Gain shield equal to current HP
				if source and not source.is_dead:
					var shield_amount = source.current_hp
					source.add_block(shield_amount)
					print(source.hero_data.get("name", "Hero") + " gained " + str(shield_amount) + " Shield from current HP!")
			"break":
				# Caelum's EX: Apply Break debuff (+50% damage taken)
				if target and not target.is_dead:
					target.apply_debuff("break", 1, source_atk, "own_turn_end")
			"thunder":
				# Apply 1 Thunder stack to target
				if target and not target.is_dead:
					target.apply_debuff("thunder", 1, source_atk)
			"thunder_all":
				# Apply 1 Thunder stack to all enemies
				var enemies = enemy_heroes if source.is_player_hero else player_heroes
				for enemy in enemies:
					if not enemy.is_dead:
						enemy.apply_debuff("thunder", 1, source_atk)
			"thunder_stack_2":
				# Add 2 Thunder stacks to target (only if they have Thunder)
				if target and not target.is_dead and target.has_debuff("thunder"):
					target.add_thunder_stacks(2, source_atk)
			"draw_1":
				# Draw 1 card
				if source and source.is_player_hero:
					GameManager.draw_cards(1)
					_refresh_hand()

func _apply_upgrade_shuffle(card_data: Dictionary) -> void:
	# Upgrade the card's atk_multiplier and shuffle back into deck
	var upgrade_mult = card_data.get("upgrade_multiplier", 0.2)
	var current_mult = card_data.get("atk_multiplier", 0.5)
	var new_mult = current_mult + upgrade_mult
	
	# Find the card in discard pile and upgrade it
	for i in range(GameManager.discard_pile.size() - 1, -1, -1):
		var discard_card = GameManager.discard_pile[i]
		if discard_card.get("id", "") == card_data.get("id", ""):
			# Remove from discard
			GameManager.discard_pile.remove_at(i)
			# Upgrade the multiplier
			discard_card["atk_multiplier"] = new_mult
			# Update description
			var new_damage = int(10 * new_mult)
			discard_card["description"] = "Deal " + str(new_damage) + " damage to all enemies. Gain Taunt. +2 damage on shuffle."
			# Add back to deck
			GameManager.deck.append(discard_card)
			GameManager.deck.shuffle()
			print("War Stomp upgraded to " + str(new_mult * 100) + "% ATK and shuffled into deck")
			break

func _get_taunt_target(enemies: Array) -> Hero:
	for enemy in enemies:
		if not enemy.is_dead and enemy.has_buff("taunt"):
			return enemy
	return null

func _cancel_ex_skill() -> void:
	if ex_skill_hero:
		ex_skill_hero = null
	_force_hide_card_display()
	_clear_highlights()
	current_phase = BattlePhase.PLAYING
	if turn_indicator:
		turn_indicator.text = "YOUR TURN"

func _deselect_card() -> void:
	if selected_card and is_instance_valid(selected_card):
		selected_card.set_selected(false)
	selected_card = null
	_force_hide_card_display()
	_clear_highlights()
	current_phase = BattlePhase.PLAYING
	if turn_indicator:
		turn_indicator.text = "YOUR TURN"

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if current_phase == BattlePhase.TARGETING:
				_deselect_card()
			elif current_phase == BattlePhase.EX_TARGETING:
				_cancel_ex_skill()

func _on_end_turn_pressed() -> void:
	if current_phase == BattlePhase.PLAYING or current_phase == BattlePhase.TARGETING or current_phase == BattlePhase.EX_TARGETING:
		# Disable button immediately to prevent double-clicks
		end_turn_button.disabled = true
		
		if selected_card and is_instance_valid(selected_card):
			selected_card.set_selected(false)
		selected_card = null
		ex_skill_hero = null
		_clear_highlights()
		
		# Wait for any queued cards to finish playing
		if is_casting or not card_queue.is_empty():
			await _wait_for_queue_to_finish()
		
		_force_hide_card_display()
		
		# HOST-AUTHORITATIVE: Handle turn end
		if is_multiplayer and network_manager:
			var role = "[HOST]" if is_host else "[GUEST]"
			print("\n=== TURN END: ", role, " ===")
			print("  current_phase: ", current_phase)
			print("  GameManager.is_player_turn: ", GameManager.is_player_turn)
			print("  GameManager.turn_number: ", GameManager.turn_number)
			
			if is_host:
				# Host ending turn: notify Guest via result
				print("  → HOST sending end_turn result to Guest")
				var result = {
					"action_type": "end_turn",
					"success": true,
					"whose_turn_ended": "host"
				}
				network_manager.send_action_result(result)
			else:
				# Guest ending turn: send request to Host
				print("  → GUEST sending end_turn request to Host")
				var request = {
					"action_type": "end_turn",
					"timestamp": Time.get_unix_time_from_system()
				}
				network_manager.send_action_request(request)
				# Guest waits for Host to process - don't continue locally
				waiting_for_opponent = true
				print("  → GUEST waiting for Host to process turn end...")
				print("===\n")
				return  # Don't execute turn end logic locally
			print("===\n")
		
		# === PLAYER TURN END: Expire buffs/debuffs ===
		# Player's heroes: remove "own_turn_end" buffs/debuffs (empower, regen, etc.)
		for hero in player_heroes:
			if not hero.is_dead:
				hero.on_own_turn_end()
		# Enemy's heroes: remove "opponent_turn_end" buffs/debuffs (their shields, taunt, etc.)
		for enemy in enemy_heroes:
			if not enemy.is_dead:
				enemy.on_opponent_turn_end()
		
		# Trigger Thunder damage on ALL heroes at end of player turn
		await _trigger_thunder_damage(enemy_heroes)
		await _trigger_thunder_damage(player_heroes)
		
		# Clear ENEMY shields at end of player turn (enemy used them last turn, now they expire)
		for enemy in enemy_heroes:
			if enemy.block > 0:
				enemy.block = 0
				enemy._update_ui()
				enemy._hide_shield_effect()
		
		current_phase = BattlePhase.ENEMY_TURN
		GameManager.end_player_turn()

func _wait_for_queue_to_finish() -> void:
	# Wait until all queued cards have been played
	while is_casting or not card_queue.is_empty():
		await get_tree().create_timer(0.1).timeout

func _on_turn_started(is_player: bool) -> void:
	var role = "[HOST]" if is_host else "[GUEST]"
	print("\n=== TURN STARTED: ", role, " ===")
	print("  is_player_turn: ", is_player)
	print("  is_multiplayer: ", is_multiplayer)
	print("  waiting_for_opponent: ", waiting_for_opponent)
	print("  GameManager.turn_number: ", GameManager.turn_number)
	print("===\n")
	
	_force_hide_card_display()
	_update_turn_display()
	_update_deck_display()
	
	# Animate turn transition
	await _animate_turn_transition(is_player)
	
	if is_player:
		# === PLAYER TURN START ===
		# Buffs/debuffs already expired at end of previous turns.
		# Just apply start-of-turn effects (regen, cleansing charm, etc.)
		for hero in player_heroes:
			if not hero.is_dead:
				hero.on_turn_start()
				_trigger_equipment_effects(hero, "on_turn_start", {})
		
		current_phase = BattlePhase.PLAYING
		if turn_indicator:
			turn_indicator.text = "YOUR TURN"
		end_turn_button.disabled = false
		_flip_to_player_turn()
		_refresh_hand()
	else:
		# === ENEMY TURN START ===
		# For single-player AI: the "enemy turn end" happens here since AI doesn't
		# press end turn. Expire enemy's "own_turn_end" and player's "opponent_turn_end".
		if not is_multiplayer:
			for enemy in enemy_heroes:
				if not enemy.is_dead:
					enemy.on_own_turn_end()
			for hero in player_heroes:
				if not hero.is_dead:
					hero.on_opponent_turn_end()
		
		# Apply start-of-turn effects for enemies
		for enemy in enemy_heroes:
			if not enemy.is_dead:
				enemy.on_turn_start()
		
		current_phase = BattlePhase.ENEMY_TURN
		if turn_indicator:
			turn_indicator.text = "ENEMY TURN"
		end_turn_button.disabled = true
		_flip_to_opponent_turn()
		# Enemy draws cards at start of turn (only for AI - in multiplayer, opponent manages their own hand)
		if not is_multiplayer:
			if GameManager.turn_number > 1:
				var current_hand_size = GameManager.get_enemy_hand_size()
				var cards_to_draw = min(3, 10 - current_hand_size)
				if cards_to_draw > 0:
					GameManager.enemy_draw_cards(cards_to_draw)
					_refresh_enemy_hand_display()
		_do_enemy_turn()

func _animate_turn_transition(is_player: bool) -> void:
	if not turn_indicator:
		return
	
	var turn_text = "YOUR TURN" if is_player else "ENEMY TURN"
	var turn_color = Color(0.2, 0.8, 0.3) if is_player else Color(0.8, 0.2, 0.2)
	
	# Slide out old text
	var original_pos = turn_indicator.position
	turn_indicator.modulate.a = 1.0
	
	var out_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	out_tween.tween_property(turn_indicator, "position:x", original_pos.x - 100, 0.15)
	out_tween.parallel().tween_property(turn_indicator, "modulate:a", 0.0, 0.15)
	await out_tween.finished
	
	# Update text and color
	turn_indicator.text = turn_text
	turn_indicator.add_theme_color_override("font_color", turn_color)
	turn_indicator.position.x = original_pos.x + 100
	
	# Slide in new text
	var in_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	in_tween.tween_property(turn_indicator, "position:x", original_pos.x, 0.2)
	in_tween.parallel().tween_property(turn_indicator, "modulate:a", 1.0, 0.15)
	await in_tween.finished
	
	# Brief scale pulse
	var pulse_tween = create_tween().set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(turn_indicator, "scale", Vector2(1.1, 1.1), 0.1)
	pulse_tween.tween_property(turn_indicator, "scale", Vector2(1.0, 1.0), 0.1)
	await pulse_tween.finished

func _do_enemy_turn() -> void:
	await get_tree().create_timer(0.5).timeout
	
	var alive_player_heroes = player_heroes.filter(func(h): return not h.is_dead)
	var alive_enemy_heroes = enemy_heroes.filter(func(h): return not h.is_dead)
	
	if alive_player_heroes.is_empty() or alive_enemy_heroes.is_empty():
		_force_hide_card_display()
		GameManager.end_enemy_turn()
		return
	
	# In multiplayer, wait for opponent actions instead of AI
	if is_multiplayer:
		waiting_for_opponent = true
		# Opponent actions will be received via network_manager signals
		# Turn will end when opponent sends turn_end signal
		return
	
	# AI battle logic
	var enemy_mana = GameManager.max_mana
	var actions_taken = 0
	var max_actions = 4
	
	while actions_taken < max_actions and enemy_mana >= 0:
		alive_player_heroes = player_heroes.filter(func(h): return not h.is_dead)
		alive_enemy_heroes = enemy_heroes.filter(func(h): return not h.is_dead)
		
		if alive_player_heroes.is_empty() or alive_enemy_heroes.is_empty():
			break
		
		# Check if enemy has cards to play
		if GameManager.enemy_hand.is_empty():
			break
		
		var action_taken = await _ai_take_action(alive_enemy_heroes, alive_player_heroes, enemy_mana)
		if action_taken.taken:
			enemy_mana -= action_taken.cost
			actions_taken += 1
			_refresh_enemy_hand_display()
			await get_tree().create_timer(0.3).timeout
		else:
			break
	
	_force_hide_card_display()
	
	# Trigger Thunder damage on ALL heroes at end of enemy turn
	await _trigger_thunder_damage(player_heroes)
	await _trigger_thunder_damage(enemy_heroes)
	
	# Clear PLAYER shields at end of enemy turn (player used them last turn, now they expire)
	for ally in player_heroes:
		if ally.block > 0:
			ally.block = 0
			ally._update_ui()
			ally._hide_shield_effect()
	
	GameManager.end_enemy_turn()

func _ai_take_action(alive_enemies: Array, alive_players: Array, mana: int) -> Dictionary:
	var result = {"taken": false, "cost": 0}
	
	# Filter out stunned enemies - they cannot act
	var non_stunned_enemies = alive_enemies.filter(func(e): return not e.has_debuff("stun"))
	
	if non_stunned_enemies.is_empty():
		return result  # All enemies are stunned, skip turn
	
	# Check for EX skills first (these don't use cards from hand)
	for enemy in non_stunned_enemies:
		if enemy.energy >= enemy.max_energy:
			var target = _ai_get_best_target(alive_players, "damage")
			if target:
				await _ai_use_ex_skill(enemy, target)
				result.taken = true
				result.cost = 0
				return result
	
	# Build possible actions from actual enemy hand
	var possible_actions = []
	
	for card in GameManager.enemy_hand:
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
					"priority": _ai_get_card_priority(card, alive_players, alive_enemies)
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
	
	if card_type == "mana":
		# Enemy plays mana card - just discard it and gain mana (not tracked for enemy)
		GameManager.enemy_play_card(card, attacker, null)
		result.taken = true
		result.cost = 0
	elif card_type == "energy":
		# Energy cards like Bull Rage - add energy to attacker
		GameManager.enemy_play_card(card, attacker, null)
		await _show_card_display(card)
		# Play cast animation
		await _animate_cast_buff(attacker, attacker)
		var energy_gain = card.get("energy_gain", 0)
		attacker.add_energy(energy_gain)
		await _hide_card_display()
		result.taken = true
		result.cost = card.get("cost", 0)
	elif card_type == "attack":
		var target = _ai_get_best_target(alive_players, "damage")
		if target:
			await _ai_play_attack(attacker, target, card)
			result.taken = true
			result.cost = card.get("cost", 0)
	elif card_type == "heal":
		var target = _ai_get_best_target(alive_enemies, "heal")
		if target:
			await _ai_play_heal(attacker, target, card)
			result.taken = true
			result.cost = card.get("cost", 0)
	elif card_type == "buff":
		var target = _ai_get_best_target(alive_enemies, "buff")
		if target:
			await _ai_play_buff(attacker, target, card)
			result.taken = true
			result.cost = card.get("cost", 0)
	
	return result

func _ai_get_card_priority(card: Dictionary, players: Array, enemies: Array) -> int:
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
			if enemy.current_hp < enemy.max_hp * 0.5:
				priority += 5
	elif card_type == "buff":
		priority += 3
	elif card_type == "energy":
		priority += 2
	
	if cost == 0:
		priority += 1
	
	return priority

func _ai_get_best_target(targets: Array, action_type: String) -> Hero:
	if targets.is_empty():
		return null
	
	if action_type == "damage":
		# Check for taunt - if any target has taunt, must target them
		var taunt_target = _get_taunt_target(targets)
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

func _ai_use_ex_skill(attacker: Hero, target: Hero) -> void:
	attacker.use_ex_skill()
	
	# Track EX skill usage for enemy
	GameManager.add_ex_skill_used("enemy_" + attacker.hero_id)
	
	var ex_data = attacker.hero_data.get("ex_skill", {})
	
	# Play cut-in effect first (from right side for enemy)
	await _play_ex_cutin(attacker, false)
	
	var ex_card = {
		"name": ex_data.get("name", "EX Skill"),
		"cost": 0,
		"hero_color": attacker.get_color(),
		"image": ex_data.get("image", "")
	}
	
	await _show_card_display(ex_card)
	
	var base_atk = attacker.hero_data.get("base_attack", 10)
	var atk_mult = ex_data.get("atk_multiplier", 2.0)
	var damage_mult = attacker.get_damage_multiplier()
	var damage = int(base_atk * atk_mult * damage_mult)
	await _animate_attack(attacker, target, damage)
	
	# Process EX skill effects
	var effects = ex_data.get("effects", [])
	_apply_effects(effects, attacker, target, base_atk)
	
	await _hide_card_display()

func _ai_play_attack(attacker: Hero, target: Hero, card: Dictionary) -> void:
	# Remove card from enemy hand
	GameManager.enemy_play_card(card, attacker, target)
	
	await _show_card_display(card)
	
	var base_atk = attacker.hero_data.get("base_attack", 10)
	var atk_mult = card.get("atk_multiplier", 1.0)
	var damage_mult = attacker.get_damage_multiplier()
	var damage = int(base_atk * atk_mult * damage_mult)
	if damage == 0:
		damage = 10
	var target_type = card.get("target", "single")
	var enemy_stat_id = "enemy_" + attacker.hero_id
	
	if target_type == "all_enemy":
		var alive_players = player_heroes.filter(func(h): return not h.is_dead)
		attacker._play_attack_animation()
		var total_damage = 0
		for player in alive_players:
			# Guardian's Shield: reduce damage dealt by attacker, reduce damage received by target
			var final_damage = damage
			var atk_guardian = _get_guardian_reduction(attacker)
			if atk_guardian > 0:
				final_damage = max(1, final_damage - atk_guardian)
			var def_guardian = _get_guardian_reduction(player)
			if def_guardian > 0:
				final_damage = max(1, final_damage - def_guardian)
			player.take_damage(final_damage)
			player.play_hit_anim()
			total_damage += final_damage
			# Trigger on_damage_taken equipment effects (Thorned Armor)
			_trigger_equipment_effects(player, "on_damage_taken", {"damage": final_damage, "attacker": attacker})
			# Check for on_low_hp trigger (Berserker's Axe)
			_trigger_equipment_effects(player, "on_low_hp", {})
			# Check if player died
			if player.is_dead:
				_trigger_equipment_effects(player, "on_death", {})
			await get_tree().create_timer(0.1).timeout
		GameManager.add_damage_dealt(enemy_stat_id, total_damage)
		# Process card effects
		var effects = card.get("effects", [])
		if not effects.is_empty():
			_apply_effects(effects, attacker, null, base_atk)
	else:
		await _animate_attack(attacker, target, damage)
		GameManager.add_damage_dealt(enemy_stat_id, damage)
	
	attacker.add_energy(10)
	await _hide_card_display()

func _ai_play_heal(attacker: Hero, target: Hero, card: Dictionary) -> void:
	# Remove card from enemy hand
	GameManager.enemy_play_card(card, attacker, target)
	
	await _show_card_display(card)
	
	var base_atk = attacker.hero_data.get("base_attack", 10)
	var hp_mult = card.get("hp_multiplier", 0.0)
	var heal_amount: int
	if hp_mult > 0:
		heal_amount = attacker.calculate_heal(hp_mult)
	else:
		var heal_mult = card.get("heal_multiplier", 1.0)
		heal_amount = int(base_atk * heal_mult)
	var target_type = card.get("target", "single")
	var enemy_stat_id = "enemy_" + attacker.hero_id
	
	if target_type == "all_ally":
		var alive_enemies = enemy_heroes.filter(func(h): return not h.is_dead)
		var total_heal = 0
		for enemy in alive_enemies:
			enemy.heal(heal_amount)
			total_heal += heal_amount
		GameManager.add_healing_done(enemy_stat_id, total_heal)
	else:
		target.heal(heal_amount)
		GameManager.add_healing_done(enemy_stat_id, heal_amount)
		# Check if card also gives shield
		var card_base_shield = card.get("base_shield", 0)
		var def_mult = card.get("def_multiplier", 0.0)
		var shield_mult = card.get("shield_multiplier", 0.0)
		var shield_amount = 0
		if card_base_shield > 0 or def_mult > 0:
			shield_amount = attacker.calculate_shield(card_base_shield, def_mult)
		elif shield_mult > 0:
			shield_amount = int(base_atk * shield_mult)
		if shield_amount > 0:
			target.add_block(shield_amount)
			GameManager.add_shield_given(enemy_stat_id, shield_amount)
	
	await _hide_card_display()

func _ai_play_buff(attacker: Hero, target: Hero, card: Dictionary) -> void:
	# Remove card from enemy hand
	GameManager.enemy_play_card(card, attacker, target)
	
	await _show_card_display(card)
	
	var base_atk = attacker.hero_data.get("base_attack", 10)
	var card_base_shield = card.get("base_shield", 0)
	var def_mult = card.get("def_multiplier", 0.0)
	var shield_mult_legacy = card.get("shield_multiplier", 0.0)
	var shield = 0
	if card_base_shield > 0 or def_mult > 0:
		shield = attacker.calculate_shield(card_base_shield, def_mult)
	elif shield_mult_legacy > 0:
		shield = int(base_atk * shield_mult_legacy)
	var target_type = card.get("target", "single")
	var enemy_stat_id = "enemy_" + attacker.hero_id
	
	if target_type == "all_ally":
		var alive_enemies = enemy_heroes.filter(func(h): return not h.is_dead)
		var total_shield = 0
		for enemy in alive_enemies:
			if shield > 0:
				enemy.add_block(shield)
				total_shield += shield
		if total_shield > 0:
			GameManager.add_shield_given(enemy_stat_id, total_shield)
	else:
		if shield > 0:
			target.add_block(shield)
			GameManager.add_shield_given(enemy_stat_id, shield)
	
	await _hide_card_display()

func _on_hero_died(hero: Hero) -> void:
	print(hero.hero_data.get("name", "Hero") + " has died!")
	
	var hero_id = hero.hero_data.get("id", "")
	var hero_color = hero.hero_data.get("color", "")
	
	if hero.is_player_hero:
		# Process card removal for player heroes
		GameManager.on_hero_died(hero_id, hero_color)
		_refresh_hand()
		_update_deck_display()
	else:
		# Process card removal for enemy heroes
		GameManager.on_enemy_hero_died(hero_id, hero_color)
		_refresh_enemy_hand_display()

func _on_mana_changed(current: int, max_mana: int) -> void:
	if mana_label:
		mana_label.text = str(current) + "/" + str(max_mana)
	
	# Animate mana orb when gaining mana
	if current > last_mana and mana_display:
		_animate_mana_gain()
	last_mana = current

func _animate_mana_gain() -> void:
	if not mana_display:
		return
	var original_scale = mana_display.scale
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(mana_display, "scale", original_scale * 1.2, 0.15)
	tween.tween_property(mana_display, "scale", original_scale, 0.2)

func _update_ui() -> void:
	if mana_label:
		mana_label.text = str(GameManager.current_mana) + "/" + str(GameManager.max_mana)
	if deck_label:
		deck_label.text = str(GameManager.deck.size())

func _on_game_over(player_won: bool) -> void:
	current_phase = BattlePhase.GAME_OVER
	
	# In multiplayer, notify opponent of game over
	if is_multiplayer and network_manager:
		network_manager.send_concede()  # Notify opponent the game ended
		
		# Leave the matchmaking lobby
		if has_node("/root/MatchmakingManager"):
			get_node("/root/MatchmakingManager").leave_battle()
	
	# Record win/loss to PlayerData
	_record_battle_result(player_won)
	
	# Play victory/defeat sound
	if player_won:
		_play_audio("play_victory")
	else:
		_play_audio("play_defeat")
		_play_vfx("shake_screen", [15.0, 3.0])
	
	# Hide old game over panel
	if game_over_panel:
		game_over_panel.visible = false
	
	# Wait a moment then show battle summary
	await get_tree().create_timer(1.0).timeout
	_show_battle_summary(player_won)

func _record_battle_result(player_won: bool) -> void:
	# Record to PlayerData (is_pvp = true for multiplayer battles)
	if has_node("/root/PlayerData"):
		var player_data = get_node("/root/PlayerData")
		if player_won:
			player_data.record_win(is_multiplayer)
		else:
			player_data.record_loss(is_multiplayer)

func _show_battle_summary(player_won: bool) -> void:
	var summary_scene = preload("res://scenes/battle/battle_summary.tscn")
	var summary = summary_scene.instantiate()
	add_child(summary)
	summary.show_summary(player_won)

func _on_concede_pressed() -> void:
	# Player gives up - show summary with defeat
	current_phase = BattlePhase.GAME_OVER
	
	# Notify opponent in multiplayer
	if is_multiplayer and network_manager:
		network_manager.send_concede()
	
	# Record loss to PlayerData
	_record_battle_result(false)
	
	# Hide old game over panel
	if game_over_panel:
		game_over_panel.visible = false
	
	# Show battle summary
	await get_tree().create_timer(0.5).timeout
	_show_battle_summary(false)

func _on_opponent_conceded() -> void:
	# Opponent gave up - we win!
	print("Battle: Opponent conceded! We win!")
	current_phase = BattlePhase.GAME_OVER
	
	# Record win
	_record_battle_result(true)
	
	# Hide old game over panel
	if game_over_panel:
		game_over_panel.visible = false
	
	# Show battle summary with victory
	await get_tree().create_timer(0.5).timeout
	_show_battle_summary(true)

func _on_opponent_disconnected() -> void:
	# Opponent disconnected - we win!
	print("Battle: Opponent disconnected! We win!")
	current_phase = BattlePhase.GAME_OVER
	
	# Record win
	_record_battle_result(true)
	
	# Hide old game over panel
	if game_over_panel:
		game_over_panel.visible = false
	
	# Show battle summary with victory
	await get_tree().create_timer(0.5).timeout
	_show_battle_summary(true)
	
func _setup_button_hover(button: Button) -> void:
	if not button:
		return
	button.mouse_entered.connect(func(): _on_button_hover(button, true))
	button.mouse_exited.connect(func(): _on_button_hover(button, false))

func _on_button_hover(button: Button, hovered: bool) -> void:
	if not button:
		return
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if hovered:
		tween.tween_property(button, "scale", Vector2(1.1, 1.1), 0.1)
		button.modulate = Color(1.2, 1.2, 1.2)
	else:
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.1)
		button.modulate = Color(1.0, 1.0, 1.0)

func _spawn_card_trail(card: Control, start_pos: Vector2, end_pos: Vector2, trail_color: Color) -> void:
	var trail_count = 8
	var direction = (end_pos - start_pos).normalized()
	
	for i in range(trail_count):
		var particle = ColorRect.new()
		particle.size = Vector2(8, 8)
		particle.color = trail_color
		particle.z_index = 9
		animation_layer.add_child(particle)
		
		# Stagger spawn along the path
		var t = float(i) / trail_count
		var spawn_pos = start_pos.lerp(end_pos, t * 0.5)
		spawn_pos += Vector2(randf_range(-10, 10), randf_range(-10, 10))
		particle.position = spawn_pos
		
		var delay = t * 0.15
		var fade_duration = 0.4
		
		var tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.tween_interval(delay)
		tween.tween_property(particle, "modulate:a", 0.0, fade_duration)
		tween.parallel().tween_property(particle, "size", Vector2(3, 3), fade_duration)
		tween.tween_callback(particle.queue_free)

func _get_trail_color_from_hero(hero_color: String) -> Color:
	match hero_color:
		"yellow":
			return Color(1.0, 0.9, 0.3, 0.8)  # Yellow/gold
		"violet", "purple":
			return Color(0.7, 0.3, 1.0, 0.8)  # Violet/purple
		"red":
			return Color(1.0, 0.3, 0.3, 0.8)  # Red
		"blue":
			return Color(0.3, 0.6, 1.0, 0.8)  # Blue
		"green":
			return Color(0.3, 1.0, 0.5, 0.8)  # Green
		_:
			return Color(0.8, 0.9, 1.0, 0.6)  # Default light blue

func _flip_to_opponent_turn() -> void:
	# 3D-like flip animation for turn diamond
	_animate_3d_flip(turn_display, turn_icon, opponent_turn_diamond, null, "")
	
	# 3D-like flip animation for end turn button
	_animate_3d_flip(end_turn_container, end_turn_bg, opponent_endturn_bg, end_turn_label, "OPPONENT'S TURN")

func _flip_to_player_turn() -> void:
	# 3D-like flip animation for turn diamond
	_animate_3d_flip(turn_display, turn_icon, player_turn_diamond, null, "")
	
	# 3D-like flip animation for end turn button
	_animate_3d_flip(end_turn_container, end_turn_bg, player_endturn_bg, end_turn_label, "END TURN")

func _animate_3d_flip(container: Control, texture_node: TextureRect, new_texture: Texture2D, label_node: Label, new_text: String = "") -> void:
	if not container:
		return
	
	# Set pivot to center of the element for proper rotation (same as dashboard)
	container.pivot_offset = container.size / 2
	
	# Phase 1: Scale X to 0 (Y-axis flip effect) - same as dashboard
	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(container, "scale:x", 0.0, 0.15)
	
	# At midpoint: swap texture and text
	tween.tween_callback(func():
		if texture_node:
			texture_node.texture = new_texture
		if label_node and not new_text.is_empty():
			label_node.text = new_text
	)
	
	# Phase 2: Scale X back to 1 - same as dashboard
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(container, "scale:x", 1.0, 0.2)

# ============================================
# MULTIPLAYER FUNCTIONS
# ============================================

func _setup_multiplayer() -> void:
	# Check for ENet multiplayer first (new system)
	if has_node("/root/ENetMultiplayerManager"):
		var enet = get_node("/root/ENetMultiplayerManager")
		if enet.is_multiplayer:
			is_multiplayer = true
			is_host = enet.is_host
			
			# Store player identity
			my_player_id = enet.my_player_id
			opponent_player_id = enet.opponent_player_id
			
			# Create network manager
			network_manager = battle_network_manager_script.new()
			network_manager.name = "BattleNetworkManager"
			add_child(network_manager)
			
			var opponent_id = enet.opponent_id
			var opponent_name = enet.opponent_username if not enet.opponent_username.is_empty() else "Opponent"
			
			network_manager.initialize(self, is_multiplayer, is_host, opponent_id)
			
			if enemy_name_label:
				enemy_name_label.text = opponent_name
			
			# Connect network signals
			network_manager.opponent_turn_ended.connect(_on_opponent_turn_ended)
			network_manager.opponent_disconnected.connect(_on_opponent_disconnected)
			network_manager.opponent_conceded.connect(_on_opponent_conceded)
			network_manager.action_request_received.connect(_on_action_request_received)
			network_manager.action_result_received.connect(_on_action_result_received)
			network_manager.opponent_team_received.connect(_on_opponent_team_received)
			
			print("Battle: ENet Multiplayer [HOST-AUTHORITATIVE] - Host: ", is_host)
			print("  My player_id: ", my_player_id, " Opponent player_id: ", opponent_player_id)
			return
	
	# No multiplayer - AI battle mode
	print("Battle: AI battle mode (no ENet connection)")

# ============================================
# HOST-AUTHORITATIVE: Host receives Guest's action requests
# ============================================

func _on_action_request_received(request: Dictionary) -> void:
	## HOST ONLY: Guest sent us an action request. Execute it and send results back.
	## IMPORTANT: This is called from a signal callback (RPC → signal → here).
	## We must NOT use await directly — use call_deferred instead.
	if not is_host:
		push_warning("Battle: Guest received action request - should not happen!")
		return
	
	var action_type = request.get("action_type", "")
	print("\n>>> HOST: _on_action_request_received <<<")
	print("  action_type: ", action_type)
	print("  current_phase: ", current_phase)
	print("  waiting_for_opponent: ", waiting_for_opponent)
	
	# Defer processing to avoid await-in-signal-callback issues
	_deferred_process_action_request.call_deferred(request)

func _deferred_process_action_request(request: Dictionary) -> void:
	## Process action requests in a deferred context so await works properly
	var action_type = request.get("action_type", "")
	print("  → Deferred processing request action_type: ", action_type)
	
	match action_type:
		"play_card":
			print("  → Calling _host_execute_card_request")
			await _host_execute_card_request(request)
		"use_ex_skill":
			print("  → Calling _host_execute_ex_skill_request")
			await _host_execute_ex_skill_request(request)
		"end_turn":
			print("  → Calling _host_execute_end_turn_request")
			_host_execute_end_turn_request(request)
		_:
			print("  → UNKNOWN action_type: ", action_type)

func _host_execute_card_request(request: Dictionary) -> void:
	## HOST: Execute a card play request from Guest and send results
	var card_data = request.get("card_data", {})
	var source_hero_id = request.get("source_hero_id", "")
	var source_instance_id = request.get("source_instance_id", "")
	var target_hero_id = request.get("target_hero_id", "")
	var target_instance_id = request.get("target_instance_id", "")
	var is_guest_targeting_enemy = request.get("target_is_enemy", false)
	
	print("\n--- HOST: _host_execute_card_request ---")
	print("  card_name: ", card_data.get("name", "?"))
	print("  card_type: ", card_data.get("type", "?"))
	print("  source: hero_id=", source_hero_id, " iid=", source_instance_id)
	print("  target: hero_id=", target_hero_id, " iid=", target_instance_id)
	print("  is_guest_targeting_enemy: ", is_guest_targeting_enemy)
	
	# Use instance_id for precise lookup (no ambiguity with duplicate hero_ids)
	var target: Hero = null
	if not target_instance_id.is_empty():
		target = _find_hero_by_instance_id(target_instance_id)
	# Fallback to hero_id + perspective if instance_id not found
	if target == null and not target_hero_id.is_empty():
		print("  WARNING: instance_id lookup failed, falling back to hero_id")
		var search_array = player_heroes if is_guest_targeting_enemy else enemy_heroes
		for hero in search_array:
			if hero.hero_id == target_hero_id:
				target = hero
				break
		if target == null:
			for hero in player_heroes + enemy_heroes:
				if hero.hero_id == target_hero_id:
					target = hero
					break
	
	# Find source hero by instance_id first
	var source: Hero = null
	if not source_instance_id.is_empty():
		source = _find_hero_by_instance_id(source_instance_id)
	# Fallback to hero_id
	if source == null and not source_hero_id.is_empty():
		for hero in enemy_heroes:
			if hero.hero_id == source_hero_id:
				source = hero
				break
	
	print("  Found source: ", source.hero_id if source else "NULL!", " iid=", source.instance_id if source else "?")
	print("  Found target: ", target.hero_id if target else "NULL!", " iid=", target.instance_id if target else "?")
	
	if source == null and card_data.get("type", "") != "equipment":
		print("  ERROR: Source hero not found! Cannot execute card.")
		print("---\n")
		return
	if source == null:
		print("  NOTE: Source is null (equipment card - this is OK)")
	
	# RC1: Auto-resolve target for cards that don't need an explicit target
	var card_target_type = card_data.get("target", "")
	var card_type = card_data.get("type", "")
	if target == null:
		if card_target_type in ["all_ally", "all_enemy"]:
			# Multi-target cards: null target is OK, resolved inside _execute_card_and_collect_results
			print("  NOTE: Multi-target card (", card_target_type, ") - target resolved in execute")
		elif card_target_type == "self" or card_type == "energy":
			# Self-target / energy cards: use source as target
			target = source
			print("  NOTE: Auto-resolved self/energy target to source: ", target.hero_id if target else "NULL!")
		elif card_type == "equipment" and source == null:
			# Equipment with no source - already handled above
			pass
		else:
			print("  ERROR: Target hero not found! Cannot execute card.")
			print("---\n")
			return
	
	# Build send callback that adds metadata and sends result before animations
	var _src = source
	var _src_hid = source_hero_id
	var _src_iid = source.instance_id if source else source_instance_id
	var _tgt_hid = target_hero_id
	var _tgt_iid = target.instance_id if target else target_instance_id
	var _tgt_is_enemy = not is_guest_targeting_enemy
	var _nm = network_manager
	var _opid = opponent_player_id
	var _cd = card_data
	var send_cb = func(res: Dictionary) -> void:
		res["action_type"] = "play_card"
		res["played_by"] = _opid
		res["card_id"] = _cd.get("base_id", _cd.get("id", ""))
		res["card_name"] = _cd.get("name", "Unknown")
		res["card_type"] = _cd.get("type", "")
		res["source_hero_id"] = _src_hid
		res["source_instance_id"] = _src_iid
		res["target_hero_id"] = _tgt_hid
		res["target_instance_id"] = _tgt_iid
		res["target_is_enemy"] = _tgt_is_enemy
		_nm.send_action_result(res)
		print("Battle: [HOST] Sent Guest card results BEFORE animations")
	
	# Execute: pre-compute → send via callback → animate on Host
	print("  → Executing card...")
	await _execute_card_and_collect_results(card_data, source, target, send_cb)

func _host_execute_ex_skill_request(request: Dictionary) -> void:
	## HOST: Execute an EX skill request from Guest and send results
	var source_hero_id = request.get("source_hero_id", "")
	var source_instance_id = request.get("source_instance_id", "")
	var target_hero_id = request.get("target_hero_id", "")
	var target_instance_id = request.get("target_instance_id", "")
	var is_guest_targeting_enemy = request.get("target_is_enemy", false)
	
	# Find source by instance_id first
	var source: Hero = null
	if not source_instance_id.is_empty():
		source = _find_hero_by_instance_id(source_instance_id)
	if source == null:
		for hero in enemy_heroes:
			if hero.hero_id == source_hero_id:
				source = hero
				break
	
	# Find target by instance_id first
	var target: Hero = null
	if not target_instance_id.is_empty():
		target = _find_hero_by_instance_id(target_instance_id)
	if target == null and not target_hero_id.is_empty():
		var search_array = player_heroes if is_guest_targeting_enemy else enemy_heroes
		for hero in search_array:
			if hero.hero_id == target_hero_id:
				target = hero
				break
	
	if source and target:
		var result = await _execute_ex_skill_and_collect_results(source, target)
		result["action_type"] = "use_ex_skill"
		result["played_by"] = opponent_player_id  # Guest used this EX skill
		result["source_hero_id"] = source_hero_id
		result["source_instance_id"] = source.instance_id
		result["target_hero_id"] = target_hero_id
		result["target_instance_id"] = target.instance_id
		network_manager.send_action_result(result)

func _host_execute_end_turn_request(request: Dictionary) -> void:
	## HOST: Guest ended their turn
	var result = {
		"action_type": "end_turn",
		"success": true,
		"whose_turn_ended": "guest"  # Guest's turn ended, now it's Host's turn
	}
	network_manager.send_action_result(result)
	
	# Process turn end - Guest's turn ended, now it's Host's turn
	waiting_for_opponent = false
	GameManager.end_enemy_turn()
	print("Battle: [HOST] Guest ended turn, now it's our turn")

# ============================================
# HOST-AUTHORITATIVE: Guest receives results from Host
# ============================================

func _on_action_result_received(result: Dictionary) -> void:
	## GUEST ONLY: Host sent us action results. Apply them directly (no game logic).
	## IMPORTANT: This is called from a signal callback (RPC → signal → here).
	## We must NOT use await directly in signal callbacks in Godot 4 — it can silently fail.
	## Instead, we use call_deferred to process results in the next frame.
	if is_host:
		push_warning("Battle: Host received action result - should not happen!")
		return
	
	var action_type = result.get("action_type", "")
	print("\n>>> GUEST: _on_action_result_received <<<")
	print("  action_type: ", action_type)
	print("  current_phase: ", current_phase)
	print("  is_casting: ", is_casting)
	
	# Defer processing to avoid await-in-signal-callback issues
	_deferred_process_action_result.call_deferred(result)

func _deferred_process_action_result(result: Dictionary) -> void:
	## Process action results in a deferred context so await works properly
	var action_type = result.get("action_type", "")
	print("  → Deferred processing action_type: ", action_type)
	
	match action_type:
		"play_card":
			print("  → Calling _guest_apply_card_result")
			await _guest_apply_card_result(result)
		"use_ex_skill":
			print("  → Calling _guest_apply_ex_skill_result")
			await _guest_apply_ex_skill_result(result)
		"end_turn":
			print("  → Calling _guest_apply_end_turn_result")
			_guest_apply_end_turn_result(result)
		_:
			print("  → UNKNOWN action_type: ", action_type)

func _guest_apply_card_result(result: Dictionary) -> void:
	## GUEST: Apply card play results from Host with animations
	var effects = result.get("effects", [])
	var card_id = result.get("card_id", "")
	var card_name = result.get("card_name", "Unknown Card")
	var card_type = result.get("card_type", "")
	
	# Look up full card data locally (both clients have same cards.json)
	var display_card_data: Dictionary = {}
	if not card_id.is_empty():
		display_card_data = CardDatabase.get_card(card_id)
		if display_card_data.is_empty():
			display_card_data = EquipmentDatabase.get_equipment(card_id)
	if display_card_data.is_empty():
		display_card_data = {"name": card_name, "type": card_type}
	var source_hero_id = result.get("source_hero_id", "")
	var source_instance_id = result.get("source_instance_id", "")
	var target_hero_id = result.get("target_hero_id", "")
	var target_instance_id = result.get("target_instance_id", "")
	var played_by = result.get("played_by", "")
	
	print("Battle: [GUEST] Applying card result - name: ", card_name, " type: ", card_type, " effects: ", effects.size())
	print("Battle: [GUEST]   played_by: ", played_by, " my_player_id: ", my_player_id)
	print("Battle: [GUEST]   source: iid=", source_instance_id, " hero_id=", source_hero_id)
	print("Battle: [GUEST]   target: iid=", target_instance_id, " hero_id=", target_hero_id)
	
	# Use instance_id for precise hero lookup (no ambiguity)
	var source: Hero = null
	if not source_instance_id.is_empty():
		source = _find_hero_by_instance_id(source_instance_id)
	# Fallback: use played_by + hero_id
	if source == null and not source_hero_id.is_empty():
		var i_played_it = (played_by == my_player_id)
		var source_search = player_heroes if i_played_it else enemy_heroes
		for h in source_search:
			if h.hero_id == source_hero_id:
				source = h
				break
		if source == null:
			for h in player_heroes + enemy_heroes:
				if h.hero_id == source_hero_id:
					source = h
					break
	
	# Use instance_id for target lookup
	var target: Hero = null
	if not target_instance_id.is_empty():
		target = _find_hero_by_instance_id(target_instance_id)
	# Fallback: use card type context + hero_id
	if target == null and not target_hero_id.is_empty():
		var i_played_it = (played_by == my_player_id)
		var is_offensive = card_type in ["attack", "basic_attack", "debuff"]
		var target_search_primary: Array
		if is_offensive:
			target_search_primary = enemy_heroes if i_played_it else player_heroes
		else:
			target_search_primary = player_heroes if i_played_it else enemy_heroes
		for h in target_search_primary:
			if h.hero_id == target_hero_id:
				target = h
				break
		if target == null:
			for h in player_heroes + enemy_heroes:
				if h.hero_id == target_hero_id:
					target = h
					break
	
	print("Battle: [GUEST]   Found source: ", source.hero_id if source else "NULL!", " iid=", source.instance_id if source else "?")
	print("Battle: [GUEST]   Found target: ", target.hero_id if target else "NULL!", " iid=", target.instance_id if target else "?")
	
	# For multi-target cards, target may be null - resolve an animation target from effects
	var anim_target = target
	if anim_target == null and effects.size() > 0:
		var first_effect_iid = effects[0].get("instance_id", "")
		if not first_effect_iid.is_empty():
			anim_target = _find_hero_by_instance_id(first_effect_iid)
		if anim_target == null:
			var first_effect_hid = effects[0].get("hero_id", "")
			if not first_effect_hid.is_empty():
				for h in player_heroes + enemy_heroes:
					if h.hero_id == first_effect_hid:
						anim_target = h
						break
	
	# Play VISUAL-ONLY animation based on card type
	# Guest must NOT call _animate_attack (it applies damage via take_damage).
	# Instead, use _guest_animate_attack which is visual-only.
	# _apply_effect will set the authoritative HP values from Host afterward.
	if card_type in ["attack", "basic_attack"] and source and anim_target:
		var damage = 0
		for effect in effects:
			if effect.get("type", "") == "damage":
				damage = int(effect.get("amount", 0))
				break
		print("Battle: [GUEST] ANIM: attack - source=", source.hero_id, " target=", anim_target.hero_id, " damage=", damage)
		await _show_card_display(display_card_data)
		if damage > 0:
			await _guest_animate_attack(source, anim_target, damage)
		await _hide_card_display()
		print("Battle: [GUEST] ANIM: attack animation complete")
	elif card_type == "heal" and source:
		var heal_target = anim_target if anim_target else source
		print("Battle: [GUEST] ANIM: heal - source=", source.hero_id, " target=", heal_target.hero_id)
		await _show_card_display(display_card_data)
		await _animate_cast_heal(source, heal_target)
		await _hide_card_display()
		print("Battle: [GUEST] ANIM: heal animation complete")
	elif card_type == "buff" and source:
		var buff_target = anim_target if anim_target else source
		print("Battle: [GUEST] ANIM: buff - source=", source.hero_id, " target=", buff_target.hero_id)
		await _show_card_display(display_card_data)
		await _animate_cast_buff(source, buff_target)
		await _hide_card_display()
		print("Battle: [GUEST] ANIM: buff animation complete")
	elif card_type == "debuff" and source:
		var debuff_target = anim_target if anim_target else source
		print("Battle: [GUEST] ANIM: debuff - source=", source.hero_id, " target=", debuff_target.hero_id)
		await _show_card_display(display_card_data)
		await _animate_cast_debuff(source, debuff_target)
		await _hide_card_display()
		print("Battle: [GUEST] ANIM: debuff animation complete")
	elif card_type == "equipment" and anim_target:
		var caster = source if source else anim_target
		print("Battle: [GUEST] ANIM: equipment - caster=", caster.hero_id, " target=", anim_target.hero_id)
		await _show_card_display(display_card_data)
		await _animate_cast_buff(caster, anim_target)
		await _hide_card_display()
		print("Battle: [GUEST] ANIM: equipment animation complete")
	elif card_type == "energy" and source:
		print("Battle: [GUEST] ANIM: energy - source=", source.hero_id)
		await _show_card_display(display_card_data)
		await _animate_cast_buff(source, source)
		await _hide_card_display()
		print("Battle: [GUEST] ANIM: energy animation complete")
	else:
		print("Battle: [GUEST] ANIM: SKIPPED! card_type='", card_type, "' source=", source != null, " target=", anim_target != null)
		if card_type.is_empty():
			print("Battle: [GUEST] WARNING: card_type is EMPTY - animation will not play!")
		if source == null:
			print("Battle: [GUEST] WARNING: source hero NOT FOUND for id '", source_hero_id, "'")
		if anim_target == null:
			print("Battle: [GUEST] WARNING: target hero NOT FOUND for animation")
	
	# Apply each effect (set authoritative values from Host after animation)
	print("Battle: [GUEST] Applying ", effects.size(), " effects...")
	for i in range(effects.size()):
		var effect = effects[i]
		print("Battle: [GUEST]   Applying effect[", i, "]: ", effect.get("type", "?"), " on ", effect.get("hero_id", "?"))
		_apply_effect(effect)
	
	_refresh_enemy_hand_display()
	print("Battle: [GUEST] Card result fully applied\n")

func _guest_apply_ex_skill_result(result: Dictionary) -> void:
	## GUEST: Apply EX skill results from Host
	var effects = result.get("effects", [])
	var source_hero_id = result.get("source_hero_id", "")
	var target_hero_id = result.get("target_hero_id", "")
	
	print("Battle: [GUEST] Applying EX skill result - source: ", source_hero_id, " target: ", target_hero_id, " effects: ", effects.size())
	
	for i in range(effects.size()):
		var effect = effects[i]
		print("Battle: [GUEST]   EX effect[", i, "]: ", effect.get("type", "?"), " on ", effect.get("hero_id", "?"))
		_apply_effect(effect)
	
	print("Battle: [GUEST] EX skill result fully applied\n")

func _guest_apply_end_turn_result(result: Dictionary) -> void:
	## GUEST: Received end_turn result from Host
	var whose_turn_ended = result.get("whose_turn_ended", "")
	
	if whose_turn_ended == "host":
		# Host ended their turn -> Now it's Guest's turn
		waiting_for_opponent = false
		GameManager.end_enemy_turn()
		print("Battle: [GUEST] Host ended turn, now it's our turn")
	else:
		# Host processed Guest's turn end request -> Now it's Host's turn
		waiting_for_opponent = true
		current_phase = BattlePhase.ENEMY_TURN
		GameManager.end_player_turn()
		print("Battle: [GUEST] Our turn ended, now waiting for Host")

func _apply_effect(effect: Dictionary) -> void:
	## Apply a single effect directly (no calculation, just set values)
	var effect_type = effect.get("type", "")
	var hero_id = effect.get("hero_id", "")
	var instance_id = effect.get("instance_id", "")
	var is_host_hero = effect.get("is_host_hero", true)
	
	print("Battle: [GUEST] _apply_effect - type: ", effect_type, " hero_id: ", hero_id, " iid: ", instance_id, " is_host_hero: ", is_host_hero)
	
	# Use instance_id for precise lookup first
	var hero: Hero = null
	if not instance_id.is_empty():
		hero = _find_hero_by_instance_id(instance_id)
	
	# Fallback: use is_host_hero + hero_id
	if hero == null:
		var search_array = enemy_heroes if is_host_hero else player_heroes
		for h in search_array:
			if h.hero_id == hero_id:
				hero = h
				break
	
	# Fallback: search all heroes
	if hero == null:
		for h in player_heroes + enemy_heroes:
			if h.hero_id == hero_id:
				hero = h
				break
	
	if hero == null:
		print("Battle: [GUEST] Could not find hero for effect: ", hero_id)
		print("Battle: [GUEST] Available heroes: ", player_heroes.map(func(h): return h.hero_id), " + ", enemy_heroes.map(func(h): return h.hero_id))
		return
	
	print("Battle: [GUEST] Found hero: ", hero.hero_id, " is_player_hero: ", hero.is_player_hero, " current_hp: ", hero.current_hp)
	
	match effect_type:
		"damage":
			var new_hp = effect.get("new_hp", hero.current_hp)
			hero.current_hp = new_hp
			hero._update_ui()
			if new_hp <= 0:
				hero._die()
		"heal":
			var new_hp = effect.get("new_hp", hero.current_hp)
			hero.current_hp = mini(new_hp, hero.max_hp)
			hero._update_ui()
		"block":
			var new_block = effect.get("new_block", 0)
			hero.block = new_block
			hero._update_ui()
		"buff":
			var buff_type = effect.get("buff_type", "")
			var duration = effect.get("duration", 1)
			var value = effect.get("value", 0)
			var expire_on = effect.get("expire_on", _get_buff_expire_on(buff_type))
			if not buff_type.is_empty():
				hero.apply_buff(buff_type, duration, value, expire_on)
		"debuff":
			var debuff_type = effect.get("debuff_type", "")
			var duration = effect.get("duration", 1)
			var value = effect.get("value", 0)
			var expire_on = effect.get("expire_on", _get_debuff_expire_on(debuff_type))
			if not debuff_type.is_empty():
				hero.apply_debuff(debuff_type, duration, value, expire_on)
		"energy":
			var new_energy = effect.get("new_energy", hero.energy)
			hero.energy = new_energy
			hero._update_ui()
		"equipment":
			var equipment_data = effect.get("equipment_data", {})
			if not equipment_data.is_empty():
				hero.add_equipment(equipment_data)
		"mana":
			var new_mana = effect.get("new_mana", GameManager.current_mana)
			GameManager.current_mana = new_mana
			GameManager.mana_changed.emit(new_mana, GameManager.max_mana)
		"cleanse":
			hero.clear_all_debuffs()
		"draw":
			var amount = effect.get("amount", 1)
			if hero.is_player_hero:
				GameManager.draw_cards(amount)
				_refresh_hand()
		"revive":
			var new_hp = effect.get("new_hp", 1)
			hero.revive(new_hp)

func _on_opponent_turn_ended() -> void:
	# Opponent ended their turn, now it's our turn
	waiting_for_opponent = false
	GameManager.end_enemy_turn()

# ============================================
# HOST-AUTHORITATIVE: Execute and collect results
# ============================================

func _execute_card_and_collect_results(card_data: Dictionary, source: Hero, target: Hero, send_result_callback: Callable = Callable()) -> Dictionary:
	## HOST ONLY: Execute a card and collect all effects as results.
	## If send_result_callback is provided (multiplayer), it will be called with the
	## result dictionary BEFORE animations play, so Guest receives results early.
	## Supports multi-target (all_ally/all_enemy) and card effects array.
	print("Battle: [HOST] _execute_card_and_collect_results")
	print("  card: ", card_data.get("name", "?"))
	print("  source: ", source.hero_id if source else "null")
	print("  target: ", target.hero_id if target else "null", " HP before: ", target.current_hp if target else 0)
	
	var effects: Array = []
	var card_type = card_data.get("type", "")
	var target_type = card_data.get("target", "single_enemy")
	var base_atk = source.hero_data.get("base_attack", 10) if source else 10
	var damage_mult = source.get_damage_multiplier() if source else 1.0
	var card_effects = card_data.get("effects", [])
	
	# Resolve target list for multi-target cards
	var targets: Array = []
	if target_type == "all_ally":
		var ally_team = player_heroes if (source and source.is_player_hero) else enemy_heroes
		for h in ally_team:
			if not h.is_dead:
				targets.append(h)
		print("Battle: [HOST] Multi-target all_ally: ", targets.size(), " targets")
	elif target_type == "all_enemy":
		var enemy_team = enemy_heroes if (source and source.is_player_hero) else player_heroes
		for h in enemy_team:
			if not h.is_dead:
				targets.append(h)
		print("Battle: [HOST] Multi-target all_enemy: ", targets.size(), " targets")
	elif target:
		targets.append(target)
	
	# ========================================
	# PRE-COMPUTE: Calculate all effect values (NO animations, NO state changes yet)
	# This lets us send results to Guest before animations play.
	# ========================================
	var precomputed: Dictionary = {}
	
	match card_type:
		"attack", "basic_attack":
			var atk_mult = card_data.get("atk_multiplier", 1.0)
			var damage = int(base_atk * atk_mult * damage_mult)
			precomputed["damage"] = damage
			
			# Handle Mana Surge
			if card_effects.has("mana_surge"):
				var mana_spent = card_data.get("mana_spent", 1)
				damage = int(base_atk * atk_mult * mana_spent * damage_mult)
				precomputed["damage"] = damage
			
			# Pre-compute damage results for each target (before applying)
			for t in targets:
				var old_hp = t.current_hp
				var old_block = t.block
				# Simulate take_damage to get final values
				var after_def = t.apply_def_reduction(damage)
				var modified = int(after_def * t.get_damage_taken_multiplier())
				var actual_damage = modified
				var sim_block = t.block
				if sim_block >= modified:
					actual_damage = 0
					sim_block -= modified
				elif sim_block > 0:
					actual_damage = modified - sim_block
					sim_block = 0
				var new_hp = max(0, t.current_hp - actual_damage)
				
				effects.append({
					"type": "damage",
					"hero_id": t.hero_id,
					"instance_id": t.instance_id,
					"is_host_hero": t.is_player_hero,
					"amount": damage,
					"new_hp": new_hp,
					"new_block": sim_block
				})
			
			# Pre-compute card effects
			if card_effects.size() > 0 and source:
				var primary_target = target if target else (targets[0] if targets.size() > 0 else null)
				_apply_effects(card_effects, source, primary_target, base_atk, card_data)
				_collect_effects_snapshot(effects, card_effects, source, primary_target, targets)
		
		"heal":
			var hp_mult = card_data.get("hp_multiplier", 0.0)
			var heal_amount: int
			if hp_mult > 0 and source:
				heal_amount = source.calculate_heal(hp_mult)
			else:
				var heal_mult = card_data.get("heal_multiplier", card_data.get("atk_multiplier", 1.0))
				heal_amount = int(base_atk * heal_mult)
			precomputed["heal_amount"] = heal_amount
			
			for t in targets:
				var new_hp = min(t.max_hp, t.current_hp + heal_amount)
				effects.append({
					"type": "heal",
					"hero_id": t.hero_id,
					"instance_id": t.instance_id,
					"is_host_hero": t.is_player_hero,
					"amount": heal_amount,
					"new_hp": new_hp
				})
			
			if card_effects.size() > 0 and source:
				var primary_target = target if target else (targets[0] if targets.size() > 0 else null)
				_apply_effects(card_effects, source, primary_target, base_atk, card_data)
				_collect_effects_snapshot(effects, card_effects, source, primary_target, targets)
		
		"buff":
			var card_base_shield = card_data.get("base_shield", 0)
			var def_mult = card_data.get("def_multiplier", 0.0)
			var shield_mult_legacy = card_data.get("shield_multiplier", 0.0)
			var buff_type = card_data.get("buff_type", "")
			var duration = card_data.get("duration", 1)
			
			for t in targets:
				var shield_amount = 0
				if card_base_shield > 0 or def_mult > 0:
					shield_amount = source.calculate_shield(card_base_shield, def_mult) if source else card_base_shield
				elif shield_mult_legacy > 0:
					shield_amount = int(base_atk * shield_mult_legacy)
				if shield_amount > 0:
					effects.append({
						"type": "block",
						"hero_id": t.hero_id,
						"instance_id": t.instance_id,
						"is_host_hero": t.is_player_hero,
						"amount": shield_amount,
						"new_block": t.block + shield_amount
					})
				if not buff_type.is_empty():
					effects.append({
						"type": "buff",
						"hero_id": t.hero_id,
						"instance_id": t.instance_id,
						"is_host_hero": t.is_player_hero,
						"buff_type": buff_type,
						"duration": duration,
						"value": base_atk
					})
			
			if card_effects.size() > 0 and source:
				var primary_target = target if target else (targets[0] if targets.size() > 0 else null)
				_apply_effects(card_effects, source, primary_target, base_atk, card_data)
				_collect_effects_snapshot(effects, card_effects, source, primary_target, targets)
		
		"debuff":
			var debuff_type = card_data.get("debuff_type", "")
			var duration = card_data.get("duration", 1)
			for t in targets:
				if not debuff_type.is_empty():
					effects.append({
						"type": "debuff",
						"hero_id": t.hero_id,
						"instance_id": t.instance_id,
						"is_host_hero": t.is_player_hero,
						"debuff_type": debuff_type,
						"duration": duration,
						"value": base_atk
					})
			if card_effects.size() > 0 and source:
				var primary_target = target if target else (targets[0] if targets.size() > 0 else null)
				_apply_effects(card_effects, source, primary_target, base_atk, card_data)
				_collect_effects_snapshot(effects, card_effects, source, primary_target, targets)
		
		"equipment":
			if target:
				effects.append({
					"type": "equipment",
					"hero_id": target.hero_id,
					"instance_id": target.instance_id,
					"is_host_hero": target.is_player_hero,
					"equipment_data": card_data
				})
				var eq_base_shield = card_data.get("base_shield", 0)
				var eq_def_mult = card_data.get("def_multiplier", 0.0)
				var eq_shield_legacy = card_data.get("shield_multiplier", 0.0)
				var eq_shield_amount = 0
				if eq_base_shield > 0 or eq_def_mult > 0:
					eq_shield_amount = target.calculate_shield(eq_base_shield, eq_def_mult)
				elif eq_shield_legacy > 0:
					eq_shield_amount = int(base_atk * eq_shield_legacy)
				if eq_shield_amount > 0:
					effects.append({
						"type": "block",
						"hero_id": target.hero_id,
						"instance_id": target.instance_id,
						"is_host_hero": target.is_player_hero,
						"amount": eq_shield_amount,
						"new_block": target.block + eq_shield_amount
					})
				var buff_type = card_data.get("buff_type", "")
				var duration = card_data.get("duration", -1)
				if not buff_type.is_empty():
					effects.append({
						"type": "buff",
						"hero_id": target.hero_id,
						"instance_id": target.instance_id,
						"is_host_hero": target.is_player_hero,
						"buff_type": buff_type,
						"duration": duration,
						"value": base_atk
					})
		
		"energy":
			if source:
				var energy_gain = card_data.get("energy_gain", 0)
				effects.append({
					"type": "energy",
					"hero_id": source.hero_id,
					"instance_id": source.instance_id,
					"is_host_hero": source.is_player_hero,
					"amount": energy_gain,
					"new_energy": source.energy + energy_gain
				})
	
	# ========================================
	# SEND RESULT TO GUEST (before animations)
	# ========================================
	var result = {"success": true, "effects": effects}
	if send_result_callback.is_valid():
		send_result_callback.call(result)
		print("Battle: [HOST] Sent result to Guest via callback BEFORE animations")
	
	# ========================================
	# PHASE 2: Actually apply effects + play animations (Host only)
	# ========================================
	await _show_card_display(card_data)
	
	match card_type:
		"attack", "basic_attack":
			var damage = precomputed.get("damage", 10)
			for t in targets:
				var old_hp = t.current_hp
				print("Battle: [HOST] Executing attack - damage: ", damage, " on ", t.hero_id)
				if source:
					await _animate_attack(source, t, damage)
				else:
					t.take_damage(damage)
				print("Battle: [HOST] After attack - ", t.hero_id, " HP: ", t.current_hp, " (was ", old_hp, ")")
		
		"heal":
			var heal_amount = precomputed.get("heal_amount", 0)
			for t in targets:
				t.heal(heal_amount)
				if source and t == targets[0]:
					await _animate_cast_heal(source, t)
		
		"buff":
			var card_base_shield = card_data.get("base_shield", 0)
			var def_mult_val = card_data.get("def_multiplier", 0.0)
			var shield_mult_legacy = card_data.get("shield_multiplier", 0.0)
			var buff_type = card_data.get("buff_type", "")
			for t in targets:
				var shield_amount = 0
				if card_base_shield > 0 or def_mult_val > 0:
					shield_amount = source.calculate_shield(card_base_shield, def_mult_val) if source else card_base_shield
				elif shield_mult_legacy > 0:
					shield_amount = int(base_atk * shield_mult_legacy)
				if shield_amount > 0:
					t.add_block(shield_amount)
				if not buff_type.is_empty():
					var buff_expire = _get_buff_expire_on(buff_type)
					t.apply_buff(buff_type, 1, base_atk, buff_expire)
			if source and targets.size() > 0:
				await _animate_cast_buff(source, targets[0])
		
		"debuff":
			var debuff_type = card_data.get("debuff_type", "")
			for t in targets:
				if not debuff_type.is_empty():
					var debuff_expire = _get_debuff_expire_on(debuff_type)
					t.apply_debuff(debuff_type, 1, base_atk, debuff_expire)
			if source and targets.size() > 0:
				await _animate_cast_debuff(source, targets[0])
		
		"equipment":
			if target:
				var caster = source if source else target
				if caster:
					await _animate_cast_buff(caster, target)
				target.add_equipment(card_data)
				var eq_base_shield = card_data.get("base_shield", 0)
				var eq_def_mult = card_data.get("def_multiplier", 0.0)
				var eq_shield_legacy = card_data.get("shield_multiplier", 0.0)
				var eq_shield_amount = 0
				if eq_base_shield > 0 or eq_def_mult > 0:
					eq_shield_amount = target.calculate_shield(eq_base_shield, eq_def_mult)
				elif eq_shield_legacy > 0:
					eq_shield_amount = int(base_atk * eq_shield_legacy)
				if eq_shield_amount > 0:
					target.add_block(eq_shield_amount)
				var buff_type = card_data.get("buff_type", "")
				if not buff_type.is_empty():
					target.apply_buff(buff_type, -1, base_atk, "permanent")
		
		"energy":
			if source:
				var energy_gain = card_data.get("energy_gain", 0)
				source.add_energy(energy_gain)
				await _animate_cast_buff(source, source)
	
	await _hide_card_display()
	
	return result

func _collect_effects_snapshot(effects: Array, card_effects: Array, source: Hero, primary_target: Hero, targets: Array) -> void:
	## After _apply_effects has been called, snapshot any state changes caused by
	## the card's effects array so the Guest can replicate them.
	## This collects buff/debuff/block/hp/energy changes from effects like stun, empower, taunt, etc.
	for effect_name in card_effects:
		match effect_name:
			"stun":
				if primary_target and not primary_target.is_dead:
					effects.append({
						"type": "debuff",
						"hero_id": primary_target.hero_id,
						"instance_id": primary_target.instance_id,
						"is_host_hero": primary_target.is_player_hero,
						"debuff_type": "stun",
						"duration": 1,
						"expire_on": "own_turn_end",
						"value": source.hero_data.get("base_attack", 10) if source else 10
					})
			"weak":
				if primary_target and not primary_target.is_dead:
					effects.append({
						"type": "debuff",
						"hero_id": primary_target.hero_id,
						"instance_id": primary_target.instance_id,
						"is_host_hero": primary_target.is_player_hero,
						"debuff_type": "weak",
						"duration": 1,
						"expire_on": "own_turn_end",
						"value": source.hero_data.get("base_attack", 10) if source else 10
					})
			"empower":
				if source and not source.is_dead:
					effects.append({
						"type": "buff",
						"hero_id": source.hero_id,
						"instance_id": source.instance_id,
						"is_host_hero": source.is_player_hero,
						"buff_type": "empower",
						"duration": 1,
						"expire_on": "own_turn_end",
						"value": source.hero_data.get("base_attack", 10)
					})
			"empower_target":
				if primary_target and not primary_target.is_dead:
					effects.append({
						"type": "buff",
						"hero_id": primary_target.hero_id,
						"instance_id": primary_target.instance_id,
						"is_host_hero": primary_target.is_player_hero,
						"buff_type": "empower",
						"duration": 1,
						"expire_on": "own_turn_end",
						"value": source.hero_data.get("base_attack", 10) if source else 10
					})
			"empower_all":
				var allies = player_heroes if (source and source.is_player_hero) else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						effects.append({
							"type": "buff",
							"hero_id": ally.hero_id,
							"instance_id": ally.instance_id,
							"is_host_hero": ally.is_player_hero,
							"buff_type": "empower",
							"duration": 1,
							"expire_on": "own_turn_end",
							"value": source.hero_data.get("base_attack", 10) if source else 10
						})
			"taunt":
				if source and not source.is_dead:
					effects.append({
						"type": "buff",
						"hero_id": source.hero_id,
						"instance_id": source.instance_id,
						"is_host_hero": source.is_player_hero,
						"buff_type": "taunt",
						"duration": 1,
						"expire_on": "opponent_turn_end",
						"value": source.hero_data.get("base_attack", 10)
					})
			"regen":
				if primary_target and not primary_target.is_dead:
					effects.append({
						"type": "buff",
						"hero_id": primary_target.hero_id,
						"instance_id": primary_target.instance_id,
						"is_host_hero": primary_target.is_player_hero,
						"buff_type": "regen",
						"duration": -1,
						"expire_on": "permanent",
						"value": source.hero_data.get("base_attack", 10) if source else 10
					})
			"cleanse":
				if primary_target and not primary_target.is_dead:
					effects.append({
						"type": "cleanse",
						"hero_id": primary_target.hero_id,
						"instance_id": primary_target.instance_id,
						"is_host_hero": primary_target.is_player_hero
					})
			"cleanse_all":
				var allies = player_heroes if (source and source.is_player_hero) else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						effects.append({
							"type": "cleanse",
							"hero_id": ally.hero_id,
							"instance_id": ally.instance_id,
							"is_host_hero": ally.is_player_hero
						})
			"thunder":
				if primary_target and not primary_target.is_dead:
					effects.append({
						"type": "debuff",
						"hero_id": primary_target.hero_id,
						"instance_id": primary_target.instance_id,
						"is_host_hero": primary_target.is_player_hero,
						"debuff_type": "thunder",
						"duration": 1,
						"value": source.hero_data.get("base_attack", 10) if source else 10
					})
			"thunder_all":
				var enemies = enemy_heroes if (source and source.is_player_hero) else player_heroes
				for enemy in enemies:
					if not enemy.is_dead:
						effects.append({
							"type": "debuff",
							"hero_id": enemy.hero_id,
							"instance_id": enemy.instance_id,
							"is_host_hero": enemy.is_player_hero,
							"debuff_type": "thunder",
							"duration": 1,
							"value": source.hero_data.get("base_attack", 10) if source else 10
						})
			"thunder_stack_2":
				if primary_target and not primary_target.is_dead and primary_target.has_debuff("thunder"):
					effects.append({
						"type": "debuff",
						"hero_id": primary_target.hero_id,
						"instance_id": primary_target.instance_id,
						"is_host_hero": primary_target.is_player_hero,
						"debuff_type": "thunder_stack_2",
						"duration": 1,
						"value": source.hero_data.get("base_attack", 10) if source else 10
					})
			"penetrate":
				# Penetrate damage is already applied by _apply_effects
				# Snapshot the behind-target's HP
				if primary_target and not primary_target.is_dead:
					var target_team = player_heroes if primary_target.is_player_hero else enemy_heroes
					var target_index = target_team.find(primary_target)
					var behind_index = target_index - 1 if primary_target.is_player_hero else target_index + 1
					if behind_index >= 0 and behind_index < target_team.size():
						var behind_target = target_team[behind_index]
						if not behind_target.is_dead:
							effects.append({
								"type": "damage",
								"hero_id": behind_target.hero_id,
								"instance_id": behind_target.instance_id,
								"is_host_hero": behind_target.is_player_hero,
								"amount": int(source.hero_data.get("base_attack", 10) * 1.0),
								"new_hp": behind_target.current_hp,
								"new_block": behind_target.block
							})
							effects.append({
								"type": "debuff",
								"hero_id": behind_target.hero_id,
								"instance_id": behind_target.instance_id,
								"is_host_hero": behind_target.is_player_hero,
								"debuff_type": "weak",
								"duration": 1,
								"expire_on": "own_turn_end",
								"value": source.hero_data.get("base_attack", 10)
							})
			"shield_current_hp":
				if source and not source.is_dead:
					effects.append({
						"type": "block",
						"hero_id": source.hero_id,
						"instance_id": source.instance_id,
						"is_host_hero": source.is_player_hero,
						"amount": source.current_hp,
						"new_block": source.block
					})
			"break":
				if primary_target and not primary_target.is_dead:
					effects.append({
						"type": "debuff",
						"hero_id": primary_target.hero_id,
						"instance_id": primary_target.instance_id,
						"is_host_hero": primary_target.is_player_hero,
						"debuff_type": "break",
						"duration": 1,
						"expire_on": "own_turn_end",
						"value": source.hero_data.get("base_attack", 10) if source else 10
					})
			"draw_1":
				if source and source.is_player_hero:
					effects.append({
						"type": "draw",
						"hero_id": source.hero_id,
						"instance_id": source.instance_id,
						"is_host_hero": source.is_player_hero,
						"amount": 1
					})
			"mana_surge":
				# Mana surge bonus damage is already applied by _apply_effects
				# Just note it for the Guest (no extra snapshot needed)
				pass

func _execute_ex_skill_and_collect_results(source: Hero, target: Hero) -> Dictionary:
	## HOST ONLY: Execute an EX skill and collect all effects as results
	## Handles all EX types: damage, self_buff, thunder_all, revive, multi-target
	var effects: Array = []
	
	if source == null:
		return {"success": false, "effects": []}
	
	var ex_data = source.hero_data.get("ex_skill", {})
	var ex_type = ex_data.get("type", "damage")
	var ex_effects = ex_data.get("effects", [])
	var base_atk = source.hero_data.get("base_attack", 10)
	
	print("Battle: [HOST] _execute_ex_skill_and_collect_results")
	print("  source: ", source.hero_id, " ex_type: ", ex_type)
	print("  target: ", target.hero_id if target else "null")
	print("  ex_effects: ", ex_effects)
	
	# Snapshot all heroes BEFORE execution so we can detect changes
	var pre_snapshot: Dictionary = {}
	for h in player_heroes + enemy_heroes:
		pre_snapshot[h.instance_id] = {
			"hp": h.current_hp,
			"block": h.block,
			"energy": h.energy,
			"is_dead": h.is_dead
		}
	
	# For self_buff and thunder_all, target may be source itself
	if target == null and (ex_type == "self_buff" or ex_type == "thunder_all"):
		target = source
	
	# Execute the EX skill (runs animation + applies effects on Host)
	if target:
		await _execute_ex_skill(source, target)
	else:
		# Fallback: execute with source as target (shouldn't happen normally)
		await _execute_ex_skill(source, source)
	
	# Always collect source energy change (EX costs energy)
	effects.append({
		"type": "energy",
		"hero_id": source.hero_id,
		"instance_id": source.instance_id,
		"is_host_hero": source.is_player_hero,
		"new_energy": source.energy
	})
	
	# Detect and collect all state changes by comparing to pre-snapshot
	for h in player_heroes + enemy_heroes:
		var pre = pre_snapshot.get(h.instance_id, {})
		if pre.is_empty():
			continue
		
		# HP changed (damage or heal)
		if h.current_hp != pre.get("hp", h.current_hp):
			if h.current_hp < pre.get("hp", h.current_hp):
				effects.append({
					"type": "damage",
					"hero_id": h.hero_id,
					"instance_id": h.instance_id,
					"is_host_hero": h.is_player_hero,
					"amount": pre.get("hp", 0) - h.current_hp,
					"new_hp": h.current_hp,
					"new_block": h.block
				})
			else:
				effects.append({
					"type": "heal",
					"hero_id": h.hero_id,
					"instance_id": h.instance_id,
					"is_host_hero": h.is_player_hero,
					"amount": h.current_hp - pre.get("hp", 0),
					"new_hp": h.current_hp
				})
		
		# Block changed
		if h.block != pre.get("block", h.block):
			effects.append({
				"type": "block",
				"hero_id": h.hero_id,
				"instance_id": h.instance_id,
				"is_host_hero": h.is_player_hero,
				"amount": h.block - pre.get("block", 0),
				"new_block": h.block
			})
		
		# Hero died
		if h.is_dead and not pre.get("is_dead", false):
			# Already captured in damage effect above with new_hp <= 0
			pass
		
		# Hero revived (was dead, now alive)
		if not h.is_dead and pre.get("is_dead", false):
			effects.append({
				"type": "revive",
				"hero_id": h.hero_id,
				"instance_id": h.instance_id,
				"is_host_hero": h.is_player_hero,
				"new_hp": h.current_hp
			})
	
	# Collect buff/debuff effects from the EX skill's effects array
	# These are applied by _apply_effects inside _execute_ex_skill
	_collect_effects_snapshot(effects, ex_effects, source, target, [])
	
	print("Battle: [HOST] EX skill collected ", effects.size(), " effects")
	for i in range(effects.size()):
		var e = effects[i]
		print("  effect[", i, "]: ", e.get("type", "?"), " on ", e.get("hero_id", "?"))
	
	return {
		"success": true,
		"effects": effects
	}

func _execute_opponent_card(card_id: String, target_hero_id: String) -> void:
	# Find the card in enemy hand and play it
	var card_data: Dictionary = {}
	for card in GameManager.enemy_hand:
		if card.get("id", "") == card_id:
			card_data = card
			break
	
	if card_data.is_empty():
		print("Battle: Could not find opponent card: ", card_id)
		return
	
	# Find target hero
	var target: Hero = null
	if not target_hero_id.is_empty():
		for hero in player_heroes + enemy_heroes:
			if hero.hero_id == target_hero_id:
				target = hero
				break
	
	# Execute the card effect (similar to AI but for opponent)
	await _animate_opponent_card_play(card_data, target)

func _execute_opponent_ex_skill(hero_id: String, target_hero_id: String) -> void:
	# Find the enemy hero using the EX skill
	var source_hero: Hero = null
	for hero in enemy_heroes:
		if hero.hero_id == hero_id:
			source_hero = hero
			break
	
	if source_hero == null:
		print("Battle: Could not find opponent hero: ", hero_id)
		return
	
	# Find target
	var target: Hero = null
	if not target_hero_id.is_empty():
		for hero in player_heroes + enemy_heroes:
			if hero.hero_id == target_hero_id:
				target = hero
				break
	
	# Execute EX skill
	if target:
		await _execute_ex_skill(source_hero, target)

func _execute_opponent_card_with_data(card_data: Dictionary, source_hero_id: String, target_hero_id: String, target_is_enemy: bool) -> void:
	## NEW: Execute opponent's card using full card data (no lookup needed)
	print("Battle: Executing opponent card: ", card_data.get("name", "Unknown"), " -> ", target_hero_id)
	
	# Find source hero (from opponent's perspective, so in enemy_heroes for us)
	var source_hero: Hero = null
	for hero in enemy_heroes:
		if hero.hero_id == source_hero_id:
			source_hero = hero
			break
	
	# Find target hero
	# IMPORTANT: target_is_enemy is from OPPONENT's perspective
	# If opponent targeted their enemy (us), target_is_enemy = true, so we look in player_heroes
	# If opponent targeted their ally (themselves), target_is_enemy = false, so we look in enemy_heroes
	var target: Hero = null
	if not target_hero_id.is_empty():
		var search_array = player_heroes if target_is_enemy else enemy_heroes
		for hero in search_array:
			if hero.hero_id == target_hero_id:
				target = hero
				break
		# Fallback: search all heroes if not found
		if target == null:
			for hero in player_heroes + enemy_heroes:
				if hero.hero_id == target_hero_id:
					target = hero
					break
	
	if target == null and not target_hero_id.is_empty():
		print("Battle: Could not find target hero: ", target_hero_id)
		return
	
	# Show and resolve the card effect
	await _show_card_display(card_data)
	await _resolve_opponent_card_effect(card_data, source_hero, target)
	await _hide_card_display()
	
	# Update enemy hand display (decrement count)
	_refresh_enemy_hand_display()

func _resolve_opponent_card_effect(card_data: Dictionary, source: Hero, target: Hero) -> void:
	## Resolve card effect when opponent plays a card
	var card_type = card_data.get("type", "")
	var base_atk = source.hero_data.get("base_attack", 10) if source else 10
	var damage_mult = source.get_damage_multiplier() if source else 1.0
	
	match card_type:
		"attack", "basic_attack":
			if target:
				var atk_mult = card_data.get("atk_multiplier", 1.0)
				var damage = int(base_atk * atk_mult * damage_mult)
				if source:
					await _animate_attack(source, target, damage)
				else:
					target.take_damage(damage)
		"heal":
			if target:
				var hp_mult = card_data.get("hp_multiplier", 0.0)
				var heal_amount: int
				if hp_mult > 0 and source:
					heal_amount = source.calculate_heal(hp_mult)
				else:
					var heal_mult = card_data.get("heal_multiplier", card_data.get("atk_multiplier", 1.0))
					heal_amount = int(base_atk * heal_mult)
				target.heal(heal_amount)
				if source:
					await _animate_cast_heal(source, target)
		"buff":
			if target:
				var card_base_shield = card_data.get("base_shield", 0)
				var def_mult = card_data.get("def_multiplier", 0.0)
				var shield_mult_legacy = card_data.get("shield_multiplier", 0.0)
				var shield_amount = 0
				if card_base_shield > 0 or def_mult > 0:
					shield_amount = source.calculate_shield(card_base_shield, def_mult) if source else card_base_shield
				elif shield_mult_legacy > 0:
					shield_amount = int(base_atk * shield_mult_legacy)
				if shield_amount > 0:
					target.add_block(shield_amount)
				var buff_type = card_data.get("buff_type", "")
				if not buff_type.is_empty():
					var buff_expire = _get_buff_expire_on(buff_type)
					target.apply_buff(buff_type, 1, base_atk, buff_expire)
				if source:
					await _animate_cast_buff(source, target)
		"debuff":
			if target:
				var debuff_type = card_data.get("debuff_type", "")
				if not debuff_type.is_empty():
					var debuff_expire = _get_debuff_expire_on(debuff_type)
					target.apply_debuff(debuff_type, 1, base_atk, debuff_expire)
				if source:
					await _animate_cast_debuff(source, target)
		"equipment":
			if target:
				# Apply equipment to target
				target.add_equipment(card_data)
				var eq_base_shield = card_data.get("base_shield", 0)
				var eq_def_mult = card_data.get("def_multiplier", 0.0)
				var eq_shield_legacy = card_data.get("shield_multiplier", 0.0)
				var eq_shield_amount = 0
				if eq_base_shield > 0 or eq_def_mult > 0:
					eq_shield_amount = target.calculate_shield(eq_base_shield, eq_def_mult)
				elif eq_shield_legacy > 0:
					eq_shield_amount = int(base_atk * eq_shield_legacy)
				if eq_shield_amount > 0:
					target.add_block(eq_shield_amount)
				var buff_type = card_data.get("buff_type", "")
				if not buff_type.is_empty():
					target.apply_buff(buff_type, -1, base_atk, "permanent")
				if source:
					await _animate_cast_buff(source, target)
				print(target.hero_data.get("name", "Hero"), " equipped: ", card_data.get("name", "Unknown"))

func _animate_opponent_card_play(card_data: Dictionary, target: Hero) -> void:
	# Show the card being played by opponent
	await _show_card_display(card_data)
	
	var card_type = card_data.get("type", "")
	var source_hero = _get_enemy_source_hero(card_data)
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	
	match card_type:
		"attack", "basic_attack":
			if target:
				var atk_mult = card_data.get("atk_multiplier", 1.0)
				var damage = int(base_atk * atk_mult)
				if source_hero:
					await _animate_attack(source_hero, target, damage)
		"heal":
			if target:
				var hp_mult = card_data.get("hp_multiplier", 0.0)
				var heal_amount: int
				if hp_mult > 0 and source_hero:
					heal_amount = source_hero.calculate_heal(hp_mult)
				else:
					var heal_mult = card_data.get("heal_multiplier", 1.0)
					heal_amount = int(base_atk * heal_mult)
				target.heal(heal_amount)
				if source_hero:
					await _animate_cast_heal(source_hero, target)
		"buff":
			if target:
				var card_base_shield = card_data.get("base_shield", 0)
				var def_mult = card_data.get("def_multiplier", 0.0)
				var shield_mult_legacy = card_data.get("shield_multiplier", 0.0)
				var shield_amount = 0
				if card_base_shield > 0 or def_mult > 0:
					shield_amount = source_hero.calculate_shield(card_base_shield, def_mult) if source_hero else card_base_shield
				elif shield_mult_legacy > 0:
					shield_amount = int(base_atk * shield_mult_legacy)
				if shield_amount > 0:
					target.add_block(shield_amount)
				if source_hero:
					await _animate_cast_buff(source_hero, target)
	
	# Remove from enemy hand
	for i in range(GameManager.enemy_hand.size() - 1, -1, -1):
		if GameManager.enemy_hand[i].get("id", "") == card_data.get("id", ""):
			GameManager.enemy_hand.remove_at(i)
			break
	
	await _hide_card_display()
	_refresh_enemy_hand_display()

func _get_enemy_source_hero(card_data: Dictionary) -> Hero:
	var hero_color = card_data.get("hero_color", "")
	for hero in enemy_heroes:
		if hero.get_color() == hero_color:
			return hero
	return null

func _show_disconnect_popup() -> void:
	var popup = Panel.new()
	popup.custom_minimum_size = Vector2(400, 150)
	popup.position = Vector2(get_viewport_rect().size.x / 2 - 200, get_viewport_rect().size.y / 2 - 75)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	popup.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 15)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	popup.add_child(vbox)
	
	var label = Label.new()
	label.text = "Opponent Disconnected"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	vbox.add_child(label)
	
	var claim_btn = Button.new()
	claim_btn.text = "Claim Victory"
	claim_btn.custom_minimum_size = Vector2(150, 40)
	claim_btn.pressed.connect(func():
		popup.queue_free()
		_on_game_over(true)  # Player wins
	)
	vbox.add_child(claim_btn)
	
	add_child(popup)

func _on_network_game_over(player_won: bool) -> void:
	# Called when opponent sends game over signal
	_on_game_over(player_won)
