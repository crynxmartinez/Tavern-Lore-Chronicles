extends Control

enum Tab { HEROES, EQUIPMENTS }

var current_tab: Tab = Tab.HEROES
var dragging_hero: String = ""
var dragging_equipment: String = ""
var dragging_from_slot: int = -1  # -1 = from roster, 0-3 = from slot
var drag_preview: TextureRect = null
var team_slots: Array = []
var equipment_slots: Array = []
var hero_thumbnails: Dictionary = {}
var equipment_thumbnails: Dictionary = {}
var hover_tooltip: Panel = null

@onready var back_button: Button = $UI/MainLayout/ContentArea/TopBar/BackButton
@onready var confirm_button: Button = $UI/MainLayout/ContentArea/ConfirmButton
@onready var hero_roster: HBoxContainer = $UI/MainLayout/ContentArea/HeroSection/HeroRoster/VBox/ScrollContainer/HeroContainer
@onready var hero_scroll: ScrollContainer = $UI/MainLayout/ContentArea/HeroSection/HeroRoster/VBox/ScrollContainer
@onready var team_container: HBoxContainer = $UI/MainLayout/ContentArea/HeroSection/SlotsArea/TeamContainer
@onready var left_panel: Panel = $UI/MainLayout/LeftMenu
@onready var left_menu_vbox: VBoxContainer = $UI/MainLayout/LeftMenu/VBox

# Sections
@onready var hero_section: VBoxContainer = $UI/MainLayout/ContentArea/HeroSection
@onready var equipment_section: VBoxContainer = $UI/MainLayout/ContentArea/EquipmentSection
@onready var equipment_roster: HBoxContainer = $UI/MainLayout/ContentArea/EquipmentSection/EquipmentRoster/VBox/ScrollContainer/EquipmentContainer
@onready var equipment_scroll: ScrollContainer = $UI/MainLayout/ContentArea/EquipmentSection/EquipmentRoster/VBox/ScrollContainer
@onready var equipment_slots_container: HBoxContainer = $UI/MainLayout/ContentArea/EquipmentSection/SlotsArea/SlotsContainer

# Tab buttons (created dynamically)
var heroes_tab: Button
var equipments_tab: Button

var stage_texture = preload("res://asset/Others/stage.png")
var card_scene = preload("res://scenes/components/card.tscn")

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	
	# Hide scrollbars
	_hide_scrollbars()
	
	_create_left_menu()
	_setup_hero_roster()
	_setup_team_slots()
	_setup_equipment_roster()
	_setup_equipment_slots()
	_load_current_team()
	_load_current_equipment()
	_update_tab_visuals()

func _hide_scrollbars() -> void:
	# Get the horizontal scrollbar and hide it
	var h_scroll = hero_scroll.get_h_scroll_bar()
	if h_scroll:
		h_scroll.modulate.a = 0  # Make invisible but still functional
	
	var eq_h_scroll = equipment_scroll.get_h_scroll_bar()
	if eq_h_scroll:
		eq_h_scroll.modulate.a = 0

func _create_left_menu() -> void:
	# Add tab buttons to the VBox inside left menu
	heroes_tab = Button.new()
	heroes_tab.text = "HEROES"
	heroes_tab.custom_minimum_size = Vector2(0, 40)
	heroes_tab.toggle_mode = true
	heroes_tab.button_pressed = true
	heroes_tab.pressed.connect(_on_heroes_tab_pressed)
	left_menu_vbox.add_child(heroes_tab)
	
	equipments_tab = Button.new()
	equipments_tab.text = "EQUIPMENT"
	equipments_tab.custom_minimum_size = Vector2(0, 40)
	equipments_tab.toggle_mode = true
	equipments_tab.pressed.connect(_on_equipments_tab_pressed)
	left_menu_vbox.add_child(equipments_tab)

func _on_heroes_tab_pressed() -> void:
	current_tab = Tab.HEROES
	_update_tab_visuals()

func _on_equipments_tab_pressed() -> void:
	current_tab = Tab.EQUIPMENTS
	_update_tab_visuals()

func _update_tab_visuals() -> void:
	heroes_tab.button_pressed = current_tab == Tab.HEROES
	equipments_tab.button_pressed = current_tab == Tab.EQUIPMENTS
	
	# Show/hide sections based on tab
	hero_section.visible = current_tab == Tab.HEROES
	equipment_section.visible = current_tab == Tab.EQUIPMENTS

