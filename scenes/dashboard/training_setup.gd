extends CanvasLayer

signal training_confirmed(enemy_team: Array, player_first: bool)
signal training_cancelled

enum Phase { TEAM_TYPE, HERO_PICKER, TURN_ORDER }

var current_phase: Phase = Phase.TEAM_TYPE
var enemy_team: Array = []
var hero_thumbnails: Dictionary = {}
var team_slots: Array = []

# UI references
var blur_overlay: ColorRect
var main_panel: Panel
var phase_container: Control

# Team type phase
var random_button: Button
var create_button: Button
var mirror_button: Button

# Hero picker phase
var roster_scroll: ScrollContainer
var roster_container: HBoxContainer
var slots_container: HBoxContainer
var picker_confirm_button: Button
var picker_back_button: Button
var picker_title: Label

# Turn order phase
var we_start_button: Button
var opponent_start_button: Button
var turn_title: Label
var team_preview_container: HBoxContainer

func _ready() -> void:
	_build_ui()
	_show_phase(Phase.TEAM_TYPE)
	_animate_in()

func _build_ui() -> void:
	# Blur overlay
	blur_overlay = ColorRect.new()
	blur_overlay.color = Color(0, 0, 0, 0.7)
	blur_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur_overlay.modulate.a = 0
	add_child(blur_overlay)
	
	# Main panel
	main_panel = Panel.new()
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(700, 500)
	main_panel.position = Vector2(-350, -250)
	main_panel.modulate.a = 0
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.6, 1.0, 0.6)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	main_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(main_panel)
	
	# Phase container (holds all phase UIs)
	phase_container = Control.new()
	phase_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_panel.add_child(phase_container)
	
	_build_team_type_phase()
	_build_hero_picker_phase()
	_build_turn_order_phase()

# ============================================
# PHASE 1: TEAM TYPE SELECTION
# ============================================

func _build_team_type_phase() -> void:
	var container = VBoxContainer.new()
	container.name = "TeamTypePhase"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("separation", 20)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	phase_container.add_child(container)
	
	# Title
	var title = Label.new()
	title.text = "TRAINING MODE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	container.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Choose your opponent"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	container.add_child(subtitle)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer)
	
	# Buttons container (horizontal)
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	container.add_child(buttons)
	
	random_button = _create_mode_button("RANDOM\nENEMY", "AI drafts a balanced team", Color(0.2, 0.6, 1.0))
	random_button.pressed.connect(_on_random_pressed)
	buttons.add_child(random_button)
	
	create_button = _create_mode_button("CREATE\nOPPONENT", "Pick the enemy team yourself", Color(0.9, 0.5, 0.1))
	create_button.pressed.connect(_on_create_pressed)
	buttons.add_child(create_button)
	
	mirror_button = _create_mode_button("MIRROR\nMATCH", "Fight a copy of your team", Color(0.6, 0.2, 0.8))
	mirror_button.pressed.connect(_on_mirror_pressed)
	buttons.add_child(mirror_button)
	
	# Cancel button
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 36)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.pressed.connect(_on_cancel)
	container.add_child(cancel_btn)

func _create_mode_button(title_text: String, desc_text: String, accent: Color) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(180, 140)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.12, 0.18, 0.95)
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = accent.darkened(0.3)
	style_normal.corner_radius_top_left = 12
	style_normal.corner_radius_top_right = 12
	style_normal.corner_radius_bottom_left = 12
	style_normal.corner_radius_bottom_right = 12
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover = style_normal.duplicate()
	style_hover.border_color = accent
	style_hover.bg_color = Color(0.15, 0.15, 0.22, 0.95)
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = accent.darkened(0.6)
	style_pressed.border_color = accent
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.text = title_text + "\n\n" + desc_text
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color.WHITE)
	
	return btn

# ============================================
# PHASE 2: HERO PICKER
# ============================================

