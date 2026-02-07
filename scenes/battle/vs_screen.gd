extends Control

const AI_NAMES = [
	"AI Challenger", "Shadow Tactician", "Iron Strategist",
	"Crimson Rival", "Storm Commander", "Phantom General",
	"Blade Oracle", "Void Warden", "Arcane Duelist",
	"Steel Phantom", "Ember Warlord", "Frost Sentinel"
]

var player_team: Array = []
var enemy_team: Array = []
var ai_name: String = "AI Challenger"

@onready var background: ColorRect = $Background
@onready var player_container: HBoxContainer = $PlayerSide/HeroContainer
@onready var enemy_container: HBoxContainer = $EnemySide/HeroContainer
@onready var player_label: Label = $PlayerSide/TeamLabel
@onready var enemy_label: Label = $EnemySide/TeamLabel
@onready var vs_label: Label = $VSLabel
@onready var player_side: Control = $PlayerSide
@onready var enemy_side: Control = $EnemySide

func _ready() -> void:
	# Get teams from HeroDatabase
	player_team = HeroDatabase.get_current_team()
	enemy_team = HeroDatabase.ai_enemy_team
	ai_name = AI_NAMES[randi() % AI_NAMES.size()]
	
	# Get player name
	var player_name = "Player"
	if has_node("/root/PlayerData"):
		player_name = get_node("/root/PlayerData").username
	
	player_label.text = player_name
	enemy_label.text = ai_name
	
	# Build hero portraits
	_build_hero_row(player_container, player_team)
	_build_hero_row(enemy_container, enemy_team)
	
	# Start hidden for animation
	player_side.modulate.a = 0
	player_side.position.x -= 200
	enemy_side.modulate.a = 0
	enemy_side.position.x += 200
	vs_label.modulate.a = 0
	vs_label.scale = Vector2(3.0, 3.0)
	
	# Run entrance animation
	await _play_entrance()

func _build_hero_row(container: HBoxContainer, team: Array) -> void:
	for hero_id in team:
		var hero_data = HeroDatabase.get_hero(hero_id)
		if hero_data.is_empty():
			continue
		
		var card = _create_hero_card(hero_data)
		container.add_child(card)

func _create_hero_card(hero_data: Dictionary) -> Control:
	var card = Control.new()
	card.custom_minimum_size = Vector2(140, 180)
	
	# Border with role color
	var border = Panel.new()
	border.custom_minimum_size = Vector2(140, 140)
	border.position = Vector2(0, 0)
	
	var style = StyleBoxFlat.new()
	var role = hero_data.get("role", "tank")
	var role_color = HeroDatabase.get_role_color(role)
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	style.border_color = role_color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	border.add_theme_stylebox_override("panel", style)
	card.add_child(border)
	
	# Portrait
	var portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(130, 130)
	portrait.position = Vector2(5, 5)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_path = hero_data.get("portrait", "")
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	card.add_child(portrait)
	
	# Name
	var name_label = Label.new()
	name_label.text = hero_data.get("name", "???")
	name_label.position = Vector2(0, 145)
	name_label.custom_minimum_size = Vector2(140, 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	card.add_child(name_label)
	
	# Role tag
	var role_label = Label.new()
	role_label.text = role.to_upper()
	role_label.position = Vector2(0, 163)
	role_label.custom_minimum_size = Vector2(140, 16)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.add_theme_font_size_override("font_size", 10)
	role_label.add_theme_color_override("font_color", role_color)
	card.add_child(role_label)
	
	return card

func _play_entrance() -> void:
	# Player side slides in from left
	var p_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	p_tween.set_parallel(true)
	p_tween.tween_property(player_side, "modulate:a", 1.0, 0.4)
	p_tween.tween_property(player_side, "position:x", player_side.position.x + 200, 0.5)
	await p_tween.finished
	
	# VS slams in
	var vs_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	vs_tween.set_parallel(true)
	vs_tween.tween_property(vs_label, "modulate:a", 1.0, 0.2)
	vs_tween.tween_property(vs_label, "scale", Vector2(1.0, 1.0), 0.3)
	await vs_tween.finished
	
	# Enemy side slides in from right
	var e_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	e_tween.set_parallel(true)
	e_tween.tween_property(enemy_side, "modulate:a", 1.0, 0.4)
	e_tween.tween_property(enemy_side, "position:x", enemy_side.position.x - 200, 0.5)
	await e_tween.finished
	
	# Hold for a moment
	await get_tree().create_timer(1.5).timeout
	
	# Transition to battle
	SceneTransition.change_scene("res://scenes/battle/battle.tscn")