func _setup_hero_roster() -> void:
	# Clear existing children
	for child in hero_roster.get_children():
		child.queue_free()
	
	# Create thumbnail for each hero
	for hero_id in HeroDatabase.heroes.keys():
		var hero_data = HeroDatabase.get_hero(hero_id)
		var thumbnail = _create_hero_thumbnail(hero_id, hero_data)
		hero_roster.add_child(thumbnail)
		hero_thumbnails[hero_id] = thumbnail

func _create_hero_thumbnail(hero_id: String, hero_data: Dictionary) -> Control:
	var thumb_size = 80
	var container = Control.new()
	container.custom_minimum_size = Vector2(thumb_size, thumb_size + 20)
	container.set_meta("hero_id", hero_id)
	
	# Border panel with role color
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
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	border.add_theme_stylebox_override("panel", style)
	container.add_child(border)
	
	# Portrait image
	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(thumb_size - 6, thumb_size - 6)
	portrait.position = Vector2(3, 3)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path = hero_data.get("portrait", "")
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	container.add_child(portrait)
	
	# Hero name label
	var name_label = Label.new()
	name_label.text = hero_data.get("name", hero_id)
	name_label.position = Vector2(0, thumb_size + 2)
	name_label.custom_minimum_size = Vector2(thumb_size, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	container.add_child(name_label)
	
	# Make it interactive
	var button = Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(thumb_size, thumb_size)
	button.position = Vector2(0, 0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.button_down.connect(_on_thumbnail_pressed.bind(hero_id))
	button.button_up.connect(_on_thumbnail_released.bind(hero_id))
	container.add_child(button)
	
	return container

func _setup_team_slots() -> void:
	team_slots.clear()
	
	# Clear existing children
	for child in team_container.get_children():
		child.queue_free()
	
	# Create 4 team slots
	for i in range(4):
		var slot = _create_team_slot(i)
		team_container.add_child(slot)
		team_slots.append(slot)

func _create_team_slot(index: int) -> Control:
	# Match equipment slot layout pattern
	var slot_width = 200
	var slot_height = 230  # Same as equipment slot_height
	
	var container = Control.new()
	container.custom_minimum_size = Vector2(slot_width, slot_height + 25)
	container.set_meta("slot_index", index)
	container.set_meta("hero_id", "")
	
	# Slot label at top (like equipment)
	var slot_label = Label.new()
	slot_label.text = str(index + 1)
	slot_label.position = Vector2(0, slot_height + 5)
	slot_label.custom_minimum_size = Vector2(slot_width, 20)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.add_theme_font_size_override("font_size", 14)
	slot_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	slot_label.name = "SlotLabel"
	container.add_child(slot_label)
	
	# Background panel - positioned at top, same height as equipment
	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(slot_width, slot_height)
	bg.name = "Background"
	bg.position = Vector2(0, 0)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.3)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.5, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)
	container.add_child(bg)
	
	# Hero sprite - ORIGINAL SIZE, bottom aligned to background bottom
	var sprite = TextureRect.new()
	sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE  # Keep original texture size
	sprite.stretch_mode = TextureRect.STRETCH_KEEP  # No stretching
	sprite.name = "HeroSprite"
	sprite.visible = false
	container.add_child(sprite)
	
	# Empty slot indicator - centered in background
	var empty_label = Label.new()
	empty_label.text = "+"
	empty_label.position = Vector2(0, slot_height / 2 - 30)
	empty_label.custom_minimum_size = Vector2(slot_width, 60)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.5))
	empty_label.add_theme_font_size_override("font_size", 48)
	empty_label.name = "EmptyLabel"
	container.add_child(empty_label)
	
	# Click area - covers background area
	var click_area = Button.new()
	click_area.flat = true
	click_area.custom_minimum_size = Vector2(slot_width, slot_height)
	click_area.position = Vector2(0, 0)
	click_area.button_down.connect(_on_slot_pressed.bind(index))
	click_area.button_up.connect(_on_slot_released.bind(index))
	click_area.name = "ClickArea"
	
	var empty_style = StyleBoxEmpty.new()
	click_area.add_theme_stylebox_override("normal", empty_style)
	click_area.add_theme_stylebox_override("hover", empty_style)
	click_area.add_theme_stylebox_override("pressed", empty_style)
	click_area.add_theme_stylebox_override("focus", empty_style)
	click_area.add_theme_stylebox_override("disabled", empty_style)
	
	container.add_child(click_area)
	
	return container

