extends Control

enum BattlePhase { MULLIGAN, PLAYING, TARGETING, EX_TARGETING, ENEMY_TURN, GAME_OVER, CARD_SELECTING }

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
var card_queue: Array = []  # Array of {card_data, card_id, queue_uid, mana_spent}
var is_casting: bool = false
var queued_card_visuals: Array = []  # Flying card visuals for queued cards
var _queue_uid_counter: int = 0  # Unique ID per queued card to avoid duplicate card_id collisions

var _pending_dig: Dictionary = {}
var _last_played_source_hero: Hero = null
var _last_played_card_data: Dictionary = {}

# Card selection state (Reshuffle / Scrapyard Overflow)
var _card_select_mode: String = ""  # "reshuffle" or "scrapyard_discard"
var _card_select_picks: Array = []  # Selected Card instances
var _card_select_required: int = -1  # -1 = any amount, >0 = exact count required
var _card_select_source: Hero = null  # Hero who cast the skill

# HP snapshot for Temporal Shift (Nyra EX) — stores HP at start of each player turn
# Format: { instance_id: { "hp": int, "was_dead": bool } }
var _hp_snapshot_last_turn: Dictionary = {}
var _hp_snapshot_this_turn: Dictionary = {}

# Battle Log
var battle_log_entries: Array = []
var battle_log_panel: PanelContainer = null
var battle_log_scroll: ScrollContainer = null
var battle_log_container: VBoxContainer = null
var battle_log_button: Button = null
var battle_log_visible: bool = false

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

# Practice mode
var is_practice_mode: bool = false
var practice_panel: PanelContainer = null
var practice_panel_vbox: VBoxContainer = null
var practice_panel_collapsed: bool = false
var practice_panel_dragging: bool = false
var practice_panel_drag_offset: Vector2 = Vector2.ZERO
var practice_hero_picker: CanvasLayer = null
var _practice_spawn_is_player: bool = false
var _practice_controlling_enemy: bool = false
var _practice_dragging_hero: Hero = null
var _practice_drag_ghost: TextureRect = null
var _practice_drag_start_pos: Vector2 = Vector2.ZERO
var _practice_drag_origin: Vector2 = Vector2.ZERO
var _practice_drag_active: bool = false
const PRACTICE_DRAG_THRESHOLD: float = 10.0
var _practice_selected_hero: Hero = null
var _practice_select_highlight: ColorRect = null
var _practice_selected_label: Label = null
var _practice_unli_mana: bool = false
var _practice_unli_mana_btn: Button = null
var _practice_replace_btn: Button = null
var _practice_replacing_hero: Hero = null

func _ready() -> void:
	GameManager.mana_changed.connect(_on_mana_changed)
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.game_over.connect(_on_game_over)
	GameManager.deck_shuffled.connect(_on_deck_shuffled)
	
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	mulligan_button.pressed.connect(_on_mulligan_confirm)
	if concede_button:
		concede_button.pressed.connect(_on_concede_pressed)
	
	_init_effect_registry()
	
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
	
	_setup_battle_log()
	_setup_battle()

func _input(event: InputEvent) -> void:
	# Right-click to cancel targeting / EX targeting
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if current_phase == BattlePhase.TARGETING:
				_deselect_card()
			elif current_phase == BattlePhase.EX_TARGETING:
				_cancel_ex_skill()
	
	# Practice mode: drag-and-drop hero repositioning
	if not is_practice_mode:
		return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Mouse down — check if we clicked on a hero
			var mouse_pos = event.global_position
			var hero = _practice_get_hero_at(mouse_pos)
			if hero and not hero.is_dead:
				_practice_dragging_hero = hero
				_practice_drag_start_pos = mouse_pos
				_practice_drag_origin = hero.global_position
				_practice_drag_active = false
			else:
				# Clicked empty space — deselect hero (but not if clicking on practice panel UI)
				if _practice_selected_hero:
					var panel_rect = practice_panel.get_global_rect() if practice_panel and is_instance_valid(practice_panel) else Rect2()
					if not panel_rect.has_point(mouse_pos):
						_practice_deselect()
		else:
			# Mouse up — finish drag or let click through
			if _practice_drag_active and _practice_dragging_hero:
				_practice_finish_drag()
				# Consume the event so the ClickArea button doesn't fire hero_clicked
				get_viewport().set_input_as_handled()
			_practice_dragging_hero = null
			_practice_drag_active = false
	
	elif event is InputEventMouseMotion and _practice_dragging_hero:
		var dist = event.global_position.distance_to(_practice_drag_start_pos)
		if not _practice_drag_active and dist >= PRACTICE_DRAG_THRESHOLD:
			# Start drag
			_practice_drag_active = true
			_practice_start_drag()
		if _practice_drag_active:
			_practice_update_drag(event.global_position)

func _practice_get_hero_at(pos: Vector2) -> Hero:
	for hero in player_heroes + enemy_heroes:
		if not is_instance_valid(hero):
			continue
		var rect = Rect2(hero.global_position, hero.size)
		if rect.has_point(pos):
			return hero
	return null

func _practice_start_drag() -> void:
	if not _practice_dragging_hero:
		return
	# Create ghost preview
	_practice_drag_ghost = TextureRect.new()
	_practice_drag_ghost.custom_minimum_size = Vector2(100, 100)
	_practice_drag_ghost.size = Vector2(100, 100)
	_practice_drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_practice_drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path = _practice_dragging_hero.hero_data.get("portrait", "")
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		_practice_drag_ghost.texture = load(portrait_path)
	_practice_drag_ghost.modulate = Color(1, 1, 1, 0.7)
	_practice_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_practice_drag_ghost.z_index = 100
	add_child(_practice_drag_ghost)
	# Dim the dragged hero
	_practice_dragging_hero.modulate = Color(0.5, 0.5, 0.5, 0.5)

func _practice_update_drag(mouse_pos: Vector2) -> void:
	if _practice_drag_ghost:
		_practice_drag_ghost.global_position = mouse_pos - Vector2(50, 50)

func _practice_finish_drag() -> void:
	var mouse_pos = get_global_mouse_position()
	var drop_target = _practice_get_hero_at(mouse_pos)
	
	if drop_target and drop_target != _practice_dragging_hero and not drop_target.is_dead:
		# Swap positions
		var pos_a = _practice_drag_origin
		var pos_b = drop_target.global_position
		var z_a = _practice_dragging_hero.z_index
		var z_b = drop_target.z_index
		var idx_a = _practice_dragging_hero.team_index
		var idx_b = drop_target.team_index
		
		_practice_dragging_hero.global_position = pos_b
		drop_target.global_position = pos_a
		_practice_dragging_hero.z_index = z_b
		drop_target.z_index = z_a
		_practice_dragging_hero.team_index = idx_b
		drop_target.team_index = idx_a
		
		# Update array order for same-team swaps
		if _practice_dragging_hero.is_player_hero == drop_target.is_player_hero:
			var arr = player_heroes if _practice_dragging_hero.is_player_hero else enemy_heroes
			var i_a = arr.find(_practice_dragging_hero)
			var i_b = arr.find(drop_target)
			if i_a >= 0 and i_b >= 0:
				arr[i_a] = drop_target
				arr[i_b] = _practice_dragging_hero
		
		print("[Practice] Swapped: ", _practice_dragging_hero.hero_data.get("name", "?"), " <-> ", drop_target.hero_data.get("name", "?"))
	else:
		# Snap back to original position
		_practice_dragging_hero.global_position = _practice_drag_origin
	
	# Restore hero appearance
	_practice_dragging_hero.modulate = Color(1, 1, 1, 1)
	
	# Remove ghost
	if _practice_drag_ghost and is_instance_valid(_practice_drag_ghost):
		_practice_drag_ghost.queue_free()
	_practice_drag_ghost = null

func _setup_battle() -> void:
	# Check for practice mode
	if HeroDatabase.practice_mode:
		is_practice_mode = true
		HeroDatabase.practice_mode = false  # Reset flag so returning to collection doesn't re-trigger
		var practice_hero = HeroDatabase.practice_hero_id
		var player_team = [practice_hero]
		var enemy_team = HeroDatabase.ai_enemy_team
		if enemy_team.is_empty():
			var all_ids = HeroDatabase.heroes.keys()
			var others = all_ids.filter(func(id): return id != practice_hero)
			others.shuffle()
			enemy_team = [others[0]]
		print("Battle: Practice mode — hero: ", practice_hero, " vs ", enemy_team)
		_finalize_battle_setup(player_team, enemy_team)
		return
	
	# Check if this is a multiplayer battle
	_setup_multiplayer()
	
	var player_team = HeroDatabase.get_current_team()
	
	if is_multiplayer:
		# In multiplayer, we need to exchange teams with opponent
		await _setup_multiplayer_battle(player_team)
	else:
		# AI battle: use generated AI team, fallback to reversed player team
		var enemy_team = HeroDatabase.ai_enemy_team
		if enemy_team.is_empty():
			enemy_team = player_team.duplicate()
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
	# Reset all GameManager state (mana, turn, decks, heroes) to prevent leaks from previous battles
	GameManager.start_game()
	
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
		var stat_key = hero.instance_id if is_practice_mode else hero.hero_id
		GameManager.init_hero_stats(
			stat_key,
			true,
			hero_data.get("portrait", ""),
			hero_data.get("name", "Hero")
		)
	for hero in enemy_heroes:
		var hero_data = hero.hero_data
		var stat_key = hero.instance_id if is_practice_mode else ("enemy_" + hero.hero_id)
		GameManager.init_hero_stats(
			stat_key,
			false,
			hero_data.get("portrait", ""),
			hero_data.get("name", "Hero")
		)
	
	# Build player deck
	if is_practice_mode:
		# Instance-based build supports duplicate heroes (3× Squire etc.)
		GameManager.build_deck_from_instances(player_heroes, false)
	else:
		var hero_data_list = []
		for hero_id in player_team:
			hero_data_list.append(HeroDatabase.get_hero(hero_id))
		GameManager.build_deck(hero_data_list)
	
	# Build enemy deck (only for AI battles - in multiplayer, opponent manages their own deck)
	if not is_multiplayer:
		if is_practice_mode:
			GameManager.build_enemy_deck_from_instances(enemy_heroes)
		else:
			var enemy_hero_data_list = []
			for hero_id in enemy_team:
				enemy_hero_data_list.append(HeroDatabase.get_hero(hero_id))
			GameManager.build_enemy_deck(enemy_hero_data_list)
		
		# Enemy draws initial hand (same as player starting hand)
		GameManager.enemy_draw_cards(5)
	
	_setup_enemy_hand_display()
	_start_rps_minigame()
	
	if is_practice_mode:
		_setup_practice_ui()

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
		hero_instance.team_index = i
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
		hero_instance.shield_broken.connect(_on_shield_broken)
		hero_instance.counter_triggered.connect(_on_counter_triggered)
		
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
		if _practice_controlling_enemy:
			deck_label.text = str(GameManager.enemy_deck.size())
		else:
			deck_label.text = str(GameManager.deck.size())

func _update_turn_display() -> void:
	if turn_label:
		turn_label.text = str(GameManager.turn_number)

var rps_minigame_scene = preload("res://scenes/battle/rps_minigame.tscn")
var player_goes_first: bool = true

func _start_rps_minigame() -> void:
	# Training mode: skip RPS, use chosen turn order
	if not is_multiplayer:
		var player_first = HeroDatabase.training_player_first
		print("Battle: Training mode — skipping RPS, player_first = ", player_first)
		_on_rps_finished(player_first)
		return
	
	# Multiplayer: use RPS minigame
	var rps = rps_minigame_scene.instantiate()
	
	if network_manager:
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
	# Also handle card selection confirm (Reshuffle / Scrapyard Overflow)
	if current_phase == BattlePhase.CARD_SELECTING:
		_confirm_card_select()
		return
	
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
	
	# AI smart mulligan — replace expensive/bad cards
	var cards_to_replace = GameManager.enemy_smart_mulligan()
	
	if cards_to_replace > 0:
		# Animate enemy hand changing (cards go down, new ones come up)
		for i in range(cards_to_replace):
			if enemy_hand_container.get_child_count() > i:
				var card_back = enemy_hand_container.get_child(i)
				var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
				tween.tween_property(card_back, "modulate:a", 0.0, 0.15)
		
		await get_tree().create_timer(0.3).timeout
		
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

func _refresh_hand_descriptions() -> void:
	## Lightweight: update card descriptions in-place to reflect current empower/weak state
	for card_instance in hand_container.get_children():
		if is_instance_valid(card_instance) and card_instance.has_method("refresh_description"):
			var source_hero = _get_source_hero(card_instance.card_data)
			card_instance.refresh_description(source_hero)
			# Update stun overlay
			if source_hero and card_instance.has_method("set_stunned"):
				card_instance.set_stunned(source_hero.is_stunned())

func _refresh_hand(animate: bool = false) -> void:
	# In practice enemy control, show enemy hand instead
	if _practice_controlling_enemy:
		_practice_show_enemy_hand()
		return
	
	for child in hand_container.get_children():
		if is_instance_valid(child):
			child.queue_free()
	
	var index = 0
	for card_data in GameManager.hand:
		var card_instance = card_scene.instantiate()
		hand_container.add_child(card_instance)
		card_instance.setup(card_data)
		card_instance.card_clicked.connect(_on_card_clicked)
		
		# Apply empower/weak state to description
		var source_hero_emp = _get_source_hero(card_data)
		card_instance.refresh_description(source_hero_emp)
		
		# Apply frost cost modifier
		var source_hero_frost = _get_source_hero(card_data)
		if source_hero_frost and source_hero_frost.has_debuff("frost"):
			card_instance.update_display_cost(1)
		
		if current_phase == BattlePhase.MULLIGAN:
			card_instance.can_interact = true
		else:
			var source_hero = _get_source_hero(card_data)
			var can_play = card_instance.can_play(GameManager.current_mana) and _can_pay_hp_cost(card_data, source_hero)
			card_instance.set_playable(can_play)
			# Show stun overlay if source hero is stunned
			if source_hero and source_hero.is_stunned():
				card_instance.set_stunned(true)
		
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
		
		# Apply empower/weak state to description
		var source_hero_emp = _get_source_hero(card_data)
		card_instance.refresh_description(source_hero_emp)
		
		# Apply frost cost modifier
		var source_hero_frost = _get_source_hero(card_data)
		if source_hero_frost and source_hero_frost.has_debuff("frost"):
			card_instance.update_display_cost(1)
		
		if current_phase == BattlePhase.MULLIGAN:
			card_instance.can_interact = true
		else:
			var source_hero = _get_source_hero(card_data)
			var can_play = card_instance.can_play(GameManager.current_mana) and _can_pay_hp_cost(card_data, source_hero)
			card_instance.set_playable(can_play)
			# Show stun overlay if source hero is stunned
			if source_hero and source_hero.is_stunned():
				card_instance.set_stunned(true)
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
	if current_phase == BattlePhase.CARD_SELECTING:
		_toggle_card_select(card)
		return
	elif current_phase == BattlePhase.MULLIGAN:
		_toggle_mulligan_selection(card)
	elif current_phase == BattlePhase.PLAYING and (GameManager.is_player_turn or _practice_controlling_enemy):
		# Block new cards while a deck manipulation card is mid-execution (awaiting selection UI)
		if _deck_manipulation_active:
			return
		# Only allow playing cards during player's turn (or enemy turn in practice)
		var source_hero = _get_source_hero(card.card_data)
		var active_mana = GameManager.enemy_current_mana if _practice_controlling_enemy else GameManager.current_mana
		if card.can_play(active_mana) and _can_pay_hp_cost(card.card_data, source_hero):
			# Check if the source hero is stunned
			if source_hero and source_hero.is_stunned():
				print("Cannot play card - " + source_hero.hero_data.get("name", "Hero") + " is stunned!")
				_log_event(source_hero.hero_data.get("name", "Hero") + " is STUNNED! Cannot play cards.", Color(1.0, 0.3, 0.3))
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
			elif card_type in ["dig", "search_deck", "check_discard"]:
				auto_cast = true
			
			if auto_cast:
				# UNIFIED STACK SYSTEM: Auto-cast cards go to the stack
				_add_card_to_stack(card)
			else:
				# Requires targeting - block if a queued card is mid-execution
				if is_casting:
					return
				_select_card(card)

func _toggle_mulligan_selection(card: Card) -> void:
	if card in mulligan_selections:
		mulligan_selections.erase(card)
		card.set_selected(false)
	else:
		mulligan_selections.append(card)
		card.set_selected(true)

func _toggle_card_select(card: Card) -> void:
	if card in _card_select_picks:
		_card_select_picks.erase(card)
		card.set_selected(false)
	else:
		# If exact count required and already at limit, don't allow more
		if _card_select_required > 0 and _card_select_picks.size() >= _card_select_required:
			return
		_card_select_picks.append(card)
		card.set_selected(true)
	# Update confirm button text
	var count = _card_select_picks.size()
	if _card_select_mode == "reshuffle":
		if turn_indicator:
			turn_indicator.text = "RESHUFFLE: Select cards to return (" + str(count) + " selected)\nClick Confirm when ready"
	elif _card_select_mode == "scrapyard_discard":
		if turn_indicator:
			turn_indicator.text = "DISCARD: Select " + str(_card_select_required) + " cards (" + str(count) + "/" + str(_card_select_required) + ")\nClick Confirm when ready"

func _start_card_select(mode: String, required: int, source: Hero) -> void:
	_card_select_mode = mode
	_card_select_picks.clear()
	_card_select_required = required
	_card_select_source = source
	current_phase = BattlePhase.CARD_SELECTING
	# Make all cards in hand interactable
	for child in hand_container.get_children():
		if child is Card:
			child.can_interact = true
	# Show mulligan panel as confirm button
	mulligan_panel.visible = true
	if mulligan_button:
		mulligan_button.text = "Confirm"
	if mode == "reshuffle":
		if turn_indicator:
			turn_indicator.text = "RESHUFFLE: Select cards to return (0 selected)\nClick Confirm when ready"
	elif mode == "scrapyard_discard":
		if turn_indicator:
			turn_indicator.text = "DISCARD: Select " + str(required) + " cards (0/" + str(required) + ")\nClick Confirm when ready"

func _confirm_card_select() -> void:
	if _card_select_mode == "scrapyard_discard" and _card_select_required > 0:
		if _card_select_picks.size() != _card_select_required:
			print("[Card Select] Must select exactly " + str(_card_select_required) + " cards")
			return
	
	var selected_cards: Array = []
	for card in _card_select_picks:
		selected_cards.append(card.card_data)
	
	mulligan_panel.visible = false
	if mulligan_button:
		mulligan_button.text = "Confirm"
	
	if _card_select_mode == "reshuffle":
		_execute_reshuffle(selected_cards)
	elif _card_select_mode == "scrapyard_discard":
		_execute_scrapyard_discard(selected_cards)
	
	_card_select_mode = ""
	_card_select_picks.clear()
	_card_select_required = -1
	_card_select_source = null
	current_phase = BattlePhase.PLAYING
	_refresh_hand()

func _execute_reshuffle(cards_to_return: Array) -> void:
	var count = cards_to_return.size()
	if count == 0:
		print("[Reshuffle] No cards selected — nothing to reshuffle")
		return
	var rs_hand = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
	var rs_deck = GameManager.enemy_deck if _practice_controlling_enemy else GameManager.deck
	# Remove selected cards from hand and put back in deck
	for card_data in cards_to_return:
		var idx = -1
		for i in range(rs_hand.size()):
			if rs_hand[i].get("id", "") == card_data.get("id", "") and rs_hand[i] == card_data:
				idx = i
				break
		if idx >= 0:
			rs_hand.remove_at(idx)
			rs_deck.append(card_data)
	# Shuffle deck
	rs_deck.shuffle()
	# Draw same amount
	if _practice_controlling_enemy:
		GameManager.enemy_draw_cards(count)
	else:
		GameManager.draw_cards(count)
	_refresh_hand(true)
	_update_deck_display()
	print("[Reshuffle] Returned " + str(count) + " cards to deck, drew " + str(count) + " new cards")

func _execute_scrapyard_discard(cards_to_discard: Array) -> void:
	var sd_hand = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
	var sd_discard = GameManager.enemy_discard_pile if _practice_controlling_enemy else GameManager.discard_pile
	for card_data in cards_to_discard:
		var idx = -1
		for i in range(sd_hand.size()):
			if sd_hand[i].get("id", "") == card_data.get("id", "") and sd_hand[i] == card_data:
				idx = i
				break
		if idx >= 0:
			var removed = sd_hand[idx]
			sd_hand.remove_at(idx)
			sd_discard.append(removed)
	_refresh_hand(true)
	_update_deck_display()
	print("[Scrapyard Overflow] Discarded " + str(cards_to_discard.size()) + " cards")

func _add_card_to_stack(card: Card) -> void:
	var card_id = card.card_data.get("id", "")
	var this_cost = card.card_data.get("cost", 0)
	var source_hero = _get_source_hero(card.card_data)
	if not _can_pay_hp_cost(card.card_data, source_hero):
		return
	
	# Handle Mana Surge (cost = -1 means use ALL mana)
	var active_mana_pool = GameManager.enemy_current_mana if _practice_controlling_enemy else GameManager.current_mana
	if this_cost == -1:
		this_cost = active_mana_pool
		if this_cost < 1:
			return  # Need at least 1 mana
		# Store the mana spent for damage calculation
		card.card_data["mana_spent"] = this_cost
	else:
		# Frost debuff: +1 card cost for each frosted hero on the source's team
		if source_hero and source_hero.has_debuff("frost"):
			this_cost += 1
	
	# Check if we have enough mana
	if active_mana_pool < this_cost:
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
			if not _can_pay_hp_cost(card.card_data, source_hero):
				return
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
	if _practice_controlling_enemy:
		GameManager.enemy_current_mana -= this_cost
		GameManager.mana_changed.emit(GameManager.enemy_current_mana, GameManager.enemy_max_mana)
	else:
		GameManager.current_mana -= this_cost
		GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
	
	# Store card data with unique queue ID
	_queue_uid_counter += 1
	var queue_uid = _queue_uid_counter
	var queued_data = {
		card_data = card.card_data.duplicate(),
		card_id = card_id,
		queue_uid = queue_uid,
		mana_spent = this_cost
	}
	card_queue.append(queued_data)
	
	# Remove from hand (player or enemy)
	var active_hand = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
	for i in range(active_hand.size() - 1, -1, -1):
		if active_hand[i].get("id", "") == card_id:
			active_hand.remove_at(i)
			break
	
	# Add to discard pile (skip temporary, equipment, and shuffle_to_deck cards)
	if card.card_data.get("shuffle_to_deck", false):
		# Shuffle back into deck instead of discard (e.g. Nyxara's Crescent Moon)
		var active_deck = GameManager.enemy_deck if _practice_controlling_enemy else GameManager.deck
		active_deck.append(card.card_data.duplicate())
		active_deck.shuffle()
		_update_deck_display()
		print("[Shuffle to Deck] " + card.card_data.get("name", "Card") + " shuffled into deck")
	elif not card.card_data.get("temporary", false) and card.card_data.get("type", "") != "equipment":
		var active_discard = GameManager.enemy_discard_pile if _practice_controlling_enemy else GameManager.discard_pile
		active_discard.append(card.card_data.duplicate())
	
	# Calculate stack position (0 = front, 1+ = behind)
	var stack_position = card_queue.size() - 1
	
	# Create visual and add to stack
	_create_stack_visual(card, stack_position, queue_uid)
	
	# If this is the first card (front of stack), start playing it
	if stack_position == 0:
		is_casting = true
		# Small delay to let the card fly to position first
		await get_tree().create_timer(0.3).timeout
		_play_front_card()

func _create_stack_visual(card: Card, stack_position: int, queue_uid: int = -1) -> void:
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
	
	# Store visual reference using unique queue_uid
	queued_card_visuals.append({visual = flying_card, queue_uid = queue_uid})
	
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
	var uid = front.queue_uid
	
	# Find the front visual by unique queue_uid
	var front_visual: Node = null
	for visual_data in queued_card_visuals:
		if visual_data.queue_uid == uid:
			front_visual = visual_data.visual
			break
	
	if not front_visual or not is_instance_valid(front_visual):
		# No visual, remove from queue and try next
		card_queue.pop_front()
		for i in range(queued_card_visuals.size() - 1, -1, -1):
			if queued_card_visuals[i].queue_uid == uid:
				queued_card_visuals.remove_at(i)
				break
		_play_front_card()
		return
	
	# Execute the card effect
	await _play_queued_card(card_data, front_visual)

