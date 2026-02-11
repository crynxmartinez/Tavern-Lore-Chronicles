extends Control

# Collection scene - view heroes, poses, cards, and skins

enum CollectionTab { HEROES, CARDS, OTHERS }

var current_tab: CollectionTab = CollectionTab.HEROES
var selected_hero_id: String = ""
var hero_thumbnails: Dictionary = {}
var skin_buttons: Array = []
var roster_container: HBoxContainer
var skins_container: VBoxContainer
var heroes_btn: Button
var cards_btn: Button
var others_btn: Button
var placeholder_panel: Panel = null
var cards_content: Control = null
var cards_hero_roster: HBoxContainer = null
var cards_hero_thumbnails: Dictionary = {}
var cards_display_container: HBoxContainer = null
var selected_cards_hero_id: String = ""

@onready var back_button: Button = $UI/MainLayout/ContentArea/TopBar/BackButton
@onready var practice_button: Button = $UI/MainLayout/ContentArea/TopBar/PracticeButton
@onready var left_menu: Panel = $UI/MainLayout/LeftMenu
@onready var left_menu_vbox: VBoxContainer = $UI/MainLayout/LeftMenu/VBox
@onready var hero_roster_panel: Panel = $UI/MainLayout/ContentArea/HeroRoster
@onready var hero_roster: HBoxContainer = $UI/MainLayout/ContentArea/HeroRoster/VBox/ScrollContainer/HeroContainer
@onready var hero_scroll: ScrollContainer = $UI/MainLayout/ContentArea/HeroRoster/VBox/ScrollContainer
@onready var pose_idle: Panel = $UI/MainLayout/ContentArea/PosesArea/PosesContainer/Pose_IDLE
@onready var pose_hit: Panel = $UI/MainLayout/ContentArea/PosesArea/PosesContainer/Pose_HIT
@onready var pose_cast: Panel = $UI/MainLayout/ContentArea/PosesArea/PosesContainer/Pose_CAST
@onready var pose_attack: Panel = $UI/MainLayout/ContentArea/PosesArea/PosesContainer/Pose_ATTACK
@onready var poses_container: HBoxContainer = $UI/MainLayout/ContentArea/PosesArea/PosesContainer
@onready var right_menu: Panel = $UI/MainLayout/RightMenu
@onready var right_menu_vbox: VBoxContainer = $UI/MainLayout/RightMenu/VBox

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_setup_practice_button()
	_hide_scrollbars()
	_setup_left_menu()
	_setup_hero_roster()
	_setup_skins_container()
	_select_first_hero()

func _hide_scrollbars() -> void:
	var h_scroll = hero_scroll.get_h_scroll_bar()
	if h_scroll:
		h_scroll.modulate.a = 0

func _setup_left_menu() -> void:
	# Add tab buttons to the VBox inside left menu
	heroes_btn = Button.new()
	heroes_btn.text = "HEROES"
	heroes_btn.custom_minimum_size = Vector2(0, 35)
	heroes_btn.toggle_mode = true
	heroes_btn.button_pressed = true
	heroes_btn.pressed.connect(_on_heroes_tab_pressed)
	left_menu_vbox.add_child(heroes_btn)
	
	cards_btn = Button.new()
	cards_btn.text = "CARDS"
	cards_btn.custom_minimum_size = Vector2(0, 35)
	cards_btn.toggle_mode = true
	cards_btn.pressed.connect(_on_cards_tab_pressed)
	left_menu_vbox.add_child(cards_btn)
	
	others_btn = Button.new()
	others_btn.text = "OTHERS"
	others_btn.custom_minimum_size = Vector2(0, 35)
	others_btn.toggle_mode = true
	others_btn.pressed.connect(_on_others_tab_pressed)
	left_menu_vbox.add_child(others_btn)

func _setup_hero_roster() -> void:
	# Clear existing children from the HBoxContainer
	for child in hero_roster.get_children():
		child.queue_free()
	
	# Add hero thumbnails directly to the HBoxContainer (inside ScrollContainer)
	for hero_id in HeroDatabase.heroes.keys():
		var hero_data = HeroDatabase.get_hero(hero_id)
		var thumbnail = _create_hero_thumbnail(hero_id, hero_data)
		hero_roster.add_child(thumbnail)
		hero_thumbnails[hero_id] = thumbnail
	
	# Store reference for compatibility
	roster_container = hero_roster