func _build_hero_picker_phase() -> void:
	var container = VBoxContainer.new()
	container.name = "HeroPickerPhase"
	container.visible = false
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("separation", 10)
	phase_container.add_child(container)
	
	# Top bar
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	container.add_child(top_bar)
	
	picker_back_button = Button.new()
	picker_back_button.text = "< Back"
	picker_back_button.custom_minimum_size = Vector2(80, 32)
	picker_back_button.add_theme_font_size_override("font_size", 14)
	picker_back_button.pressed.connect(_on_picker_back)
	top_bar.add_child(picker_back_button)
	
	picker_title = Label.new()
	picker_title.text = "SELECT ENEMY TEAM (pick 3-4 heroes)"
	picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	picker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_title.add_theme_font_size_override("font_size", 18)
	picker_title.add_theme_color_override("font_color", Color(0.9, 0.5, 0.1))
	top_bar.add_child(picker_title)
	
	# Enemy team slots (3-4 slots at top)
	var slots_panel = Panel.new()
	slots_panel.custom_minimum_size = Vector2(0, 110)
	var slots_style = StyleBoxFlat.new()
	slots_style.bg_color = Color(0.05, 0.05, 0.08, 0.8)
	slots_style.corner_radius_top_left = 8
	slots_style.corner_radius_top_right = 8
	slots_style.corner_radius_bottom_left = 8
	slots_style.corner_radius_bottom_right = 8
	slots_panel.add_theme_stylebox_override("panel", slots_style)
	container.add_child(slots_panel)
	
	slots_container = HBoxContainer.new()
	slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_container.add_theme_constant_override("separation", 15)
	slots_container.position = Vector2(10, 5)
	slots_container.custom_minimum_size = Vector2(680, 100)
	slots_panel.add_child(slots_container)
	
	# Create 4 enemy slots
	for i in range(4):
		var slot = _create_enemy_slot(i)
		slots_container.add_child(slot)
		team_slots.append(slot)
	
	# Hero roster (scrollable)
	var roster_label = Label.new()
	roster_label.text = "HERO ROSTER"
	roster_label.add_theme_font_size_override("font_size", 14)
	roster_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	container.add_child(roster_label)
	
	roster_scroll = ScrollContainer.new()
	roster_scroll.custom_minimum_size = Vector2(0, 200)
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(roster_scroll)
	
	roster_container = HBoxContainer.new()
	roster_container.add_theme_constant_override("separation", 8)
	roster_scroll.add_child(roster_container)
	
	# Populate roster
	for hero_id in HeroDatabase.heroes.keys():
		var hero_data = HeroDatabase.get_hero(hero_id)
		var thumb = _create_roster_thumbnail(hero_id, hero_data)
		roster_container.add_child(thumb)
		hero_thumbnails[hero_id] = thumb
	
	# Bottom bar
	var bottom_bar = HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END
	bottom_bar.add_theme_constant_override("separation", 10)
	container.add_child(bottom_bar)
	
	picker_confirm_button = Button.new()
	picker_confirm_button.text = "Confirm Team"
	picker_confirm_button.custom_minimum_size = Vector2(140, 40)
	picker_confirm_button.add_theme_font_size_override("font_size", 16)
	picker_confirm_button.pressed.connect(_on_picker_confirm)
	bottom_bar.add_child(picker_confirm_button)

func _create_enemy_slot(index: int) -> Control:
	var slot_size = 90
	var container = Control.new()
	container.custom_minimum_size = Vector2(slot_size, slot_size + 10)
	container.set_meta("slot_index", index)
	container.set_meta("hero_id", "")
	
	# Background
	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(slot_size, slot_size)
	bg.name = "Background"
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.4, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)
	container.add_child(bg)
	
	# Portrait
	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(slot_size - 6, slot_size - 6)
	portrait.position = Vector2(3, 3)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.name = "Portrait"
	portrait.visible = false
	container.add_child(portrait)
	
	# Empty label
	var empty_label = Label.new()
	empty_label.text = str(index + 1)
	empty_label.position = Vector2(0, slot_size / 2 - 15)
	empty_label.custom_minimum_size = Vector2(slot_size, 30)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.5))
	empty_label.add_theme_font_size_override("font_size", 24)
	empty_label.name = "EmptyLabel"
	container.add_child(empty_label)
	
	# Click to remove
	var click_btn = Button.new()
	click_btn.flat = true
	click_btn.custom_minimum_size = Vector2(slot_size, slot_size)
	click_btn.position = Vector2(0, 0)
	click_btn.pressed.connect(_on_slot_clicked.bind(index))
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_style = StyleBoxEmpty.new()
	click_btn.add_theme_stylebox_override("normal", empty_style)
	click_btn.add_theme_stylebox_override("hover", empty_style)
	click_btn.add_theme_stylebox_override("pressed", empty_style)
	click_btn.add_theme_stylebox_override("focus", empty_style)
	container.add_child(click_btn)
	
	return container