func _load_current_team() -> void:
	var team = HeroDatabase.get_current_team()
	for i in range(min(team.size(), 4)):
		_assign_hero_to_slot(team[i], i)

# ============================================
# EQUIPMENT FUNCTIONS
# ============================================

func _setup_equipment_roster() -> void:
	for child in equipment_roster.get_children():
		child.queue_free()
	
	for equip_id in EquipmentDatabase.get_all_equipments().keys():
		var equip_data = EquipmentDatabase.get_equipment(equip_id)
		var thumbnail = _create_equipment_thumbnail(equip_id, equip_data)
		equipment_roster.add_child(thumbnail)
		equipment_thumbnails[equip_id] = thumbnail

func _create_equipment_thumbnail(equip_id: String, equip_data: Dictionary) -> Control:
	var thumb_size = 80
	var container = Control.new()
	container.custom_minimum_size = Vector2(thumb_size, thumb_size + 20)
	container.set_meta("equip_id", equip_id)
	
	var border = Panel.new()
	border.custom_minimum_size = Vector2(thumb_size, thumb_size)
	border.position = Vector2(0, 0)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.6, 0.5, 0.2)  # Gold/brown for equipment
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	border.add_theme_stylebox_override("panel", style)
	container.add_child(border)
	
	# Equipment icon
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(thumb_size - 6, thumb_size - 6)
	icon.position = Vector2(3, 3)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var image_path = equip_data.get("image", "")
	if ResourceLoader.exists(image_path):
		icon.texture = load(image_path)
	container.add_child(icon)
	
	# Cost indicator
	var cost_label = Label.new()
	cost_label.text = str(int(equip_data.get("cost", 0)))
	cost_label.position = Vector2(4, 4)
	cost_label.add_theme_font_size_override("font_size", 14)
	cost_label.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
	container.add_child(cost_label)
	
	# Equipment name
	var name_label = Label.new()
	name_label.text = equip_data.get("name", equip_id)
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
	button.button_down.connect(_on_equipment_thumbnail_pressed.bind(equip_id))
	button.button_up.connect(_on_equipment_thumbnail_released.bind(equip_id))
	button.mouse_entered.connect(_on_equipment_hover.bind(container, equip_data))
	button.mouse_exited.connect(_on_equipment_hover_exit)
	container.add_child(button)
	
	return container

func _setup_equipment_slots() -> void:
	equipment_slots.clear()
	
	for child in equipment_slots_container.get_children():
		child.queue_free()
	
	for i in range(4):
		var slot = _create_equipment_slot(i)
		equipment_slots_container.add_child(slot)
		equipment_slots.append(slot)

func _create_equipment_slot(index: int) -> Control:
	# Slot container for equipment cards
	var slot_width = 160.0
	var slot_height = 230.0
	
	var container = Control.new()
	container.custom_minimum_size = Vector2(slot_width, slot_height + 25)
	container.set_meta("slot_index", index)
	container.set_meta("equip_id", "")
	
	# Slot label
	var slot_label = Label.new()
	slot_label.text = "Slot " + str(index + 1)
	slot_label.position = Vector2(0, 0)
	slot_label.custom_minimum_size = Vector2(slot_width, 20)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.add_theme_font_size_override("font_size", 14)
	slot_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	container.add_child(slot_label)
	
	# Background panel (shown when empty)
	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(slot_width, slot_height)
	bg.position = Vector2(0, 20)
	bg.name = "Background"
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.4)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)
	container.add_child(bg)
	
	# Empty label
	var empty_label = Label.new()
	empty_label.text = "+"
	empty_label.position = Vector2(0, 100)
	empty_label.custom_minimum_size = Vector2(slot_width, 50)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.5))
	empty_label.add_theme_font_size_override("font_size", 50)
	empty_label.name = "EmptyLabel"
	container.add_child(empty_label)
	
	# Card container (will hold the Card instance when equipped)
	var card_container = Control.new()
	card_container.position = Vector2(0, 20)
	card_container.custom_minimum_size = Vector2(slot_width, slot_height)
	card_container.name = "CardContainer"
	card_container.visible = false
	container.add_child(card_container)
	
	# Click area
	var click_area = Button.new()
	click_area.flat = true
	click_area.custom_minimum_size = Vector2(slot_width, slot_height)
	click_area.position = Vector2(0, 20)
	click_area.button_down.connect(_on_equipment_slot_pressed.bind(index))
	click_area.button_up.connect(_on_equipment_slot_released.bind(index))
	click_area.name = "ClickArea"
	
	var empty_style = StyleBoxEmpty.new()
	click_area.add_theme_stylebox_override("normal", empty_style)
	click_area.add_theme_stylebox_override("hover", empty_style)
	click_area.add_theme_stylebox_override("pressed", empty_style)
	click_area.add_theme_stylebox_override("focus", empty_style)
	click_area.add_theme_stylebox_override("disabled", empty_style)
	
	container.add_child(click_area)
	
	return container