func _create_hero_thumbnail(hero_id: String, hero_data: Dictionary) -> Control:
	var thumb_size = 70
	var container = Control.new()
	container.custom_minimum_size = Vector2(thumb_size, thumb_size + 18)
	container.set_meta("hero_id", hero_id)
	
	var border = Panel.new()
	border.custom_minimum_size = Vector2(thumb_size, thumb_size)
	border.position = Vector2(0, 0)
	
	var style = StyleBoxFlat.new()
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = role_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	border.add_theme_stylebox_override("panel", style)
	border.name = "Border"
	container.add_child(border)
	
	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(thumb_size - 6, thumb_size - 6)
	portrait.position = Vector2(3, 3)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path = hero_data.get("portrait", "")
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	container.add_child(portrait)
	
	var name_label = Label.new()
	name_label.text = hero_data.get("name", hero_id)
	name_label.position = Vector2(0, thumb_size + 2)
	name_label.custom_minimum_size = Vector2(thumb_size, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	container.add_child(name_label)
	
	var button = Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(thumb_size, thumb_size)
	button.position = Vector2(0, 0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_hero_selected.bind(hero_id))
	container.add_child(button)
	
	return container

func _setup_practice_button() -> void:
	practice_button.pressed.connect(_on_practice_pressed)
	practice_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	practice_button.add_theme_font_size_override("font_size", 13)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.3, 0.5, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.6, 1.0, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	practice_button.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = Color(0.18, 0.4, 0.6, 0.95)
	hover.border_color = Color(0.4, 0.7, 1.0)
	practice_button.add_theme_stylebox_override("hover", hover)

func _setup_skins_container() -> void:
	# Create skins container inside the right menu VBox (after the label)
	skins_container = VBoxContainer.new()
	skins_container.add_theme_constant_override("separation", 8)
	right_menu_vbox.add_child(skins_container)

func _select_first_hero() -> void:
	var keys = HeroDatabase.heroes.keys()
	if keys.size() > 0:
		_on_hero_selected(keys[0])

func _on_hero_selected(hero_id: String) -> void:
	selected_hero_id = hero_id
	_update_hero_selection_visuals()
	
	if current_tab == CollectionTab.HEROES:
		_display_hero_poses(hero_id)
		_display_hero_skins(hero_id)
	elif current_tab == CollectionTab.CARDS:
		_display_cards_in_pose_panels()

func _update_hero_selection_visuals() -> void:
	for id in hero_thumbnails.keys():
		var thumbnail = hero_thumbnails[id]
		var border = thumbnail.get_node("Border")
		var style = border.get_theme_stylebox("panel").duplicate()
		if id == selected_hero_id:
			style.bg_color = Color(0.3, 0.3, 0.5, 0.9)
		else:
			style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
		border.add_theme_stylebox_override("panel", style)

func _display_hero_poses(hero_id: String) -> void:
	var hero_data = HeroDatabase.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	
	_setup_pose_panel(pose_idle, "IDLE", hero_data.get("idle_sprite", ""), role_color)
	_setup_pose_panel(pose_hit, "HIT", hero_data.get("hit_sprite", ""), role_color)
	_setup_pose_panel(pose_cast, "CAST", hero_data.get("cast_sprite", ""), role_color)
	_setup_pose_panel(pose_attack, "ATTACK", hero_data.get("attack_sprite", ""), role_color)

func _setup_pose_panel(panel: Panel, pose_name: String, sprite_path: String, role_color: Color) -> void:
	# Clear existing children except keep panel style
	for child in panel.get_children():
		child.queue_free()
	
	# Fixed dimensions matching team editor
	var panel_width = 200
	var panel_height = 230  # Same as team editor slot_height
	var label_height = 25
	var ground_y = panel_height + label_height  # Bottom of panel = ground level
	
	# Set panel border color
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.3)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = role_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	
	# Add label at top
	var label = Label.new()
	label.text = pose_name
	label.position = Vector2(0, 5)
	label.custom_minimum_size = Vector2(panel_width, label_height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	panel.add_child(label)
	
	# Add sprite - ORIGINAL SIZE, bottom-center aligned (ground level)
	var sprite = TextureRect.new()
	sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE  # Keep original texture size
	sprite.stretch_mode = TextureRect.STRETCH_KEEP  # No stretching
	sprite.name = "Sprite"
	
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
		# Position sprite: horizontally centered, bottom at ground level
		var tex_size = sprite.texture.get_size()
		sprite.position.x = (panel_width - tex_size.x) / 2
		sprite.position.y = ground_y - tex_size.y
	
	panel.add_child(sprite)

func _display_hero_skins(hero_id: String) -> void:
	# Clear existing skin buttons
	for child in skins_container.get_children():
		child.queue_free()
	skin_buttons.clear()
	
	var hero_data = HeroDatabase.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	var skins = hero_data.get("skins", [])
	var equipped_skin = hero_data.get("equipped_skin", "default")
	
	for skin in skins:
		var skin_button = _create_skin_button(hero_id, skin, equipped_skin)
		skins_container.add_child(skin_button)
		skin_buttons.append(skin_button)

func _create_skin_button(hero_id: String, skin: Dictionary, equipped_skin: String) -> Button:
	var button = Button.new()
	button.custom_minimum_size = Vector2(157, 40)
	button.text = skin.get("name", "Unknown")
	
	var is_equipped = skin.get("id", "") == equipped_skin
	var is_unlocked = skin.get("unlocked", false)
	
	if is_equipped:
		button.text += " [E]"
	if not is_unlocked:
		button.text += " [LOCKED]"
		button.disabled = true
	
	button.pressed.connect(_on_skin_selected.bind(hero_id, skin))
	button.set_meta("skin_id", skin.get("id", ""))
	
	return button

func _on_skin_selected(hero_id: String, skin: Dictionary) -> void:
	if not skin.get("unlocked", false):
		return
	
	var skin_id = skin.get("id", "default")
	HeroDatabase.heroes[hero_id]["equipped_skin"] = skin_id
	
	_display_hero_skins(hero_id)
	_display_hero_poses(hero_id)

func _on_practice_pressed() -> void:
	if selected_hero_id.is_empty():
		return
	# Set practice mode flags
	HeroDatabase.practice_mode = true
	HeroDatabase.practice_hero_id = selected_hero_id
	# Pick a random enemy hero (different from practice hero)
	var all_ids = HeroDatabase.heroes.keys()
	var enemy_ids = all_ids.filter(func(id): return id != selected_hero_id)
	enemy_ids.shuffle()
	HeroDatabase.ai_enemy_team = [enemy_ids[0]]
	HeroDatabase.training_player_first = true
	SceneTransition.change_scene("res://scenes/battle/battle.tscn")

func _on_back_pressed() -> void:
	SceneTransition.change_scene("res://scenes/dashboard/dashboard.tscn")

func _on_heroes_tab_pressed() -> void:
	current_tab = CollectionTab.HEROES
	_update_tab_visuals()

func _on_cards_tab_pressed() -> void:
	current_tab = CollectionTab.CARDS
	_update_tab_visuals()

func _on_others_tab_pressed() -> void:
	current_tab = CollectionTab.OTHERS
	_update_tab_visuals()

func _update_tab_visuals() -> void:
	# Update button states
	heroes_btn.button_pressed = current_tab == CollectionTab.HEROES
	cards_btn.button_pressed = current_tab == CollectionTab.CARDS
	others_btn.button_pressed = current_tab == CollectionTab.OTHERS
	
	# Show/hide content based on tab
	var show_heroes = current_tab == CollectionTab.HEROES
	var show_cards = current_tab == CollectionTab.CARDS
	
	# Hero roster is visible for both Heroes and Cards tabs
	hero_roster_panel.visible = show_heroes or show_cards
	
	# Pose panels container only for Heroes tab
	poses_container.visible = show_heroes
	
	# Right menu for Heroes (skins), Card info for Cards
	right_menu.visible = show_heroes or show_cards
	_update_right_menu_title(show_heroes)
	_toggle_card_info_panel(show_cards)
	
	# Handle Cards tab - use pose panel positions for cards
	if show_cards:
		_display_cards_in_pose_panels()
		_hide_placeholder()
	elif current_tab == CollectionTab.OTHERS:
		_hide_cards_panels()
		_show_placeholder()
	else:
		_hide_cards_panels()
		_hide_placeholder()

func _update_right_menu_title(is_heroes: bool) -> void:
	var label = right_menu_vbox.get_node_or_null("Label")
	if label:
		label.text = "SKINS" if is_heroes else "CARD TEMPLATE"

func _show_placeholder() -> void:
	if placeholder_panel and is_instance_valid(placeholder_panel):
		placeholder_panel.visible = true
		return
	
	var viewport_size = get_viewport_rect().size
	var panel_width = 400.0
	var panel_height = 150.0
	
	placeholder_panel = Panel.new()
	placeholder_panel.position = Vector2((viewport_size.x - panel_width) / 2, (viewport_size.y - panel_height) / 2)
	placeholder_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.5)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	placeholder_panel.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.text = "COMING SOON"
	label.custom_minimum_size = Vector2(panel_width, panel_height)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	placeholder_panel.add_child(label)
	
	add_child(placeholder_panel)

