extends Control

enum Tab { HEROES, CARDS, OTHERS }

var current_tab: Tab = Tab.HEROES
var selected_hero_id: String = ""
var hero_thumbnails: Dictionary = {}
var pose_nodes: Dictionary = {}  # pose_name -> Control node
var skin_buttons: Array = []

# UI references - created dynamically
var back_button: Button
var heroes_tab: Button
var cards_tab: Button
var others_tab: Button
var hero_roster: HBoxContainer
var poses_container: Control
var skins_container: VBoxContainer
var heroes_content: Control
var cards_content: Control
var others_content: Control
var cards_hero_roster: HBoxContainer
var cards_hero_thumbnails: Dictionary = {}
var cards_display_container: HBoxContainer
var selected_cards_hero_id: String = ""
var template_selector_container: VBoxContainer
var template_buttons: Array = []

var stage_texture = preload("res://asset/Others/stage.png")
var card_scene = preload("res://scenes/components/card.tscn")

func _ready() -> void:
	_create_ui()
	_setup_hero_roster()
	_select_first_hero()
	_update_tab_visuals()

func _create_ui() -> void:
	# Background
	var bg = TextureRect.new()
	bg.texture = stage_texture
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.7, 0.7, 0.7, 1.0)  # Slightly darkened instead of blur
	add_child(bg)
	
	# Title
	var title = Label.new()
	title.text = "COLLECTION"
	title.position = Vector2(450, 15)
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)
	
	# Back button
	back_button = Button.new()
	back_button.text = "← BACK"
	back_button.position = Vector2(20, 15)
	back_button.custom_minimum_size = Vector2(80, 30)
	back_button.pressed.connect(_on_back_pressed)
	add_child(back_button)
	
	# Left menu panel
	var left_panel = Panel.new()
	left_panel.position = Vector2(20, 70)
	left_panel.custom_minimum_size = Vector2(120, 480)
	add_child(left_panel)
	
	var menu_label = Label.new()
	menu_label.text = "MENU"
	menu_label.position = Vector2(40, 10)
	left_panel.add_child(menu_label)
	
	heroes_tab = Button.new()
	heroes_tab.text = "HEROES"
	heroes_tab.position = Vector2(10, 45)
	heroes_tab.custom_minimum_size = Vector2(100, 40)
	heroes_tab.toggle_mode = true
	heroes_tab.button_pressed = true
	heroes_tab.pressed.connect(_on_heroes_tab_pressed)
	left_panel.add_child(heroes_tab)
	
	cards_tab = Button.new()
	cards_tab.text = "CARDS"
	cards_tab.position = Vector2(10, 95)
	cards_tab.custom_minimum_size = Vector2(100, 40)
	cards_tab.toggle_mode = true
	cards_tab.pressed.connect(_on_cards_tab_pressed)
	left_panel.add_child(cards_tab)
	
	others_tab = Button.new()
	others_tab.text = "OTHERS"
	others_tab.position = Vector2(10, 145)
	others_tab.custom_minimum_size = Vector2(100, 40)
	others_tab.toggle_mode = true
	others_tab.pressed.connect(_on_others_tab_pressed)
	left_panel.add_child(others_tab)
	
	# Heroes content area
	heroes_content = Control.new()
	heroes_content.position = Vector2(150, 70)
	heroes_content.custom_minimum_size = Vector2(730, 480)
	add_child(heroes_content)
	
	# Hero roster panel at top
	var roster_panel = Panel.new()
	roster_panel.position = Vector2(100, 0)
	roster_panel.custom_minimum_size = Vector2(440, 120)
	heroes_content.add_child(roster_panel)
	
	var roster_label = Label.new()
	roster_label.text = "SELECT HERO"
	roster_label.position = Vector2(10, 5)
	roster_panel.add_child(roster_label)
	
	hero_roster = HBoxContainer.new()
	hero_roster.position = Vector2(20, 25)
	hero_roster.add_theme_constant_override("separation", 10)
	roster_panel.add_child(hero_roster)
	
	# Poses container
	poses_container = HBoxContainer.new()
	poses_container.position = Vector2(0, 140)
	poses_container.add_theme_constant_override("separation", 15)
	heroes_content.add_child(poses_container)
	
	# Right menu panel (skins)
	var right_panel = Panel.new()
	right_panel.position = Vector2(600, 0)
	right_panel.custom_minimum_size = Vector2(140, 480)
	heroes_content.add_child(right_panel)
	
	var skins_label = Label.new()
	skins_label.text = "SKINS"
	skins_label.position = Vector2(50, 10)
	right_panel.add_child(skins_label)
	
	skins_container = VBoxContainer.new()
	skins_container.position = Vector2(10, 45)
	skins_container.add_theme_constant_override("separation", 10)
	right_panel.add_child(skins_container)
	
	# Cards content
	cards_content = Control.new()
	cards_content.position = Vector2(150, 70)
	cards_content.custom_minimum_size = Vector2(730, 480)
	cards_content.visible = false
	add_child(cards_content)
	
	# Hero roster panel for cards tab
	var cards_roster_panel = Panel.new()
	cards_roster_panel.position = Vector2(100, 0)
	cards_roster_panel.custom_minimum_size = Vector2(440, 120)
	cards_content.add_child(cards_roster_panel)
	
	var cards_roster_label = Label.new()
	cards_roster_label.text = "SELECT HERO"
	cards_roster_label.position = Vector2(10, 5)
	cards_roster_panel.add_child(cards_roster_label)
	
	cards_hero_roster = HBoxContainer.new()
	cards_hero_roster.position = Vector2(20, 25)
	cards_hero_roster.add_theme_constant_override("separation", 10)
	cards_roster_panel.add_child(cards_hero_roster)
	
	# Cards display container
	cards_display_container = HBoxContainer.new()
	cards_display_container.position = Vector2(0, 140)
	cards_display_container.add_theme_constant_override("separation", 15)
	cards_content.add_child(cards_display_container)
	
	# Template selector panel (right side)
	var template_panel = Panel.new()
	template_panel.position = Vector2(550, 130)
	template_panel.custom_minimum_size = Vector2(180, 340)
	cards_content.add_child(template_panel)
	
	var template_label = Label.new()
	template_label.text = "CARD TEMPLATE"
	template_label.position = Vector2(30, 10)
	template_label.add_theme_font_size_override("font_size", 12)
	template_panel.add_child(template_label)
	
	template_selector_container = VBoxContainer.new()
	template_selector_container.position = Vector2(10, 40)
	template_selector_container.add_theme_constant_override("separation", 8)
	template_panel.add_child(template_selector_container)
	
	# Others content (placeholder)
	others_content = Control.new()
	others_content.position = Vector2(150, 70)
	others_content.custom_minimum_size = Vector2(730, 480)
	others_content.visible = false
	add_child(others_content)
	
	var others_label = Label.new()
	others_label.text = "OTHERS - Coming Soon"
	others_label.position = Vector2(300, 200)
	others_content.add_child(others_label)