func _create_roster_thumbnail(hero_id: String, hero_data: Dictionary) -> Control:
	var thumb_size = 70
	var container = Control.new()
	container.custom_minimum_size = Vector2(thumb_size, thumb_size + 18)
	container.set_meta("hero_id", hero_id)
	
	# Border
	var border = Panel.new()
	border.custom_minimum_size = Vector2(thumb_size, thumb_size)
	
	var style = StyleBoxFlat.new()
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = role_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	border.add_theme_stylebox_override("panel", style)
	container.add_child(border)
	
	# Portrait
	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(thumb_size - 4, thumb_size - 4)
	portrait.position = Vector2(2, 2)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path = hero_data.get("portrait", "")
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	container.add_child(portrait)
	
	# Name
	var name_label = Label.new()
	name_label.text = hero_data.get("name", hero_id)
	name_label.position = Vector2(0, thumb_size + 1)
	name_label.custom_minimum_size = Vector2(thumb_size, 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	container.add_child(name_label)
	
	# Click button
	var btn = Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(thumb_size, thumb_size)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_on_roster_hero_clicked.bind(hero_id))
	var empty_style = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("hover", empty_style)
	btn.add_theme_stylebox_override("pressed", empty_style)
	btn.add_theme_stylebox_override("focus", empty_style)
	container.add_child(btn)
	
	return container

# ============================================
# PHASE 3: TURN ORDER
# ============================================

func _build_turn_order_phase() -> void:
	var container = VBoxContainer.new()
	container.name = "TurnOrderPhase"
	container.visible = false
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("separation", 20)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	phase_container.add_child(container)
	
	turn_title = Label.new()
	turn_title.text = "WHO GOES FIRST?"
	turn_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_title.add_theme_font_size_override("font_size", 28)
	turn_title.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	container.add_child(turn_title)
	
	# Enemy team preview
	var preview_label = Label.new()
	preview_label.text = "Enemy Team:"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.add_theme_font_size_override("font_size", 14)
	preview_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	container.add_child(preview_label)
	
	team_preview_container = HBoxContainer.new()
	team_preview_container.alignment = BoxContainer.ALIGNMENT_CENTER
	team_preview_container.add_theme_constant_override("separation", 10)
	container.add_child(team_preview_container)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer)
	
	# Turn order buttons
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	container.add_child(buttons)
	
	we_start_button = _create_mode_button("WE\nSTART", "Your team acts first", Color(0.2, 0.8, 0.4))
	we_start_button.pressed.connect(_on_we_start)
	buttons.add_child(we_start_button)
	
	opponent_start_button = _create_mode_button("OPPONENT\nSTARTS", "Enemy team acts first", Color(0.9, 0.3, 0.3))
	opponent_start_button.pressed.connect(_on_opponent_start)
	buttons.add_child(opponent_start_button)

# ============================================
# PHASE MANAGEMENT
# ============================================

func _show_phase(phase: Phase) -> void:
	current_phase = phase
	
	var team_type = phase_container.get_node("TeamTypePhase")
	var hero_picker = phase_container.get_node("HeroPickerPhase")
	var turn_order = phase_container.get_node("TurnOrderPhase")
	
	team_type.visible = phase == Phase.TEAM_TYPE
	hero_picker.visible = phase == Phase.HERO_PICKER
	turn_order.visible = phase == Phase.TURN_ORDER
	
	if phase == Phase.TURN_ORDER:
		_update_team_preview()
	
	if phase == Phase.HERO_PICKER:
		_update_picker_confirm_state()

func _update_team_preview() -> void:
	# Clear existing previews
	for child in team_preview_container.get_children():
		child.queue_free()
	
	for hero_id in enemy_team:
		var hero_data = HeroDatabase.get_hero(hero_id)
		if hero_data.is_empty():
			continue
		
		var card = Control.new()
		card.custom_minimum_size = Vector2(80, 100)
		
		var border = Panel.new()
		border.custom_minimum_size = Vector2(80, 80)
		var style = StyleBoxFlat.new()
		var role = hero_data.get("role", "tank")
		style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = HeroDatabase.get_role_color(role)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		border.add_theme_stylebox_override("panel", style)
		card.add_child(border)
		
		var portrait = TextureRect.new()
		portrait.custom_minimum_size = Vector2(74, 74)
		portrait.position = Vector2(3, 3)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var portrait_path = hero_data.get("portrait", "")
		if ResourceLoader.exists(portrait_path):
			portrait.texture = load(portrait_path)
		card.add_child(portrait)
		
		var name_label = Label.new()
		name_label.text = hero_data.get("name", "???")
		name_label.position = Vector2(0, 82)
		name_label.custom_minimum_size = Vector2(80, 16)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 10)
		card.add_child(name_label)
		
		team_preview_container.add_child(card)

# ============================================
# CALLBACKS
# ============================================

func _on_random_pressed() -> void:
	HeroDatabase.generate_ai_team()
	enemy_team = HeroDatabase.ai_enemy_team
	HeroDatabase.training_custom_team = false
	_show_phase(Phase.TURN_ORDER)

