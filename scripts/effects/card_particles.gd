extends GPUParticles2D
class_name CardParticles

enum ParticleType {
	CARD_PLAY,
	CARD_DRAW,
	DAMAGE,
	HEAL,
	BUFF,
	DEBUFF
}

func _ready() -> void:
	one_shot = true
	emitting = false

func play_effect(type: ParticleType, color: Color = Color.WHITE) -> void:
	match type:
		ParticleType.CARD_PLAY:
			_setup_card_play(color)
		ParticleType.CARD_DRAW:
			_setup_card_draw(color)
		ParticleType.DAMAGE:
			_setup_damage()
		ParticleType.HEAL:
			_setup_heal()
		ParticleType.BUFF:
			_setup_buff(color)
		ParticleType.DEBUFF:
			_setup_debuff()
	
	emitting = true
	# Auto-cleanup after particles finish
	await get_tree().create_timer(lifetime + 0.5).timeout
	queue_free()

func _setup_card_play(color: Color) -> void:
	amount = 20
	lifetime = 0.8
	explosiveness = 0.9
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 30.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 100.0
	mat.initial_velocity_max = 200.0
	mat.gravity = Vector3(0, 200, 0)
	mat.scale_min = 3.0
	mat.scale_max = 6.0
	mat.color = color
	process_material = mat

func _setup_card_draw(color: Color) -> void:
	amount = 10
	lifetime = 0.5
	explosiveness = 0.8
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(40, 60, 0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 20.0
	mat.initial_velocity_min = 50.0
	mat.initial_velocity_max = 100.0
	mat.gravity = Vector3(0, -50, 0)
	mat.scale_min = 2.0
	mat.scale_max = 4.0
	mat.color = color
	process_material = mat

func _setup_damage() -> void:
	amount = 15
	lifetime = 0.6
	explosiveness = 1.0
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 20.0
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 150.0
	mat.gravity = Vector3(0, 300, 0)
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	mat.color = Color(1, 0.2, 0.1, 1)
	process_material = mat

func _setup_heal() -> void:
	amount = 12
	lifetime = 1.0
	explosiveness = 0.3
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(30, 10, 0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 80.0
	mat.gravity = Vector3(0, -20, 0)
	mat.scale_min = 3.0
	mat.scale_max = 5.0
	mat.color = Color(0.2, 1, 0.3, 1)
	process_material = mat

func _setup_buff(color: Color) -> void:
	amount = 8
	lifetime = 0.8
	explosiveness = 0.5
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 0, 1)
	mat.emission_ring_radius = 40.0
	mat.emission_ring_inner_radius = 35.0
	mat.emission_ring_height = 0.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 10.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 60.0
	mat.gravity = Vector3(0, -30, 0)
	mat.scale_min = 2.0
	mat.scale_max = 4.0
	mat.color = color
	process_material = mat

func _setup_debuff() -> void:
	amount = 10
	lifetime = 0.7
	explosiveness = 0.6
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 25.0
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 50.0
	mat.gravity = Vector3(0, 100, 0)
	mat.scale_min = 2.0
	mat.scale_max = 4.0
	mat.color = Color(0.5, 0.1, 0.5, 1)
	process_material = mat