func _hide_placeholder() -> void:
	if placeholder_panel and is_instance_valid(placeholder_panel):
		placeholder_panel.visible = false

var card_panels: Array = []
var card_info_panel: Panel = null
var selected_card_data: Dictionary = {}

func _toggle_card_info_panel(show: bool) -> void:
	# Hide skins container when showing cards
	if skins_container:
		skins_container.visible = not show
	
	if show:
		_populate_template_buttons()

func _populate_template_buttons() -> void:
	# Use the right menu vbox for template buttons
	# First, remove any existing template container
	var existing = right_menu_vbox.get_node_or_null("TemplateContainer")
	if existing:
		existing.queue_free()
	
	# Create template container
	var template_container = VBoxContainer.new()
	template_container.name = "TemplateContainer"
	template_container.add_theme_constant_override("separation", 8)
	right_menu_vbox.add_child(template_container)
	
	# Get hero color and map to template
	var hero_data = HeroDatabase.get_hero(selected_hero_id)
	var hero_color = hero_data.get("color", "yellow")
	
	# Default button (hero's color template) - always selected
	var default_btn = Button.new()
	default_btn.text = "Default ✓"
	default_btn.custom_minimum_size = Vector2(0, 32)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.5, 0.3, 0.9)
	btn_style.corner_radius_top_left = 4
	btn_style.corner_radius_top_right = 4
	btn_style.corner_radius_bottom_left = 4
	btn_style.corner_radius_bottom_right = 4
	default_btn.add_theme_stylebox_override("normal", btn_style)
	template_container.add_child(default_btn)

