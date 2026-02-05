extends CanvasLayer

signal cutin_finished

@onready var dark_overlay: ColorRect = $DarkOverlay
@onready var white_flash: ColorRect = $WhiteFlash
@onready var diagonal_stripe: Panel = $DiagonalStripe
@onready var splash_art: TextureRect = $DiagonalStripe/SplashArt
@onready var skill_name_label: Label = $SkillNameLabel

var is_player_side: bool = true

# Values from ex_cutin_test.tscn (player/left side)
# DiagonalStripe: offset_left=-87, offset_top=-89, rotation=-30
# SplashArt: offset_left=136.71, offset_top=-96.77
# SkillNameLabel: offset_left=680, offset_top=944

# Values from ex_cutin_test_right.tscn (enemy/right side)
# DiagonalStripe: offset_left=1048, offset_top=-144, rotation=30, scale=(-1,1)
# SplashArt: offset_left=109.66, offset_top=-181.23
# SkillNameLabel: offset_left=840, offset_top=985

const SCREEN_WIDTH = 1920.0

# Player side (left) - from ex_cutin_test.tscn
const PLAYER_STRIPE_FINAL_X = -87.0
const PLAYER_STRIPE_FINAL_Y = -89.0
const PLAYER_STRIPE_START_X = -1000.0
const PLAYER_LABEL_X = 680.0
const PLAYER_LABEL_Y = 944.0
const PLAYER_SPLASH_X = 136.71
const PLAYER_SPLASH_Y = -96.77

# Enemy side (right) - from ex_cutin_test_right.tscn
const ENEMY_STRIPE_FINAL_X = 1048.0
const ENEMY_STRIPE_FINAL_Y = -144.0
const ENEMY_STRIPE_START_X = 2100.0  # Off screen right
const ENEMY_LABEL_X = 840.0
const ENEMY_LABEL_Y = 985.0
const ENEMY_SPLASH_X = 109.66
const ENEMY_SPLASH_Y = -181.23

func _ready() -> void:
	# Start everything hidden
	dark_overlay.modulate.a = 0
	white_flash.modulate.a = 0
	diagonal_stripe.modulate.a = 0
	skill_name_label.modulate.a = 0

func play_cutin(splash_texture: Texture2D, hero_color: Color, skill_name: String, from_left: bool = true) -> void:
	is_player_side = from_left
	
	# Set splash art texture
	if splash_texture:
		splash_art.texture = splash_texture
	
	# Set stripe color via StyleBox
	var style = diagonal_stripe.get_theme_stylebox("panel").duplicate()
	style.bg_color = hero_color
	style.bg_color.a = 0.85
	diagonal_stripe.add_theme_stylebox_override("panel", style)
	
	# Set skill name
	skill_name_label.text = skill_name
	
	# Configure for player (left) or enemy (right) side
	if is_player_side:
		# Left side - from ex_cutin_test.tscn
		diagonal_stripe.rotation_degrees = -30
		diagonal_stripe.scale = Vector2(1, 1)
		diagonal_stripe.offset_left = PLAYER_STRIPE_START_X
		diagonal_stripe.offset_top = PLAYER_STRIPE_FINAL_Y
		splash_art.offset_left = PLAYER_SPLASH_X
		splash_art.offset_top = PLAYER_SPLASH_Y
		splash_art.flip_h = false
		skill_name_label.offset_left = PLAYER_LABEL_X
		skill_name_label.offset_top = PLAYER_LABEL_Y
	else:
		# Right side - from ex_cutin_test_right.tscn
		diagonal_stripe.rotation_degrees = 30
		diagonal_stripe.scale = Vector2(-1, 1)  # Flip the whole stripe horizontally
		diagonal_stripe.offset_left = ENEMY_STRIPE_START_X
		diagonal_stripe.offset_top = ENEMY_STRIPE_FINAL_Y
		splash_art.offset_left = ENEMY_SPLASH_X
		splash_art.offset_top = ENEMY_SPLASH_Y
		splash_art.flip_h = false  # Don't flip splash since stripe is flipped
		skill_name_label.offset_left = ENEMY_LABEL_X
		skill_name_label.offset_top = ENEMY_LABEL_Y
	
	# Animation sequence
	await _animate_in()
	await get_tree().create_timer(0.3).timeout  # Hold
	await _animate_out()
	
	cutin_finished.emit()
	queue_free()

func _animate_in() -> void:
	# White flash
	white_flash.modulate.a = 1.0
	var flash_tween = create_tween()
	flash_tween.tween_property(white_flash, "modulate:a", 0.0, 0.12)
	
	# Dark overlay fade in
	var overlay_tween = create_tween()
	overlay_tween.tween_property(dark_overlay, "modulate:a", 0.5, 0.1)
	
	# Stripe slides in using offset_left
	diagonal_stripe.modulate.a = 1.0
	var stripe_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	
	var stripe_target_x = PLAYER_STRIPE_FINAL_X if is_player_side else ENEMY_STRIPE_FINAL_X
	stripe_tween.tween_property(diagonal_stripe, "offset_left", stripe_target_x, 0.25)
	
	# Skill name fade in
	await get_tree().create_timer(0.1).timeout
	var name_tween = create_tween()
	name_tween.tween_property(skill_name_label, "modulate:a", 1.0, 0.15)
	
	await stripe_tween.finished

func _animate_out() -> void:
	# Everything slides out - player slides right, enemy slides left
	var out_x = 600.0 if is_player_side else -600.0
	
	var stripe_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	stripe_tween.tween_property(diagonal_stripe, "offset_left", diagonal_stripe.offset_left + out_x, 0.2)
	stripe_tween.parallel().tween_property(diagonal_stripe, "modulate:a", 0.0, 0.2)
	
	var name_tween = create_tween()
	name_tween.tween_property(skill_name_label, "modulate:a", 0.0, 0.1)
	
	var overlay_tween = create_tween()
	overlay_tween.tween_property(dark_overlay, "modulate:a", 0.0, 0.15)
	
	await stripe_tween.finished