func _load_current_equipment() -> void:
	var equipped = EquipmentDatabase.get_equipped_items()
	for i in range(min(equipped.size(), 4)):
		_assign_equipment_to_slot(equipped[i], i)

func _assign_equipment_to_slot(equip_id: String, slot_index: int) -> void:
	if slot_index < 0 or slot_index >= equipment_slots.size():
		return
	
	var slot = equipment_slots[slot_index]
	var equip_data = EquipmentDatabase.get_equipment(equip_id)
	
	if equip_data.is_empty():
		return
	
	slot.set_meta("equip_id", equip_id)
	
	# Hide empty elements
	var bg = slot.get_node("Background")
	bg.visible = false
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = false
	
	# Show card container and create Card instance
	var card_container = slot.get_node("CardContainer")
	card_container.visible = true
	
	# Clear existing card if any
	for child in card_container.get_children():
		child.queue_free()
	
	# Create card with proper template
	var card_instance = card_scene.instantiate()
	card_container.add_child(card_instance)
	card_instance.can_interact = false
	
	# Setup card with equipment data (template will be applied from equip_data.template)
	card_instance.setup(equip_data)
	
	_update_equipment_thumbnail_state(equip_id, true)

func _remove_equipment_from_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= equipment_slots.size():
		return
	
	var slot = equipment_slots[slot_index]
	var equip_id = slot.get_meta("equip_id")
	
	if equip_id == "":
		return
	
	slot.set_meta("equip_id", "")
	
	# Show empty elements
	var bg = slot.get_node("Background")
	bg.visible = true
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = true
	
	# Hide and clear card container
	var card_container = slot.get_node("CardContainer")
	card_container.visible = false
	for child in card_container.get_children():
		child.queue_free()
	
	_update_equipment_thumbnail_state(equip_id, false)

func _update_equipment_thumbnail_state(equip_id: String, is_used: bool) -> void:
	if not equipment_thumbnails.has(equip_id):
		return
	
	var thumbnail = equipment_thumbnails[equip_id]
	if is_used:
		thumbnail.modulate = Color(0.5, 0.5, 0.5, 0.7)
	else:
		thumbnail.modulate = Color(1, 1, 1, 1)

func _on_equipment_thumbnail_pressed(equip_id: String) -> void:
	# Check if equipment is already in slots
	for slot in equipment_slots:
		if slot.get_meta("equip_id") == equip_id:
			return
	
	dragging_equipment = equip_id
	dragging_from_slot = -1
	_create_equipment_drag_preview(equip_id)

func _on_equipment_thumbnail_released(_equip_id: String) -> void:
	if dragging_equipment == "":
		return
	
	_handle_equipment_drop()

func _create_equipment_drag_preview(equip_id: String) -> void:
	var equip_data = EquipmentDatabase.get_equipment(equip_id)
	drag_preview = TextureRect.new()
	drag_preview.custom_minimum_size = Vector2(100, 140)
	drag_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Load the card image
	var image_path = equip_data.get("image", "")
	if ResourceLoader.exists(image_path):
		drag_preview.texture = load(image_path)
	
	drag_preview.modulate = Color(1, 1, 1, 0.8)
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drag_preview)

