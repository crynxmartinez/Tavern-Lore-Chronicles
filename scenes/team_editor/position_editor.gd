extends Control

var slot_nodes: Array = []  # Array of slot Controls (index = position)
var dragging_from_slot: int = -1
var drag_preview: TextureRect = null

@onready var back_button: Button = $UI/BackButton
@onready var save_button: Button = $UI/SaveButton
@onready var battlefield: Control = $Battlefield

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	save_button.pressed.connect(_on_save_pressed)
	
	_create_position_slots()
	_load_current_team()

func _create_position_slots() -> void:
	# Create 4 fixed position slots matching battle layout
	var slot_positions = [
		Vector2(150, 300),
		Vector2(400, 300),
		Vector2(650, 300),
		Vector2(900, 300)
	]
	
	for i in range(4):
		var slot = _create_slot(i, slot_positions[i])
		battlefield.add_child(slot)
		slot_nodes.append(slot)

func _create_slot(index: int, pos: Vector2) -> Control:
	var container = Control.new()
	container.position = pos
	container.custom_minimum_size = Vector2(200, 280)
	container.set_meta("slot_index", index)
	container.set_meta("hero_id", "")
	
	# Position label
	var pos_label = Label.new()
	pos_label.text = "Position " + str(index + 1)
	pos_label.position = Vector2(0, -30)
	pos_label.custom_minimum_size = Vector2(200, 25)
	pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pos_label.add_theme_font_size_override("font_size", 16)
	pos_label.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(pos_label)
	
	# Background panel (hidden when empty)
	var bg = Panel.new()
	bg.custom_minimum_size = Vector2(200, 250)
	bg.position = Vector2(0, 0)
	bg.name = "Background"
	bg.visible = false
	container.add_child(bg)
	
	# Hero sprite
	var sprite = TextureRect.new()
	sprite.position = Vector2(0, 0)
	sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	sprite.name = "HeroSprite"
	sprite.visible = false
	container.add_child(sprite)
	
	# Empty slot indicator
	var empty_label = Label.new()
	empty_label.text = "+"
	empty_label.position = Vector2(0, 100)
	empty_label.custom_minimum_size = Vector2(200, 60)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.5))
	empty_label.add_theme_font_size_override("font_size", 48)
	empty_label.name = "EmptyLabel"
	container.add_child(empty_label)
	
	# Click area for dragging
	var click_area = Button.new()
	click_area.flat = true
	click_area.custom_minimum_size = Vector2(200, 250)
	click_area.position = Vector2(0, 0)
	click_area.button_down.connect(_on_slot_pressed.bind(index))
	click_area.button_up.connect(_on_slot_released.bind(index))
	click_area.name = "ClickArea"
	
	# Make button invisible
	var empty_style = StyleBoxEmpty.new()
	click_area.add_theme_stylebox_override("normal", empty_style)
	click_area.add_theme_stylebox_override("hover", empty_style)
	click_area.add_theme_stylebox_override("pressed", empty_style)
	click_area.add_theme_stylebox_override("focus", empty_style)
	container.add_child(click_area)
	
	return container

func _load_current_team() -> void:
	var team = HeroDatabase.get_current_team()
	for i in range(min(team.size(), slot_nodes.size())):
		_assign_hero_to_slot(team[i], i)

