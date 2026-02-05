extends Node

# VFX Manager - Handles visual effects spawning
# Add to autoload as "VFXManager"

var DamageNumberScene: PackedScene = null
var CardParticlesScene: PackedScene = null

# Screen shake
var shake_intensity: float = 0.0
var shake_decay: float = 5.0
var original_camera_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Lazy load scenes to avoid startup errors
	if ResourceLoader.exists("res://scenes/effects/damage_number.tscn"):
		DamageNumberScene = load("res://scenes/effects/damage_number.tscn")
	if ResourceLoader.exists("res://scenes/effects/card_particles.tscn"):
		CardParticlesScene = load("res://scenes/effects/card_particles.tscn")

func _process(delta: float) -> void:
	if shake_intensity > 0:
		shake_intensity = max(shake_intensity - shake_decay * delta, 0)
		_apply_shake()

# ============================================
# DAMAGE NUMBERS
# ============================================

func spawn_damage_number(parent: Node, position: Vector2, value: int, type: String = "damage") -> void:
	if DamageNumberScene == null:
		return
	var damage_num = DamageNumberScene.instantiate()
	parent.add_child(damage_num)
	damage_num.global_position = position
	damage_num.setup(value, type)

func spawn_damage(parent: Node, position: Vector2, value: int) -> void:
	spawn_damage_number(parent, position, value, "damage")

func spawn_heal(parent: Node, position: Vector2, value: int) -> void:
	spawn_damage_number(parent, position, value, "heal")

func spawn_shield(parent: Node, position: Vector2, value: int) -> void:
	spawn_damage_number(parent, position, value, "shield")

func spawn_crit(parent: Node, position: Vector2, value: int) -> void:
	spawn_damage_number(parent, position, value, "crit")

func spawn_miss(parent: Node, position: Vector2) -> void:
	spawn_damage_number(parent, position, 0, "miss")

func spawn_block(parent: Node, position: Vector2) -> void:
	spawn_damage_number(parent, position, 0, "block")

# ============================================
# PARTICLES
# ============================================

func spawn_card_play_particles(parent: Node, position: Vector2, color: Color = Color.GOLD) -> void:
	if CardParticlesScene == null:
		return
	var particles = CardParticlesScene.instantiate()
	parent.add_child(particles)
	particles.global_position = position
	particles.play_effect(CardParticles.ParticleType.CARD_PLAY, color)

func spawn_card_draw_particles(parent: Node, position: Vector2, color: Color = Color.WHITE) -> void:
	if CardParticlesScene == null:
		return
	var particles = CardParticlesScene.instantiate()
	parent.add_child(particles)
	particles.global_position = position
	particles.play_effect(CardParticles.ParticleType.CARD_DRAW, color)

func spawn_damage_particles(parent: Node, position: Vector2) -> void:
	if CardParticlesScene == null:
		return
	var particles = CardParticlesScene.instantiate()
	parent.add_child(particles)
	particles.global_position = position
	particles.play_effect(CardParticles.ParticleType.DAMAGE)

func spawn_heal_particles(parent: Node, position: Vector2) -> void:
	if CardParticlesScene == null:
		return
	var particles = CardParticlesScene.instantiate()
	parent.add_child(particles)
	particles.global_position = position
	particles.play_effect(CardParticles.ParticleType.HEAL)

func spawn_buff_particles(parent: Node, position: Vector2, color: Color = Color.YELLOW) -> void:
	if CardParticlesScene == null:
		return
	var particles = CardParticlesScene.instantiate()
	parent.add_child(particles)
	particles.global_position = position
	particles.play_effect(CardParticles.ParticleType.BUFF, color)

func spawn_debuff_particles(parent: Node, position: Vector2) -> void:
	if CardParticlesScene == null:
		return
	var particles = CardParticlesScene.instantiate()
	parent.add_child(particles)
	particles.global_position = position
	particles.play_effect(CardParticles.ParticleType.DEBUFF)

# ============================================
# SCREEN SHAKE
# ============================================

func shake_screen(intensity: float = 10.0, decay: float = 5.0) -> void:
	shake_intensity = intensity
	shake_decay = decay

func _apply_shake() -> void:
	var viewport = get_viewport()
	if viewport:
		var offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		viewport.canvas_transform.origin = offset

# ============================================
# FLASH EFFECTS
# ============================================

func flash_node(node: CanvasItem, color: Color = Color.WHITE, duration: float = 0.1) -> void:
	if not is_instance_valid(node):
		return
	
	var original_modulate = node.modulate
	node.modulate = color
	
	await get_tree().create_timer(duration).timeout
	
	if is_instance_valid(node):
		node.modulate = original_modulate

func flash_damage(node: CanvasItem) -> void:
	flash_node(node, Color(1, 0.3, 0.3), 0.15)

func flash_heal(node: CanvasItem) -> void:
	flash_node(node, Color(0.3, 1, 0.3), 0.15)

# ============================================
# TWEEN EFFECTS
# ============================================

func punch_scale(node: Control, punch_amount: float = 0.2, duration: float = 0.2) -> void:
	if not is_instance_valid(node):
		return
	
	var original_scale = node.scale
	var tween = create_tween()
	tween.tween_property(node, "scale", original_scale * (1.0 + punch_amount), duration * 0.3)
	tween.tween_property(node, "scale", original_scale, duration * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

func bounce_in(node: Control, duration: float = 0.3) -> void:
	if not is_instance_valid(node):
		return
	
	node.scale = Vector2.ZERO
	var tween = create_tween()
	tween.tween_property(node, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func fade_in(node: CanvasItem, duration: float = 0.3) -> void:
	if not is_instance_valid(node):
		return
	
	node.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration)

func fade_out(node: CanvasItem, duration: float = 0.3, free_after: bool = false) -> void:
	if not is_instance_valid(node):
		return
	
	var tween = create_tween()
	tween.tween_property(node, "modulate:a", 0.0, duration)
	
	if free_after:
		await tween.finished
		if is_instance_valid(node):
			node.queue_free()

func slide_in(node: Control, from_offset: Vector2, duration: float = 0.3) -> void:
	if not is_instance_valid(node):
		return
	
	var target_pos = node.position
	node.position = target_pos + from_offset
	var tween = create_tween()
	tween.tween_property(node, "position", target_pos, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