func _handle_equipment_drop() -> void:
	var mouse_pos = get_global_mouse_position()
	var target_slot = -1
	
	for i in range(equipment_slots.size()):
		var slot = equipment_slots[i]
		var slot_rect = Rect2(slot.global_position, slot.size)
		if slot_rect.has_point(mouse_pos):
			target_slot = i
			break
	
	if target_slot != -1:
		if dragging_from_slot == -1:
			_remove_equipment_from_slot(target_slot)
			_assign_equipment_to_slot(dragging_equipment, target_slot)
		else:
			var target_equip = equipment_slots[target_slot].get_meta("equip_id")
			var source_equip = dragging_equipment
			
			_clear_equipment_slot_visual(dragging_from_slot)
			_clear_equipment_slot_visual(target_slot)
			
			_assign_equipment_to_slot(source_equip, target_slot)
			if target_equip != "":
				_assign_equipment_to_slot(target_equip, dragging_from_slot)
	
	dragging_equipment = ""
	dragging_from_slot = -1
	if drag_preview:
		drag_preview.queue_free()
		drag_preview = null

func _clear_equipment_slot_visual(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= equipment_slots.size():
		return
	
	var slot = equipment_slots[slot_index]
	var equip_id = slot.get_meta("equip_id")
	
	slot.set_meta("equip_id", "")
	
	# Show empty elements
	var bg = slot.get_node("Background")
	bg.visible = true
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = true
	
	# Hide and clear card container
	var card_container = slot.get_node("CardContainer")
	card_container.visible = false
	for child in card_container.get_children():
		child.queue_free()
	
	if equip_id != "":
		_update_equipment_thumbnail_state(equip_id, false)

func _on_equipment_slot_pressed(slot_index: int) -> void:
	var equip_id = equipment_slots[slot_index].get_meta("equip_id")
	if equip_id == "":
		return
	
	dragging_equipment = equip_id
	dragging_from_slot = slot_index
	_create_equipment_drag_preview(equip_id)

func _on_equipment_slot_released(_slot_index: int) -> void:
	if dragging_equipment == "":
		return
	
	_handle_equipment_drop()

func _assign_hero_to_slot(hero_id: String, slot_index: int) -> void:
	if slot_index < 0 or slot_index >= team_slots.size():
		return
	
	var slot = team_slots[slot_index]
	var hero_data = HeroDatabase.get_hero(hero_id)
	
	if hero_data.is_empty():
		return
	
	# Update slot meta
	slot.set_meta("hero_id", hero_id)
	
	var slot_width = 200
	var slot_height = 230  # Same as equipment
	var ground_y = slot_height  # Bottom of background = ground level
	
	# Update sprite - load texture and position at ground level
	var sprite = slot.get_node("HeroSprite")
	var idle_path = hero_data.get("idle_sprite", "")
	if ResourceLoader.exists(idle_path):
		sprite.texture = load(idle_path)
		sprite.visible = true
		
		# Get original texture size
		var tex_size = sprite.texture.get_size()
		
		# Position sprite: horizontally centered, bottom at ground level
		sprite.position.x = (slot_width - tex_size.x) / 2
		sprite.position.y = ground_y - tex_size.y
	
	# Update background with role color
	var bg = slot.get_node("Background")
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.2)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = role_color
	style.border_color.a = 0.9
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)
	
	# Hide empty label
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = false
	
	# Update thumbnail to show it's used
	_update_thumbnail_state(hero_id, true)

func _remove_hero_from_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= team_slots.size():
		return
	
	var slot = team_slots[slot_index]
	var hero_id = slot.get_meta("hero_id")
	
	if hero_id == "":
		return
	
	# Clear slot meta
	slot.set_meta("hero_id", "")
	
	var slot_width = 200
	var slot_height = 230
	
	# Hide sprite and clear texture
	var sprite = slot.get_node("HeroSprite")
	sprite.visible = false
	sprite.texture = null
	sprite.position = Vector2.ZERO
	
	# Show empty label
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = true
	
	# Reset background to default position
	var bg = slot.get_node("Background")
	bg.position = Vector2(0, 0)
	bg.custom_minimum_size = Vector2(slot_width, slot_height)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.3)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.5, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)
	
	# Update thumbnail to show it's available
	_update_thumbnail_state(hero_id, false)