func _play_queued_card(card_data: Dictionary, visual: Node) -> void:
	var card_type = card_data.get("type", "")
	var target_type = card_data.get("target", "single")
	var source_hero = _get_source_hero(card_data)
	
	# Track for post-action bleed
	_last_played_source_hero = source_hero
	_last_played_card_data = card_data
	
	if not _can_pay_hp_cost(card_data, source_hero):
		await _fade_out_visual(visual)
		_finish_card_play()
		return
	
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

	# Single-player (or Guest local-only UI): apply HP cost BEFORE resolving (bleed is post-action)
	if not _apply_pre_action_self_effects(card_data, source_hero, false):
		await _fade_out_visual(visual)
		_finish_card_play()
		return
	
	if card_type == "mana":
		var mana_gain := int(card_data.get("mana_gain", 1))
		if _practice_controlling_enemy:
			GameManager.enemy_current_mana += mana_gain
			GameManager.mana_changed.emit(GameManager.enemy_current_mana, GameManager.enemy_max_mana)
		else:
			GameManager.current_mana += mana_gain
			GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
		await _fade_out_visual(visual)
		_finish_card_play()
	elif card_type == "energy":
		# Energy cards like Bull Rage - add energy to source hero
		await _show_card_display(card_data)
		# Play cast animation
		if source_hero:
			await _animate_cast_buff(source_hero, source_hero)
			var energy_gain = card_data.get("energy_gain", 0)
			source_hero.add_energy(energy_gain)
		await _hide_card_display()
		await _fade_out_visual(visual)
		_finish_card_play()
	elif card_type == "attack" or card_type == "basic_attack":
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
	elif card_type in ["dig", "search_deck", "check_discard"]:
		# Deck manipulation cards: block new card plays during execution
		_deck_manipulation_active = true
		if card_type in ["dig", "search_deck"]:
			var required = int(card_data.get("dig_count", 3)) if card_type == "dig" else 1
			var proceed = await _check_deck_size_confirm(card_data, required)
			if not proceed:
				# Player chose No — refund card to hand
				var mana_cost = card_queue[0].mana_spent if not card_queue.is_empty() else 0
				await _fade_out_visual(visual)
				_refund_card_to_hand(card_data, mana_cost)
				_deck_manipulation_active = false
				_finish_card_play()
				return
		await _show_card_display(card_data)
		if source_hero:
			source_hero.play_attack_anim_with_callback(func(): pass)
		await get_tree().create_timer(0.3).timeout
		await _hide_card_display()
		await _fade_out_visual(visual)
		match card_type:
			"dig":
				await _handle_dig_card(card_data, source_hero)
			"search_deck":
				await _handle_search_deck_card(card_data, source_hero)
			"check_discard":
				await _handle_check_discard_card(card_data, source_hero)
		_deck_manipulation_active = false
		_finish_card_play()
	else:
		await _fade_out_visual(visual)
		_finish_card_play()

func _play_queued_card_as_host(card_data: Dictionary, visual: Node) -> void:
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

func _play_queued_attack(card_data: Dictionary, visual: Node, target: Hero) -> void:
	var source_hero = _get_source_hero(card_data)
	
	# Mana already spent when queued, just execute the effect
	if source_hero and source_hero.has_method("add_energy"):
		var energy_gain = int(card_data.get("energy_on_hit", GameConstants.ENERGY_ON_ATTACK))
		source_hero.add_energy(energy_gain)
	
	await _show_card_display(card_data)
	await _resolve_card_effect(card_data, source_hero, target)
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_attack_all(card_data: Dictionary, visual: Node) -> void:
	var source_hero = _get_source_hero(card_data)
	
	# Mana already spent when queued, just execute the effect
	if source_hero and source_hero.has_method("add_energy"):
		var energy_gain = int(card_data.get("energy_on_hit", GameConstants.ENERGY_ON_ATTACK))
		source_hero.add_energy(energy_gain)
	
	await _show_card_display(card_data)
	
	var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
	var atk_mult = card_data.get("atk_multiplier", 1.0)
	var damage_mult = source_hero.get_damage_multiplier() if source_hero else 1.0
	var damage = int(base_atk * atk_mult * damage_mult)
	if damage == 0:
		damage = 10
	var opp_team_aoe = player_heroes if _practice_controlling_enemy else enemy_heroes
	var alive_enemies = opp_team_aoe.filter(func(h): return not h.is_dead)
	
	if source_hero:
		source_hero._play_attack_animation()
	
	await get_tree().create_timer(0.15).timeout
	
	var attacker_id = source_hero.hero_id if source_hero else ""
	var attacker_color = source_hero.get_color() if source_hero else ""
	var total_damage = 0
	for enemy in alive_enemies:
		enemy.spawn_attack_effect(attacker_id, attacker_color)
		enemy.take_damage(damage, source_hero)
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

func _play_queued_heal_all(card_data: Dictionary, visual: Node) -> void:
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
	var my_team_heal_all = enemy_heroes if _practice_controlling_enemy else player_heroes
	var alive_allies = my_team_heal_all.filter(func(h): return not h.is_dead)
	var total_heal = 0
	
	for ally in alive_allies:
		ally.heal(heal_amount)
		total_heal += heal_amount
		# Apply card effects (regen, regen_draw, etc.) to each ally
		var effects = card_data.get("effects", [])
		if not effects.is_empty():
			_apply_effects(effects, source_hero, ally, base_atk, card_data)
	
	if source_hero:
		GameManager.add_healing_done(source_hero.hero_id, total_heal)
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_heal(card_data: Dictionary, visual: Node, target: Hero) -> void:
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
	
	# Apply card effects (regen, regen_draw, etc.)
	var effects = card_data.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, source_hero, target, base_atk, card_data)
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_buff_all(card_data: Dictionary, visual: Node) -> void:
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
	var my_team_buff_all = enemy_heroes if _practice_controlling_enemy else player_heroes
	var alive_allies = my_team_buff_all.filter(func(h): return not h.is_dead)
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
	
	# If effects triggered card selection (e.g. Reshuffle), wait for it to finish
	if current_phase == BattlePhase.CARD_SELECTING:
		while current_phase == BattlePhase.CARD_SELECTING:
			await get_tree().create_timer(0.1).timeout
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _play_queued_debuff_single(card_data: Dictionary, visual: Node, target: Hero) -> void:
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

func _play_queued_debuff_all(card_data: Dictionary, visual: Node) -> void:
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

func _play_queued_buff(card_data: Dictionary, visual: Node, target: Hero) -> void:
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
	
	# If effects triggered card selection (e.g. Reshuffle), wait for it to finish
	if current_phase == BattlePhase.CARD_SELECTING:
		while current_phase == BattlePhase.CARD_SELECTING:
			await get_tree().create_timer(0.1).timeout
	
	await _hide_card_display()
	
	await _fade_out_visual(visual)
	_finish_card_play()

func _get_lowest_hp_ally() -> Hero:
	var my_team_heal = enemy_heroes if _practice_controlling_enemy else player_heroes
	var alive_allies = my_team_heal.filter(func(h): return not h.is_dead)
	if alive_allies.is_empty():
		return null
	var lowest = alive_allies[0]
	for ally in alive_allies:
		if ally.current_hp < lowest.current_hp:
			lowest = ally
	return lowest

func _get_first_alive_ally() -> Hero:
	var my_team_first = enemy_heroes if _practice_controlling_enemy else player_heroes
	var alive_allies = my_team_first.filter(func(h): return not h.is_dead)
	if alive_allies.is_empty():
		return null
	return alive_allies[0]

func _fade_out_visual(visual: Node) -> void:
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
	elif card_type == "attack" or card_type == "basic_attack":
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
	
	# In practice enemy control: flip ally/enemy meaning
	var my_team = enemy_heroes if _practice_controlling_enemy else player_heroes
	var opp_team = player_heroes if _practice_controlling_enemy else enemy_heroes
	var targets = my_team if target_allies else opp_team
	var non_targets = opp_team if target_allies else my_team
	
	# Dim non-targets (keep them under vignette)
	for hero in non_targets:
		hero.z_index = 0
		hero.modulate = Color(1.0, 1.0, 1.0)
	
	# Check for taunt when targeting enemies
	var taunt_hero: Hero = null
	if not target_allies:
		taunt_hero = _get_taunt_target(targets)
	
	# Highlight valid targets with circle animation (bring above vignette)
	for hero in targets:
		if not hero.is_dead:
			# For equipment, check if hero already has one (skip in practice mode)
			if is_equipment and hero.has_equipment() and not is_practice_mode:
				# Hero already has equipment - dim them
				hero.z_index = 0
				hero.modulate = Color(0.5, 0.5, 0.5)
			elif taunt_hero and hero != taunt_hero:
				# Taunt active — only the taunt target is selectable
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
	
	var my_team_r = enemy_heroes if _practice_controlling_enemy else player_heroes
	var opp_team_r = player_heroes if _practice_controlling_enemy else enemy_heroes
	
	# Keep all opponents under vignette
	for hero in opp_team_r:
		hero.z_index = 0
		hero.modulate = Color(1.0, 1.0, 1.0)
	
	# Highlight dead allies for revive (bring above vignette)
	for hero in my_team_r:
		if hero.is_dead:
			hero.z_index = 20
			hero.modulate = Color(1.0, 1.0, 1.0)
			hero.show_targeting_circle()
		else:
			hero.z_index = 0
			hero.modulate = Color(1.0, 1.0, 1.0)

func _on_hero_clicked(hero: Hero) -> void:
	# If we just finished a drag, ignore this click (it's the button release after drag)
	if _practice_drag_active:
		return
	if current_phase == BattlePhase.TARGETING and selected_card:
		var card_type = selected_card.get_card_type()
		var valid_target = false
		# When controlling enemy in practice, flip ally/enemy meaning
		var is_ally = hero.is_player_hero if not _practice_controlling_enemy else not hero.is_player_hero
		
		if (card_type == "attack" or card_type == "basic_attack") and not is_ally and not hero.is_dead:
			valid_target = true
		elif card_type == "debuff" and not is_ally and not hero.is_dead:
			valid_target = true
		elif (card_type == "heal" or card_type == "buff") and is_ally and not hero.is_dead:
			valid_target = true
		elif card_type == "equipment" and is_ally and not hero.is_dead:
			# In practice mode, allow replacing existing equipment
			if hero.has_equipment() and not is_practice_mode:
				print("[Equipment] " + hero.hero_data.get("name", "Hero") + " already has equipment!")
				return  # Don't allow targeting
			valid_target = true
		
		if valid_target:
			_play_card_on_target(selected_card, hero)
	elif current_phase == BattlePhase.EX_TARGETING and ex_skill_hero:
		var ex_data = ex_skill_hero.hero_data.get("ex_skill", {})
		var ex_type = ex_data.get("type", "damage")
		
		var is_ally_ex = hero.is_player_hero if not _practice_controlling_enemy else not hero.is_player_hero
		if ex_type == "revive":
			if is_ally_ex and hero.is_dead:
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
			if not is_ally_ex and not hero.is_dead:
				# Enforce taunt: if an enemy has taunt, only allow targeting them
				var opp_team_ex = player_heroes if _practice_controlling_enemy else enemy_heroes
				var alive_enemies = opp_team_ex.filter(func(h): return not h.is_dead)
				var taunt_target = _get_taunt_target(alive_enemies)
				if taunt_target and hero != taunt_target:
					return  # Can't target non-taunt enemy
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
		var is_my_hero = hero.is_player_hero if not _practice_controlling_enemy else not hero.is_player_hero
		if is_my_hero and hero.energy >= hero.max_energy:
			# Check if hero is stunned
			if hero.is_stunned():
				print("Cannot use EX skill - " + hero.hero_data.get("name", "Hero") + " is stunned!")
				return
			_use_ex_skill(hero)
			return
		# Practice mode: select/deselect hero for practice tools
		if is_practice_mode:
			_practice_toggle_select(hero)

func _play_card_on_target(card: Card, target: Hero) -> void:
	var source_hero = _get_source_hero(card.card_data)
	var card_data_copy = card.card_data.duplicate()
	if not _can_pay_hp_cost(card_data_copy, source_hero):
		_refresh_hand()
		_clear_highlights()
		current_phase = BattlePhase.PLAYING
		return
	
	# HOST-AUTHORITATIVE MULTIPLAYER: Route through request/result system
	if is_multiplayer and network_manager:
		if not is_host:
			if not _can_pay_hp_cost(card_data_copy, source_hero):
				_refresh_hand()
				_clear_highlights()
				current_phase = BattlePhase.PLAYING
				return
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
			# Track for post-action bleed
			_last_played_source_hero = source_hero
			_last_played_card_data = card_data_copy
			
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
	# Track for post-action bleed
	_last_played_source_hero = source_hero
	_last_played_card_data = card_data_copy
	await _animate_card_to_display(card)
	# Apply HP cost BEFORE spending mana / resolving
	if not _apply_pre_action_self_effects(card_data_copy, source_hero, false):
		_refresh_hand()
		_clear_highlights()
		current_phase = BattlePhase.PLAYING
		return
	
	if _battle_play_card(card_data_copy, source_hero, target):
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
		"attack", "basic_attack":
			# Attack cards deal damage - use attack animation
			var atk_mult = card_data.get("atk_multiplier", 1.0)
			
			# Handle Mana Surge: damage = mana_spent × 100% ATK
			var effects = card_data.get("effects", [])
			if effects.has("mana_surge"):
				var mana_spent = card_data.get("mana_spent", 1)
				atk_mult *= float(mana_spent)  # X × 100% ATK
				print("[Mana Surge] Spent " + str(mana_spent) + " mana, dealing " + str(int(base_atk * atk_mult * damage_mult)) + " damage")
			
			# Card Barrage: damage scales with number of cards in hand
			if card_data.get("hand_size_scaling", false):
				var hand_count = GameManager.enemy_hand.size() if _practice_controlling_enemy else GameManager.hand.size()
				atk_mult *= float(hand_count)
				print("[Card Barrage] Hand size " + str(hand_count) + " × " + str(card_data.get("atk_multiplier", 0.5)) + " ATK = " + str(int(base_atk * atk_mult * damage_mult)) + " damage")
			
			var damage = int(base_atk * atk_mult * damage_mult)
			if damage == 0:
				damage = 10
			if source:
				await _animate_attack(source, target, damage)
				GameManager.add_damage_dealt(source_id, damage)
				_log_attack(source.hero_data.get("name", "Hero"), card_data.get("name", "Attack"), target.hero_data.get("name", "Enemy"), damage, true, card_data.get("art", card_data.get("image", "")), target.hero_data.get("portrait", ""))
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
			_log_heal(source.hero_data.get("name", "Hero") if source else "Unknown", card_data.get("name", "Heal"), target.hero_data.get("name", "Ally"), heal_amount, true, card_data.get("art", card_data.get("image", "")), target.hero_data.get("portrait", ""))
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
				_refresh_hand_descriptions()
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
			var buff_text = card_data.get("name", "Buff")
			if shield_amount > 0:
				buff_text = "+" + str(shield_amount) + " Shield"
			_log_buff(source.hero_data.get("name", "Hero") if source else "Unknown", card_data.get("name", "Buff"), target.hero_data.get("name", "Ally"), buff_text, true, card_data.get("art", card_data.get("image", "")), target.hero_data.get("portrait", ""))
		"debuff":
			# Play cast animation for debuffs targeting enemies
			if source:
				await _animate_cast_buff(source, target)
			# Apply debuff effects (thunder_stack_2, etc.)
			var effects = card_data.get("effects", [])
			if not effects.is_empty():
				_apply_effects(effects, source, target, base_atk, card_data)
			_log_buff(source.hero_data.get("name", "Hero") if source else "Unknown", card_data.get("name", "Debuff"), target.hero_data.get("name", "Enemy"), card_data.get("name", "Debuff"), true, card_data.get("art", card_data.get("image", "")), target.hero_data.get("portrait", ""))
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
				if not is_practice_mode:
					print("[Equipment] " + target.hero_data.get("name", "Hero") + " already has equipment! Cannot equip " + equip_name)
					return
				else:
					# Practice mode: remove old equipment before adding new
					print("[Practice] Replacing " + target.hero_data.get("name", "Hero") + "'s equipment with " + equip_name)
					target.clear_equipment()
			
			# Add equipment to hero using new equipment system
			target.add_equipment({
				"id": card_data.get("id", ""),
				"name": equip_name,
				"effect": equip_effect,
				"trigger": equip_trigger,
				"value": equip_value
			})
			_log_equip(card_data.get("art", card_data.get("image", "")), target.hero_data.get("portrait", ""), equip_name)
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
					_log_status(hero.hero_data.get("portrait", ""), equip_name + ": +" + str(heal_amount) + " HP", Color(0.4, 1.0, 0.4))
			
			"energy_gain":
				# Energy Pendant: Gain energy on dealing damage
				var energy_amount = int(value)
				hero.add_energy(energy_amount)
				print("[Equipment] " + equip_name + ": " + hero.hero_data.get("name", "") + " gained " + str(energy_amount) + " energy")
				_log_status(hero.hero_data.get("portrait", ""), equip_name + ": +" + str(energy_amount) + " Energy", Color(1.0, 0.87, 0.4))
			
			"apply_frost":
				# Frost Gauntlet: Apply Frost to target (+1 card cost)
				var target = context.get("target", null)
				if target and is_instance_valid(target) and not target.is_dead:
					target.apply_debuff("frost", 1, 0, "own_turn_end")
					print("[Equipment] " + equip_name + ": Applied Frost to " + target.hero_data.get("name", ""))
					_log_status(target.hero_data.get("portrait", ""), equip_name + ": Frost", Color(0.5, 0.8, 1.0))
			
			"reflect":
				# Thorned Armor: Reflect damage back to attacker
				var damage_taken = context.get("damage", 0)
				var attacker = context.get("attacker", null)
				var reflect_damage = int(damage_taken * value)
				if reflect_damage > 0 and attacker and is_instance_valid(attacker) and not attacker.is_dead:
					attacker.take_damage(reflect_damage)
					print("[Equipment] " + equip_name + ": Reflected " + str(reflect_damage) + " damage to " + attacker.hero_data.get("name", ""))
					_log_status(hero.hero_data.get("portrait", ""), equip_name + ": " + str(reflect_damage) + " DMG", Color(1.0, 0.6, 0.2))
			
			"mana_gain":
				# Mana Siphon: Gain mana on kill
				var mana_amount = int(value)
				if _practice_controlling_enemy:
					GameManager.enemy_current_mana = min(GameManager.enemy_current_mana + mana_amount, GameManager.enemy_max_mana)
					GameManager.mana_changed.emit(GameManager.enemy_current_mana, GameManager.enemy_max_mana)
				else:
					GameManager.current_mana = min(GameManager.current_mana + mana_amount, GameManager.max_mana)
					GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
				_update_ui()
				print("[Equipment] " + equip_name + ": Gained " + str(mana_amount) + " mana")
				_log_status(hero.hero_data.get("portrait", ""), equip_name + ": +" + str(mana_amount) + " Mana", Color(0.5, 0.6, 1.0))
			
			"empower_all":
				# Battle Horn: Empower all allies on kill
				var allies = player_heroes if hero.is_player_hero else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						ally.apply_buff("empower", 1, 0, "own_turn_end")
				print("[Equipment] " + equip_name + ": Empowered all allies!")
				_log_status(hero.hero_data.get("portrait", ""), equip_name + ": Empower All", Color(1.0, 0.87, 0.4))
				_refresh_hand_descriptions()
			
			"auto_revive":
				# Phoenix Feather: Revive with % HP on death (one-time use)
				var max_hp = hero.hero_data.get("max_hp", 100)
				var revive_hp = int(max_hp * value)
				hero.is_dead = false
				hero.current_hp = revive_hp
				hero._update_hp_display()
				hero.modulate = Color(1, 1, 1, 1)
				if hero.hp_bar:
					hero.hp_bar.visible = true
				if hero.energy_bar:
					hero.energy_bar.visible = true
				# Remove the equipment after use (one-time)
				hero.remove_equipment(equip.get("id", ""))
				print("[Equipment] " + equip_name + ": " + hero.hero_data.get("name", "") + " revived with " + str(revive_hp) + " HP!")
				_log_status(hero.hero_data.get("portrait", ""), equip_name + ": Revived! +" + str(revive_hp) + " HP", Color(1.0, 0.85, 0.3))
				return  # Exit early since we modified the array
			
			"empower":
				# Berserker's Axe: Gain Empower when HP drops below threshold
				var hp_percent = float(hero.current_hp) / float(hero.hero_data.get("max_hp", 100))
				if hp_percent <= value:
					# Check if already has this buff to avoid stacking
					if not hero.has_buff("empower"):
						hero.apply_buff("empower", 1, 0, "own_turn_end")
						print("[Equipment] " + equip_name + ": " + hero.hero_data.get("name", "") + " gained Empower (low HP)!")
						_log_status(hero.hero_data.get("portrait", ""), equip_name + ": Empower", Color(1.0, 0.87, 0.4))
						_refresh_hand_descriptions()
			
			"cleanse":
				# Cleansing Charm: Remove debuffs at turn start
				var cleanse_count = int(value)
				for i in range(cleanse_count):
					hero.remove_random_debuff()
				print("[Equipment] " + equip_name + ": Cleansed " + str(cleanse_count) + " debuff(s) from " + hero.hero_data.get("name", ""))
				_log_status(hero.hero_data.get("portrait", ""), equip_name + ": Cleansed", Color(0.9, 0.95, 1.0))
			
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

var _confirm_result := false
var _confirm_done := false
var _deck_manipulation_active := false

func _show_confirm_dialog(message: String) -> bool:
	## Shows a Yes/No confirmation dialog and awaits the player's choice.
	## Returns true if Yes, false if No.
	_confirm_result = false
	_confirm_done = false
	
	var overlay = CanvasLayer.new()
	overlay.layer = 90
	add_child(overlay)
	
	# Root control that fills the screen — this is the single input receiver
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(root)
	
	# Dim background (pass-through clicks to siblings above)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	
	# Center container for the panel
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	
	# Panel
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.14, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.9, 0.7, 0.2, 0.8)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	# Message label
	var label = Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(label)
	
	# Button row
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)
	
	var yes_btn = Button.new()
	yes_btn.text = "Yes"
	yes_btn.custom_minimum_size = Vector2(100, 36)
	yes_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var yes_style = StyleBoxFlat.new()
	yes_style.bg_color = Color(0.2, 0.6, 0.3, 0.9)
	yes_style.corner_radius_top_left = 6
	yes_style.corner_radius_top_right = 6
	yes_style.corner_radius_bottom_left = 6
	yes_style.corner_radius_bottom_right = 6
	yes_btn.add_theme_stylebox_override("normal", yes_style)
	hbox.add_child(yes_btn)
	
	var no_btn = Button.new()
	no_btn.text = "No"
	no_btn.custom_minimum_size = Vector2(100, 36)
	no_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var no_style = StyleBoxFlat.new()
	no_style.bg_color = Color(0.6, 0.2, 0.2, 0.9)
	no_style.corner_radius_top_left = 6
	no_style.corner_radius_top_right = 6
	no_style.corner_radius_bottom_left = 6
	no_style.corner_radius_bottom_right = 6
	no_btn.add_theme_stylebox_override("normal", no_style)
	hbox.add_child(no_btn)
	
	yes_btn.pressed.connect(_on_confirm_yes)
	no_btn.pressed.connect(_on_confirm_no)
	
	while not _confirm_done:
		await get_tree().process_frame
	
	overlay.queue_free()
	return _confirm_result

func _on_confirm_yes() -> void:
	_confirm_result = true
	_confirm_done = true

func _on_confirm_no() -> void:
	_confirm_result = false
	_confirm_done = true

func _refund_card_to_hand(card_data: Dictionary, mana_cost: int) -> void:
	## Refunds a card back to hand: removes from discard, re-adds to hand, refunds mana.
	var active_hand = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
	var active_discard = GameManager.enemy_discard_pile if _practice_controlling_enemy else GameManager.discard_pile
	
	# Remove from discard pile (it was added there by _add_card_to_stack)
	var card_id = card_data.get("id", "")
	for i in range(active_discard.size() - 1, -1, -1):
		if active_discard[i].get("id", "") == card_id:
			active_discard.remove_at(i)
			break
	
	# Re-add to hand
	active_hand.append(card_data.duplicate())
	
	# Refund mana
	if _practice_controlling_enemy:
		GameManager.enemy_current_mana += mana_cost
		GameManager.mana_changed.emit(GameManager.enemy_current_mana, GameManager.enemy_max_mana)
	else:
		GameManager.current_mana += mana_cost
		GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
	
	_refresh_hand()
	_update_deck_display()
	print("[Refund] Card returned to hand: " + card_data.get("name", "Card") + " | Mana refunded: " + str(mana_cost))

func _check_deck_size_confirm(card_data: Dictionary, required: int) -> bool:
	## Checks if deck has enough cards. If not, shows confirmation dialog.
	## Returns true to proceed, false to cancel.
	var deck = GameManager.enemy_deck if _practice_controlling_enemy else GameManager.deck
	if deck.size() >= required:
		return true
	
	var card_name = card_data.get("name", "Card")
	var msg: String
	if deck.size() == 0:
		msg = "Deck is empty. " + card_name + " needs " + str(required) + " card(s).\nProceed anyway?"
	else:
		msg = "Deck has " + str(deck.size()) + " card(s). " + card_name + " needs " + str(required) + ".\nProceed anyway?"
	
	return await _show_confirm_dialog(msg)

