@tool
extends Control

# Battle Position Editor - Works in the Godot Editor!
# Move the marker nodes in the 2D view, then click "Print Positions" button

@export var print_positions_button: bool = false:
	set(value):
		if value:
			_print_positions()

func _print_positions() -> void:
	print("\n=== COPY THIS INTO battle.gd ===\n")
	
	var code = "const PLAYER_HERO_POSITIONS = [\n"
	for i in range(1, 5):
		var marker = get_node_or_null("Board/P" + str(i))
		if marker:
			code += "\tVector2(%d, %d),  # Position %d\n" % [int(marker.position.x), int(marker.position.y), i]
	code += "]\n\n"
	
	code += "const ENEMY_HERO_POSITIONS = [\n"
	for i in range(1, 5):
		var marker = get_node_or_null("Board/E" + str(i))
		if marker:
			code += "\tVector2(%d, %d),  # Position %d\n" % [int(marker.position.x), int(marker.position.y), i + 4]
	code += "]"
	
	print(code)
	print("\n=================================\n")
