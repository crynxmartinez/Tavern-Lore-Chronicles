extends Node

# Debug script to allow dragging heroes and printing their positions
# Run this scene to position heroes, then copy the printed positions

var dragging_hero: Control = null
var drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	print("=== HERO POSITION DEBUG MODE ===")
	print("Drag heroes to position them.")
	print("Press SPACE to print all positions.")
	print("Press S to save positions to file.")
	print("================================")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_start_drag(event.position)
			else:
				_stop_drag()
	
	elif event is InputEventMouseMotion and dragging_hero:
		dragging_hero.global_position = event.position - drag_offset
	
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			_print_all_positions()
		elif event.keycode == KEY_S:
			_save_positions_to_file()

func _try_start_drag(mouse_pos: Vector2) -> void:
	# Find all heroes and check if mouse is over one
	var heroes = get_tree().get_nodes_in_group("heroes")
	if heroes.is_empty():
		# Try to find heroes by class
		for node in get_tree().get_nodes_in_group(""):
			if node.has_method("setup") and node is Control:
				heroes.append(node)
	
	# Also search for Hero nodes directly
	if heroes.is_empty():
		_find_heroes_recursive(get_tree().root, heroes)
	
	for hero in heroes:
		if hero is Control:
			var rect = Rect2(hero.global_position, hero.size)
			if rect.has_point(mouse_pos):
				dragging_hero = hero
				drag_offset = mouse_pos - hero.global_position
				print("Started dragging: ", hero.name)
				return

func _find_heroes_recursive(node: Node, heroes: Array) -> void:
	if node.name == "Hero" or (node.has_method("setup") and node is Control):
		heroes.append(node)
	for child in node.get_children():
		_find_heroes_recursive(child, heroes)

func _stop_drag() -> void:
	if dragging_hero:
		print("Dropped ", dragging_hero.name, " at position: ", dragging_hero.global_position)
		print("  z_index: ", dragging_hero.z_index)
		dragging_hero = null

func _print_all_positions() -> void:
	print("\n=== ALL HERO POSITIONS ===")
	var heroes = []
	_find_heroes_recursive(get_tree().root, heroes)
	
	var index = 1
	for hero in heroes:
		if hero is Control:
			print("Position ", index, ": ", hero.global_position, " | z_index: ", hero.z_index)
			index += 1
	print("==========================\n")

func _save_positions_to_file() -> void:
	var heroes = []
	_find_heroes_recursive(get_tree().root, heroes)
	
	var file = FileAccess.open("res://hero_positions.txt", FileAccess.WRITE)
	if file:
		file.store_line("# Hero Positions - Copy these values")
		var index = 1
		for hero in heroes:
			if hero is Control:
				file.store_line("Position %d: x=%d, y=%d, z_index=%d" % [index, hero.global_position.x, hero.global_position.y, hero.z_index])
				index += 1
		file.close()
		print("Positions saved to res://hero_positions.txt")