func _handle_dig_card(card_data: Dictionary, source: Hero) -> void:
	# Dig: Reveal top X cards from deck, player picks one matching filter
	var dig_count = card_data.get("dig_count", 3)
	var dig_filter = card_data.get("dig_filter", "equipment")
	var card_name = card_data.get("name", "Dig")
	
	# Get top X cards from deck (without removing them yet)
	var deck = GameManager.enemy_deck if _practice_controlling_enemy else GameManager.deck
	
	# If deck is empty, reshuffle discard pile into deck first
	if deck.is_empty():
		if _practice_controlling_enemy:
			GameManager.enemy_reshuffle_discard_into_deck()
		else:
			GameManager.reshuffle_discard_into_deck()
		deck = GameManager.enemy_deck if _practice_controlling_enemy else GameManager.deck
		_update_deck_display()
		if not deck.is_empty():
			print("[" + card_name + "] Reshuffled discard into deck (" + str(deck.size()) + " cards)")
	
	var revealed_cards: Array = []
	
	for i in range(min(dig_count, deck.size())):
		revealed_cards.append(deck[deck.size() - 1 - i])  # Top of deck is end of array
	
	if revealed_cards.is_empty():
		print("[" + card_name + "] Deck and discard are both empty!")
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
		var dig_hand = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
		if dig_hand.size() < GameManager.HAND_SIZE:
			dig_hand.append(selected_card)
			print("[" + card_name + "] Added " + selected_card.get("name", "card") + " to hand")
			print("[DEBUG Dig] Hand size before refresh: ", dig_hand.size(), " cards: ", dig_hand.map(func(c): return c.get("name", "?")))
			_refresh_hand()
			_log_deck_action(card_data.get("art", card_data.get("image", "")), selected_card.get("art", selected_card.get("image", "")), "Dug → Hand")
		else:
			var dig_discard = GameManager.enemy_discard_pile if _practice_controlling_enemy else GameManager.discard_pile
			dig_discard.append(selected_card)
			print("[" + card_name + "] Hand full! " + selected_card.get("name", "card") + " goes to discard")
			_log_deck_action(card_data.get("art", card_data.get("image", "")), selected_card.get("art", selected_card.get("image", "")), "Dug → Discard (full)")
	
	# Shuffle remaining revealed cards back into deck
	deck.shuffle()
	_update_ui()

func _handle_search_deck_card(card_data: Dictionary, source: Hero) -> void:
	# Search entire deck for cards matching filter
	var search_filter = card_data.get("search_filter", "equipment")
	var card_name = card_data.get("name", "Search")
	
	var deck = GameManager.enemy_deck if _practice_controlling_enemy else GameManager.deck
	
	# If deck is empty, reshuffle discard pile into deck first
	if deck.is_empty():
		if _practice_controlling_enemy:
			GameManager.enemy_reshuffle_discard_into_deck()
		else:
			GameManager.reshuffle_discard_into_deck()
		deck = GameManager.enemy_deck if _practice_controlling_enemy else GameManager.deck
		_update_deck_display()
		if not deck.is_empty():
			print("[" + card_name + "] Reshuffled discard into deck (" + str(deck.size()) + " cards)")
	
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
		var search_hand = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
		if search_hand.size() < GameManager.HAND_SIZE:
			search_hand.append(selected_card)
			print("[" + card_name + "] Added " + selected_card.get("name", "card") + " to hand")
			_refresh_hand()
			_log_deck_action(card_data.get("art", card_data.get("image", "")), selected_card.get("art", selected_card.get("image", "")), "Search → Hand")
		else:
			var search_discard = GameManager.enemy_discard_pile if _practice_controlling_enemy else GameManager.discard_pile
			search_discard.append(selected_card)
			print("[" + card_name + "] Hand full! " + selected_card.get("name", "card") + " goes to discard")
			_log_deck_action(card_data.get("art", card_data.get("image", "")), selected_card.get("art", selected_card.get("image", "")), "Search → Discard (full)")
	
	# Shuffle deck after searching
	deck.shuffle()
	_update_ui()

func _handle_check_discard_card(card_data: Dictionary, source: Hero) -> void:
	# Check discard pile, pick one card to return to hand
	var discard_filter = card_data.get("discard_filter", "any")
	var card_name = card_data.get("name", "Recycle")
	
	var discard = GameManager.enemy_discard_pile if _practice_controlling_enemy else GameManager.discard_pile
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
		var recycle_hand = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
		if recycle_hand.size() < GameManager.HAND_SIZE:
			recycle_hand.append(selected_card)
			print("[" + card_name + "] Returned " + selected_card.get("name", "card") + " to hand")
			_refresh_hand()
			_log_deck_action(card_data.get("art", card_data.get("image", "")), selected_card.get("art", selected_card.get("image", "")), "Recycle → Hand")
		else:
			discard.append(selected_card)
			print("[" + card_name + "] Hand full! Card stays in discard")
			_log_deck_action(card_data.get("art", card_data.get("image", "")), selected_card.get("art", selected_card.get("image", "")), "Recycle → Full")
	
	_update_ui()

func _card_matches_filter_type(card: Dictionary, filter: String) -> bool:
	if filter == "any":
		return true
	var card_type = card.get("type", "")
	return card_type == filter

var _card_selection_result: Dictionary = {}
var _card_selection_done := false

func _show_card_selection(cards: Array, filter: String, title: String) -> Dictionary:
	# Build a fresh card selection dialog on a high CanvasLayer (same pattern as _show_confirm_dialog)
	_card_selection_result = {}
	_card_selection_done = false
	
	var overlay = CanvasLayer.new()
	overlay.layer = 90
	add_child(overlay)
	
	# Root control fills screen and blocks input behind it
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(root)
	
	# Dim background
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	
	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	
	# Panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(800, 420)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.08, 0.06, 0.95)
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.8, 0.7, 0.4, 1)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 15
	panel_style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	# Title
	var title_label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7, 1))
	vbox.add_child(title_label)
	
	# Info label (created early so card click lambdas can reference it)
	var info_lbl = Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 14)
	info_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	
	# Buttons (created early so card click lambdas can reference confirm_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(130, 40)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	
	var confirm_btn = Button.new()
	confirm_btn.custom_minimum_size = Vector2(130, 40)
	confirm_btn.add_theme_font_size_override("font_size", 16)
	
	# Cards container
	var cards_hbox = HBoxContainer.new()
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 10)
	cards_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cards_hbox)
	
	var card_scene_res = preload("res://scenes/components/card.tscn")
	var valid_count := 0
	var card_instances: Array = []
	
	for card_data in cards:
		var card_inst = card_scene_res.instantiate()
		cards_hbox.add_child(card_inst)
		card_inst.setup(card_data)
		card_inst.scale = Vector2(0.8, 0.8)
		
		var is_valid = (filter == "any") or (card_data.get("type", "") == filter)
		if is_valid:
			valid_count += 1
			card_inst.modulate = Color(1, 1, 1, 1)
			card_inst.mouse_filter = Control.MOUSE_FILTER_STOP
			var _cd = card_data
			var _ci = card_inst
			card_inst.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_card_selection_result = _cd
					for c in card_instances:
						c.modulate = Color(1, 1, 1, 1) if c != _ci else Color(1.2, 1.2, 0.8, 1)
					info_lbl.text = "Selected: " + _cd.get("name", "Unknown")
					confirm_btn.disabled = false
					confirm_btn.text = "Confirm"
			)
		else:
			card_inst.modulate = Color(0.5, 0.5, 0.5, 0.8)
			card_inst.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_instances.append(card_inst)
	
	# Now add info label and buttons to the layout
	if valid_count > 0:
		info_lbl.text = "Click a highlighted card to select it"
		confirm_btn.text = "Confirm"
		confirm_btn.disabled = true
	else:
		info_lbl.text = "No valid cards found. Click OK to continue."
		confirm_btn.text = "OK"
		confirm_btn.disabled = false
	vbox.add_child(info_lbl)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 40)
	vbox.add_child(btn_hbox)
	btn_hbox.add_child(cancel_btn)
	btn_hbox.add_child(confirm_btn)
	
	confirm_btn.pressed.connect(_on_card_selection_confirm)
	cancel_btn.pressed.connect(_on_card_selection_cancel)
	
	# Wait for selection
	while not _card_selection_done:
		await get_tree().process_frame
	
	overlay.queue_free()
	return _card_selection_result

func _on_card_selection_confirm() -> void:
	_card_selection_done = true

func _on_card_selection_cancel() -> void:
	_card_selection_result = {}
	_card_selection_done = true

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
			# Spawn lightning explosion VFX on the target hero
			hero._spawn_thunder_explode_effect()
			
			# Deal damage
			hero.take_damage(damage)
			hero.play_hit_anim()
			print("[Thunder] " + hero.hero_data.get("name", "Hero") + " struck by lightning for " + str(damage) + " damage (" + str(stacks) + " stacks)")
			_log_status(hero.hero_data.get("portrait", ""), "Thunder: " + str(damage) + " DMG!", Color(0.6, 0.7, 1.0))
			
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
	var search_team = enemy_heroes if _practice_controlling_enemy else player_heroes
	if hero_id != "":
		for hero in search_team:
			if hero.hero_id == hero_id:
				return hero
	var color = card_data.get("hero_color", "")
	for hero in search_team:
		if hero.get_color() == color:
			return hero
	return null

func _get_nearest_enemy() -> Hero:
	var opp_team = player_heroes if _practice_controlling_enemy else enemy_heroes
	var alive_enemies = opp_team.filter(func(h): return not h.is_dead)
	if alive_enemies.is_empty():
		return null
	# Check for taunt - if any enemy has taunt, target them instead
	var taunt_target = _get_taunt_target(alive_enemies)
	if taunt_target:
		return taunt_target
	# Use team_index to find the front enemy reliably
	return _get_front_hero(opp_team)

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
	
	if _battle_play_card(card_data_copy, source_hero, null):
		await _show_card_display(card_data_copy)
		
		var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
		var atk_mult = card_data_copy.get("atk_multiplier", 1.0)
		var damage_mult = source_hero.get_damage_multiplier() if source_hero else 1.0
		var damage = int(base_atk * atk_mult * damage_mult)
		if damage == 0:
			damage = 10
		var opp_team = player_heroes if _practice_controlling_enemy else enemy_heroes
		var alive_enemies = opp_team.filter(func(h): return not h.is_dead)
		
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
			enemy.take_damage(damage, source_hero)
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
	
	if _battle_play_card(card_data_copy, source_hero, null):
		await _show_card_display(card_data_copy)
		
		var base_atk = source_hero.hero_data.get("base_attack", 10) if source_hero else 10
		var hp_mult = card_data_copy.get("hp_multiplier", 0.0)
		var heal_amount: int
		if hp_mult > 0 and source_hero:
			heal_amount = source_hero.calculate_heal(hp_mult)
		else:
			var heal_mult = card_data_copy.get("heal_multiplier", 1.0)
			heal_amount = int(base_atk * heal_mult)
		var my_team = enemy_heroes if _practice_controlling_enemy else player_heroes
		var alive_allies = my_team.filter(func(h): return not h.is_dead)
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
	
	if _battle_play_card(card_data_copy, source_hero, null):
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
		var my_team_b = enemy_heroes if _practice_controlling_enemy else player_heroes
		var alive_allies = my_team_b.filter(func(h): return not h.is_dead)
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

func _trigger_bleed_damage(hero: Hero) -> void:
	## Direct bleed damage — no await, safe to call from _finish_card_play
	if hero == null or not is_instance_valid(hero) or hero.is_dead:
		return
	if not hero.has_debuff("bleed"):
		return
	var bleed_data = hero.active_debuffs.get("bleed", {})
	var caster_atk = int(bleed_data.get("source_atk", 10))
	var dmg := int(max(1, caster_atk * 0.5))
	if dmg <= 0:
		return
	_apply_true_damage(hero, dmg, true)
	_log_status(hero.hero_data.get("portrait", ""), "Bleed: " + str(dmg) + " DMG", Color(0.9, 0.2, 0.2))
	print("[Bleed] " + hero.hero_data.get("name", "Hero") + " took " + str(dmg) + " bleed damage!")

func _battle_play_card(card_data: Dictionary, source_hero, target) -> bool:
	if _practice_controlling_enemy:
		return GameManager.practice_play_enemy_card(card_data, source_hero, target)
	return GameManager.play_card(card_data, source_hero, target)

func _finish_card_play() -> void:
	# Post-action bleed: card resolved, now bleed damages the source hero
	if _last_played_source_hero and is_instance_valid(_last_played_source_hero):
		_trigger_bleed_damage(_last_played_source_hero)
	_last_played_source_hero = null
	_last_played_card_data = {}
	
	_clear_highlights()
	selected_card = null
	current_phase = BattlePhase.PLAYING
	if turn_indicator:
		if _practice_controlling_enemy:
			turn_indicator.text = "ENEMY TURN (YOU)"
		else:
			turn_indicator.text = "YOUR TURN"
	
	# Unlimited mana: refill both teams after every card play
	if is_practice_mode and _practice_unli_mana:
		GameManager.current_mana = GameManager.MANA_CAP
		GameManager.max_mana = GameManager.MANA_CAP
		GameManager.enemy_current_mana = GameManager.MANA_CAP
		GameManager.enemy_max_mana = GameManager.MANA_CAP
		GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
	
	# Remove the front card from queue and visuals (it just finished playing)
	if not card_queue.is_empty():
		var finished_card = card_queue.pop_front()
		var finished_uid = finished_card.queue_uid
		
		# Remove its visual tracking entry by unique queue_uid
		# (The visual itself is already freed by _fade_out_visual)
		for i in range(queued_card_visuals.size() - 1, -1, -1):
			if queued_card_visuals[i].queue_uid == finished_uid:
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
	
	var mana_gain := int(card.card_data.get("mana_gain", 1))
	if _practice_controlling_enemy:
		GameManager.enemy_current_mana += mana_gain
		GameManager.mana_changed.emit(GameManager.enemy_current_mana, GameManager.enemy_max_mana)
	else:
		GameManager.current_mana += mana_gain
		GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
	
	var active_hand_m = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
	var card_index = -1
	for i in range(active_hand_m.size()):
		if active_hand_m[i].get("id", "") == card.card_data.get("id", ""):
			card_index = i
			break
	if card_index != -1:
		active_hand_m.remove_at(card_index)
	
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

func _find_redirect_target(hero: Hero) -> Hero:
	# Check if hero has redirect buff and find the hero who should receive redirected damage
	if not hero.has_buff("redirect"):
		return null
	var redirect_id = hero.get_meta("redirect_to", "")
	if str(redirect_id).is_empty() or redirect_id == -1:
		return null
	# Search in the same team
	var team = player_heroes if hero.is_player_hero else enemy_heroes
	for ally in team:
		if ally.instance_id == redirect_id and not ally.is_dead:
			return ally
	return null

func _get_damage_link_allies(hero: Hero) -> Array:
	# Returns all alive allies on the same team that have the damage_link buff
	var team = player_heroes if hero.is_player_hero else enemy_heroes
	var linked = []
	for ally in team:
		if not ally.is_dead and ally.has_buff("damage_link"):
			linked.append(ally)
	return linked

func _animate_attack(source: Hero, target: Hero, damage: int) -> void:
	if source == null or not is_instance_valid(source):
		target.take_damage(damage, null)
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
	
	# Redirect: transfer 50% of damage to the redirect target (Kalasag)
	var redirect_hero = _find_redirect_target(target)
	if redirect_hero and redirect_hero != target:
		var redirected = int(final_damage * 0.5)
		final_damage = final_damage - redirected
		redirect_hero.take_damage(redirected, source)
		redirect_hero.play_hit_anim()
		print("[Redirect] " + str(redirected) + " damage transferred from " + target.hero_data.get("name", "") + " to " + redirect_hero.hero_data.get("name", ""))
	
	# Damage Link: split damage among all linked allies
	if target.has_buff("damage_link"):
		var linked = _get_damage_link_allies(target)
		if linked.size() > 1:
			var split = int(final_damage / linked.size())
			var remainder = final_damage - (split * linked.size())
			for ally in linked:
				var ally_share = split + (remainder if ally == target else 0)
				ally.take_damage(ally_share, source)
				ally.play_hit_anim()
			print("[Damage Link] " + str(final_damage) + " damage split among " + str(linked.size()) + " linked allies (" + str(split) + " each)")
		else:
			target.take_damage(final_damage, source)
			target.play_hit_anim()
	else:
		# Normal damage
		target.take_damage(final_damage, source)
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
		target.take_damage(damage, null)
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
	
	# Redirect: transfer 50% of damage to the redirect target (Kalasag)
	var redirect_hero = _find_redirect_target(target)
	if redirect_hero and redirect_hero != target:
		var redirected = int(final_damage * 0.5)
		final_damage = final_damage - redirected
		redirect_hero.take_damage(redirected, source)
		redirect_hero.play_hit_anim()
		print("[Redirect] " + str(redirected) + " damage transferred from " + target.hero_data.get("name", "") + " to " + redirect_hero.hero_data.get("name", ""))
	
	# Damage Link: split damage among all linked allies
	if target.has_buff("damage_link"):
		var linked = _get_damage_link_allies(target)
		if linked.size() > 1:
			var split = int(final_damage / linked.size())
			var remainder = final_damage - (split * linked.size())
			for ally in linked:
				var ally_share = split + (remainder if ally == target else 0)
				ally.take_damage(ally_share, source)
				ally.play_hit_anim()
			print("[Damage Link] " + str(final_damage) + " damage split among " + str(linked.size()) + " linked allies (" + str(split) + " each)")
		else:
			target.take_damage(final_damage, source)
			target.play_hit_anim()
	else:
		# Normal damage
		target.take_damage(final_damage, source)
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
	elif ex_type == "thunder_all" or ex_type == "generate_cards" or ex_type == "temporal_shift" or ex_type == "shield_all" or ex_type == "scrapyard_overflow" or ex_type == "damage_link" or _is_aoe_ex(hero):
		# No-targeting EX skills (thunder_all, generate_cards, temporal_shift, AoE damage) - execute immediately
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
			print("Battle: [GUEST] Sent EX skill request (" + ex_type + ")")
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

func _is_aoe_ex(hero: Hero) -> bool:
	var ex_card_id = hero.hero_data.get("ex_card", "")
	if ex_card_id.is_empty():
		return false
	return CardDatabase.get_card(ex_card_id).get("target", "") == "all_enemy"

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
	_log_ex_skill(hero.hero_data.get("name", "Hero"), target.hero_data.get("name", "Target"), hero.is_player_hero, hero.hero_data.get("portrait", ""), target.hero_data.get("portrait", ""))
	
	var ex_data = hero.hero_data.get("ex_skill", {})
	var ex_type = ex_data.get("type", "damage")
	
	# Play cut-in effect first
	await _play_ex_cutin(hero, true)
	
	var done = false
	var timeout = 2.0
	var elapsed = 0.0
	
	var base_atk = hero.hero_data.get("base_attack", 10)
	
	# Eclipse buff: double EX damage (base + 100% base), then consume
	var eclipse_mult = 1.0
	if hero.has_buff("eclipse_buff"):
		eclipse_mult = 2.0
		hero.remove_buff("eclipse_buff")
		print(hero.hero_data.get("name", "Hero") + " Eclipse consumed! EX damage doubled!")
	
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
	elif ex_type == "generate_cards":
		# Cinder Storm: Add temporary cards to hand
		var gen_card_id = ex_data.get("generate_card_id", "")
		var gen_count = int(ex_data.get("generate_count", 3))
		hero.play_ex_skill_anim(func():
			if not done:
				# VFX Library: fire burst effect
				if VFX and hero.sprite:
					var sprite_center = hero.sprite.global_position + hero.sprite.size / 2
					VFX.spawn_energy_burst(sprite_center, Color(1.0, 0.4, 0.1))
				# Generate temporary cards and add to hand
				_generate_temporary_cards(gen_card_id, gen_count, hero)
				done = true
		)
	elif ex_type == "temporal_shift":
		# Nyra's Temporal Shift: Rewind all allies' HP to last turn snapshot + revive
		var allies = player_heroes if hero.is_player_hero else enemy_heroes
		hero.play_ex_skill_anim(func():
			if not done:
				if VFX and hero.sprite:
					var sprite_center = hero.sprite.global_position + hero.sprite.size / 2
					VFX.spawn_energy_burst(sprite_center, Color(0.2, 1.0, 0.8))
				_apply_temporal_shift(allies)
				done = true
		)
	elif ex_type == "damage_link":
		# Ysolde's Thread of Life: Link all allies (share damage) + apply regen to all
		var allies = player_heroes if hero.is_player_hero else enemy_heroes
		var regen_hp_pct = ex_data.get("regen_hp_pct", 0.10)
		hero.play_ex_skill_anim(func():
			if not done:
				if VFX and hero.sprite:
					var sprite_center = hero.sprite.global_position + hero.sprite.size / 2
					VFX.spawn_energy_burst(sprite_center, Color(0.9, 0.85, 0.5))
				for ally in allies:
					if not ally.is_dead:
						# Apply damage link buff
						ally.apply_buff("damage_link", 1, 0, "opponent_turn_end")
						# Apply regen based on target's max HP
						var regen_amount = int(ally.max_hp * regen_hp_pct)
						ally.apply_buff("regen", -1, regen_amount * 2, "permanent")
						if VFX and ally.sprite:
							var sc = ally.sprite.global_position + ally.sprite.size / 2
							VFX.spawn_heal_effect(sc)
				print("[Thread of Life] All allies linked + regen applied")
				done = true
		)
	elif ex_type == "scrapyard_overflow":
		# Scrap's Scrapyard Overflow: Draw 3 cards, then player chooses 2 to discard
		var draw_count = int(ex_data.get("draw_count", 3))
		var discard_count = int(ex_data.get("discard_count", 2))
		hero.play_ex_skill_anim(func():
			if not done:
				if VFX and hero.sprite:
					var sprite_center = hero.sprite.global_position + hero.sprite.size / 2
					VFX.spawn_energy_burst(sprite_center, Color(0.6, 0.2, 1.0))
				# Draw cards first
				if _practice_controlling_enemy:
					GameManager.enemy_draw_cards(draw_count)
				else:
					GameManager.draw_cards(draw_count)
				_refresh_hand(true)
				_update_deck_display()
				print("[Scrapyard Overflow] Drew " + str(draw_count) + " cards — now select " + str(discard_count) + " to discard")
				# Enter card selection mode to discard
				_start_card_select("scrapyard_discard", discard_count, hero)
				done = true
		)
	elif ex_type == "shield_all":
		# Kalasag's Tidal Bulwark: Grant Shield to all allies
		var allies = player_heroes if hero.is_player_hero else enemy_heroes
		var ex_base_shield = int(ex_data.get("base_shield", 10))
		var ex_def_mult = float(ex_data.get("def_multiplier", 3.0))
		var shield_amount = ex_base_shield + int(hero.get_def() * ex_def_mult)
		hero.play_ex_skill_anim(func():
			if not done:
				if VFX and hero.sprite:
					var sprite_center = hero.sprite.global_position + hero.sprite.size / 2
					VFX.spawn_energy_burst(sprite_center, Color(1.0, 0.85, 0.2))
				for ally in allies:
					if not ally.is_dead:
						ally.block += shield_amount
						ally._update_ui()
						ally._show_shield_effect()
						if VFX and ally.sprite:
							var sc = ally.sprite.global_position + ally.sprite.size / 2
							VFX.spawn_heal_effect(sc)
						print("[Tidal Bulwark] " + ally.hero_data.get("name", "Hero") + " gained " + str(shield_amount) + " Shield")
				done = true
		)
	else:
		var atk_mult = ex_data.get("atk_multiplier", 2.0)
		var damage_mult = hero.get_damage_multiplier()  # Apply weak/empower
		var damage = int(base_atk * atk_mult * damage_mult * eclipse_mult)
		var effects = ex_data.get("effects", [])
		var ex_ignore_shield = ex_data.get("ignore_shield", false)
		# Check if this EX is AoE (all_enemy) by reading the ex_card target
		var ex_card_id = hero.hero_data.get("ex_card", "")
		var ex_card_target = CardDatabase.get_card(ex_card_id).get("target", "single_enemy") if not ex_card_id.is_empty() else "single_enemy"
		var is_aoe_ex = ex_card_target == "all_enemy"
		hero.play_ex_skill_anim(func():
			if not done:
				if is_aoe_ex:
					# AoE EX: hit all enemies
					var enemies = enemy_heroes if hero.is_player_hero else player_heroes
					var alive = enemies.filter(func(h): return not h.is_dead)
					for enemy in alive:
						if VFX and enemy.sprite:
							var sprite_center = enemy.sprite.global_position + enemy.sprite.size / 2
							VFX.spawn_energy_burst(sprite_center, Color(1.0, 0.5, 0.2))
						enemy.take_damage(damage, hero, ex_ignore_shield)
						enemy.play_hit_anim()
						_apply_effects(effects, hero, enemy, base_atk)
				else:
					# Single-target EX
					if VFX and target.sprite:
						var sprite_center = target.sprite.global_position + target.sprite.size / 2
						VFX.spawn_energy_burst(sprite_center, Color(1.0, 0.5, 0.2))
					target.take_damage(damage, hero, ex_ignore_shield)
					if ex_ignore_shield:
						print("[Storm Lance] Bypassed shield! " + str(damage) + " damage straight to HP")
					target.play_hit_anim()
					_apply_effects(effects, hero, target, base_atk)
				done = true
		)
	
	while not done and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	
	await get_tree().create_timer(0.3).timeout
	_force_hide_card_display()
	
	# Reset EX caster sprite back to idle
	if not hero.is_dead:
		var idle = hero._resolve_flip_sprite("idle_sprite")
		hero._load_sprite(idle.path, idle.flip_h)
	
	ex_skill_hero = null
	_clear_highlights()
	current_phase = BattlePhase.PLAYING
	if turn_indicator:
		turn_indicator.text = "YOUR TURN"
	_update_ui()