func _get_template_for_color(hero_color: String) -> String:
	# Map hero colors to template IDs
	match hero_color:
		"purple":
			return "violet"
		"yellow":
			return "yellow"
		"green":
			return "green"
		"red":
			return "red"
		"blue":
			return "blue"
		_:
			return "default"

func _update_card_info(card_data: Dictionary) -> void:
	if not card_info_panel or not is_instance_valid(card_info_panel):
		return
	
	var info_label = card_info_panel.get_node_or_null("InfoLabel")
	if not info_label:
		return
	
	var cost = card_data.get("cost", 0)
	var cost_text = str(cost) if cost >= 0 else "X (All Mana)"
	
	var info_text = card_data.get("name", "Unknown") + "\n\n"
	info_text += "Cost: " + cost_text + "\n"
	info_text += "Type: " + card_data.get("type", "").capitalize() + "\n\n"
	info_text += card_data.get("description", "No description")
	
	info_label.text = info_text

func _get_card_display_description(card_data: Dictionary) -> String:
	## Compute a human-readable description with actual damage/heal/shield values
	var hero_data = HeroDatabase.get_hero(selected_hero_id)
	var base_atk = hero_data.get("base_attack", 10)
	var base_hp = hero_data.get("base_hp", 10)
	var hp_mult = hero_data.get("hp_multiplier", 10)
	var max_hp = hero_data.get("max_hp", base_hp * hp_mult)
	var base_def = hero_data.get("base_def", 0)
	
	var card_type = card_data.get("type", "")
	var desc = card_data.get("description", "")
	
	# Attack cards: compute ATK × multiplier
	var atk_multiplier = card_data.get("atk_multiplier", 0.0)
	if atk_multiplier > 0 and (card_type == "attack" or card_type == "basic_attack" or card_type == "ex"):
		var damage = int(base_atk * atk_multiplier)
		# Replace formula patterns with computed value
		var patterns = [
			"(" + str(int(atk_multiplier * 100)) + "% ATK)",
			str(int(atk_multiplier * 100)) + "% ATK"
		]
		for pattern in patterns:
			if desc.find(pattern) >= 0:
				desc = desc.replace(pattern, str(damage))
				break
	
	# Heal cards: compute max_HP × hp_multiplier
	var card_hp_mult = card_data.get("hp_multiplier", 0.0)
	if card_hp_mult > 0:
		var heal_amount = int(max_hp * card_hp_mult)
		var patterns = [
			"(" + str(int(card_hp_mult * 100)) + "% max HP)",
			str(int(card_hp_mult * 100)) + "% max HP"
		]
		for pattern in patterns:
			if desc.find(pattern) >= 0:
				desc = desc.replace(pattern, str(heal_amount) + " HP")
				break
	
	# Shield cards: compute base_shield + DEF × def_multiplier
	var card_base_shield = card_data.get("base_shield", 0)
	var card_def_mult = card_data.get("def_multiplier", 0.0)
	if card_base_shield > 0 or card_def_mult > 0:
		var shield_amount = card_base_shield + int(base_def * card_def_mult)
		var def_int = str(int(card_def_mult))
		var base_str = str(card_base_shield)
		# Try all possible × character variants
		var separators = ["×", "x", "X", "*"]
		var replaced = false
		for sep in separators:
			var with_parens = "(" + base_str + " + DEF" + sep + def_int + ")"
			if desc.find(with_parens) >= 0:
				desc = desc.replace(with_parens, str(shield_amount))
				replaced = true
				break
			var no_parens = base_str + " + DEF" + sep + def_int
			if desc.find(no_parens) >= 0:
				desc = desc.replace(no_parens, str(shield_amount))
				replaced = true
				break
	
	# Mana surge special case
	if card_data.get("effects", []).has("mana_surge"):
		desc = "Spend ALL mana. Deal " + str(int(base_atk * atk_multiplier)) + " damage per mana."
	
	return desc

