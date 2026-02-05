extends Control
class_name HeroShadow

@export var shadow_color: Color = Color(0, 0, 0, 0.75)

func _draw() -> void:
	var center = Vector2(size.x / 2, size.y / 2)
	var radius = Vector2(size.x / 2, size.y / 2)
	draw_ellipse(center, radius, shadow_color)

func draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var angle = i * TAU / segments
		var point = center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		points.append(point)
	draw_colored_polygon(points, color)