func _apply_temporal_shift(allies: Array) -> void:
	# Nyra EX: Rewind all allies' HP to last turn's snapshot. Revives dead allies.
	var snapshot = _hp_snapshot_last_turn
	if snapshot.is_empty():
		# Fallback to this turn's snapshot if no last turn data (turn 1)
		snapshot = _hp_snapshot_this_turn
	if snapshot.is_empty():
		print("[Temporal Shift] No HP snapshot available — nothing to rewind")
		return
	for ally in allies:
		var snap = snapshot.get(ally.instance_id, {})
		if snap.is_empty():
			continue
		var old_hp = int(snap.get("hp", ally.current_hp))
		var was_dead = bool(snap.get("was_dead", false))
		if was_dead:
			# Don't revive heroes who were already dead last turn
			continue
		if ally.is_dead:
			# Revive: they died this turn but were alive last turn
			ally.revive(old_hp)
			if VFX and ally.sprite:
				var sc = ally.sprite.global_position + ally.sprite.size / 2
				VFX.spawn_heal_effect(sc)
			print("[Temporal Shift] " + ally.hero_data.get("name", "Hero") + " revived to " + str(old_hp) + " HP!")
		elif ally.current_hp < old_hp:
			# Heal back to snapshot HP
			ally.current_hp = old_hp
			ally._update_ui()
			if VFX and ally.sprite:
				var sc = ally.sprite.global_position + ally.sprite.size / 2
				VFX.spawn_heal_effect(sc)
			print("[Temporal Shift] " + ally.hero_data.get("name", "Hero") + " HP rewound to " + str(old_hp))
		else:
			print("[Temporal Shift] " + ally.hero_data.get("name", "Hero") + " HP unchanged (already >= snapshot)")

func _detonate_time_bombs(heroes: Array, is_player_team: bool) -> void:
	# Detonate time_bomb debuffs: stacked damage + remove stacked number of random cards from hand
	for hero in heroes:
		if hero.is_dead:
			continue
		if not hero.has_debuff("time_bomb"):
			continue
		var bomb_data = hero.active_debuffs.get("time_bomb", {})
		var total_damage = int(bomb_data.get("total_damage", 10))
		var discard_count = int(bomb_data.get("discard_count", 1))
		var stacks = int(bomb_data.get("stacks", 1))
		# Deal stacked damage
		_apply_true_damage(hero, total_damage)
		hero.play_hit_anim()
		var stack_str = " (x" + str(stacks) + ")" if stacks > 1 else ""
		print("[Time Bomb] " + hero.hero_data.get("name", "Hero") + " took " + str(total_damage) + " damage!" + stack_str)
		_log_status(hero.hero_data.get("portrait", ""), "Time Bomb" + stack_str + ": " + str(total_damage) + " DMG!", Color(1.0, 0.4, 0.1))
		# Remove stacked number of random cards belonging to this hero from the hand
		if is_player_team:
			for _d in range(discard_count):
				var matching_cards: Array = []
				for i in range(GameManager.hand.size()):
					var card = GameManager.hand[i]
					if card.get("hero_id", "") == hero.hero_id or card.get("id", "").begins_with(hero.hero_id):
						matching_cards.append(i)
				if matching_cards.size() > 0:
					var rand_idx = matching_cards[randi() % matching_cards.size()]
					var removed = GameManager.hand[rand_idx]
					GameManager.hand.remove_at(rand_idx)
					print("[Time Bomb] Removed " + removed.get("name", "card") + " from player hand!")
				else:
					print("[Time Bomb] No matching cards in player hand to remove")
					break
			_refresh_hand()
		else:
			var e_hand = GameManager.enemy_hand
			for _d in range(discard_count):
				var matching_cards: Array = []
				for i in range(e_hand.size()):
					var card = e_hand[i]
					if card.get("hero_id", "") == hero.hero_id or card.get("id", "").begins_with(hero.hero_id):
						matching_cards.append(i)
				if matching_cards.size() > 0:
					var rand_idx = matching_cards[randi() % matching_cards.size()]
					var removed = e_hand[rand_idx]
					GameManager.enemy_deck_manager.hand.remove_at(rand_idx)
					print("[Time Bomb] Removed " + removed.get("name", "card") + " from enemy hand!")
				else:
					print("[Time Bomb] No matching cards in enemy hand to remove")
					break
			_refresh_enemy_hand_display()

func _generate_temporary_cards(card_id: String, count: int, source_hero: Hero) -> void:
	# Load the card template from cards.json and create temporary copies
	var template = CardDatabase.get_card(card_id)
	if template.is_empty():
		print("[Generate Cards] ERROR: Card template not found: " + card_id)
		return
	var active_hand_gen = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
	for i in range(count):
		var temp_card = template.duplicate()
		temp_card["temporary"] = true  # Mark as temporary — won't go to discard
		temp_card["hero_id"] = source_hero.hero_id
		active_hand_gen.append(temp_card)
	_refresh_hand()
	print("[Generate Cards] " + source_hero.hero_data.get("name", "Hero") + " generated " + str(count) + "x " + template.get("name", card_id) + " (temporary)")

# ============================================
# BUFF/DEBUFF EFFECT PROCESSING
# ============================================

func _get_buff_expire_on(buff_type: String) -> String:
	## Returns the correct expire_on for a given buff type.
	match buff_type:
		"empower", "empower_heal", "empower_shield":
			return "own_turn_end"
		"damage_link":
			return "opponent_turn_end"
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

const EFFECT_APPLY_DEBUFF := "apply_debuff"
const EFFECT_APPLY_BUFF := "apply_buff"
const EFFECT_DAMAGE := "damage"
const EFFECT_HEAL := "heal"
const EFFECT_CLEANSE := "cleanse"
const EFFECT_CLEANSE_ALL := "cleanse_all"
const EFFECT_DISPEL := "dispel"
const EFFECT_DISPEL_ALL := "dispel_all"

const EFFECT_HP_COST_PCT := "hp_cost_pct"
const EFFECT_BLEED_ON_ACTION := "bleed_on_action"

const EFFECT_THUNDER_STACK_2 := "thunder_stack_2"
const EFFECT_DRAW := "draw"

const EFFECT_SHIELD_CURRENT_HP := "shield_current_hp"

const EFFECT_PENETRATE := "penetrate"

const OP_DAMAGE := "damage"
const OP_HEAL := "heal"
const OP_BLOCK := "block"
const OP_BUFF := "buff"
const OP_DEBUFF := "debuff"
const OP_ENERGY := "energy"
const OP_CLEANSE := "cleanse"
const OP_DRAW := "draw"
const OP_REMOVE_BUFF := "remove_buff"

func _apply_ops(ops: Array) -> void:
	if ops == null or ops.is_empty():
		return
	for op in ops:
		if op is Dictionary:
			_apply_effect(op)

var _effect_registry: Dictionary = {}

func _init_effect_registry() -> void:
	# Phase 2: registry maps EffectSpec.type -> handler callable
	_effect_registry.clear()
	_effect_registry[EFFECT_APPLY_DEBUFF] = Callable(self, "_eh_apply_debuff")
	_effect_registry[EFFECT_APPLY_BUFF] = Callable(self, "_eh_apply_buff")
	_effect_registry[EFFECT_CLEANSE] = Callable(self, "_eh_cleanse")
	_effect_registry[EFFECT_CLEANSE_ALL] = Callable(self, "_eh_cleanse_all")
	_effect_registry[EFFECT_DISPEL] = Callable(self, "_eh_dispel")
	_effect_registry[EFFECT_DISPEL_ALL] = Callable(self, "_eh_dispel_all")
	_effect_registry[EFFECT_DAMAGE] = Callable(self, "_eh_damage")
	_effect_registry[EFFECT_HEAL] = Callable(self, "_eh_heal")
	_effect_registry[EFFECT_HP_COST_PCT] = Callable(self, "_eh_hp_cost_pct")
	_effect_registry[EFFECT_BLEED_ON_ACTION] = Callable(self, "_eh_bleed_on_action")
	_effect_registry[EFFECT_THUNDER_STACK_2] = Callable(self, "_eh_thunder_stack_2")
	_effect_registry[EFFECT_DRAW] = Callable(self, "_eh_draw")
	_effect_registry[EFFECT_SHIELD_CURRENT_HP] = Callable(self, "_eh_shield_current_hp")
	_effect_registry[EFFECT_PENETRATE] = Callable(self, "_eh_penetrate")

func _dispatch_effect_spec(ctx: Dictionary, spec: Dictionary) -> Array:
	if spec == null or spec.is_empty():
		return []
	var t := str(spec.get("type", ""))
	if t.is_empty():
		return []
	var handler: Callable = _effect_registry.get(t, Callable())
	if handler.is_null():
		return []
	return handler.call(ctx, spec)

func _ctx_primary_target(ctx: Dictionary) -> Hero:
	return ctx.get("primary_target", null)

func _ctx_targets(ctx: Dictionary) -> Array:
	var targets = ctx.get("targets", [])
	if targets == null:
		return []
	return targets

func _resolve_effect_target(ctx: Dictionary, spec: Dictionary) -> Hero:
	var target_mode := str(spec.get("target", "primary"))
	match target_mode:
		"source":
			return ctx.get("source", null)
		"primary":
			return _ctx_primary_target(ctx)
		_:
			return _ctx_primary_target(ctx)

func _resolve_effect_targets(ctx: Dictionary, spec: Dictionary) -> Array:
	var source: Hero = ctx.get("source", null)
	var target_mode := str(spec.get("target", "primary"))
	match target_mode:
		"source":
			return [source] if source != null else []
		"primary":
			var t = _ctx_primary_target(ctx)
			return [t] if t != null else []
		"all_targets":
			return _ctx_targets(ctx)
		"allies":
			if source == null:
				return []
			return player_heroes if source.is_player_hero else enemy_heroes
		"enemies":
			if source == null:
				return []
			return enemy_heroes if source.is_player_hero else player_heroes
		_:
			var t = _ctx_primary_target(ctx)
			return [t] if t != null else []

func _op_base_for_hero(hero: Hero) -> Dictionary:
	if hero == null:
		return {}
	return {
		"hero_id": hero.hero_id,
		"instance_id": hero.instance_id,
		"is_host_hero": hero.is_player_hero
	}

func _eh_apply_debuff(ctx: Dictionary, spec: Dictionary) -> Array:
	var targets: Array = _resolve_effect_targets(ctx, spec)
	if targets.is_empty():
		return []
	var debuff_id := str(spec.get("id", ""))
	if debuff_id.is_empty():
		return []
	var duration := int(spec.get("duration", 1))
	var expire_on := str(spec.get("expire_on", _get_debuff_expire_on(debuff_id)))
	var source: Hero = ctx.get("source", null)
	var default_value: int = int(source.hero_data.get("base_attack", 10)) if source else 10
	var value := int(spec.get("value", default_value))
	var stacks := int(spec.get("stacks", 1))
	var ops: Array = []
	for target in targets:
		if target == null or target.is_dead:
			continue
		# Apply to Host state if we're executing effects immediately (singleplayer / host local execution).
		if bool(ctx.get("apply_now", false)):
			if debuff_id == "thunder" and stacks > 1:
				target.add_thunder_stacks(stacks, value)
			else:
				target.apply_debuff(debuff_id, duration, value, expire_on)
		var op := _op_base_for_hero(target)
		op["type"] = OP_DEBUFF
		op["debuff_type"] = debuff_id
		op["duration"] = duration
		op["expire_on"] = expire_on
		op["value"] = value
		if debuff_id == "thunder" and stacks > 1:
			op["stacks"] = stacks
		ops.append(op)
	return ops

func _eh_apply_buff(ctx: Dictionary, spec: Dictionary) -> Array:
	var targets: Array = _resolve_effect_targets(ctx, spec)
	if targets.is_empty():
		return []
	var buff_id := str(spec.get("id", ""))
	if buff_id.is_empty():
		return []
	var duration := int(spec.get("duration", 1))
	var expire_on := str(spec.get("expire_on", _get_buff_expire_on(buff_id)))
	var source: Hero = ctx.get("source", null)
	var default_value: int = int(source.hero_data.get("base_attack", 10)) if source else 10
	var value := int(spec.get("value", default_value))
	var ops: Array = []
	# Multiplayer bulletproofing: taunt must be unique on a team.
	# Emit explicit ops to remove taunt from all other allies before applying it.
	if buff_id == "taunt" and source != null:
		var allies: Array = player_heroes if source.is_player_hero else enemy_heroes
		for ally in allies:
			if ally == null or ally.is_dead:
				continue
			if ally == source:
				continue
			var rop := _op_base_for_hero(ally)
			rop["type"] = OP_REMOVE_BUFF
			rop["buff_type"] = "taunt"
			ops.append(rop)
	for target in targets:
		if target == null or target.is_dead:
			continue
		var op := _op_base_for_hero(target)
		op["type"] = OP_BUFF
		op["buff_type"] = buff_id
		op["duration"] = duration
		op["expire_on"] = expire_on
		op["value"] = value
		ops.append(op)
	return ops

func _eh_cleanse(ctx: Dictionary, spec: Dictionary) -> Array:
	var target: Hero = _ctx_primary_target(ctx)
	if target == null or target.is_dead:
		return []
	var op := _op_base_for_hero(target)
	op["type"] = OP_CLEANSE
	return [op]

func _eh_cleanse_all(ctx: Dictionary, spec: Dictionary) -> Array:
	var ops: Array = []
	for t in _ctx_targets(ctx):
		if t != null and not t.is_dead:
			var op := _op_base_for_hero(t)
			op["type"] = OP_CLEANSE
			ops.append(op)
	return ops

func _eh_dispel(ctx: Dictionary, spec: Dictionary) -> Array:
	# For now, reuse the legacy op shape already supported by _apply_effect.
	var target: Hero = _ctx_primary_target(ctx)
	if target == null or target.is_dead:
		return []
	var op := _op_base_for_hero(target)
	op["type"] = EFFECT_DISPEL
	return [op]

func _eh_dispel_all(ctx: Dictionary, spec: Dictionary) -> Array:
	var ops: Array = []
	for t in _ctx_targets(ctx):
		if t != null and not t.is_dead:
			var op := _op_base_for_hero(t)
			op["type"] = EFFECT_DISPEL
			ops.append(op)
	return ops

func _eh_damage(ctx: Dictionary, spec: Dictionary) -> Array:
	# NOTE: Host will compute new_hp/new_block during Phase 3/5.
	# This handler only builds the op scaffold.
	var target: Hero = _ctx_primary_target(ctx)
	if target == null or target.is_dead:
		return []
	var amount := int(spec.get("amount", 0))
	var op := _op_base_for_hero(target)
	op["type"] = OP_DAMAGE
	op["amount"] = amount
	return [op]

func _eh_heal(ctx: Dictionary, spec: Dictionary) -> Array:
	# NOTE: Host will compute new_hp during Phase 3/5.
	var target: Hero = _ctx_primary_target(ctx)
	if target == null or target.is_dead:
		return []
	var amount := int(spec.get("amount", 0))
	var op := _op_base_for_hero(target)
	op["type"] = OP_HEAL
	op["amount"] = amount
	return [op]

func _eh_hp_cost_pct(ctx: Dictionary, spec: Dictionary) -> Array:
	# Phase 4: Host pre-action HP cost. Emits a damage op on source and applies true damage on Host.
	# Must ignore block. Must allow suicide casts. Must block if current_hp < hp_cost.
	var source: Hero = ctx.get("source", null)
	if source == null or not is_instance_valid(source) or source.is_dead:
		return []
	var pct := float(spec.get("pct", 0.0))
	if pct <= 0.0:
		return []
	var hp_cost := int(source.max_hp * pct)
	if hp_cost <= 0:
		return []
	if source.current_hp < hp_cost:
		# Signal failure to caller via ctx flag (caller decides to abort)
		ctx["blocked"] = true
		return []
	var new_hp: int = int(max(0, source.current_hp - hp_cost))
	var op := _op_base_for_hero(source)
	op["type"] = OP_DAMAGE
	op["amount"] = hp_cost
	op["new_hp"] = new_hp
	op["new_block"] = source.block
	_apply_true_damage(source, hp_cost, false)
	return [op]

func _eh_bleed_on_action(ctx: Dictionary, spec: Dictionary) -> Array:
	# Phase 4: Bleed trigger (% of caster ATK as true self-damage) on any non-EX action.
	var source: Hero = ctx.get("source", null)
	if source == null or not is_instance_valid(source) or source.is_dead:
		return []
	if bool(ctx.get("is_ex", false)):
		return []
	if not source.has_debuff("bleed"):
		return []
	# Bleed damage = 50% of the caster's ATK (stored as source_atk in the debuff)
	var bleed_data = source.active_debuffs.get("bleed", {})
	var caster_atk = int(bleed_data.get("source_atk", 10))
	var dmg := int(max(1, caster_atk * 0.5))
	if dmg <= 0:
		return []
	var new_hp: int = int(max(0, source.current_hp - dmg))
	var op := _op_base_for_hero(source)
	op["type"] = OP_DAMAGE
	op["amount"] = dmg
	op["new_hp"] = new_hp
	op["new_block"] = source.block
	_apply_true_damage(source, dmg)
	_log_status(source.hero_data.get("portrait", ""), "Bleed: " + str(dmg) + " DMG", Color(0.9, 0.2, 0.2))
	return [op]

func _eh_thunder_stack_2(ctx: Dictionary, spec: Dictionary) -> Array:
	# Phase 5: Add 2 Thunder stacks only if target already has Thunder.
	var target: Hero = _resolve_effect_target(ctx, spec)
	if target == null or target.is_dead:
		return []
	if not target.has_debuff("thunder"):
		return []
	var amount := int(spec.get("amount", 2))
	if amount <= 0:
		return []
	var source: Hero = ctx.get("source", null)
	var base_atk: int = int(source.hero_data.get("base_attack", 10)) if source else 10
	# Do not mutate Host state during snapshot/precompute.
	# Host authoritative application occurs during the actual execution phase.
	if bool(ctx.get("apply_now", false)) and is_instance_valid(target):
		target.add_thunder_stacks(amount, base_atk)
	# Emit debuff op for Guest replication.
	var op := _op_base_for_hero(target)
	op["type"] = OP_DEBUFF
	op["debuff_type"] = "thunder"
	op["duration"] = 1
	op["expire_on"] = _get_debuff_expire_on("thunder")
	op["value"] = base_atk
	return [op]

func _eh_draw(ctx: Dictionary, spec: Dictionary) -> Array:
	# Phase 5: Draw cards (player only). Guest will apply the draw op locally.
	var source: Hero = ctx.get("source", null)
	if source == null:
		return []
	var amount := int(spec.get("amount", 1))
	if amount <= 0:
		return []
	if bool(ctx.get("apply_now", false)):
		if _practice_controlling_enemy and not source.is_player_hero:
			GameManager.enemy_draw_cards(amount)
		elif source.is_player_hero:
			GameManager.draw_cards(amount)
		_refresh_hand()
	var op := _op_base_for_hero(source)
	op["type"] = OP_DRAW
	op["amount"] = amount
	return [op]

func _eh_shield_current_hp(ctx: Dictionary, spec: Dictionary) -> Array:
	# Phase 5: Give Shield equal to current HP (used by some EX skills).
	var source: Hero = ctx.get("source", null)
	if source == null or not is_instance_valid(source) or source.is_dead:
		return []
	var shield_amount := int(source.current_hp)
	if shield_amount <= 0:
		return []
	var op := _op_base_for_hero(source)
	op["type"] = OP_BLOCK
	op["amount"] = shield_amount
	op["new_block"] = source.block + shield_amount
	if bool(ctx.get("apply_now", false)):
		source.add_block(shield_amount)
	return [op]

func _eh_penetrate(ctx: Dictionary, spec: Dictionary) -> Array:
	# Phase 5/7: Emit ops for penetrate (behind-target damage + weak).
	# Host application remains handled by existing legacy logic; this only unifies replication.
	var primary_target: Hero = _ctx_primary_target(ctx)
	if primary_target == null or not is_instance_valid(primary_target) or primary_target.is_dead:
		return []
	var target_team: Array = player_heroes if primary_target.is_player_hero else enemy_heroes
	var target_index := target_team.find(primary_target)
	if target_index < 0:
		return []
	var behind_index := target_index - 1 if primary_target.is_player_hero else target_index + 1
	if behind_index < 0 or behind_index >= target_team.size():
		return []
	var behind_target: Hero = target_team[behind_index]
	if behind_target == null or not is_instance_valid(behind_target) or behind_target.is_dead:
		return []
	var source: Hero = ctx.get("source", null)
	var base_atk: int = int(source.hero_data.get("base_attack", 10)) if source else 10
	var ops: Array = []
	# Damage op uses the current post-application HP/block on host when snapshotting.
	# (Host application is already performed in precompute for penetrate.)
	ops.append({
		"type": OP_DAMAGE,
		"hero_id": behind_target.hero_id,
		"instance_id": behind_target.instance_id,
		"is_host_hero": behind_target.is_player_hero,
		"amount": int(base_atk * 1.0),
		"new_hp": behind_target.current_hp,
		"new_block": behind_target.block
	})
	ops.append({
		"type": OP_DEBUFF,
		"hero_id": behind_target.hero_id,
		"instance_id": behind_target.instance_id,
		"is_host_hero": behind_target.is_player_hero,
		"debuff_type": "weak",
		"duration": 1,
		"expire_on": "own_turn_end",
		"value": base_atk
	})
	return ops

func _normalize_effects(raw_effects: Array, source: Hero, primary_target: Hero) -> Array:
	# Phase 0: Convert legacy `effects: ["stun", "bleed"]` into structured EffectSpecs.
	# This does NOT execute effects; it only normalizes the data model.
	#
	# Output format (EffectSpec Dictionary examples):
	# - {"type":"apply_debuff","id":"stun","stacks":1,"duration":1,"expire_on":"own_turn_end"}
	# - {"type":"cleanse"}
	var specs: Array = []
	if raw_effects == null or raw_effects.is_empty():
		return specs
	for e in raw_effects:
		if e is Dictionary:
			specs.append(e)
			continue
		var name := str(e)
		match name:
			"stun", "weak", "frost", "break", "burn", "poison", "bleed", "chain", "entangle", "marked", "bomb", "thunder":
				specs.append({
					"type": EFFECT_APPLY_DEBUFF,
					"id": name,
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_debuff_expire_on(name)
				})
			"empower":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": name,
					"target": "source",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_buff_expire_on(name)
				})
			"taunt":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": name,
					"target": "source",
					"stacks": 1,
					"duration": 1,
					"expire_on": "opponent_turn_end"
				})
			"cleanse":
				specs.append({"type": EFFECT_CLEANSE})
			"cleanse_all":
				specs.append({"type": EFFECT_CLEANSE_ALL})
			"dispel":
				specs.append({"type": EFFECT_DISPEL})
			"dispel_all":
				specs.append({"type": EFFECT_DISPEL_ALL})
			"empower_target":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "empower",
					"target": "primary",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_buff_expire_on("empower")
				})
			"empower_all":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "empower",
					"target": "allies",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_buff_expire_on("empower")
				})
			"empower_heal":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "empower_heal",
					"target": "source",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_buff_expire_on("empower_heal")
				})
			"empower_heal_all":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "empower_heal",
					"target": "allies",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_buff_expire_on("empower_heal")
				})
			"empower_shield":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "empower_shield",
					"target": "source",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_buff_expire_on("empower_shield")
				})
			"empower_shield_all":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "empower_shield",
					"target": "allies",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_buff_expire_on("empower_shield")
				})
			"regen_draw":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "regen_draw",
					"target": "primary",
					"stacks": 1,
					"duration": -1,
					"expire_on": "permanent"
				})
			"damage_link_all":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "damage_link",
					"target": "allies",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_buff_expire_on("damage_link")
				})
			"thunder_all":
				specs.append({
					"type": EFFECT_APPLY_DEBUFF,
					"id": "thunder",
					"target": "enemies",
					"stacks": 1,
					"duration": 1,
					"expire_on": _get_debuff_expire_on("thunder")
				})
			"thunder_detonate":
				# Raizel EX: apply 2 Thunder stacks to all enemies.
				specs.append({
					"type": EFFECT_APPLY_DEBUFF,
					"id": "thunder",
					"target": "enemies",
					"stacks": 2,
					"duration": -1,
					"expire_on": "permanent"
				})
			"thunder_stack_2":
				specs.append({
					"type": EFFECT_THUNDER_STACK_2,
					"target": "primary",
					"amount": 2
				})
			"regen":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "regen",
					"target": "primary",
					"stacks": 1,
					"duration": -1,
					"expire_on": "permanent"
				})
			"draw_1":
				specs.append({
					"type": EFFECT_DRAW,
					"target": "source",
					"amount": 1
				})
			"shield_current_hp":
				specs.append({
					"type": EFFECT_SHIELD_CURRENT_HP,
					"target": "source"
				})
			"penetrate":
				specs.append({
					"type": EFFECT_PENETRATE,
					"target": "primary"
				})
			"dana_shield_draw":
				pass  # Handled entirely by custom handler in _apply_effects
			"counter_50":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "counter_50",
					"target": "source",
					"stacks": 1,
					"duration": 1,
					"expire_on": "opponent_turn_end"
				})
			"counter_100":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "counter_100",
					"target": "source",
					"stacks": 1,
					"duration": 1,
					"expire_on": "opponent_turn_end"
				})
			"self_break":
				specs.append({
					"type": EFFECT_APPLY_DEBUFF,
					"id": "break",
					"target": "source",
					"stacks": 1,
					"duration": 1,
					"expire_on": "opponent_turn_end"
				})
			"crescent_moon":
				pass  # Handled entirely by custom handler in _apply_effects — no generic buff spec
			"eclipse_buff":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "eclipse_buff",
					"target": "source",
					"stacks": 1,
					"duration": 1,
					"expire_on": "own_turn_end"
				})
			"rewind":
				specs.append({
					"type": "rewind",
					"target": "source"
				})
			"time_bomb":
				specs.append({
					"type": EFFECT_APPLY_DEBUFF,
					"id": "time_bomb",
					"stacks": 1,
					"duration": 1,
					"expire_on": "own_turn_end"
				})
			"reshuffle":
				specs.append({
					"type": "reshuffle",
					"target": "source"
				})
			"redirect":
				specs.append({
					"type": EFFECT_APPLY_BUFF,
					"id": "redirect",
					"target": "primary",
					"stacks": 1,
					"duration": 1,
					"expire_on": "opponent_turn_end"
				})
			"shield_all":
				specs.append({
					"type": "shield_all",
					"target": "all_ally"
				})
			_:
				# Leave unknown effects as a passthrough for now to preserve compatibility.
				specs.append({"type": name})
	return specs