func _display_cards_in_pose_panels() -> void:
	# Clear existing card panels
	_hide_cards_panels()
	
	var hero_data = HeroDatabase.get_hero(selected_hero_id)
	if hero_data.is_empty():
		return
	
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	var hero_cards = hero_data.get("cards", [])
	
	# Use same positions as pose panels (IDLE, HIT, CAST, ATTACK)
	# Position 0 = EX card, Position 1-3 = skill cards
	var positions = [
		Vector2(510, 500),   # IDLE position - EX card
		Vector2(780, 500),   # HIT position - Skill 1
		Vector2(1060, 500),  # CAST position - Skill 2
		Vector2(1330, 500)   # ATTACK position - Skill 3
	]
	var card_size = Vector2(210, 340)
	
	# Get EX card first
	var ex_card_id = hero_data.get("ex_card", "")
	if not ex_card_id.is_empty():
		var ex_card_data = CardDatabase.get_card(ex_card_id)
		if not ex_card_data.is_empty():
			var card_panel = _create_card_panel(ex_card_data, role_color, positions[0], card_size)
			add_child(card_panel)
			card_panels.append(card_panel)
	
	# Then skill cards (positions 1-3)
	for i in range(min(hero_cards.size(), 3)):
		var card_id = hero_cards[i]
		var card_data = CardDatabase.get_card(card_id)
		if card_data.is_empty():
			continue
		
		var card_panel = _create_card_panel(card_data, role_color, positions[i + 1], card_size)
		add_child(card_panel)
		card_panels.append(card_panel)

func _hide_cards_panels() -> void:
	for panel in card_panels:
		if is_instance_valid(panel):
			panel.queue_free()
	card_panels.clear()