func _on_create_pressed() -> void:
	enemy_team.clear()
	_clear_all_slots()
	_reset_all_thumbnails()
	_show_phase(Phase.HERO_PICKER)

func _on_mirror_pressed() -> void:
	enemy_team = HeroDatabase.get_current_team().duplicate()
	HeroDatabase.ai_enemy_team = enemy_team
	HeroDatabase.training_custom_team = true
	_show_phase(Phase.TURN_ORDER)

func _on_picker_back() -> void:
	_show_phase(Phase.TEAM_TYPE)

func _on_picker_confirm() -> void:
	if enemy_team.size() < 3:
		return
	HeroDatabase.ai_enemy_team = enemy_team
	HeroDatabase.training_custom_team = true
	_show_phase(Phase.TURN_ORDER)

func _on_we_start() -> void:
	HeroDatabase.training_player_first = true
	_finish(true)

func _on_opponent_start() -> void:
	HeroDatabase.training_player_first = false
	_finish(false)

func _on_cancel() -> void:
	_animate_out()
	await get_tree().create_timer(0.3).timeout
	training_cancelled.emit()
	queue_free()

func _finish(player_first: bool) -> void:
	_animate_out()
	await get_tree().create_timer(0.3).timeout
	training_confirmed.emit(enemy_team, player_first)
	queue_free()

# ============================================
# HERO PICKER LOGIC
# ============================================

func _on_roster_hero_clicked(hero_id: String) -> void:
	# Don't add if already in team
	if hero_id in enemy_team:
		return
	
	# Don't add if team is full (4 max)
	if enemy_team.size() >= 4:
		return
	
	# Add to team
	enemy_team.append(hero_id)
	_assign_hero_to_next_slot(hero_id)
	_update_thumbnail_state(hero_id, true)
	_update_picker_confirm_state()

func _on_slot_clicked(index: int) -> void:
	if index >= team_slots.size():
		return
	
	var slot = team_slots[index]
	var hero_id = slot.get_meta("hero_id")
	if hero_id == "":
		return
	
	# Remove from team
	enemy_team.erase(hero_id)
	_clear_slot(index)
	_update_thumbnail_state(hero_id, false)
	_update_picker_confirm_state()

func _assign_hero_to_next_slot(hero_id: String) -> void:
	for i in range(team_slots.size()):
		var slot = team_slots[i]
		if slot.get_meta("hero_id") == "":
			_fill_slot(i, hero_id)
			return

func _fill_slot(index: int, hero_id: String) -> void:
	var slot = team_slots[index]
	slot.set_meta("hero_id", hero_id)
	
	var hero_data = HeroDatabase.get_hero(hero_id)
	var portrait = slot.get_node("Portrait")
	var portrait_path = hero_data.get("portrait", "")
	if ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
		portrait.visible = true
	
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = false
	
	# Update border color
	var bg = slot.get_node("Background")
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
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

func _clear_slot(index: int) -> void:
	var slot = team_slots[index]
	slot.set_meta("hero_id", "")
	
	var portrait = slot.get_node("Portrait")
	portrait.visible = false
	portrait.texture = null
	
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = true
	
	var bg = slot.get_node("Background")
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.4, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)

func _clear_all_slots() -> void:
	for i in range(team_slots.size()):
		_clear_slot(i)

func _reset_all_thumbnails() -> void:
	for hero_id in hero_thumbnails:
		_update_thumbnail_state(hero_id, false)

func _update_thumbnail_state(hero_id: String, is_used: bool) -> void:
	if not hero_thumbnails.has(hero_id):
		return
	var thumb = hero_thumbnails[hero_id]
	if is_used:
		thumb.modulate = Color(0.4, 0.4, 0.4, 0.6)
	else:
		thumb.modulate = Color(1, 1, 1, 1)

func _update_picker_confirm_state() -> void:
	if picker_confirm_button:
		picker_confirm_button.disabled = enemy_team.size() < 3
		if enemy_team.size() < 3:
			picker_confirm_button.text = "Pick " + str(3 - enemy_team.size()) + " more"
		else:
			picker_confirm_button.text = "Confirm Team (" + str(enemy_team.size()) + ")"

# ============================================
# ANIMATIONS
# ============================================

func _animate_in() -> void:
	var tween = create_tween()
	tween.tween_property(blur_overlay, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(main_panel, "modulate:a", 1.0, 0.25)

func _animate_out() -> void:
	var tween = create_tween()
	tween.tween_property(main_panel, "modulate:a", 0.0, 0.2)
	tween.parallel().tween_property(blur_overlay, "modulate:a", 0.0, 0.2)
	await tween.finished