func _get_hp_cost(card_data: Dictionary, source_hero: Hero) -> int:
	var hp_cost_pct = float(card_data.get("hp_cost_pct", 0.0))
	if hp_cost_pct <= 0.0:
		return 0
	if source_hero == null:
		return 0
	return int(source_hero.max_hp * hp_cost_pct)

func _apply_true_damage(hero: Hero, amount: int, show_vfx: bool = true) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if amount <= 0:
		return
	hero.current_hp = max(0, hero.current_hp - amount)
	if show_vfx:
		hero._spawn_floating_number(amount, Color(0.9, 0.2, 0.2))
		hero.play_hit_anim()
	hero._update_ui()
	if hero.current_hp <= 0:
		hero.die()

func _can_pay_hp_cost(card_data: Dictionary, source_hero: Hero) -> bool:
	var hp_cost = _get_hp_cost(card_data, source_hero)
	if hp_cost <= 0:
		return true
	if source_hero == null:
		return false
	# Suicide cast allowed: current_hp == hp_cost is OK
	return source_hero.current_hp >= hp_cost

func _apply_pre_action_self_effects(card_data: Dictionary, source_hero: Hero, is_ex_action: bool) -> bool:
	# Phase 4: unified pre-action self effects via registry.
	# - hp_cost_pct (true damage to self, ignores block, blocks if insufficient HP)
	if source_hero == null:
		return true
	var ctx := {
		"source": source_hero,
		"primary_target": null,
		"targets": [],
		"card_data": card_data,
		"is_ex": is_ex_action,
		"battle": self
	}
	if is_ex_action:
		return true
	var hp_cost_pct_val := float(card_data.get("hp_cost_pct", 0.0))
	if hp_cost_pct_val > 0.0:
		_dispatch_effect_spec(ctx, {
			"type": EFFECT_HP_COST_PCT,
			"pct": hp_cost_pct_val,
			"target": "source"
		})
		if bool(ctx.get("blocked", false)):
			return false
	return true

func _apply_post_action_bleed(source_hero: Hero, card_data: Dictionary, is_ex_action: bool) -> void:
	## Trigger bleed damage AFTER the card action resolves.
	if source_hero == null or not is_instance_valid(source_hero) or source_hero.is_dead:
		return
	if is_ex_action:
		return
	if not source_hero.has_debuff("bleed"):
		return
	var ctx := {
		"source": source_hero,
		"primary_target": null,
		"targets": [],
		"card_data": card_data,
		"is_ex": false,
		"battle": self
	}
	_dispatch_effect_spec(ctx, {
		"type": EFFECT_BLEED_ON_ACTION,
		"target": "source"
	})
	await get_tree().create_timer(0.3).timeout

func _apply_effects(effects: Array, source: Hero, target: Hero, source_atk: int, card_data: Dictionary = {}) -> void:
	var ctx := {
		"source": source,
		"primary_target": target,
		"targets": [target] if target != null else [],
		"card_data": card_data,
		"is_ex": bool(card_data.get("is_ex", false)),
		"apply_now": true,
		"battle": self
	}
	for effect in effects:
		match effect:
			"stun":
				if target and not target.is_dead:
					target.apply_debuff("stun", 1, source_atk, "own_turn_end")
					_log_status(target.hero_data.get("portrait", ""), "Stunned!", Color(1.0, 0.5, 0.2))
			"weak":
				if target and not target.is_dead:
					target.apply_debuff("weak", 1, source_atk, "own_turn_end")
					_log_status(target.hero_data.get("portrait", ""), "Weakened", Color(0.8, 0.6, 1.0))
			"bleed":
				if target and not target.is_dead:
					target.apply_debuff("bleed", 1, source_atk, "own_turn_end")
					_log_status(target.hero_data.get("portrait", ""), "Bleeding", Color(0.9, 0.2, 0.2))
			"empower":
				if source and not source.is_dead:
					source.apply_buff("empower", 1, source_atk, "own_turn_end")
					_log_status(source.hero_data.get("portrait", ""), "Empower", Color(1.0, 0.87, 0.4))
			"empower_target":
				if target and not target.is_dead:
					target.apply_buff("empower", 1, source_atk, "own_turn_end")
					_log_status(target.hero_data.get("portrait", ""), "Empower", Color(1.0, 0.87, 0.4))
			"empower_all":
				var allies = player_heroes if source.is_player_hero else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						ally.apply_buff("empower", 1, source_atk, "own_turn_end")
				_log_status(source.hero_data.get("portrait", ""), "Empower All", Color(1.0, 0.87, 0.4))
			"empower_heal":
				if source and not source.is_dead:
					source.apply_buff("empower_heal", 1, source_atk, "own_turn_end")
					_log_status(source.hero_data.get("portrait", ""), "Empower Heal", Color(0.4, 1.0, 0.6))
			"empower_heal_all":
				var allies = player_heroes if source.is_player_hero else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						ally.apply_buff("empower_heal", 1, source_atk, "own_turn_end")
				_log_status(source.hero_data.get("portrait", ""), "Empower Heal All", Color(0.4, 1.0, 0.6))
			"empower_shield":
				if source and not source.is_dead:
					source.apply_buff("empower_shield", 1, source_atk, "own_turn_end")
					_log_status(source.hero_data.get("portrait", ""), "Empower Shield", Color(0.6, 0.85, 1.0))
			"empower_shield_all":
				var allies = player_heroes if source.is_player_hero else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						ally.apply_buff("empower_shield", 1, source_atk, "own_turn_end")
				_log_status(source.hero_data.get("portrait", ""), "Empower Shield All", Color(0.6, 0.85, 1.0))
			"regen_draw":
				if target and not target.is_dead:
					target.apply_buff("regen_draw", -1, source_atk, "permanent")
					print(target.hero_data.get("name", "Hero") + " gained Regen+ (heal + draw)")
					_log_status(target.hero_data.get("portrait", ""), "Regen+ (heal + draw)", Color(0.4, 1.0, 0.6))
			"damage_link_all":
				var allies = player_heroes if source.is_player_hero else enemy_heroes
				for ally in allies:
					if not ally.is_dead:
						ally.apply_buff("damage_link", 1, 0, "opponent_turn_end")
				print("[Damage Link] All allies linked — damage will be shared during opponent's turn")
				_log_status(source.hero_data.get("portrait", ""), "Damage Link All", Color(0.9, 0.7, 0.3))
			"taunt":
				if source and not source.is_dead:
					# Remove taunt from all other allies first
					var allies = player_heroes if source.is_player_hero else enemy_heroes
					for ally in allies:
						if ally != source:
							ally.remove_buff("taunt")
					source.apply_buff("taunt", 1, source_atk, "opponent_turn_end")
					_log_status(source.hero_data.get("portrait", ""), "Taunt", Color(1.0, 0.6, 0.2))
			"regen":
				if target and not target.is_dead:
					target.apply_buff("regen", -1, source_atk, "permanent")
					_log_status(target.hero_data.get("portrait", ""), "Regen", Color(0.4, 1.0, 0.4))
			"cleanse":
				if target and not target.is_dead:
					target.clear_all_debuffs()
					_log_status(target.hero_data.get("portrait", ""), "Cleansed", Color(0.9, 0.95, 1.0))
			"cleanse_all":
				var allies_cl = player_heroes if source.is_player_hero else enemy_heroes
				for ally in allies_cl:
					if not ally.is_dead:
						ally.clear_all_debuffs()
				_log_status(source.hero_data.get("portrait", ""), "Cleanse All", Color(0.9, 0.95, 1.0))
			"dispel_all":
				var enemies_dp = enemy_heroes if source.is_player_hero else player_heroes
				for enemy in enemies_dp:
					if not enemy.is_dead:
						enemy.clear_all_buffs()
				_log_status(source.hero_data.get("portrait", ""), "Dispel All", Color(0.8, 0.6, 1.0))
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
							behind_target.take_damage(damage, source)
							behind_target.play_hit_anim()
							# Apply weak to behind target too
							behind_target.apply_debuff("weak", 1, source_atk, "own_turn_end")
							_log_status(behind_target.hero_data.get("portrait", ""), "Penetrate: " + str(damage) + " DMG + Weak", Color(1.0, 0.4, 0.4))
			"upgrade_shuffle":
				if not card_data.is_empty():
					_apply_upgrade_shuffle(card_data)
			"shield_current_hp":
				# Stony's EX: Gain shield equal to current HP
				if source and not source.is_dead:
					var shield_amount = source.current_hp
					_dispatch_effect_spec(ctx, {"type": EFFECT_SHIELD_CURRENT_HP, "target": "source"})
					print(source.hero_data.get("name", "Hero") + " gained " + str(shield_amount) + " Shield from current HP!")
					_log_status(source.hero_data.get("portrait", ""), "+" + str(shield_amount) + " Shield", Color(0.6, 0.85, 1.0))
			"break":
				# Caelum's EX: Apply Break debuff (+50% damage taken)
				if target and not target.is_dead:
					target.apply_debuff("break", 1, source_atk, "own_turn_end")
					_log_status(target.hero_data.get("portrait", ""), "Broken!", Color(1.0, 0.4, 0.2))
			"thunder":
				# Apply 1 Thunder stack to target
				if target and not target.is_dead:
					target.apply_debuff("thunder", 1, source_atk)
					_log_status(target.hero_data.get("portrait", ""), "Thunder +1", Color(0.6, 0.7, 1.0))
			"thunder_all":
				# Apply 1 Thunder stack to all enemies
				var enemies = enemy_heroes if source.is_player_hero else player_heroes
				for enemy in enemies:
					if not enemy.is_dead:
						enemy.apply_debuff("thunder", 1, source_atk)
				_log_event("Thunder +1 to all enemies", Color(0.6, 0.7, 1.0))
			"thunder_detonate":
				# Raizel EX: Apply 2 Thunder stacks to all enemies.
				var enemies = enemy_heroes if source.is_player_hero else player_heroes
				for enemy in enemies:
					if not enemy.is_dead:
						enemy.add_thunder_stacks(2, source_atk)
				_log_event("Thunder +2 to all enemies", Color(0.6, 0.7, 1.0))
			"thunder_stack_2":
				# Add 2 Thunder stacks to target (only if they have Thunder)
				_dispatch_effect_spec(ctx, {"type": EFFECT_THUNDER_STACK_2, "target": "primary", "amount": 2})
				if target and not target.is_dead:
					_log_status(target.hero_data.get("portrait", ""), "Thunder +2", Color(0.6, 0.7, 1.0))
			"draw_1":
				# Draw 1 card
				_dispatch_effect_spec(ctx, {"type": EFFECT_DRAW, "target": "source", "amount": 1})
				_log_event("Drew 1 card", Color(0.7, 0.85, 1.0))
			"dana_shield_draw":
				# Dana's Smart Shield: attach marker buff to target
				if target and not target.is_dead:
					target.apply_buff("dana_shield_draw", -1, 0, "permanent")
					_log_status(target.hero_data.get("portrait", ""), "Smart Shield", Color(0.6, 0.85, 1.0))
			"counter_50":
				# Gavran SK1: Reflect 50% of damage back to attacker
				if source and not source.is_dead:
					source.apply_buff("counter_50", 1, 0, "opponent_turn_end")
					print(source.hero_data.get("name", "Hero") + " gained Counter (50% reflect)")
					_log_status(source.hero_data.get("portrait", ""), "Counter 50%", Color(1.0, 0.6, 0.2))
			"counter_100":
				# Gavran EX: Reflect 100% of damage back to attacker
				if source and not source.is_dead:
					source.apply_buff("counter_100", 1, 0, "opponent_turn_end")
					print(source.hero_data.get("name", "Hero") + " gained Counter (100% reflect)")
					_log_status(source.hero_data.get("portrait", ""), "Counter 100%", Color(1.0, 0.5, 0.1))
			"self_break":
				# Gavran EX: Apply Break to self (expires at opponent_turn_end, not own_turn_end)
				if source and not source.is_dead:
					source.apply_debuff("break", 1, source_atk, "opponent_turn_end")
					print(source.hero_data.get("name", "Hero") + " applied Break to self (opponent_turn_end)")
					_log_status(source.hero_data.get("portrait", ""), "Self Break", Color(1.0, 0.4, 0.2))
			"crescent_moon":
				# Nyxara SK1: Add 1 Crescent Moon stack. At 4 stacks → consume all, fill EX gauge.
				if source and not source.is_dead:
					var current_stacks = source.active_buffs.get("crescent_moon", {}).get("stacks", 0)
					var new_stacks = current_stacks + 1
					print("[Crescent Moon] " + source.hero_data.get("name", "Hero") + " current_stacks=" + str(current_stacks) + " new_stacks=" + str(new_stacks))
					if new_stacks >= 4:
						# Consume all stacks and fill EX gauge to max
						source.remove_buff("crescent_moon")
						source.energy = source.max_energy
						source._update_ui()
						print(source.hero_data.get("name", "Hero") + " Crescent Moon x4! EX gauge filled!")
						_log_status(source.hero_data.get("portrait", ""), "Crescent Moon x4 → EX Full!", Color(1.0, 0.85, 0.3))
					else:
						if source.active_buffs.has("crescent_moon"):
							# Already has buff — just update stacks (don't overwrite)
							source.active_buffs["crescent_moon"]["stacks"] = new_stacks
						else:
							# First stack — create the buff
							source.apply_buff("crescent_moon", -1, 0, "permanent")
							source.active_buffs["crescent_moon"]["stacks"] = new_stacks
						source._update_buff_icons()
						print(source.hero_data.get("name", "Hero") + " gained Crescent Moon (stack " + str(new_stacks) + "/4)")
						_log_status(source.hero_data.get("portrait", ""), "Crescent Moon " + str(new_stacks) + "/4", Color(0.8, 0.75, 1.0))
			"eclipse_buff":
				# Nyxara SK2: Gain Eclipse buff — next EX this turn deals double damage
				if source and not source.is_dead:
					source.apply_buff("eclipse_buff", 1, 0, "own_turn_end")
					print(source.hero_data.get("name", "Hero") + " gained Eclipse (next EX deals double damage)")
					_log_status(source.hero_data.get("portrait", ""), "Eclipse (2x EX)", Color(0.6, 0.4, 1.0))
			"rewind":
				# Nyra SK1: Pull 1 random card from discard pile into hand
				if source and not source.is_dead:
					var rw_discard = GameManager.enemy_discard_pile if _practice_controlling_enemy else GameManager.discard_pile
					var rw_hand = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
					if rw_discard.size() > 0:
						var rand_index = randi() % rw_discard.size()
						var rewound_card = rw_discard[rand_index]
						rw_discard.remove_at(rand_index)
						rw_hand.append(rewound_card)
						_refresh_hand()
						_update_deck_display()
						print(source.hero_data.get("name", "Hero") + " Rewind! Retrieved " + rewound_card.get("name", "card") + " from discard")
						_log_deck_action(card_data.get("art", card_data.get("image", "")), rewound_card.get("art", rewound_card.get("image", "")), "Rewind → Hand")
					else:
						print(source.hero_data.get("name", "Hero") + " Rewind failed — discard pile is empty")
						_log_event("Rewind failed — discard empty", Color(0.6, 0.5, 0.5))
			"time_bomb":
				# Nyra SK3: Apply time_bomb debuff to target (detonates at bombed hero's own turn end)
				if target and not target.is_dead:
					target.apply_debuff("time_bomb", 1, source_atk, "own_turn_end")
					print(target.hero_data.get("name", "Hero") + " has a Time Bomb! Detonates at end of opponent's turn")
					_log_status(target.hero_data.get("portrait", ""), "Time Bomb!", Color(1.0, 0.4, 0.1))
			"reshuffle":
				# Scrap SK2: Enter card selection mode — player picks cards to return to deck, then draws same amount
				if source and not source.is_dead:
					_start_card_select("reshuffle", -1, source)
					print(source.hero_data.get("name", "Hero") + " casting Reshuffle — select cards to return")
					_log_event("Reshuffle — select cards", Color(0.7, 0.85, 1.0))
			"redirect":
				# Kalasag SK1: Apply redirect buff to target ally (50% damage transferred to Kalasag)
				if target and not target.is_dead:
					# Store the source hero's instance_id so we know who receives the redirected damage
					target.apply_buff("redirect", 1, 0, "opponent_turn_end")
					target.set_meta("redirect_to", source.instance_id if source else -1)
					print(target.hero_data.get("name", "Hero") + " gained Redirect → damage transferred to " + source.hero_data.get("name", "Kalasag"))
					_log_status(target.hero_data.get("portrait", ""), "Redirect → " + source.hero_data.get("name", "Tank"), Color(0.5, 0.8, 1.0))
					# Also give Kalasag self-shield (DEF×2)
					if source and not source.is_dead:
						var self_shield_mult = card_data.get("self_shield_def_multiplier", 2.0) if card_data else 2.0
						var shield_amount = int(source.get_def() * self_shield_mult)
						if shield_amount > 0:
							source.block += shield_amount
							source._update_ui()
							source._show_shield_effect()
							print(source.hero_data.get("name", "Hero") + " gained " + str(shield_amount) + " Shield (self)")
							_log_status(source.hero_data.get("portrait", ""), "+" + str(shield_amount) + " Shield", Color(0.6, 0.85, 1.0))
	# Refresh hand card descriptions to reflect empower/weak changes
	_refresh_hand_descriptions()

func _apply_upgrade_shuffle(card_data: Dictionary) -> void:
	# Upgrade the card's atk_multiplier and shuffle back into deck
	var upgrade_mult = card_data.get("upgrade_multiplier", 0.2)
	var current_mult = card_data.get("atk_multiplier", 0.5)
	var new_mult = current_mult + upgrade_mult
	
	# Find the card in discard pile and upgrade it
	var ws_discard = GameManager.enemy_discard_pile if _practice_controlling_enemy else GameManager.discard_pile
	var ws_deck = GameManager.enemy_deck if _practice_controlling_enemy else GameManager.deck
	for i in range(ws_discard.size() - 1, -1, -1):
		var discard_card = ws_discard[i]
		if discard_card.get("id", "") == card_data.get("id", ""):
			# Remove from discard
			ws_discard.remove_at(i)
			# Upgrade the multiplier
			discard_card["atk_multiplier"] = new_mult
			# Update description
			var new_damage = int(10 * new_mult)
			discard_card["description"] = "Deal " + str(new_damage) + " damage to all enemies. Gain Taunt. +2 damage on shuffle."
			# Add back to deck
			ws_deck.append(discard_card)
			ws_deck.shuffle()
			print("War Stomp upgraded to " + str(new_mult * 100) + "% ATK and shuffled into deck")
			break

func _get_taunt_target(enemies: Array) -> Hero:
	for enemy in enemies:
		if not enemy.is_dead and enemy.has_buff("taunt"):
			return enemy
	return null

# ============================================
# POSITION-BASED TARGETING HELPERS
# ============================================

func _get_front_hero(team: Array) -> Hero:
	## Returns the frontmost alive hero in a team.
	## Player front = highest team_index. Enemy front = lowest team_index.
	var alive = team.filter(func(h): return not h.is_dead)
	if alive.is_empty():
		return null
	if alive[0].is_player_hero:
		# Player: front = highest team_index (pos 4)
		alive.sort_custom(func(a, b): return a.team_index > b.team_index)
	else:
		# Enemy: front = lowest team_index (pos 5, spawned at index 0)
		alive.sort_custom(func(a, b): return a.team_index < b.team_index)
	return alive[0]

func _get_back_hero(team: Array) -> Hero:
	## Returns the backmost alive hero in a team.
	var alive = team.filter(func(h): return not h.is_dead)
	if alive.is_empty():
		return null
	if alive[0].is_player_hero:
		# Player: back = lowest team_index (pos 1)
		alive.sort_custom(func(a, b): return a.team_index < b.team_index)
	else:
		# Enemy: back = highest team_index (pos 8)
		alive.sort_custom(func(a, b): return a.team_index > b.team_index)
	return alive[0]

func is_front_row(hero: Hero) -> bool:
	## Returns true if hero is in the front half (team_index >= 2)
	if hero.is_player_hero:
		return hero.team_index >= 2
	else:
		return hero.team_index <= 1