func _create_card_panel(card_data: Dictionary, role_color: Color, pos: Vector2, size: Vector2) -> Panel:
	var panel = Panel.new()
	panel.position = pos
	panel.custom_minimum_size = size
	panel.size = size
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent - card image fills it
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = role_color
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	panel.add_theme_stylebox_override("panel", style)
	
	# Check for layered card system (art + template)
	var art_path = card_data.get("art", "")
	var image_path = card_data.get("image", "")
	
	if not art_path.is_empty() and ResourceLoader.exists(art_path):
		# Layered system: skill art + template frame
		var hero_data = HeroDatabase.get_hero(selected_hero_id)
		var hero_color = hero_data.get("color", "yellow")
		var template_id = _get_template_for_color(hero_color)
		var template = _get_template(template_id)
		
		# Base card size (template is designed for 160x230, but we scale to panel size)
		var base_width = 160.0
		var base_height = 230.0
		var scale_x = (size.x - 6) / base_width
		var scale_y = (size.y - 6) / base_height
		
		# Skill art (behind) - scale art region to match panel size
		var skill_art = TextureRect.new()
		var art_region = template.get("art_region", {"x": 8, "y": 18, "width": 144, "height": 88})
		var art_x = 3 + art_region.get("x", 8) * scale_x
		var art_y = 3 + art_region.get("y", 18) * scale_y
		var art_w = art_region.get("width", 144) * scale_x
		var art_h = art_region.get("height", 88) * scale_y
		skill_art.position = Vector2(art_x, art_y)
		skill_art.custom_minimum_size = Vector2(art_w, art_h)
		skill_art.size = Vector2(art_w, art_h)
		skill_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		skill_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		skill_art.texture = load(art_path)
		panel.add_child(skill_art)
		
		# Template frame (on top) - fills the panel
		var frame_path = template.get("frame", "res://asset/card template/new template grey.png")
		if ResourceLoader.exists(frame_path):
			var template_frame = TextureRect.new()
			template_frame.position = Vector2(3, 3)
			template_frame.custom_minimum_size = Vector2(size.x - 6, size.y - 6)
			template_frame.size = Vector2(size.x - 6, size.y - 6)
			template_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			template_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			template_frame.texture = load(frame_path)
			panel.add_child(template_frame)
	elif ResourceLoader.exists(image_path):
		# Legacy: full card image
		var card_image = TextureRect.new()
		card_image.position = Vector2(3, 3)
		card_image.custom_minimum_size = Vector2(size.x - 6, size.y - 6)
		card_image.size = Vector2(size.x - 6, size.y - 6)
		card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_image.texture = load(image_path)
		panel.add_child(card_image)
	
	# Card name label (positioned in template's name area)
	var name_label = Label.new()
	name_label.text = card_data.get("name", "Unknown")
	name_label.position = Vector2(5, size.y * 0.48)
	name_label.custom_minimum_size = Vector2(size.x - 10, 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.1, 0.05, 0))
	name_label.add_theme_color_override("font_outline_color", Color(1, 0.95, 0.8))
	name_label.add_theme_constant_override("outline_size", 2)
	panel.add_child(name_label)
	
	# Card cost label (on the mana orb - positioned on the orb in template)
	var cost = card_data.get("cost", 0)
	var cost_text = str(int(cost)) if cost >= 0 else "X"
	var cost_label = Label.new()
	cost_label.text = cost_text
	cost_label.position = Vector2(8, 26)
	cost_label.custom_minimum_size = Vector2(32, 32)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 22)
	cost_label.add_theme_color_override("font_color", Color(1, 1, 1))
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cost_label.add_theme_constant_override("outline_size", 5)
	panel.add_child(cost_label)
	
	# Card description (in template's description area - computed values)
	var desc_label = RichTextLabel.new()
	desc_label.text = _get_card_display_description(card_data)
	desc_label.position = Vector2(20, size.y * 0.60)
	desc_label.custom_minimum_size = Vector2(size.x - 34, size.y * 0.34)
	desc_label.size = Vector2(size.x - 34, size.y * 0.34)
	desc_label.add_theme_font_size_override("normal_font_size", 13)
	desc_label.add_theme_color_override("default_color", Color(0.95, 0.95, 0.95))
	desc_label.scroll_active = false
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(desc_label)
	
	return panel

func _on_card_clicked(card_data: Dictionary) -> void:
	selected_card_data = card_data
	_update_card_info(card_data)

var _cached_templates: Dictionary = {}

func _get_template(template_id: String) -> Dictionary:
	var templates = _load_templates()
	return templates.get(template_id, templates.get("default", {}))

