extends CanvasLayer

var overlay: ColorRect
var is_transitioning: bool = false

func _ready() -> void:
	layer = 100
	
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 1)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	
	# Start faded in, then fade out to reveal scene
	_fade_in()

func _fade_in() -> void:
	overlay.modulate.a = 1.0
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.5)
	await tween.finished
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func change_scene(target_scene: String) -> void:
	if is_transitioning:
		return
	
	is_transitioning = true
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Fade out (to black)
	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(overlay, "modulate:a", 1.0, 0.4)
	await tween.finished
	
	# Change scene
	get_tree().change_scene_to_file(target_scene)
	
	# Wait a frame for scene to load
	await get_tree().process_frame
	
	# Fade in (from black)
	var tween2 = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween2.tween_property(overlay, "modulate:a", 0.0, 0.5)
	await tween2.finished
	
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