func is_back_row(hero: Hero) -> bool:
	## Returns true if hero is in the back half (team_index <= 1)
	if hero.is_player_hero:
		return hero.team_index <= 1
	else:
		return hero.team_index >= 2

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
		
		# Practice mode: ending enemy turn (player-controlled)
		if is_practice_mode and _practice_controlling_enemy:
			_practice_end_enemy_turn()
			return
		
		# === PLAYER TURN END ===
		# Snapshot HP for Temporal Shift (Nyra EX) BEFORE enemy acts
		_hp_snapshot_last_turn = _hp_snapshot_this_turn.duplicate(true)
		_hp_snapshot_this_turn.clear()
		for hero in player_heroes:
			_hp_snapshot_this_turn[hero.instance_id] = {
				"hp": hero.current_hp,
				"was_dead": hero.is_dead
			}
		
		# Expire buffs/debuffs
		# Detonate Time Bombs on PLAYER heroes (bombs placed by enemy, expire at player's own_turn_end)
		_detonate_time_bombs(player_heroes, true)
		
		# Player's heroes: remove "own_turn_end" buffs/debuffs (empower, regen, etc.)
		for hero in player_heroes:
			if not hero.is_dead:
				hero.on_own_turn_end()
		# Enemy's heroes: remove "opponent_turn_end" buffs/debuffs (their shields, taunt, etc.)
		for enemy in enemy_heroes:
			if not enemy.is_dead:
				enemy.on_opponent_turn_end()
		# Refresh hand descriptions after buffs expire
		_refresh_hand_descriptions()
		
		# Trigger Thunder damage on ALL heroes at end of player turn
		await _trigger_thunder_damage(enemy_heroes)
		await _trigger_thunder_damage(player_heroes)
		
		# Clear ENEMY shields at end of player turn (enemy used them last turn, now they expire)
		for enemy in enemy_heroes:
			if enemy.block > 0:
				# Dana's Smart Shield: trigger draw before clearing shield
				if enemy.has_buff("dana_shield_draw"):
					enemy.remove_buff("dana_shield_draw")
					GameManager.enemy_draw_cards(1)
					_refresh_enemy_hand_display()
					print("[Dana Shield Draw] " + enemy.hero_data.get("name", "Hero") + " (enemy) shield expired → draw 1")
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
	
	# Safety: reset all alive heroes to idle sprite at turn start
	for h in player_heroes + enemy_heroes:
		if not h.is_dead:
			var idle = h._resolve_flip_sprite("idle_sprite")
			if not idle.path.is_empty():
				h._load_sprite(idle.path, idle.flip_h)
	
	# Animate turn transition
	await _animate_turn_transition(is_player)
	
	if is_player:
		# === PLAYER TURN START ===
		# Reset practice enemy control flag
		_practice_controlling_enemy = false
		
		
		# Buffs/debuffs already expired at end of previous turns.
		# Just apply start-of-turn effects (regen, cleansing charm, etc.)
		for hero in player_heroes:
			if not hero.is_dead:
				hero.on_turn_start()
				if hero.regen_draw_triggered:
					hero.regen_draw_triggered = false
					GameManager.draw_cards(1)
					_refresh_hand()
					print("[Regen+] " + hero.hero_data.get("name", "Hero") + " drew 1 card!")
				_trigger_equipment_effects(hero, "on_turn_start", {})
		
		# Unlimited mana: refill at turn start
		if is_practice_mode and _practice_unli_mana:
			GameManager.current_mana = GameManager.MANA_CAP
			GameManager.max_mana = GameManager.MANA_CAP
			GameManager.enemy_current_mana = GameManager.MANA_CAP
			GameManager.enemy_max_mana = GameManager.MANA_CAP
			GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
		
		current_phase = BattlePhase.PLAYING
		if turn_indicator:
			turn_indicator.text = "YOUR TURN"
		end_turn_button.disabled = false
		_flip_to_player_turn()
		_refresh_hand()
		_log_turn_header(GameManager.turn_number, true)
	else:
		# === ENEMY TURN START ===
		# Note: enemy's "own_turn_end" expiry moved to end of _do_enemy_turn()
		# so that debuffs like stun actually prevent the enemy from acting first.
		
		# Apply start-of-turn effects for enemies
		for enemy in enemy_heroes:
			if not enemy.is_dead:
				enemy.on_turn_start()
				if enemy.regen_draw_triggered:
					enemy.regen_draw_triggered = false
					# In multiplayer, opponent manages their own hand — don't draw for them
					if not is_multiplayer:
						GameManager.enemy_draw_cards(1)
						print("[Regen+] " + enemy.hero_data.get("name", "Hero") + " (enemy) drew 1 card!")
		
		if turn_indicator:
			turn_indicator.text = "ENEMY TURN"
		_log_turn_header(GameManager.turn_number, false)
		# Enemy draws cards at start of turn (only for AI - in multiplayer, opponent manages their own hand)
		if not is_multiplayer:
			if GameManager.turn_number > 1:
				var current_hand_size = GameManager.get_enemy_hand_size()
				var cards_to_draw = min(3, 10 - current_hand_size)
				if cards_to_draw > 0:
					GameManager.enemy_draw_cards(cards_to_draw)
					_refresh_enemy_hand_display()
		
		# Practice mode: player controls enemy team instead of AI
		if is_practice_mode:
			_practice_controlling_enemy = true
			current_phase = BattlePhase.PLAYING
			end_turn_button.disabled = false
			if turn_indicator:
				turn_indicator.text = "ENEMY TURN (YOU)"
			_practice_show_enemy_hand()
			return
		
		current_phase = BattlePhase.ENEMY_TURN
		end_turn_button.disabled = true
		_flip_to_opponent_turn()
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
	
	# === ENEMY TURN END: Expire buffs/debuffs ===
	# Detonate Time Bombs on ENEMY heroes (bombs placed by player, expire at enemy's own_turn_end)
	_detonate_time_bombs(enemy_heroes, false)
	# Enemy's heroes: remove "own_turn_end" buffs/debuffs (stun, empower, etc.)
	for enemy in enemy_heroes:
		if not enemy.is_dead:
			enemy.on_own_turn_end()
	# Player's heroes: remove "opponent_turn_end" buffs/debuffs (taunt, redirect, etc.)
	for hero in player_heroes:
		if not hero.is_dead:
			hero.on_opponent_turn_end()
	# Refresh hand descriptions after buffs expire
	_refresh_hand_descriptions()
	
	# Trigger Thunder damage on ALL heroes at end of enemy turn
	await _trigger_thunder_damage(player_heroes)
	await _trigger_thunder_damage(enemy_heroes)
	
	# Clear PLAYER shields at end of enemy turn (player used them last turn, now they expire)
	for ally in player_heroes:
		if ally.block > 0:
			# Dana's Smart Shield: trigger draw before clearing shield
			if ally.has_buff("dana_shield_draw"):
				ally.remove_buff("dana_shield_draw")
				GameManager.draw_cards(1)
				_refresh_hand()
				print("[Dana Shield Draw] " + ally.hero_data.get("name", "Hero") + " shield expired → draw 1")
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
	
	# Check for EX skills — use strategically (not always immediately)
	for enemy in non_stunned_enemies:
		if enemy.energy >= enemy.max_energy:
			var ex_data = enemy.hero_data.get("ex_skill", {})
			var ex_type = ex_data.get("type", "damage")
			
			# Determine EX target based on type
			var ex_target: Hero = null
			var is_support_ex = ex_type in ["self_buff", "shield_all", "damage_link", "temporal_shift", "revive", "scrapyard_overflow", "thunder_all", "generate_cards"]
			
			if is_support_ex:
				# Support/utility EX: target self or allies
				ex_target = enemy
			else:
				# Damage EX: target enemy player
				ex_target = _ai_get_best_target(alive_players, "damage", ex_data)
			
			if ex_target:
				# Use EX strategically — don't always fire immediately
				var should_ex = false
				if is_support_ex:
					# Support EX: use when allies need help or proactively
					var any_low_hp = alive_enemies.any(func(e): return float(e.current_hp) / float(max(e.max_hp, 1)) < 0.5)
					if any_low_hp:
						should_ex = true  # Allies need healing/protection
					elif alive_enemies.size() >= 2 and mana <= 1:
						should_ex = true  # Good value, no mana for cards
					elif alive_enemies.size() <= 1:
						should_ex = true  # Last hero, use everything
					elif mana <= 1:
						should_ex = true  # No mana, use free EX
				else:
					# Damage EX: use when high value
					if ex_target.has_debuff("break"):
						should_ex = true  # Amplified damage on broken target
					elif ex_target.current_hp < ex_target.max_hp * 0.35:
						should_ex = true  # Likely kill — secure it
					elif alive_players.size() >= 3 and mana >= 2:
						should_ex = true  # Good value with follow-up mana
					elif mana <= 1:
						should_ex = true  # No mana for cards, use free EX
					elif alive_enemies.size() <= 1:
						should_ex = true  # Last hero standing, go all out
				# Otherwise hold EX — save for a better moment
				
				if should_ex:
					await _ai_use_ex_skill(enemy, ex_target)
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
					"priority": _ai_get_card_priority(card, alive_players, alive_enemies, mana)
				})
	
	if possible_actions.is_empty():
		return result
	
	# Sort by priority — always pick the best action (no randomness)
	possible_actions.sort_custom(func(a, b): return a.priority > b.priority)
	var chosen = possible_actions[0]
	
	var card = chosen.card
	var attacker = chosen.enemy
	var card_type = card.get("type", "attack")
	
	if card_type == "mana":
		GameManager.enemy_play_card(card, attacker, null)
		_apply_pre_action_self_effects(card, attacker, false)
		_trigger_bleed_damage(attacker)
		result.taken = true
		result.cost = 0
	elif card_type == "energy":
		GameManager.enemy_play_card(card, attacker, null)
		if not _apply_pre_action_self_effects(card, attacker, false):
			await _hide_card_display()
			return result
		await _show_card_display(card)
		await _animate_cast_buff(attacker, attacker)
		var energy_gain = card.get("energy_gain", 0)
		attacker.add_energy(energy_gain)
		await _hide_card_display()
		_trigger_bleed_damage(attacker)
		result.taken = true
		result.cost = card.get("cost", 0)
	elif card_type == "attack" or card_type == "basic_attack":
		var target: Hero = null
		var card_target_type = card.get("target", "single_enemy")
		if card_target_type == "front_enemy":
			# Use team_index to find the front player hero reliably
			var taunt_target = _get_taunt_target(alive_players)
			target = taunt_target if taunt_target else _get_front_hero(alive_players)
		else:
			target = _ai_get_best_target(alive_players, "damage", card)
		if target:
			await _ai_play_attack(attacker, target, card)
			result.taken = true
			result.cost = card.get("cost", 0)
	elif card_type == "heal":
		var target = _ai_get_best_target(alive_enemies, "heal", card)
		if target:
			await _ai_play_heal(attacker, target, card)
			result.taken = true
			result.cost = card.get("cost", 0)
		else:
			# Nobody needs healing — skip this card, try next action
			return result
	elif card_type == "buff":
		var target = _ai_get_best_target(alive_enemies, "buff", card)
		if target:
			await _ai_play_buff(attacker, target, card)
			result.taken = true
			result.cost = card.get("cost", 0)
	
	return result

func _ai_get_card_priority(card: Dictionary, players: Array, enemies: Array, mana: int) -> int:
	var card_type = card.get("type", "attack")
	var cost = card.get("cost", 0)
	var priority = 0
	var target_type = card.get("target", "single")
	
	# --- PHASE SCORING: buffs/debuffs first, then attacks ---
	
	if card_type == "buff":
		# Buffs are high priority early (setup phase)
		priority += 50
		var effects = card.get("effects", [])
		for eff in effects:
			var eff_type = eff.get("type", "") if eff is Dictionary else str(eff)
			if eff_type == "apply_empower" or eff_type == "empower" or eff_type == "empower_all":
				priority += 20  # Empower before attacks = huge value
			elif eff_type == "empower_heal_all" or eff_type == "empower_heal":
				# Empower Heal: valuable when allies have regen or will heal
				var any_damaged = enemies.any(func(e): return float(e.current_hp) / float(max(e.max_hp, 1)) < 0.7)
				priority += 18 if any_damaged else 8
			elif eff_type == "empower_shield_all" or eff_type == "empower_shield":
				priority += 15  # Empower Shield: decent setup
			elif eff_type == "apply_taunt" or eff_type == "taunt":
				# Taunt is valuable if we have a high-HP tank
				var has_tank = enemies.any(func(e): return e.hero_data.get("role", "") == "tank")
				if has_tank:
					priority += 15
			elif eff_type == "apply_break" or eff_type == "apply_weak" or eff_type == "break" or eff_type == "weak":
				priority += 18  # Debuffs on enemies before attacking
			elif eff_type == "redirect":
				# Redirect is useless if a teammate already has taunt (enemies can't hit the redirected ally anyway)
				var ally_has_taunt = enemies.any(func(e): return e.has_buff("taunt"))
				if ally_has_taunt:
					priority += 2  # Almost worthless — taunt already protects squishies
				else:
					priority += 12
			elif eff_type == "reshuffle":
				priority += 5  # Low priority for AI (hand management is less useful)
		# Shield value scales with how damaged allies are
		var has_shield = card.get("base_shield", 0) > 0 or card.get("shield_multiplier", 0.0) > 0 or card.get("def_multiplier", 0.0) > 0
		if has_shield:
			var any_damaged = enemies.any(func(e): return float(e.current_hp) / float(max(e.max_hp, 1)) < 0.6)
			priority += 15 if any_damaged else 5
	
	elif card_type == "attack" or card_type == "basic_attack":
		priority += 30
		var atk_mult = card.get("atk_multiplier", 1.0)
		# Higher multiplier = higher priority
		priority += int(atk_mult * 8)
		# AoE bonus when many targets alive
		if target_type == "all_enemy":
			priority += players.size() * 5
			if players.size() >= 3:
				priority += 10  # Big AoE bonus
		# Bonus if any player has break debuff (attack will deal more)
		var any_broken = players.any(func(p): return p.has_debuff("break"))
		if any_broken:
			priority += 12
		# Bonus for effects on attack cards (burn, bleed, etc.)
		var effects = card.get("effects", [])
		priority += effects.size() * 3
	
	elif card_type == "heal":
		# Heal priority scales with how much damage allies have taken
		var most_damaged_pct = 1.0
		for enemy in enemies:
			var hp_pct = float(enemy.current_hp) / float(max(enemy.max_hp, 1))
			if hp_pct < most_damaged_pct:
				most_damaged_pct = hp_pct
		if most_damaged_pct < 0.3:
			priority += 60  # Emergency heal — top priority
		elif most_damaged_pct < 0.5:
			priority += 40
		elif most_damaged_pct < 0.7:
			priority += 20
		else:
			priority += 5  # Low priority if everyone is healthy
		# AoE heal bonus
		if target_type == "all_ally":
			var damaged_count = enemies.filter(func(e): return float(e.current_hp) / float(max(e.max_hp, 1)) < 0.7).size()
			priority += damaged_count * 5
		# Regen cards are preventive — always decent value
		var heal_effects = card.get("effects", [])
		for eff in heal_effects:
			var eff_type = eff.get("type", "") if eff is Dictionary else str(eff)
			if eff_type == "regen":
				priority += 10  # Regen is always useful
			elif eff_type == "regen_draw":
				priority += 15  # Regen + draw is high value
	
	elif card_type == "energy":
		priority += 15
	
	elif card_type == "mana":
		priority += 10  # Free mana is always decent
	
	# --- COST EFFICIENCY ---
	# Prefer cheaper cards when mana is low
	if cost == 0:
		priority += 5
	elif mana <= 2 and cost <= 1:
		priority += 3
	
	return priority

func _ai_get_best_target(targets: Array, action_type: String, card: Dictionary = {}) -> Hero:
	if targets.is_empty():
		return null
	
	if action_type == "damage":
		# 1. Must hit taunt target
		var taunt_target = _get_taunt_target(targets)
		if taunt_target:
			return taunt_target
		
		# 2. Score each target
		var best_target = targets[0]
		var best_score = -999.0
		for t in targets:
			var score = 0.0
			var hp_pct = float(t.current_hp) / float(max(t.max_hp, 1))
			
			# Prefer low HP targets (focus fire / secure kills)
			score += (1.0 - hp_pct) * 30.0
			
			# Bonus if target has break debuff (+50% damage taken)
			if t.has_debuff("break"):
				score += 25.0
			
			# Bonus if target has marked debuff
			if t.has_debuff("marked"):
				score += 15.0
			
			# Bonus if we can kill this target (estimate damage)
			var atk_mult = card.get("atk_multiplier", 1.0)
			var est_damage = int(15.0 * atk_mult)  # rough estimate
			if t.current_hp <= est_damage:
				score += 40.0  # Big bonus for securing kills
			
			# Small bonus for targets with high energy (deny EX skills)
			var energy_pct = float(t.energy) / float(max(t.max_energy, 1))
			if energy_pct >= 0.7:
				score += 10.0
			
			if score > best_score:
				best_score = score
				best_target = t
		
		return best_target
	
	elif action_type == "heal":
		# Check if this heal card has regen/regen_draw effects (preventive — always useful)
		var heal_effects = card.get("effects", [])
		var has_regen = false
		for eff in heal_effects:
			var eff_type = eff.get("type", "") if eff is Dictionary else str(eff)
			if eff_type in ["regen", "regen_draw"]:
				has_regen = true
				break
		
		# Heal the most damaged ally (by HP%)
		var best = targets[0]
		var lowest_pct = 999.0
		for t in targets:
			var hp_pct = float(t.current_hp) / float(max(t.max_hp, 1))
			if hp_pct < lowest_pct:
				lowest_pct = hp_pct
				best = t
		# Don't skip regen cards — they're preventive buffs, always useful
		if has_regen:
			return best
		# Don't heal if everyone is above 90%
		if lowest_pct > 0.9:
			return null
		return best
	
	elif action_type == "buff":
		var buff_effects = card.get("effects", [])
		var has_empower = false
		var has_empower_heal = false
		var has_shield = card.get("base_shield", 0) > 0 or card.get("def_multiplier", 0.0) > 0 or card.get("shield_multiplier", 0.0) > 0
		var has_taunt_buff = false
		var has_redirect = false
		var is_all_ally = card.get("target", "") == "all_ally"
		for eff in buff_effects:
			var eff_type = eff.get("type", "") if eff is Dictionary else str(eff)
			if eff_type in ["apply_empower", "empower", "empower_all"]:
				has_empower = true
			if eff_type in ["empower_heal", "empower_heal_all"]:
				has_empower_heal = true
			if eff_type in ["apply_taunt", "taunt"]:
				has_taunt_buff = true
			if eff_type == "redirect":
				has_redirect = true
		
		# AoE buffs: just return any alive ally (target doesn't matter for all_ally)
		if is_all_ally:
			return targets[0]
		
		# Redirect: protect the squishiest non-taunting ally (never redirect the taunter)
		if has_redirect:
			var best = null
			var lowest_hp = 999999
			for t in targets:
				if t.has_buff("taunt"):
					continue
				if t.current_hp < lowest_hp:
					lowest_hp = t.current_hp
					best = t
			if best:
				return best
			return targets[0]
		
		if has_empower:
			# Give empower to highest base_attack ally (DPS/mage)
			var best = targets[0]
			for t in targets:
				if t.hero_data.get("base_attack", 0) > best.hero_data.get("base_attack", 0):
					best = t
			return best
		elif has_empower_heal:
			# Give empower heal to the support or most damaged ally
			var best = targets[0]
			var lowest_pct = 999.0
			for t in targets:
				var hp_pct = float(t.current_hp) / float(max(t.max_hp, 1))
				if hp_pct < lowest_pct:
					lowest_pct = hp_pct
					best = t
			return best
		elif has_taunt_buff:
			# Give taunt to highest HP tank
			var best = targets[0]
			for t in targets:
				if t.current_hp > best.current_hp:
					best = t
			return best
		elif has_shield:
			# Shield the most damaged ally
			var best = targets[0]
			var lowest_pct = 999.0
			for t in targets:
				var hp_pct = float(t.current_hp) / float(max(t.max_hp, 1))
				if hp_pct < lowest_pct:
					lowest_pct = hp_pct
					best = t
			return best
		else:
			# Generic buff — give to the ally with highest ATK (most value)
			var best = targets[0]
			for t in targets:
				if t.hero_data.get("base_attack", 0) > best.hero_data.get("base_attack", 0):
					best = t
			return best
	
	return targets[0]

func _ai_use_ex_skill(attacker: Hero, target: Hero) -> void:
	# Use the full _execute_ex_skill which handles ALL EX types properly
	# (damage, self_buff, thunder_all, shield_all, damage_link, temporal_shift, etc.)
	await _execute_ex_skill(attacker, target)
	
	# Track EX skill usage for enemy
	GameManager.add_ex_skill_used("enemy_" + attacker.hero_id)

func _ai_play_attack(attacker: Hero, target: Hero, card: Dictionary) -> void:
	# Remove card from enemy hand
	GameManager.enemy_play_card(card, attacker, target)
	if not _apply_pre_action_self_effects(card, attacker, false):
		await _hide_card_display()
		return
	
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
			player.take_damage(final_damage, attacker)
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
		_log_aoe_attack(attacker.hero_data.get("name", "Enemy"), card.get("name", "Attack"), total_damage, alive_players.size(), false, card.get("art", card.get("image", "")))
		# Process card effects
		var effects = card.get("effects", [])
		if not effects.is_empty():
			_apply_effects(effects, attacker, null, base_atk)
	else:
		await _animate_attack(attacker, target, damage)
		GameManager.add_damage_dealt(enemy_stat_id, damage)
		_log_attack(attacker.hero_data.get("name", "Enemy"), card.get("name", "Attack"), target.hero_data.get("name", "Hero"), damage, false, card.get("art", card.get("image", "")), target.hero_data.get("portrait", ""))
	
	var energy_gain = int(card.get("energy_on_hit", GameConstants.ENERGY_ON_ATTACK))
	attacker.add_energy(energy_gain)
	await _hide_card_display()
	_trigger_bleed_damage(attacker)

func _ai_play_heal(attacker: Hero, target: Hero, card: Dictionary) -> void:
	# Remove card from enemy hand
	GameManager.enemy_play_card(card, attacker, target)
	if not _apply_pre_action_self_effects(card, attacker, false):
		await _hide_card_display()
		return
	
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
		_log_heal(attacker.hero_data.get("name", "Enemy"), card.get("name", "Heal"), "All Allies", total_heal, false, card.get("art", card.get("image", "")), attacker.hero_data.get("portrait", ""))
	else:
		target.heal(heal_amount)
		GameManager.add_healing_done(enemy_stat_id, heal_amount)
		_log_heal(attacker.hero_data.get("name", "Enemy"), card.get("name", "Heal"), target.hero_data.get("name", "Ally"), heal_amount, false, card.get("art", card.get("image", "")), target.hero_data.get("portrait", ""))
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
	
	# Apply card effects (regen, regen_draw, etc.)
	var effects = card.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, attacker, target, base_atk, card)
	
	await _hide_card_display()
	_trigger_bleed_damage(attacker)

func _ai_play_buff(attacker: Hero, target: Hero, card: Dictionary) -> void:
	# Remove card from enemy hand
	GameManager.enemy_play_card(card, attacker, target)
	if not _apply_pre_action_self_effects(card, attacker, false):
		await _hide_card_display()
		return
	
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
	
	# Apply card effects (empower_heal_all, taunt, redirect, reshuffle, etc.)
	var effects = card.get("effects", [])
	if not effects.is_empty():
		_apply_effects(effects, attacker, target, base_atk, card)
	
	var buff_text = card.get("name", "Buff")
	if shield > 0:
		buff_text = "+" + str(shield) + " Shield"
	var buff_target_name = target.hero_data.get("name", "Ally") if target_type != "all_ally" else "All Allies"
	var buff_target_portrait = target.hero_data.get("portrait", "") if target_type != "all_ally" else attacker.hero_data.get("portrait", "")
	_log_buff(attacker.hero_data.get("name", "Enemy"), card.get("name", "Buff"), buff_target_name, buff_text, false, card.get("art", card.get("image", "")), buff_target_portrait)
	
	await _hide_card_display()
	_trigger_bleed_damage(attacker)

func _on_counter_triggered(defender: Hero, attacker: Hero, reflect_damage: int) -> void:
	# Counter (Reflect): apply reflect damage to the attacker as true damage (ignores DEF/shield)
	if attacker == null or attacker.is_dead or reflect_damage <= 0:
		return
	attacker.current_hp = max(0, attacker.current_hp - reflect_damage)
	attacker._spawn_floating_number(reflect_damage, Color(1.0, 0.6, 0.2))
	attacker._play_hit_animation()
	attacker._update_ui()
	# VFX: reflect spark on attacker
	if VFX and attacker.sprite:
		var sprite_center = attacker.sprite.global_position + attacker.sprite.size / 2
		VFX.spawn_particles(sprite_center, Color(1.0, 0.8, 0.2), 8)
	print("[Counter] " + defender.hero_data.get("name", "") + " reflected " + str(reflect_damage) + " to " + attacker.hero_data.get("name", ""))
	_log_status(defender.hero_data.get("portrait", ""), "Reflect " + str(reflect_damage) + " DMG → " + attacker.hero_data.get("name", ""), Color(1.0, 0.6, 0.2))
	if attacker.current_hp <= 0:
		attacker.die()

func _on_shield_broken(hero: Hero) -> void:
	# Dana's Smart Shield: when shield is fully consumed by damage, trigger draw 1
	if hero.has_buff("dana_shield_draw"):
		hero.remove_buff("dana_shield_draw")
		if hero.is_player_hero:
			GameManager.draw_cards(1)
			_refresh_hand()
			print("[Dana Shield Draw] " + hero.hero_data.get("name", "Hero") + " shield broken → draw 1")
		else:
			GameManager.enemy_draw_cards(1)
			_refresh_enemy_hand_display()
			if _practice_controlling_enemy:
				_practice_show_enemy_hand()
			print("[Dana Shield Draw] " + hero.hero_data.get("name", "Hero") + " (enemy) shield broken → draw 1")

func _on_hero_died(hero: Hero) -> void:
	print(hero.hero_data.get("name", "Hero") + " has died!")
	_log_death(hero.hero_data.get("name", "Hero"), hero.is_player_hero, hero.hero_data.get("portrait", ""))
	
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
		# In practice enemy control, also refresh the main hand (showing enemy cards)
		if _practice_controlling_enemy:
			_practice_show_enemy_hand()

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
		if _practice_controlling_enemy:
			mana_label.text = str(GameManager.enemy_current_mana) + "/" + str(GameManager.enemy_max_mana)
		else:
			mana_label.text = str(GameManager.current_mana) + "/" + str(GameManager.max_mana)
	if deck_label:
		if _practice_controlling_enemy:
			deck_label.text = str(GameManager.enemy_deck.size())
		else:
			deck_label.text = str(GameManager.deck.size())

func _on_game_over(player_won: bool) -> void:
	# In practice mode, skip game over — just let user reset
	if is_practice_mode:
		current_phase = BattlePhase.PLAYING
		print("[Practice] Game over suppressed — use Reset HP to continue")
		return
	
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
		"dig_choice":
			print("  → Calling _host_execute_dig_choice_request")
			await _host_execute_dig_choice_request(request)
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

	# Multiplayer bulletproofing: dig requires a player choice and deterministic deck mutation.
	# For Guest-played dig cards, send a prompt to the Guest and wait for a dig_choice request.
	var card_type = str(card_data.get("type", ""))
	if card_type == "dig" and source != null and not source.is_player_hero:
		await _host_send_dig_prompt(request, card_data, source)
		return
	
	# RC1: Auto-resolve target for cards that don't need an explicit target
	var card_target_type = card_data.get("target", "")
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

func _host_send_dig_prompt(request: Dictionary, card_data: Dictionary, source: Hero) -> void:
	if network_manager == null:
		return
	var dig_count := int(card_data.get("dig_count", 3))
	var dig_filter := str(card_data.get("dig_filter", "equipment"))
	var deck: Array = GameManager.enemy_deck
	var revealed_cards: Array = []
	for i in range(min(dig_count, deck.size())):
		revealed_cards.append(deck[deck.size() - 1 - i])
	if revealed_cards.is_empty():
		return
	var reveal_iids: Array = []
	for c in revealed_cards:
		reveal_iids.append(str(c.get("instance_id", c.get("id", ""))))
	var dig_request_id := str(Time.get_unix_time_from_system()) + "_" + str(randi())
	_pending_dig = {
		"dig_request_id": dig_request_id,
		"card_data": card_data,
		"source_instance_id": source.instance_id,
		"source_hero_id": source.hero_id,
		"reveal_iids": reveal_iids,
		"dig_filter": dig_filter,
		"dig_count": dig_count
	}
	var prompt := {
		"action_type": "dig_prompt",
		"played_by": opponent_player_id,
		"card_id": card_data.get("base_id", card_data.get("id", "")),
		"card_name": card_data.get("name", "Dig"),
		"card_type": "dig",
		"source_hero_id": source.hero_id,
		"source_instance_id": source.instance_id,
		"dig_request_id": dig_request_id,
		"dig_filter": dig_filter,
		"reveal_iids": reveal_iids
	}
	network_manager.send_action_result(prompt)