func _setup_hero_roster() -> void:
	# Setup Heroes tab roster
	for child in hero_roster.get_children():
		child.queue_free()
	
	for hero_id in HeroDatabase.heroes.keys():
		var hero_data = HeroDatabase.get_hero(hero_id)
		var thumbnail = _create_hero_thumbnail(hero_id, hero_data, false)
		hero_roster.add_child(thumbnail)
		hero_thumbnails[hero_id] = thumbnail
	
	# Setup Cards tab roster
	for child in cards_hero_roster.get_children():
		child.queue_free()
	
	for hero_id in HeroDatabase.heroes.keys():
		var hero_data = HeroDatabase.get_hero(hero_id)
		var thumbnail = _create_hero_thumbnail(hero_id, hero_data, true)
		cards_hero_roster.add_child(thumbnail)
		cards_hero_thumbnails[hero_id] = thumbnail

func _create_hero_thumbnail(hero_id: String, hero_data: Dictionary, for_cards: bool = false) -> Control:
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
	if for_cards:
		button.pressed.connect(_on_cards_hero_selected.bind(hero_id))
	else:
		button.pressed.connect(_on_hero_selected.bind(hero_id))
	container.add_child(button)
	
	return container

func _select_first_hero() -> void:
	var keys = HeroDatabase.heroes.keys()
	if keys.size() > 0:
		_on_hero_selected(keys[0])
		_on_cards_hero_selected(keys[0])

func _on_hero_selected(hero_id: String) -> void:
	selected_hero_id = hero_id
	_update_hero_selection_visuals()
	_display_hero_poses(hero_id)
	_display_hero_skins(hero_id)

func _on_cards_hero_selected(hero_id: String) -> void:
	selected_cards_hero_id = hero_id
	_update_cards_hero_selection_visuals()
	_display_hero_cards(hero_id)
	_display_template_options(hero_id)

func _update_hero_selection_visuals() -> void:
	for id in hero_thumbnails.keys():
		var thumbnail = hero_thumbnails[id]
		var border = thumbnail.get_node("Border")
		var style = border.get_theme_stylebox("panel").duplicate()
		if id == selected_hero_id:
			style.bg_color = Color(0.3, 0.3, 0.4, 0.9)
		else:
			style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
		border.add_theme_stylebox_override("panel", style)

func _update_cards_hero_selection_visuals() -> void:
	for id in cards_hero_thumbnails.keys():
		var thumbnail = cards_hero_thumbnails[id]
		var border = thumbnail.get_node("Border")
		var style = border.get_theme_stylebox("panel").duplicate()
		if id == selected_cards_hero_id:
			style.bg_color = Color(0.3, 0.3, 0.4, 0.9)
		else:
			style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
		border.add_theme_stylebox_override("panel", style)

func _display_hero_poses(hero_id: String) -> void:
	for child in poses_container.get_children():
		child.queue_free()
	pose_nodes.clear()
	
	var hero_data = HeroDatabase.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	var poses = [
		{"name": "IDLE", "sprite_key": "idle_sprite"},
		{"name": "HIT", "sprite_key": "hit_sprite"},
		{"name": "CAST", "sprite_key": "cast_sprite"},
		{"name": "ATTACK", "sprite_key": "attack_sprite"}
	]
	
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	
	for pose in poses:
		var pose_container = _create_pose_display(hero_data, pose, role_color)
		poses_container.add_child(pose_container)