func _update_thumbnail_state(hero_id: String, is_used: bool) -> void:
	if not hero_thumbnails.has(hero_id):
		return
	
	var thumbnail = hero_thumbnails[hero_id]
	if is_used:
		thumbnail.modulate = Color(0.5, 0.5, 0.5, 0.7)
	else:
		thumbnail.modulate = Color(1, 1, 1, 1)

func _on_thumbnail_pressed(hero_id: String) -> void:
	# Check if hero is already in team
	for slot in team_slots:
		if slot.get_meta("hero_id") == hero_id:
			return  # Already in team
	
	# Check role limit (max 2 of same role)
	var hero_data = HeroDatabase.get_hero(hero_id)
	var hero_role = hero_data.get("role", "")
	if _count_role_in_team(hero_role) >= 2:
		_show_role_limit_notification(hero_role)
		return
	
	dragging_hero = hero_id
	dragging_from_slot = -1  # From roster
	_create_drag_preview(hero_id)

func _on_thumbnail_released(hero_id: String) -> void:
	if dragging_hero == "":
		return
	
	_handle_drop()

func _create_drag_preview(hero_id: String) -> void:
	var hero_data = HeroDatabase.get_hero(hero_id)
	drag_preview = TextureRect.new()
	drag_preview.custom_minimum_size = Vector2(80, 80)
	drag_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path = hero_data.get("portrait", "")
	if ResourceLoader.exists(portrait_path):
		drag_preview.texture = load(portrait_path)
	drag_preview.modulate = Color(1, 1, 1, 0.8)
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(drag_preview)

func _handle_drop() -> void:
	var mouse_pos = get_global_mouse_position()
	var target_slot = -1
	
	# Find which slot we're over
	for i in range(team_slots.size()):
		var slot = team_slots[i]
		var slot_rect = Rect2(slot.global_position, slot.size)
		if slot_rect.has_point(mouse_pos):
			target_slot = i
			break
	
	if target_slot != -1:
		if dragging_from_slot == -1:
			# Dragging from roster to slot
			_remove_hero_from_slot(target_slot)
			_assign_hero_to_slot(dragging_hero, target_slot)
		else:
			# Dragging from slot to slot (swap)
			var target_hero = team_slots[target_slot].get_meta("hero_id")
			var source_hero = dragging_hero
			
			# Clear both slots first
			_clear_slot_visual(dragging_from_slot)
			_clear_slot_visual(target_slot)
			
			# Assign swapped heroes
			_assign_hero_to_slot(source_hero, target_slot)
			if target_hero != "":
				_assign_hero_to_slot(target_hero, dragging_from_slot)
	
	# Cleanup
	dragging_hero = ""
	dragging_from_slot = -1
	if drag_preview:
		drag_preview.queue_free()
		drag_preview = null

func _clear_slot_visual(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= team_slots.size():
		return
	
	var slot = team_slots[slot_index]
	var hero_id = slot.get_meta("hero_id")
	var slot_width = 200
	var slot_height = 230
	
	slot.set_meta("hero_id", "")
	
	var sprite = slot.get_node("HeroSprite")
	sprite.visible = false
	sprite.texture = null
	sprite.position = Vector2.ZERO
	
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = true
	
	# Reset background to default position
	var bg = slot.get_node("Background")
	bg.position = Vector2(0, 0)
	bg.custom_minimum_size = Vector2(slot_width, slot_height)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.3)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.5, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)
	
	if hero_id != "":
		_update_thumbnail_state(hero_id, false)

func _process(_delta: float) -> void:
	if drag_preview and (dragging_hero != "" or dragging_equipment != ""):
		drag_preview.global_position = get_global_mouse_position() - Vector2(40, 40)

func _on_slot_pressed(slot_index: int) -> void:
	var hero_id = team_slots[slot_index].get_meta("hero_id")
	if hero_id == "":
		return  # Empty slot
	
	dragging_hero = hero_id
	dragging_from_slot = slot_index
	_create_drag_preview(hero_id)

func _on_slot_released(slot_index: int) -> void:
	if dragging_hero == "":
		return
	
	_handle_drop()

func _on_back_pressed() -> void:
	SceneTransition.change_scene("res://scenes/dashboard/dashboard.tscn")