func _host_execute_dig_choice_request(request: Dictionary) -> void:
	if _pending_dig.is_empty():
		return
	var dig_request_id := str(request.get("dig_request_id", ""))
	if dig_request_id.is_empty() or dig_request_id != str(_pending_dig.get("dig_request_id", "")):
		return
	var chosen_iid := str(request.get("chosen_instance_id", ""))
	var card_data: Dictionary = _pending_dig.get("card_data", {})
	var source_iid := str(_pending_dig.get("source_instance_id", ""))
	var source: Hero = _find_hero_by_instance_id(source_iid)
	if source == null:
		_pending_dig = {}
		return
	var deck: Array = GameManager.enemy_deck
	var hand: Array = GameManager.enemy_hand
	var discard: Array = GameManager.enemy_discard_pile
	var selected_card: Dictionary = {}
	if not chosen_iid.is_empty():
		for i in range(deck.size()):
			var iid = str(deck[i].get("instance_id", deck[i].get("id", "")))
			if iid == chosen_iid:
				selected_card = deck[i]
				deck.remove_at(i)
				break
	var effects: Array = []
	if not selected_card.is_empty():
		effects.append({
			"type": "deck_remove_card",
			"is_host_hero": false,
			"card_instance_id": chosen_iid
		})
		if hand.size() < GameManager.HAND_SIZE:
			hand.append(selected_card)
			effects.append({
				"type": "hand_add_card",
				"is_host_hero": false,
				"card_instance_id": chosen_iid,
				"card_data": selected_card
			})
		else:
			discard.append(selected_card)
			effects.append({
				"type": "discard_add_card",
				"is_host_hero": false,
				"card_instance_id": chosen_iid,
				"card_data": selected_card
			})
	var shuffle_seed := int(randi())
	deck = _deterministic_shuffle_with_seed(deck, shuffle_seed)
	GameManager.enemy_deck_manager.deck = deck
	effects.append({
		"type": "deck_shuffle",
		"is_host_hero": false,
		"seed": shuffle_seed
	})
	_refresh_hand()
	_update_ui()
	var result := {
		"action_type": "play_card",
		"played_by": opponent_player_id,
		"card_id": card_data.get("base_id", card_data.get("id", "")),
		"card_name": card_data.get("name", "Dig"),
		"card_type": "dig",
		"source_hero_id": source.hero_id,
		"source_instance_id": source.instance_id,
		"target_hero_id": "",
		"target_instance_id": "",
		"target_is_enemy": false,
		"success": true,
		"effects": effects
	}
	network_manager.send_action_result(result)
	_pending_dig = {}

func _deterministic_shuffle_with_seed(array: Array, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shuffled := array.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j = int(rng.randi() % (i + 1))
		var temp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = temp
	return shuffled

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
		"dig_prompt":
			print("  → Calling _guest_handle_dig_prompt")
			await _guest_handle_dig_prompt(result)
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
	_apply_ops(effects)
	
	_refresh_enemy_hand_display()
	print("Battle: [GUEST] Card result fully applied\n")

func _guest_handle_dig_prompt(result: Dictionary) -> void:
	# Guest receives a dig prompt from Host, chooses a card locally, then sends dig_choice back.
	var dig_request_id := str(result.get("dig_request_id", ""))
	var dig_filter := str(result.get("dig_filter", "equipment"))
	var reveal_iids: Array = result.get("reveal_iids", [])
	if dig_request_id.is_empty() or reveal_iids.is_empty():
		return

	# Rebuild the revealed card dictionaries from our local deck using instance_id.
	var deck: Array = GameManager.deck
	var revealed_cards: Array = []
	for iid in reveal_iids:
		for c in deck:
			var cid := str(c.get("instance_id", c.get("id", "")))
			if cid == str(iid):
				revealed_cards.append(c)
				break
	if revealed_cards.is_empty():
		return

	var selected: Dictionary = await _show_card_selection(revealed_cards, dig_filter, "Dig - Select a Card")
	var chosen_iid := ""
	if not selected.is_empty():
		chosen_iid = str(selected.get("instance_id", selected.get("id", "")))

	var req := {
		"action_type": "dig_choice",
		"dig_request_id": dig_request_id,
		"chosen_instance_id": chosen_iid,
		"card_data": {},
		"source_hero_id": result.get("source_hero_id", ""),
		"source_instance_id": result.get("source_instance_id", ""),
		"target_hero_id": "",
		"target_instance_id": "",
		"target_is_enemy": false,
		"timestamp": Time.get_unix_time_from_system()
	}
	if network_manager:
		network_manager.send_action_request(req)

func _guest_apply_ex_skill_result(result: Dictionary) -> void:
	## GUEST: Apply EX skill results from Host
	var effects = result.get("effects", [])
	var source_hero_id = result.get("source_hero_id", "")
	var target_hero_id = result.get("target_hero_id", "")
	
	print("Battle: [GUEST] Applying EX skill result - source: ", source_hero_id, " target: ", target_hero_id, " effects: ", effects.size())
	
	_apply_ops(effects)
	
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

	# Deck/hand/discard ops do not target a hero. Handle them before hero lookup.
	match effect_type:
		"deck_remove_card", "hand_add_card", "discard_add_card", "deck_shuffle":
			var dm: DeckManager = GameManager.enemy_deck_manager if is_host_hero else GameManager.player_deck_manager
			if dm == null:
				return
			match effect_type:
				"deck_remove_card":
					var iid := str(effect.get("card_instance_id", ""))
					if iid.is_empty():
						return
					for i in range(dm.deck.size()):
						var cid := str(dm.deck[i].get("instance_id", dm.deck[i].get("id", "")))
						if cid == iid:
							dm.deck.remove_at(i)
							break
				"hand_add_card":
					var card_data: Dictionary = effect.get("card_data", {})
					if card_data.is_empty():
						return
					if dm.hand.size() < GameManager.HAND_SIZE:
						dm.hand.append(card_data)
					else:
						dm.discard_pile.append(card_data)
				"discard_add_card":
					var card_data: Dictionary = effect.get("card_data", {})
					if card_data.is_empty():
						return
					dm.discard_pile.append(card_data)
				"deck_shuffle":
					var seed_value := int(effect.get("seed", 0))
					if seed_value == 0:
						return
					dm.deck = _deterministic_shuffle_with_seed(dm.deck, seed_value)
			_refresh_hand()
			_refresh_enemy_hand_display()
			_update_ui()
			return
	
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
			hero.current_hp = min(new_hp, hero.max_hp)
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
		"remove_buff":
			var buff_type = effect.get("buff_type", "")
			if not buff_type.is_empty():
				hero.remove_buff(buff_type)
		"debuff":
			var debuff_type = effect.get("debuff_type", "")
			var duration = effect.get("duration", 1)
			var value = effect.get("value", 0)
			var expire_on = effect.get("expire_on", _get_debuff_expire_on(debuff_type))
			if not debuff_type.is_empty():
				if debuff_type == "thunder":
					var stacks := int(effect.get("stacks", 1))
					if stacks > 1:
						hero.add_thunder_stacks(stacks, value)
					else:
						hero.apply_debuff(debuff_type, duration, value, expire_on)
				else:
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
		"dispel":
			hero.clear_all_buffs()
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
	elif target_type == "self" or card_type == "energy":
		if source:
			targets.append(source)
	elif target:
		targets.append(target)
	
	# Phase 4: Pre-action self effects (HP cost + Bleed trigger) via registry.
	# These are true-damage effects on the source and must be replicated to Guest.
	if source:
		var pre_ctx := {
			"source": source,
			"primary_target": target,
			"targets": targets,
			"card_data": card_data,
			"is_ex": bool(card_data.get("is_ex", false)),
			"battle": self
		}
		if not bool(pre_ctx.get("is_ex", false)):
			var hp_cost_pct_val := float(card_data.get("hp_cost_pct", 0.0))
			if hp_cost_pct_val > 0.0:
				var hp_ops = _dispatch_effect_spec(pre_ctx, {
					"type": EFFECT_HP_COST_PCT,
					"pct": hp_cost_pct_val,
					"target": "source"
				})
				if bool(pre_ctx.get("blocked", false)):
					return {"success": false, "effects": []}
				for op in hp_ops:
					effects.append(op)
			# Bleed is now post-action — handled after card resolves
	
	# ========================================
	# PRE-COMPUTE: Calculate all effect values (NO animations, NO state changes yet)
	# This lets us send results to Guest before animations play.
	# ========================================
	var precomputed: Dictionary = {}
	
	match card_type:
		"mana":
			var mana_gain := int(card_data.get("mana_gain", 1))
			var new_mana := int(GameManager.current_mana + mana_gain)
			effects.append({
				"type": "mana",
				"hero_id": source.hero_id if source else "",
				"instance_id": source.instance_id if source else "",
				"is_host_hero": source.is_player_hero if source else true,
				"amount": mana_gain,
				"new_mana": new_mana
			})
			precomputed["new_mana"] = new_mana
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
				# Avoid mutating Host state during precompute.
				# Only apply effects here if they inherently perform extra damage logic that must be snapshotted.
				if card_effects.has("penetrate"):
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
				if card_effects.has("penetrate"):
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
				if card_effects.has("penetrate"):
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
				if card_effects.has("penetrate"):
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
		"mana":
			var new_mana := int(precomputed.get("new_mana", GameManager.current_mana))
			GameManager.current_mana = new_mana
			GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
			if source:
				await _animate_cast_buff(source, source)
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
			# Apply card effects (buffs/debuffs/etc.) on Host after attack.
			if card_effects.size() > 0 and source:
				var primary_target = target if target else (targets[0] if targets.size() > 0 else null)
				if not card_effects.has("penetrate"):
					_apply_effects(card_effects, source, primary_target, base_atk, card_data)
		
		"heal":
			var heal_amount = precomputed.get("heal_amount", 0)
			for t in targets:
				t.heal(heal_amount)
				if source and t == targets[0]:
					await _animate_cast_heal(source, t)
			if card_effects.size() > 0 and source:
				var primary_target = target if target else (targets[0] if targets.size() > 0 else null)
				if not card_effects.has("penetrate"):
					_apply_effects(card_effects, source, primary_target, base_atk, card_data)
		
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
			if card_effects.size() > 0 and source:
				var primary_target = target if target else (targets[0] if targets.size() > 0 else null)
				if not card_effects.has("penetrate"):
					_apply_effects(card_effects, source, primary_target, base_atk, card_data)
		
		"debuff":
			var debuff_type = card_data.get("debuff_type", "")
			for t in targets:
				if not debuff_type.is_empty():
					var debuff_expire = _get_debuff_expire_on(debuff_type)
					t.apply_debuff(debuff_type, 1, base_atk, debuff_expire)
			if source and targets.size() > 0:
				await _animate_cast_debuff(source, targets[0])
			if card_effects.size() > 0 and source:
				var primary_target = target if target else (targets[0] if targets.size() > 0 else null)
				if not card_effects.has("penetrate"):
					_apply_effects(card_effects, source, primary_target, base_atk, card_data)
		
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
	
	# Post-action bleed: card resolved, now bleed damages the source hero
	if source:
		_trigger_bleed_damage(source)
	
	return result

func _collect_effects_snapshot(effects: Array, card_effects: Array, source: Hero, primary_target: Hero, targets: Array) -> void:
	## After _apply_effects has been called, snapshot any state changes caused by
	## the card's effects array so the Guest can replicate them.
	## This collects buff/debuff/block/hp/energy changes from effects like stun, empower, taunt, etc.
	# Phase 3: generate ops for common effects via registry (keeps special cases below).
	var ctx := {
		"source": source,
		"primary_target": primary_target,
		"targets": targets,
		"card_data": {},
		"is_ex": false,
		"apply_now": false,
		"battle": self
	}
	var normalized_specs = _normalize_effects(card_effects, source, primary_target)
	for spec in normalized_specs:
		if not (spec is Dictionary):
			continue
		var t := str(spec.get("type", ""))
		if t in [EFFECT_APPLY_DEBUFF, EFFECT_APPLY_BUFF, EFFECT_CLEANSE, EFFECT_CLEANSE_ALL, EFFECT_DISPEL, EFFECT_DISPEL_ALL, EFFECT_THUNDER_STACK_2, EFFECT_DRAW, EFFECT_SHIELD_CURRENT_HP, EFFECT_PENETRATE]:
			var ops = _dispatch_effect_spec(ctx, spec)
			for op in ops:
				effects.append(op)
	for effect_name in card_effects:
		# Skip effects already emitted via registry above.
		if str(effect_name) in ["stun", "weak", "bleed", "thunder", "break", "empower", "taunt", "cleanse", "cleanse_all", "dispel", "dispel_all", "empower_target", "empower_all", "empower_heal", "empower_heal_all", "empower_shield", "empower_shield_all", "regen_draw", "damage_link_all", "thunder_all", "regen", "thunder_stack_2", "draw_1", "shield_current_hp", "penetrate", "mana_surge"]:
			continue
		match effect_name:
			_:
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
	
	# For self_buff, thunder_all, shield_all, temporal_shift, scrapyard_overflow, damage_link — target may be source itself
	if target == null and (ex_type == "self_buff" or ex_type == "thunder_all" or ex_type == "shield_all" or ex_type == "temporal_shift" or ex_type == "scrapyard_overflow" or ex_type == "damage_link"):
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
	# Avoid duplicating stateful ops already captured by pre/post snapshots (e.g. shield_current_hp -> block).
	var ex_effects_for_snapshot: Array = []
	for eff in ex_effects:
		if str(eff) in ["shield_current_hp"]:
			continue
		ex_effects_for_snapshot.append(eff)
	_collect_effects_snapshot(effects, ex_effects_for_snapshot, source, target, [])
	
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

# ============================================
# BATTLE LOG SYSTEM
# ============================================

func _setup_battle_log() -> void:
	# Toggle button — above mana display (mana is at y=350)
	battle_log_button = Button.new()
	battle_log_button.text = "LOG"
	battle_log_button.custom_minimum_size = Vector2(60, 30)
	battle_log_button.position = Vector2(20, 310)
	battle_log_button.add_theme_font_size_override("font_size", 12)
	battle_log_button.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	battle_log_button.modulate = Color(1, 1, 1, 0.8)
	battle_log_button.pressed.connect(_toggle_battle_log)
	battle_log_button.z_index = 20
	$UI.add_child(battle_log_button)
	
	# Log panel — slides out from left
	battle_log_panel = PanelContainer.new()
	battle_log_panel.custom_minimum_size = Vector2(380, 400)
	battle_log_panel.position = Vector2(90, 60)
	battle_log_panel.z_index = 15
	battle_log_panel.visible = false
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.06, 0.04, 0.92)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.6, 0.5, 0.3, 0.8)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10
	battle_log_panel.add_theme_stylebox_override("panel", panel_style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	battle_log_panel.add_child(vbox)
	
	# Header
	var header = Label.new()
	header.text = "Battle Log"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)
	
	# Separator
	var sep = HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.5, 0.4, 0.3, 0.6))
	vbox.add_child(sep)
	
	# Scroll container
	battle_log_scroll = ScrollContainer.new()
	battle_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_log_scroll.custom_minimum_size = Vector2(0, 340)
	vbox.add_child(battle_log_scroll)
	
	# VBox for visual log entries (card image → hero portrait → damage)
	battle_log_container = VBoxContainer.new()
	battle_log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_log_container.add_theme_constant_override("separation", 4)
	battle_log_scroll.add_child(battle_log_container)
	
	$UI.add_child(battle_log_panel)

func _toggle_battle_log() -> void:
	battle_log_visible = !battle_log_visible
	if battle_log_visible:
		battle_log_panel.visible = true
		battle_log_panel.modulate = Color(1, 1, 1, 0)
		var tween = create_tween()
		tween.tween_property(battle_log_panel, "modulate:a", 1.0, 0.2)
		# Auto-scroll to bottom
		await get_tree().process_frame
		battle_log_scroll.scroll_vertical = battle_log_scroll.get_v_scroll_bar().max_value
	else:
		var tween = create_tween()
		tween.tween_property(battle_log_panel, "modulate:a", 0.0, 0.15)
		tween.tween_callback(func(): battle_log_panel.visible = false)

func _add_visual_log_entry(row: Control) -> void:
	if battle_log_container:
		battle_log_container.add_child(row)
		# Auto-scroll if panel is open
		if battle_log_visible and battle_log_scroll:
			await get_tree().process_frame
			battle_log_scroll.scroll_vertical = battle_log_scroll.get_v_scroll_bar().max_value

func _create_log_image(path: String, size: Vector2 = Vector2(40, 40)) -> TextureRect:
	var tex_rect = TextureRect.new()
	tex_rect.custom_minimum_size = size
	tex_rect.expand_mode = 1  # EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = 5  # STRETCH_KEEP_ASPECT_CENTERED
	if not path.is_empty() and ResourceLoader.exists(path):
		tex_rect.texture = load(path)
	return tex_rect

func _create_log_arrow() -> Label:
	var arrow = Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", 16)
	arrow.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return arrow

func _create_log_text(text: String, color: Color, font_size: int = 12) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _log_turn_header(turn_num: int, is_player: bool) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var side_text = "You" if is_player else "Enemy"
	var side_color = Color(0.56, 0.78, 1.0) if is_player else Color(1.0, 0.53, 0.53)
	row.add_child(_create_log_text("── Turn " + str(turn_num) + " — ", Color(0.63, 0.56, 0.44), 13))
	row.add_child(_create_log_text(side_text, side_color, 13))
	row.add_child(_create_log_text(" ──", Color(0.63, 0.56, 0.44), 13))
	_add_visual_log_entry(row)

func _log_attack(source_name: String, card_name: String, target_name: String, damage: int, is_player: bool, card_art: String = "", target_portrait: String = "") -> void:
	# Row: [Card Art] → [Hero Portrait] : DMG text
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 44
	row.add_child(_create_log_image(card_art, Vector2(40, 40)))
	row.add_child(_create_log_arrow())
	row.add_child(_create_log_image(target_portrait, Vector2(36, 36)))
	row.add_child(_create_log_text(str(damage) + " DMG", Color(1.0, 0.4, 0.4), 13))
	_add_visual_log_entry(row)

func _log_aoe_attack(source_name: String, card_name: String, total_damage: int, target_count: int, is_player: bool, card_art: String = "") -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 44
	row.add_child(_create_log_image(card_art, Vector2(40, 40)))
	row.add_child(_create_log_arrow())
	row.add_child(_create_log_text("ALL", Color(1.0, 0.6, 0.3), 11))
	row.add_child(_create_log_text(str(total_damage) + " DMG", Color(1.0, 0.4, 0.4), 13))
	_add_visual_log_entry(row)

func _log_heal(source_name: String, card_name: String, target_name: String, amount: int, is_player: bool, card_art: String = "", target_portrait: String = "") -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 44
	row.add_child(_create_log_image(card_art, Vector2(40, 40)))
	row.add_child(_create_log_arrow())
	row.add_child(_create_log_image(target_portrait, Vector2(36, 36)))
	row.add_child(_create_log_text("+" + str(amount) + " HP", Color(0.4, 1.0, 0.4), 13))
	_add_visual_log_entry(row)

func _log_buff(source_name: String, card_name: String, target_name: String, effect_text: String, is_player: bool, card_art: String = "", target_portrait: String = "") -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 44
	row.add_child(_create_log_image(card_art, Vector2(40, 40)))
	row.add_child(_create_log_arrow())
	row.add_child(_create_log_image(target_portrait, Vector2(36, 36)))
	row.add_child(_create_log_text(effect_text, Color(1.0, 0.87, 0.4), 12))
	_add_visual_log_entry(row)

func _log_death(hero_name: String, is_player: bool, hero_portrait: String = "") -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 44
	row.add_child(_create_log_image(hero_portrait, Vector2(36, 36)))
	row.add_child(_create_log_text(hero_name + " DEFEATED!", Color(1.0, 0.27, 0.27), 13))
	_add_visual_log_entry(row)

func _log_ex_skill(source_name: String, target_name: String, is_player: bool, source_portrait: String = "", target_portrait: String = "") -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 44
	row.add_child(_create_log_image(source_portrait, Vector2(36, 36)))
	row.add_child(_create_log_text("EX", Color(1.0, 0.67, 0.0), 14))
	row.add_child(_create_log_arrow())
	row.add_child(_create_log_image(target_portrait, Vector2(36, 36)))
	_add_visual_log_entry(row)

func _log_equip(card_art: String, target_portrait: String, equip_name: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 44
	row.add_child(_create_log_image(card_art, Vector2(40, 40)))
	row.add_child(_create_log_arrow())
	row.add_child(_create_log_image(target_portrait, Vector2(36, 36)))
	row.add_child(_create_log_text("Equipped " + equip_name, Color(0.6, 0.85, 1.0), 12))
	_add_visual_log_entry(row)

func _log_deck_action(card_art: String, found_card_art: String, action_text: String) -> void:
	# For dig, search, check_discard — shows card played → card found → result
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 44
	row.add_child(_create_log_image(card_art, Vector2(40, 40)))
	row.add_child(_create_log_arrow())
	row.add_child(_create_log_image(found_card_art, Vector2(36, 36)))
	row.add_child(_create_log_text(action_text, Color(0.7, 0.85, 1.0), 12))
	_add_visual_log_entry(row)

func _log_status(hero_portrait: String, status_text: String, color: Color = Color(1.0, 0.87, 0.4)) -> void:
	# Generic status effect log: [Hero Portrait] status text
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 36
	row.add_child(_create_log_image(hero_portrait, Vector2(30, 30)))
	row.add_child(_create_log_text(status_text, color, 11))
	_add_visual_log_entry(row)

func _log_event(text: String, color: Color = Color(0.75, 0.72, 0.65)) -> void:
	# Simple text-only log for misc events (draw, shuffle, etc.)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 24
	row.add_child(_create_log_text("  " + text, color, 11))
	_add_visual_log_entry(row)

# ============================================
# PRACTICE MODE UI
# ============================================

func _setup_practice_ui() -> void:
	# Create a side panel with practice tools
	practice_panel = PanelContainer.new()
	practice_panel.position = Vector2(10, 80)
	practice_panel.z_index = 50
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.1, 0.85)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.6, 1.0, 0.6)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	practice_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(practice_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	practice_panel.add_child(vbox)
	practice_panel_vbox = vbox
	
	# Title — clickable to collapse, draggable to move panel
	var title_btn = Button.new()
	title_btn.text = "PRACTICE"
	title_btn.custom_minimum_size = Vector2(100, 24)
	title_btn.add_theme_font_size_override("font_size", 14)
	title_btn.mouse_default_cursor_shape = Control.CURSOR_MOVE
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = Color(0.1, 0.15, 0.3, 0.9)
	title_style.corner_radius_top_left = 6
	title_style.corner_radius_top_right = 6
	title_style.corner_radius_bottom_left = 6
	title_style.corner_radius_bottom_right = 6
	title_btn.add_theme_stylebox_override("normal", title_style)
	var title_hover = title_style.duplicate()
	title_hover.bg_color = Color(0.15, 0.2, 0.4, 0.9)
	title_btn.add_theme_stylebox_override("hover", title_hover)
	title_btn.add_theme_stylebox_override("pressed", title_hover)
	title_btn.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	title_btn.gui_input.connect(_on_practice_title_gui_input)
	vbox.add_child(title_btn)
	
	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# --- Selected hero label ---
	_practice_selected_label = Label.new()
	_practice_selected_label.text = ">> None"
	_practice_selected_label.add_theme_font_size_override("font_size", 11)
	_practice_selected_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	vbox.add_child(_practice_selected_label)
	
	# --- Spawn buttons ---
	_add_practice_button(vbox, "+ Enemy", _on_practice_add_enemy, Color(0.8, 0.3, 0.3))
	_add_practice_button(vbox, "+ Ally", _on_practice_add_ally, Color(0.3, 0.7, 0.4))
	_practice_replace_btn = _add_practice_button(vbox, "Replace Hero", _on_practice_replace_hero, Color(0.7, 0.5, 0.9))
	_practice_replace_btn.disabled = true
	
	# Separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)
	
	# --- Resource buttons ---
	_add_practice_button(vbox, "Fill EX", _on_practice_fill_ex, Color(0.9, 0.7, 0.2))
	_add_practice_button(vbox, "Reset HP", _on_practice_reset_hp, Color(0.3, 0.8, 0.5))
	_add_practice_button(vbox, "Clear Status", _on_practice_clear_status, Color(0.9, 0.4, 0.4))
	_add_practice_button(vbox, "Draw Card", _on_practice_draw_card, Color(0.6, 0.5, 0.8))
	_add_practice_button(vbox, "Redeck", _on_practice_redeck, Color(0.4, 0.6, 0.9))
	_add_practice_button(vbox, "+ Equip", _on_practice_add_equipment, Color(0.85, 0.6, 0.2))
	
	# Separator
	var sep3 = HSeparator.new()
	vbox.add_child(sep3)
	
	# --- Toggle & Turn buttons ---
	_practice_unli_mana_btn = _add_practice_button(vbox, "Unli Mana: OFF", _on_practice_toggle_unli_mana, Color(0.3, 0.5, 0.9))
	_add_practice_button(vbox, "Skip Turn", _on_practice_skip_turn, Color(0.6, 0.6, 0.6))
	
	# Separator
	var sep4 = HSeparator.new()
	vbox.add_child(sep4)
	
	# --- Exit ---
	_add_practice_button(vbox, "Exit", _on_practice_exit, Color(0.7, 0.3, 0.3))

func _add_practice_button(parent: VBoxContainer, text: String, callback: Callable, accent: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 28)
	btn.add_theme_font_size_override("font_size", 12)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	var style = StyleBoxFlat.new()
	style.bg_color = accent.darkened(0.6)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = accent.darkened(0.2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style)
	
	var hover = style.duplicate()
	hover.bg_color = accent.darkened(0.4)
	hover.border_color = accent
	btn.add_theme_stylebox_override("hover", hover)
	
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

var _practice_drag_started_pos: Vector2 = Vector2.ZERO

func _on_practice_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				practice_panel_dragging = true
				practice_panel_drag_offset = practice_panel.position - event.global_position
				_practice_drag_started_pos = event.global_position
			else:
				# If released without significant movement, treat as click → collapse
				var moved = event.global_position.distance_to(_practice_drag_started_pos)
				if moved < 5.0:
					_toggle_practice_panel_collapse()
				practice_panel_dragging = false
	elif event is InputEventMouseMotion and practice_panel_dragging:
		practice_panel.position = event.global_position + practice_panel_drag_offset

func _toggle_practice_panel_collapse() -> void:
	practice_panel_collapsed = not practice_panel_collapsed
	if practice_panel_vbox:
		for i in range(1, practice_panel_vbox.get_child_count()):
			practice_panel_vbox.get_child(i).visible = not practice_panel_collapsed
		var title_btn = practice_panel_vbox.get_child(0) as Button
		if title_btn:
			title_btn.text = "PRACTICE ▶" if practice_panel_collapsed else "PRACTICE"
	# Force panel to shrink when collapsed
	if practice_panel:
		practice_panel.reset_size()

func _on_practice_add_enemy() -> void:
	if enemy_heroes.size() >= 4:
		print("[Practice] Max 4 enemies")
		return
	_practice_spawn_is_player = false
	_show_hero_picker_modal("Choose Enemy")

func _on_practice_add_ally() -> void:
	if player_heroes.size() >= 4:
		print("[Practice] Max 4 allies")
		return
	_practice_spawn_is_player = true
	_show_hero_picker_modal("Choose Ally")

func _show_hero_picker_modal(title_text: String) -> void:
	if practice_hero_picker and is_instance_valid(practice_hero_picker):
		practice_hero_picker.queue_free()
	
	practice_hero_picker = CanvasLayer.new()
	practice_hero_picker.layer = 100
	add_child(practice_hero_picker)
	
	# Dim background
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	practice_hero_picker.add_child(dim)
	
	# Center panel
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.14, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.6, 1.0, 0.7)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# Center the panel
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	practice_hero_picker.add_child(center)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	# Title row with close button
	var title_row = HBoxContainer.new()
	vbox.add_child(title_row)
	
	var title_label = Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(_close_hero_picker)
	title_row.add_child(close_btn)
	
	# Hero grid
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	
	# Collect heroes already on the field
	var used_ids = []
	for h in player_heroes:
		used_ids.append(h.hero_id)
	for h in enemy_heroes:
		used_ids.append(h.hero_id)
	
	# Add all heroes as selectable thumbnails
	for hero_id in HeroDatabase.heroes.keys():
		var hero_data = HeroDatabase.get_hero(hero_id)
		var is_on_field = hero_id in used_ids
		var thumb = _create_picker_thumbnail(hero_id, hero_data, is_on_field)
		grid.add_child(thumb)