func _load_templates() -> Dictionary:
	if not _cached_templates.is_empty():
		return _cached_templates
	
	var file = FileAccess.open("res://data/templates.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_cached_templates = json.get_data()
			return _cached_templates
	
	# Fallback default
	_cached_templates = {"default": {"frame": "res://asset/card template/new template grey.png", "art_region": {"x": 8, "y": 18, "width": 144, "height": 88}}}
	return _cached_templates

func _show_cards_content() -> void:
	if cards_content and is_instance_valid(cards_content):
		cards_content.visible = true
		return
	
	# Create cards content container
	cards_content = Control.new()
	cards_content.position = Vector2(220, 70)
	cards_content.custom_minimum_size = Vector2(800, 500)
	add_child(cards_content)
	
	# Hero roster panel for cards tab
	var cards_roster_panel = Panel.new()
	cards_roster_panel.position = Vector2(50, 0)
	cards_roster_panel.custom_minimum_size = Vector2(500, 120)
	var roster_style = StyleBoxFlat.new()
	roster_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	roster_style.corner_radius_top_left = 8
	roster_style.corner_radius_top_right = 8
	roster_style.corner_radius_bottom_left = 8
	roster_style.corner_radius_bottom_right = 8
	cards_roster_panel.add_theme_stylebox_override("panel", roster_style)
	cards_content.add_child(cards_roster_panel)
	
	var cards_roster_label = Label.new()
	cards_roster_label.text = "SELECT HERO"
	cards_roster_label.position = Vector2(10, 5)
	cards_roster_label.add_theme_font_size_override("font_size", 14)
	cards_roster_panel.add_child(cards_roster_label)
	
	cards_hero_roster = HBoxContainer.new()
	cards_hero_roster.position = Vector2(20, 30)
	cards_hero_roster.add_theme_constant_override("separation", 10)
	cards_roster_panel.add_child(cards_hero_roster)
	
	# Add hero thumbnails for cards tab
	for hero_id in HeroDatabase.heroes.keys():
		var hero_data = HeroDatabase.get_hero(hero_id)
		var thumbnail = _create_cards_hero_thumbnail(hero_id, hero_data)
		cards_hero_roster.add_child(thumbnail)
		cards_hero_thumbnails[hero_id] = thumbnail
	
	# Cards display container
	cards_display_container = HBoxContainer.new()
	cards_display_container.position = Vector2(0, 140)
	cards_display_container.add_theme_constant_override("separation", 15)
	cards_content.add_child(cards_display_container)
	
	# Select first hero
	var keys = HeroDatabase.heroes.keys()
	if keys.size() > 0:
		_on_cards_hero_selected(keys[0])

func _hide_cards_content() -> void:
	if cards_content and is_instance_valid(cards_content):
		cards_content.visible = false

func _create_cards_hero_thumbnail(hero_id: String, hero_data: Dictionary) -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(80, 100)
	container.set_meta("hero_id", hero_id)
	
	var border = Panel.new()
	border.custom_minimum_size = Vector2(80, 80)
	border.position = Vector2(0, 0)
	
	var style = StyleBoxFlat.new()
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = role_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	border.add_theme_stylebox_override("panel", style)
	border.name = "Border"
	container.add_child(border)
	
	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(70, 70)
	portrait.position = Vector2(5, 5)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path = hero_data.get("portrait", "")
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	container.add_child(portrait)
	
	var name_label = Label.new()
	name_label.text = hero_data.get("name", hero_id)
	name_label.position = Vector2(0, 82)
	name_label.custom_minimum_size = Vector2(80, 18)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	container.add_child(name_label)
	
	var button = Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(80, 80)
	button.position = Vector2(0, 0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_on_cards_hero_selected.bind(hero_id))
	container.add_child(button)
	
	return container

func _on_cards_hero_selected(hero_id: String) -> void:
	selected_cards_hero_id = hero_id
	_update_cards_hero_selection_visuals()
	_display_hero_cards(hero_id)

func _update_cards_hero_selection_visuals() -> void:
	for id in cards_hero_thumbnails.keys():
		var thumbnail = cards_hero_thumbnails[id]
		var border = thumbnail.get_node("Border")
		var style = border.get_theme_stylebox("panel").duplicate()
		if id == selected_cards_hero_id:
			style.bg_color = Color(0.3, 0.3, 0.5, 0.9)
		else:
			style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
		border.add_theme_stylebox_override("panel", style)

func _display_hero_cards(hero_id: String) -> void:
	for child in cards_display_container.get_children():
		child.queue_free()
	
	var hero_data = HeroDatabase.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	
	# Get hero's cards
	var hero_cards = hero_data.get("cards", [])
	
	for card_id in hero_cards:
		var card_data = CardDatabase.get_card(card_id)
		if card_data.is_empty():
			continue
		var card_display = _create_card_display(card_data, role_color)
		cards_display_container.add_child(card_display)

func _create_card_display(card_data: Dictionary, role_color: Color) -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(140, 200)
	
	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(140, 180)
	bg.position = Vector2(0, 0)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = role_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)
	container.add_child(bg)
	
	# Card image — prefer skill art (layered system) over legacy full image
	var art_path = card_data.get("art", "")
	var image_path = card_data.get("image", "")
	
	if not art_path.is_empty() and ResourceLoader.exists(art_path):
		# Layered system: skill art + template frame
		var hero_id = card_data.get("hero_id", "")
		var hero_color = card_data.get("hero_color", "")
		if not hero_id.is_empty() and hero_color.is_empty():
			var hero_data_lookup = HeroDatabase.get_hero(hero_id)
			hero_color = hero_data_lookup.get("color", "yellow")
		var template_id = _get_template_for_color(hero_color)
		var template = _get_template(template_id)
		
		var base_width = 160.0
		var base_height = 230.0
		var panel_w = 120.0
		var panel_h = 90.0
		var scale_x = panel_w / base_width
		var scale_y = panel_h / base_height
		
		# Skill art (behind)
		var skill_art = TextureRect.new()
		var art_region = template.get("art_region", {"x": 8, "y": 18, "width": 144, "height": 88})
		var art_x = 10 + art_region.get("x", 8) * scale_x
		var art_y = 10 + art_region.get("y", 18) * scale_y
		var art_w = art_region.get("width", 144) * scale_x
		var art_h = art_region.get("height", 88) * scale_y
		skill_art.position = Vector2(art_x, art_y)
		skill_art.custom_minimum_size = Vector2(art_w, art_h)
		skill_art.size = Vector2(art_w, art_h)
		skill_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		skill_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		skill_art.texture = load(art_path)
		container.add_child(skill_art)
		
		# Template frame (on top)
		var frame_path = template.get("frame", "res://asset/card template/new template grey.png")
		if ResourceLoader.exists(frame_path):
			var template_frame = TextureRect.new()
			template_frame.position = Vector2(10, 10)
			template_frame.custom_minimum_size = Vector2(panel_w, panel_h)
			template_frame.size = Vector2(panel_w, panel_h)
			template_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			template_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			template_frame.texture = load(frame_path)
			container.add_child(template_frame)
	elif not image_path.is_empty() and ResourceLoader.exists(image_path):
		# Legacy: full card image
		var card_image = TextureRect.new()
		card_image.position = Vector2(10, 10)
		card_image.custom_minimum_size = Vector2(120, 90)
		card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_image.texture = load(image_path)
		container.add_child(card_image)
	
	# Card name
	var name_label = Label.new()
	name_label.text = card_data.get("name", "Unknown")
	name_label.position = Vector2(5, 105)
	name_label.custom_minimum_size = Vector2(130, 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	container.add_child(name_label)
	
	# Card cost
	var cost = card_data.get("cost", 0)
	var cost_text = str(cost) if cost >= 0 else "X"
	var cost_label = Label.new()
	cost_label.text = "Cost: " + cost_text
	cost_label.position = Vector2(5, 125)
	cost_label.custom_minimum_size = Vector2(130, 18)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 10)
	cost_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	container.add_child(cost_label)
	
	# Card type
	var type_label = Label.new()
	type_label.text = card_data.get("type", "").capitalize()
	type_label.position = Vector2(5, 143)
	type_label.custom_minimum_size = Vector2(130, 18)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 10)
	type_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	container.add_child(type_label)
	
	# Card description (truncated)
	var desc_label = Label.new()
	var desc = card_data.get("description", "")
	if desc.length() > 40:
		desc = desc.substr(0, 37) + "..."
	desc_label.text = desc
	desc_label.position = Vector2(5, 160)
	desc_label.custom_minimum_size = Vector2(130, 18)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 8)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	container.add_child(desc_label)
	
	return container