func _on_confirm_pressed() -> void:
	# Build team array from slots
	var new_team: Array = []
	for slot in team_slots:
		var hero_id = slot.get_meta("hero_id")
		if hero_id != "":
			new_team.append(hero_id)
	
	# Build equipment array from slots
	var new_equipment: Array = []
	for slot in equipment_slots:
		var equip_id = slot.get_meta("equip_id")
		if equip_id != "":
			new_equipment.append(equip_id)
	
	# Save team to HeroDatabase and persist to file
	HeroDatabase.set_current_team(new_team)
	HeroDatabase.save_data()
	
	# Save equipment to EquipmentDatabase and persist to file
	EquipmentDatabase.set_equipped_items(new_equipment)
	EquipmentDatabase.save_data()
	
	# Save to PlayerData for cloud sync (slot 0 = current team)
	if has_node("/root/PlayerData"):
		var player_data = get_node("/root/PlayerData")
		player_data.save_team_loadout(0, "Current Team", new_team, new_equipment)
	
	# Trigger cloud sync if logged in
	if has_node("/root/AccountManager"):
		var account_mgr = get_node("/root/AccountManager")
		if account_mgr.is_logged_in() and not account_mgr.is_guest():
			account_mgr.sync_to_cloud()
	
	print("Team saved: ", new_team)
	print("Equipment saved: ", new_equipment)
	_show_save_notification()

func _count_role_in_team(role: String) -> int:
	var count = 0
	for slot in team_slots:
		var hero_id = slot.get_meta("hero_id")
		if hero_id != "":
			var hero_data = HeroDatabase.get_hero(hero_id)
			if hero_data.get("role", "") == role:
				count += 1
	return count

func _show_role_limit_notification(role: String) -> void:
	var popup = Panel.new()
	popup.custom_minimum_size = Vector2(300, 60)
	popup.position = Vector2(get_viewport_rect().size.x / 2 - 150, 100)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.7, 0.2, 0.2, 0.9)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	popup.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.text = "Max 2 " + role.capitalize() + "s allowed!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(300, 60)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	popup.add_child(label)
	
	add_child(popup)
	
	var tween = create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(popup, "modulate:a", 0.0, 0.5)
	tween.tween_callback(popup.queue_free)

func _show_save_notification() -> void:
	# Determine if cloud sync is happening
	var is_syncing_to_cloud = false
	if has_node("/root/AccountManager"):
		var account_mgr = get_node("/root/AccountManager")
		is_syncing_to_cloud = account_mgr.is_logged_in() and not account_mgr.is_guest()
	
	# Create popup notification
	var popup = Panel.new()
	popup.custom_minimum_size = Vector2(280, 60)
	popup.position = Vector2(get_viewport_rect().size.x / 2 - 140, 100)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.6, 0.2, 0.9)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	popup.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	if is_syncing_to_cloud:
		label.text = "Team Saved & Synced to Cloud!"
	else:
		label.text = "Team & Equipment Saved!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(280, 60)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	popup.add_child(label)
	
	add_child(popup)
	
	# Fade out and remove after 1.5 seconds
	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(popup, "modulate:a", 0.0, 0.5)
	tween.tween_callback(popup.queue_free)

func _on_equipment_hover(container: Control, equip_data: Dictionary) -> void:
	_on_equipment_hover_exit()  # Clear any existing tooltip
	
	hover_tooltip = Panel.new()
	hover_tooltip.custom_minimum_size = Vector2(280, 80)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0)  # 100% opacity
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.5, 0.2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	hover_tooltip.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(10, 8)
	vbox.custom_minimum_size = Vector2(260, 60)
	
	var name_label = Label.new()
	name_label.text = equip_data.get("name", "")
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(name_label)
	
	var desc_label = Label.new()
	desc_label.text = equip_data.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(260, 40)
	vbox.add_child(desc_label)
	
	hover_tooltip.add_child(vbox)
	
	# Position below the hovered item
	hover_tooltip.position = container.global_position + Vector2(0, 125)
	hover_tooltip.z_index = 100
	
	add_child(hover_tooltip)

func _on_equipment_hover_exit() -> void:
	if hover_tooltip and is_instance_valid(hover_tooltip):
		hover_tooltip.queue_free()
		hover_tooltip = null