func _create_picker_thumbnail(hero_id: String, hero_data: Dictionary, is_on_field: bool) -> Control:
	var thumb_size = 80
	var container = Control.new()
	container.custom_minimum_size = Vector2(thumb_size, thumb_size + 20)
	
	# Border panel with role color
	var border = Panel.new()
	border.custom_minimum_size = Vector2(thumb_size, thumb_size)
	border.position = Vector2(0, 0)
	var style = StyleBoxFlat.new()
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = role_color if not is_on_field else role_color.darkened(0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	border.add_theme_stylebox_override("panel", style)
	container.add_child(border)
	
	# Portrait
	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(thumb_size - 6, thumb_size - 6)
	portrait.position = Vector2(3, 3)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path = hero_data.get("portrait", "")
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	if is_on_field:
		portrait.modulate = Color(0.5, 0.5, 0.5, 0.7)
	container.add_child(portrait)
	
	# Name label
	var name_label = Label.new()
	name_label.text = hero_data.get("name", hero_id)
	name_label.position = Vector2(0, thumb_size + 2)
	name_label.custom_minimum_size = Vector2(thumb_size, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	if is_on_field:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	container.add_child(name_label)
	
	# Clickable button overlay
	var btn = Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(thumb_size, thumb_size)
	btn.position = Vector2(0, 0)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_hero_picker_selected.bind(hero_id))
	container.add_child(btn)
	
	return container

func _on_hero_picker_selected(hero_id: String) -> void:
	# Grab the replacing ref BEFORE closing the picker (close clears it)
	var replacing = _practice_replacing_hero
	_practice_replacing_hero = null
	_close_hero_picker()
	# Check if we're replacing an existing hero (use stored ref — _practice_selected_hero may have been cleared)
	if replacing and is_instance_valid(replacing):
		_practice_selected_hero = replacing
		_practice_replace_selected_hero(hero_id)
	else:
		_practice_spawn_hero(hero_id, _practice_spawn_is_player)

func _close_hero_picker() -> void:
	if practice_hero_picker and is_instance_valid(practice_hero_picker):
		practice_hero_picker.queue_free()
		practice_hero_picker = null
	# If closing without selecting (e.g. X button), clear the replacing flag
	# (This is safe — if a hero was selected, _on_hero_picker_selected already consumed it)
	_practice_replacing_hero = null

func _practice_spawn_hero(hero_id: String, as_player: bool) -> void:
	if as_player:
		var positions = PLAYER_HERO_POSITIONS
		var z_indices = PLAYER_HERO_Z_INDEX
		var idx = player_heroes.size()
		
		var hero_instance = hero_scene.instantiate()
		$Board.add_child(hero_instance)
		hero_instance.setup(hero_id)
		hero_instance.is_player_hero = true
		hero_instance.team_index = idx
		hero_instance.instance_id = "p_" + hero_id + "_" + str(idx) + "_" + str(randi() % 1000)
		hero_instance.hero_clicked.connect(_on_hero_clicked)
		hero_instance.hero_died.connect(_on_hero_died)
		hero_instance.shield_broken.connect(_on_shield_broken)
		hero_instance.counter_triggered.connect(_on_counter_triggered)
		player_heroes.append(hero_instance)
		hero_instance.global_position = positions[idx]
		hero_instance.z_index = z_indices[idx]
		
		GameManager.player_heroes = player_heroes
		GameManager.init_hero_stats(hero_instance.instance_id, true, hero_instance.hero_data.get("portrait", ""), hero_instance.hero_data.get("name", "Hero"))
		
		# Rebuild player deck using instances (supports duplicate heroes, skip dead)
		var alive_players = player_heroes.filter(func(h): return not h.is_dead)
		GameManager.build_deck_from_instances(alive_players, false)
		var cards_to_draw = min(3, GameConstants.HAND_SIZE - GameManager.hand.size())
		if cards_to_draw > 0:
			GameManager.draw_cards(cards_to_draw)
		_refresh_hand()
		print("[Practice] Added ally: ", hero_id, " (", hero_instance.instance_id, ")")
	else:
		var positions = ENEMY_HERO_POSITIONS
		var z_indices = ENEMY_HERO_Z_INDEX
		var idx = enemy_heroes.size()
		
		var hero_instance = hero_scene.instantiate()
		$Board.add_child(hero_instance)
		hero_instance.setup(hero_id)
		hero_instance.is_player_hero = false
		hero_instance.team_index = idx
		hero_instance.instance_id = "e_" + hero_id + "_" + str(idx) + "_" + str(randi() % 1000)
		hero_instance.hero_clicked.connect(_on_hero_clicked)
		hero_instance.hero_died.connect(_on_hero_died)
		hero_instance.shield_broken.connect(_on_shield_broken)
		hero_instance.counter_triggered.connect(_on_counter_triggered)
		enemy_heroes.append(hero_instance)
		hero_instance.global_position = positions[idx]
		hero_instance.z_index = z_indices[idx]
		hero_instance.flip_sprite()
		
		GameManager.enemy_heroes = enemy_heroes
		GameManager.init_hero_stats(hero_instance.instance_id, false, hero_instance.hero_data.get("portrait", ""), hero_instance.hero_data.get("name", "Hero"))
		
		# Rebuild enemy deck using instances (supports duplicate heroes, skip dead)
		var alive_enemies = enemy_heroes.filter(func(h): return not h.is_dead)
		GameManager.build_enemy_deck_from_instances(alive_enemies)
		GameManager.enemy_draw_cards(5)
		_refresh_enemy_hand_display()
		print("[Practice] Added enemy: ", hero_id, " (", hero_instance.instance_id, ")")

func _on_practice_toggle_unli_mana() -> void:
	_practice_unli_mana = not _practice_unli_mana
	if _practice_unli_mana_btn:
		_practice_unli_mana_btn.text = "Unli Mana: ON" if _practice_unli_mana else "Unli Mana: OFF"
	if _practice_unli_mana:
		# Immediately fill both teams' mana
		GameManager.current_mana = GameManager.MANA_CAP
		GameManager.max_mana = GameManager.MANA_CAP
		GameManager.enemy_current_mana = GameManager.MANA_CAP
		GameManager.enemy_max_mana = GameManager.MANA_CAP
		GameManager.mana_changed.emit(GameManager.current_mana, GameManager.max_mana)
	print("[Practice] Unlimited mana: ", "ON" if _practice_unli_mana else "OFF")

func _on_practice_fill_ex() -> void:
	if _practice_selected_hero:
		_practice_selected_hero.energy = _practice_selected_hero.max_energy
		_practice_selected_hero._update_ui()
		print("[Practice] EX filled: ", _practice_selected_hero.hero_data.get("name", "Hero"))
	else:
		var team = enemy_heroes if _practice_controlling_enemy else player_heroes
		for hero in team:
			hero.energy = hero.max_energy
			hero._update_ui()
		var side = "enemy" if _practice_controlling_enemy else "player"
		print("[Practice] All ", side, " heroes EX filled")

func _on_practice_reset_hp() -> void:
	if _practice_selected_hero:
		_practice_selected_hero.current_hp = _practice_selected_hero.max_hp
		_practice_selected_hero.block = 0
		_practice_selected_hero.is_dead = false
		_practice_selected_hero.visible = true
		_practice_selected_hero.modulate.a = 1.0
		if _practice_selected_hero.hp_bar:
			_practice_selected_hero.hp_bar.visible = true
		if _practice_selected_hero.energy_bar:
			_practice_selected_hero.energy_bar.visible = true
		_practice_selected_hero._update_ui()
		print("[Practice] HP reset: ", _practice_selected_hero.hero_data.get("name", "Hero"))
	else:
		var team = enemy_heroes if _practice_controlling_enemy else player_heroes
		for hero in team:
			hero.current_hp = hero.max_hp
			hero.block = 0
			hero.is_dead = false
			hero.visible = true
			hero.modulate.a = 1.0
			if hero.hp_bar:
				hero.hp_bar.visible = true
			if hero.energy_bar:
				hero.energy_bar.visible = true
			hero._update_ui()
		var side = "enemy" if _practice_controlling_enemy else "player"
		print("[Practice] All ", side, " heroes HP reset")

func _on_practice_clear_status() -> void:
	if _practice_selected_hero:
		_practice_selected_hero.clear_all_buffs_and_debuffs()
		_practice_selected_hero._update_ui()
		print("[Practice] Status cleared: ", _practice_selected_hero.hero_data.get("name", "Hero"))
	else:
		var team = enemy_heroes if _practice_controlling_enemy else player_heroes
		for hero in team:
			hero.clear_all_buffs_and_debuffs()
			hero._update_ui()
		var side = "enemy" if _practice_controlling_enemy else "player"
		print("[Practice] All ", side, " heroes status cleared")

func _on_practice_draw_card() -> void:
	if _practice_controlling_enemy:
		var drawn = GameManager.enemy_draw_cards(1)
		if drawn.size() > 0:
			_practice_show_enemy_hand()
			print("[Practice] Enemy drew 1 card")
		else:
			GameManager.enemy_reshuffle_discard_into_deck()
			drawn = GameManager.enemy_draw_cards(1)
			if drawn.size() > 0:
				_practice_show_enemy_hand()
				print("[Practice] Enemy reshuffled and drew 1 card")
			else:
				print("[Practice] No enemy cards to draw")
	else:
		var drawn = GameManager.draw_cards(1)
		if drawn.size() > 0:
			_refresh_hand()
			print("[Practice] Drew 1 card")
		else:
			GameManager.reshuffle_discard_into_deck()
			drawn = GameManager.draw_cards(1)
			if drawn.size() > 0:
				_refresh_hand()
				print("[Practice] Reshuffled and drew 1 card")
			else:
				print("[Practice] No cards to draw")

func _on_practice_redeck() -> void:
	if _practice_controlling_enemy:
		var alive_enemies = enemy_heroes.filter(func(h): return not h.is_dead)
		GameManager.enemy_redeck_from_instances(alive_enemies)
		var deck_size = GameManager.enemy_deck.size()
		_update_deck_display()
		print("[Practice] Enemy redecked — " + str(deck_size) + " cards in deck")
	else:
		var alive_players = player_heroes.filter(func(h): return not h.is_dead)
		GameManager.redeck_from_instances(alive_players, false)
		var deck_size = GameManager.deck.size()
		_update_deck_display()
		print("[Practice] Player redecked — " + str(deck_size) + " cards in deck")

func _on_practice_skip_turn() -> void:
	_on_end_turn_pressed()
	print("[Practice] Turn skipped")

func _on_practice_add_equipment() -> void:
	_show_equipment_picker_modal()

func _on_practice_replace_hero() -> void:
	if not _practice_selected_hero:
		print("[Practice] No hero selected to replace")
		return
	# Store the hero to replace so it survives even if _practice_selected_hero gets deselected
	_practice_replacing_hero = _practice_selected_hero
	_practice_spawn_is_player = _practice_selected_hero.is_player_hero
	_show_hero_picker_modal("Replace: " + _practice_selected_hero.hero_data.get("name", "Hero"))

func _practice_replace_selected_hero(new_hero_id: String) -> void:
	var old_hero = _practice_selected_hero
	if not old_hero or not is_instance_valid(old_hero):
		_practice_deselect()
		return
	
	var is_player = old_hero.is_player_hero
	var old_pos = old_hero.global_position
	var old_z = old_hero.z_index
	var old_idx = old_hero.team_index
	var old_flipped = not is_player
	var old_name = old_hero.hero_data.get("name", "Hero")
	
	# Remove old hero from array
	var arr = player_heroes if is_player else enemy_heroes
	var arr_index = arr.find(old_hero)
	if arr_index >= 0:
		arr.remove_at(arr_index)
	
	# Remove old hero's cards from hand/deck/discard
	if is_player:
		_practice_remove_hero_cards(old_hero, false)
	else:
		_practice_remove_hero_cards(old_hero, true)
	
	# Deselect and destroy old hero
	_practice_deselect()
	old_hero.queue_free()
	
	# Spawn new hero at the same position
	var hero_instance = hero_scene.instantiate()
	$Board.add_child(hero_instance)
	hero_instance.setup(new_hero_id)
	hero_instance.is_player_hero = is_player
	hero_instance.team_index = old_idx
	var prefix = "p_" if is_player else "e_"
	hero_instance.instance_id = prefix + new_hero_id + "_" + str(old_idx) + "_" + str(randi() % 1000)
	hero_instance.hero_clicked.connect(_on_hero_clicked)
	hero_instance.hero_died.connect(_on_hero_died)
	hero_instance.shield_broken.connect(_on_shield_broken)
	hero_instance.counter_triggered.connect(_on_counter_triggered)
	hero_instance.global_position = old_pos
	hero_instance.z_index = old_z
	if old_flipped:
		hero_instance.flip_sprite()
	
	# Insert into array at the same index
	if arr_index >= 0 and arr_index <= arr.size():
		arr.insert(arr_index, hero_instance)
	else:
		arr.append(hero_instance)
	
	# Update GameManager references
	GameManager.player_heroes = player_heroes
	GameManager.enemy_heroes = enemy_heroes
	GameManager.init_hero_stats(hero_instance.instance_id, is_player, hero_instance.hero_data.get("portrait", ""), hero_instance.hero_data.get("name", "Hero"))
	
	# Rebuild deck for the affected team
	if is_player:
		GameManager.build_deck_from_instances(player_heroes, false)
		_refresh_hand()
	else:
		GameManager.build_enemy_deck_from_instances(enemy_heroes)
		_refresh_enemy_hand_display()
		if _practice_controlling_enemy:
			_practice_show_enemy_hand()
	
	print("[Practice] Replaced ", old_name, " with ", hero_instance.hero_data.get("name", new_hero_id))

func _practice_remove_hero_cards(hero: Hero, is_enemy: bool) -> void:
	var hid = hero.hero_id
	var iid = hero.instance_id
	if is_enemy:
		GameManager.enemy_hand = GameManager.enemy_hand.filter(func(c): return c.get("hero_id", "") != hid and c.get("instance_id", "").find(iid) == -1)
		GameManager.enemy_deck = GameManager.enemy_deck.filter(func(c): return c.get("hero_id", "") != hid and c.get("instance_id", "").find(iid) == -1)
		GameManager.enemy_discard_pile = GameManager.enemy_discard_pile.filter(func(c): return c.get("hero_id", "") != hid and c.get("instance_id", "").find(iid) == -1)
	else:
		GameManager.hand = GameManager.hand.filter(func(c): return c.get("hero_id", "") != hid and c.get("instance_id", "").find(iid) == -1)
		GameManager.deck = GameManager.deck.filter(func(c): return c.get("hero_id", "") != hid and c.get("instance_id", "").find(iid) == -1)
		GameManager.discard_pile = GameManager.discard_pile.filter(func(c): return c.get("hero_id", "") != hid and c.get("instance_id", "").find(iid) == -1)

func _show_equipment_picker_modal() -> void:
	if practice_hero_picker and is_instance_valid(practice_hero_picker):
		practice_hero_picker.queue_free()
	
	practice_hero_picker = CanvasLayer.new()
	practice_hero_picker.layer = 100
	add_child(practice_hero_picker)
	
	# Dim background
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	practice_hero_picker.add_child(dim)
	
	# Center panel
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.14, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.85, 0.6, 0.2, 0.7)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 16
	panel_style.content_margin_right = 16
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	practice_hero_picker.add_child(center)
	center.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	# Title row with close button
	var title_row = HBoxContainer.new()
	vbox.add_child(title_row)
	
	var title_label = Label.new()
	title_label.text = "Choose Equipment"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.2))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(_close_hero_picker)
	title_row.add_child(close_btn)
	
	# Equipment grid
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	
	var all_equips = EquipmentDatabase.get_all_equipments()
	for equip_id in all_equips.keys():
		var equip_data = all_equips[equip_id]
		var thumb = _create_equip_thumbnail(equip_id, equip_data)
		grid.add_child(thumb)

func _create_equip_thumbnail(equip_id: String, equip_data: Dictionary) -> Control:
	var thumb_size = 80
	var container = Control.new()
	container.custom_minimum_size = Vector2(thumb_size, thumb_size + 20)
	
	# Border panel
	var border = Panel.new()
	border.custom_minimum_size = Vector2(thumb_size, thumb_size)
	border.position = Vector2(0, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.95)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.85, 0.6, 0.2, 0.8)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	border.add_theme_stylebox_override("panel", style)
	container.add_child(border)
	
	# Equipment art
	var art = TextureRect.new()
	art.custom_minimum_size = Vector2(thumb_size - 6, thumb_size - 6)
	art.position = Vector2(3, 3)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var art_path = equip_data.get("art", equip_data.get("image", ""))
	if ResourceLoader.exists(art_path):
		art.texture = load(art_path)
	container.add_child(art)
	
	# Name label
	var name_label = Label.new()
	name_label.text = equip_data.get("name", equip_id)
	name_label.position = Vector2(0, thumb_size + 2)
	name_label.custom_minimum_size = Vector2(thumb_size, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	container.add_child(name_label)
	
	# Clickable button overlay
	var btn = Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(thumb_size, thumb_size)
	btn.position = Vector2(0, 0)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_equip_picker_selected.bind(equip_id))
	container.add_child(btn)
	
	return container

func _on_equip_picker_selected(equip_id: String) -> void:
	_close_hero_picker()
	var equip_data = EquipmentDatabase.get_equipment(equip_id)
	if equip_data.is_empty():
		print("[Practice] Equipment not found: ", equip_id)
		return
	# Create a card copy and add it directly to the active hand
	var equip_card = equip_data.duplicate()
	equip_card["base_id"] = equip_id
	equip_card["id"] = equip_id + "_practice_" + str(randi())
	equip_card["instance_id"] = equip_card["id"]
	var active_hand_eq = GameManager.enemy_hand if _practice_controlling_enemy else GameManager.hand
	active_hand_eq.append(equip_card)
	_refresh_hand()
	print("[Practice] Added equipment to hand: ", equip_data.get("name", equip_id))

# ============================================
# PRACTICE MODE — HERO SELECTION & TOOLS
# ============================================

func _practice_toggle_select(hero: Hero) -> void:
	if _practice_selected_hero == hero:
		_practice_deselect()
	else:
		_practice_deselect()
		_practice_selected_hero = hero
		# Add highlight
		_practice_select_highlight = ColorRect.new()
		_practice_select_highlight.color = Color(0.3, 0.7, 1.0, 0.25)
		_practice_select_highlight.size = hero.size
		_practice_select_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero.add_child(_practice_select_highlight)
		# Update label
		if _practice_selected_label:
			_practice_selected_label.text = ">> " + hero.hero_data.get("name", "Hero")
		# Enable replace button
		if _practice_replace_btn:
			_practice_replace_btn.disabled = false
		print("[Practice] Selected: ", hero.hero_data.get("name", "Hero"))

func _practice_deselect() -> void:
	if _practice_select_highlight and is_instance_valid(_practice_select_highlight):
		_practice_select_highlight.queue_free()
	_practice_select_highlight = null
	_practice_selected_hero = null
	if _practice_selected_label:
		_practice_selected_label.text = ">> None"
	if _practice_replace_btn:
		_practice_replace_btn.disabled = true

func _on_practice_exit() -> void:
	# Clean up practice mode and return to collection
	is_practice_mode = false
	_practice_controlling_enemy = false
	HeroDatabase.practice_mode = false
	SceneTransition.change_scene("res://scenes/collection/collection_new.tscn")

# ============================================
# PRACTICE MODE — ENEMY HAND CONTROL
# ============================================

func _practice_show_enemy_hand() -> void:
	# Clear current hand display and populate with enemy cards
	for child in hand_container.get_children():
		if is_instance_valid(child):
			child.queue_free()
	
	for card_data in GameManager.enemy_hand:
		var card_instance = card_scene.instantiate()
		hand_container.add_child(card_instance)
		card_instance.setup(card_data)
		card_instance.card_clicked.connect(_on_card_clicked)
		
		# Apply frost cost modifier
		var source_hero_frost = _get_source_hero(card_data)
		if source_hero_frost and source_hero_frost.has_debuff("frost"):
			card_instance.update_display_cost(1)
		
		var source_hero = _get_source_hero(card_data)
		var can_play = card_instance.can_play(GameManager.enemy_current_mana) and _can_pay_hp_cost(card_data, source_hero)
		card_instance.set_playable(can_play)
		# Show stun overlay if source hero is stunned
		if source_hero and source_hero.is_stunned():
			card_instance.set_stunned(true)
	
	_update_deck_display()

func _practice_end_enemy_turn() -> void:
	# Mirror of player turn end but for enemy heroes
	end_turn_button.disabled = true
	
	# Detonate Time Bombs on ENEMY heroes (bombs placed by player, expire at enemy's own_turn_end)
	_detonate_time_bombs(enemy_heroes, false)
	
	# Enemy's heroes: remove "own_turn_end" buffs/debuffs
	for enemy in enemy_heroes:
		if not enemy.is_dead:
			enemy.on_own_turn_end()
	# Player's heroes: remove "opponent_turn_end" buffs/debuffs
	for hero in player_heroes:
		if not hero.is_dead:
			hero.on_opponent_turn_end()
	# Refresh hand descriptions after buffs expire
	_refresh_hand_descriptions()
	
	# Trigger Thunder damage on ALL heroes at end of enemy turn
	await _trigger_thunder_damage(player_heroes)
	await _trigger_thunder_damage(enemy_heroes)
	
	# Clear PLAYER shields at end of enemy turn (player used them last turn)
	for hero in player_heroes:
		if hero.block > 0:
			if hero.has_buff("dana_shield_draw"):
				hero.remove_buff("dana_shield_draw")
				GameManager.draw_cards(1)
				print("[Dana Shield Draw] " + hero.hero_data.get("name", "Hero") + " (player) shield expired → draw 1")
			hero.block = 0
			hero._update_ui()
			hero._hide_shield_effect()
	
	# Reset enemy control flag before transitioning
	_practice_controlling_enemy = false
	
	# Restore player hand display
	_refresh_hand()
	
	current_phase = BattlePhase.ENEMY_TURN
	GameManager.end_enemy_turn()
