extends Node2D
class_name DamageNumber

@onready var label: Label = $Label

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 1.0
var gravity: float = 100.0
var fade_start: float = 0.5

func _ready() -> void:
	# Random horizontal spread
	velocity = Vector2(randf_range(-50, 50), -150)

func _process(delta: float) -> void:
	# Apply gravity
	velocity.y += gravity * delta
	position += velocity * delta
	
	# Fade out
	lifetime -= delta
	if lifetime <= fade_start:
		modulate.a = lifetime / fade_start
	
	if lifetime <= 0:
		queue_free()

func setup(value: int, type: String = "damage") -> void:
	if not label:
		label = $Label
	
	label.text = str(abs(value))
	
	match type:
		"damage":
			label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
			label.add_theme_font_size_override("font_size", 24)
		"heal":
			label.add_theme_color_override("font_color", Color(0.2, 1, 0.2))
			label.add_theme_font_size_override("font_size", 24)
			label.text = "+" + str(abs(value))
		"shield":
			label.add_theme_color_override("font_color", Color(0.3, 0.7, 1))
			label.add_theme_font_size_override("font_size", 22)
			label.text = "+" + str(abs(value))
		"crit":
			label.add_theme_color_override("font_color", Color(1, 0.8, 0))
			label.add_theme_font_size_override("font_size", 32)
			label.text = str(abs(value)) + "!"
		"miss":
			label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			label.add_theme_font_size_override("font_size", 20)
			label.text = "MISS"
		"block":
			label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.8))
			label.add_theme_font_size_override("font_size", 20)
			label.text = "BLOCKED"
	
	# Add outline
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 3)