func _assign_hero_to_slot(hero_id: String, slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slot_nodes.size():
		return
	
	var slot = slot_nodes[slot_index]
	var hero_data = HeroDatabase.get_hero(hero_id)
	
	if hero_data.is_empty():
		return
	
	slot.set_meta("hero_id", hero_id)
	
	# Update sprite
	var sprite = slot.get_node("HeroSprite")
	var idle_path = hero_data.get("idle_sprite", "")
	if ResourceLoader.exists(idle_path):
		sprite.texture = load(idle_path)
		sprite.visible = true
		
		var tex_size = sprite.texture.get_size()
		
		# Show and style background
		var bg = slot.get_node("Background")
		bg.visible = true
		var bg_height = 250
		bg.position.y = tex_size.y - bg_height
		bg.custom_minimum_size = Vector2(tex_size.x, bg_height)
		
		var role = hero_data.get("role", "tank")
		var role_color = HeroDatabase.get_role_color(role)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.1)
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		style.border_color = role_color
		style.border_color.a = 0.8
		style.corner_radius_top_left = 5
		style.corner_radius_top_right = 5
		style.corner_radius_bottom_left = 5
		style.corner_radius_bottom_right = 5
		bg.add_theme_stylebox_override("panel", style)
	
	# Hide empty label
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = false

func _clear_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slot_nodes.size():
		return
	
	var slot = slot_nodes[slot_index]
	slot.set_meta("hero_id", "")
	
	var sprite = slot.get_node("HeroSprite")
	sprite.visible = false
	sprite.texture = null
	
	var empty_label = slot.get_node("EmptyLabel")
	empty_label.visible = true
	
	var bg = slot.get_node("Background")
	bg.visible = false

func _on_slot_pressed(slot_index: int) -> void:
	var hero_id = slot_nodes[slot_index].get_meta("hero_id")
	if hero_id == "":
		return
	
	dragging_from_slot = slot_index
	_create_drag_preview(hero_id)

func _on_slot_released(_slot_index: int) -> void:
	if dragging_from_slot == -1:
		return
	
	_handle_drop()

func _create_drag_preview(hero_id: String) -> void:
	var hero_data = HeroDatabase.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
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
	for i in range(slot_nodes.size()):
		var slot = slot_nodes[i]
		var slot_rect = Rect2(slot.global_position, slot.custom_minimum_size)
		if slot_rect.has_point(mouse_pos):
			target_slot = i
			break
	
	if target_slot != -1 and target_slot != dragging_from_slot:
		# Swap heroes between slots
		var source_hero = slot_nodes[dragging_from_slot].get_meta("hero_id")
		var target_hero = slot_nodes[target_slot].get_meta("hero_id")
		
		_clear_slot(dragging_from_slot)
		_clear_slot(target_slot)
		
		_assign_hero_to_slot(source_hero, target_slot)
		if target_hero != "":
			_assign_hero_to_slot(target_hero, dragging_from_slot)
	
	# Cleanup
	dragging_from_slot = -1
	if drag_preview:
		drag_preview.queue_free()
		drag_preview = null

func _process(_delta: float) -> void:
	if drag_preview and dragging_from_slot != -1:
		drag_preview.global_position = get_global_mouse_position() - Vector2(40, 40)

func _on_back_pressed() -> void:
	SceneTransition.change_scene("res://scenes/team_editor/team_editor.tscn")

func _on_save_pressed() -> void:
	# Build new team order from slots
	var new_team: Array = []
	for slot in slot_nodes:
		var hero_id = slot.get_meta("hero_id")
		if hero_id != "":
			new_team.append(hero_id)
	
	# Save reordered team to HeroDatabase and persist to file
	HeroDatabase.set_current_team(new_team)
	HeroDatabase.save_data()
	
	print("Team order saved:")
	for i in range(new_team.size()):
		print("  Position %d: %s" % [i + 1, new_team[i]])
	
	_show_save_notification()

func _show_save_notification() -> void:
	# Create popup notification
	var popup = Panel.new()
	popup.custom_minimum_size = Vector2(200, 60)
	popup.position = Vector2(get_viewport_rect().size.x / 2 - 100, 100)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.6, 0.2, 0.9)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	popup.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.text = "Position Saved!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(200, 60)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	popup.add_child(label)
	
	add_child(popup)
	
	# Fade out and remove after 1.5 seconds
	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(popup, "modulate:a", 0.0, 0.5)
	tween.tween_callback(popup.queue_free)