func _create_pose_display(hero_data: Dictionary, pose: Dictionary, role_color: Color) -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(180, 280)
	
	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(180, 250)
	bg.position = Vector2(0, 0)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.2)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = role_color
	style.border_color.a = 0.6
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	bg.add_theme_stylebox_override("panel", style)
	container.add_child(bg)
	
	var sprite = TextureRect.new()
	sprite.position = Vector2(10, 10)
	sprite.custom_minimum_size = Vector2(160, 220)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var sprite_path = hero_data.get(pose["sprite_key"], "")
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	sprite.name = "Sprite"
	container.add_child(sprite)
	pose_nodes[pose["name"]] = sprite
	
	var label = Label.new()
	label.text = pose["name"]
	label.position = Vector2(0, 255)
	label.custom_minimum_size = Vector2(180, 25)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	container.add_child(label)
	
	return container

func _display_hero_skins(hero_id: String) -> void:
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
	button.custom_minimum_size = Vector2(140, 40)
	button.text = skin.get("name", "Unknown")
	
	var is_equipped = skin.get("id", "") == equipped_skin
	var is_unlocked = skin.get("unlocked", false)
	
	if is_equipped:
		button.text += " ✓"
	if not is_unlocked:
		button.text += " 🔒"
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

func _display_hero_cards(hero_id: String) -> void:
	for child in cards_display_container.get_children():
		child.queue_free()
	
	var hero_data = HeroDatabase.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	# Get equipped template for this hero
	var template_id = HeroDatabase.get_hero_template(hero_id)
	
	# Get hero's cards from CardDatabase
	var hero_cards = hero_data.get("cards", [])
	
	for card_id in hero_cards:
		var card_data = CardDatabase.get_card(card_id)
		if card_data.is_empty():
			continue
		
		# Use Card scene with template support
		var card_instance = card_scene.instantiate()
		card_instance.can_interact = false  # Disable interaction in collection
		cards_display_container.add_child(card_instance)
		card_instance.setup(card_data, template_id)
		card_instance.scale = Vector2(1.2, 1.2)  # Slightly larger for viewing

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
	
	# Card image
	var card_image = TextureRect.new()
	card_image.position = Vector2(10, 10)
	card_image.custom_minimum_size = Vector2(120, 90)
	card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var image_path = card_data.get("image", "")
	if ResourceLoader.exists(image_path):
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

func _display_template_options(hero_id: String) -> void:
	# Clear existing template buttons
	for child in template_selector_container.get_children():
		child.queue_free()
	template_buttons.clear()
	
	# Get current equipped template for this hero
	var equipped_template = HeroDatabase.get_hero_template(hero_id)
	
	# Get all available templates (global + hero-specific)
	var available_templates = TemplateDatabase.get_available_templates(hero_id)
	
	for template in available_templates:
		var template_id = template.get("id", "default")
		var template_name = template.get("name", "Unknown")
		var rarity = template.get("rarity", "common")
		
		var button = Button.new()
		button.custom_minimum_size = Vector2(160, 35)
		button.text = template_name
		
		# Add rarity indicator
		match rarity:
			"rare":
				button.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
			"epic":
				button.add_theme_color_override("font_color", Color(0.7, 0.4, 0.9))
			"legendary":
				button.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		
		# Mark equipped template
		if template_id == equipped_template:
			button.text += " ✓"
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.4, 0.3, 0.8)
			style.corner_radius_top_left = 4
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_left = 4
			style.corner_radius_bottom_right = 4
			button.add_theme_stylebox_override("normal", style)
		
		button.pressed.connect(_on_template_selected.bind(hero_id, template_id))
		button.set_meta("template_id", template_id)
		template_selector_container.add_child(button)
		template_buttons.append(button)

func _on_template_selected(hero_id: String, template_id: String) -> void:
	# Save the selected template for this hero
	HeroDatabase.set_hero_template(hero_id, template_id)
	
	# Refresh the display
	_display_hero_cards(hero_id)
	_display_template_options(hero_id)

func _update_tab_visuals() -> void:
	heroes_tab.button_pressed = current_tab == Tab.HEROES
	cards_tab.button_pressed = current_tab == Tab.CARDS
	others_tab.button_pressed = current_tab == Tab.OTHERS
	
	heroes_content.visible = current_tab == Tab.HEROES
	cards_content.visible = current_tab == Tab.CARDS
	others_content.visible = current_tab == Tab.OTHERS

func _on_heroes_tab_pressed() -> void:
	current_tab = Tab.HEROES
	_update_tab_visuals()

func _on_cards_tab_pressed() -> void:
	current_tab = Tab.CARDS
	_update_tab_visuals()

func _on_others_tab_pressed() -> void:
	current_tab = Tab.OTHERS
	_update_tab_visuals()

func _on_back_pressed() -> void:
	SceneTransition.change_scene("res://scenes/dashboard/dashboard.tscn")
