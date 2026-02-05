extends CanvasLayer

signal continue_pressed

@onready var blur_rect: ColorRect = $BlurRect
@onready var panel: PanelContainer = $Panel
@onready var result_label: Label = $Panel/VBoxContainer/ResultLabel
@onready var player_heroes_container: HBoxContainer = $Panel/VBoxContainer/TeamsContainer/PlayerTeamContainer/HeroesContainer
@onready var enemy_heroes_container: HBoxContainer = $Panel/VBoxContainer/TeamsContainer/EnemyTeamContainer/HeroesContainer
@onready var continue_button: Button = $Panel/VBoxContainer/ContinueButton
@onready var countdown_label: Label = $Panel/VBoxContainer/CountdownLabel
@onready var wins_label: Label = $Panel/VBoxContainer/StatsContainer/WinsLabel
@onready var losses_label: Label = $Panel/VBoxContainer/StatsContainer/LossesLabel
@onready var win_rate_label: Label = $Panel/VBoxContainer/StatsContainer/WinRateLabel
@onready var streak_label: Label = $Panel/VBoxContainer/StatsContainer/StreakLabel

var hero_stat_card_scene = preload("res://scenes/components/hero_stat_card.tscn")
var auto_return_timer: float = 10.0
var is_counting_down: bool = false

func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	
	# Start hidden
	panel.modulate.a = 0
	panel.scale = Vector2(0.8, 0.8)
	
	# Set blur to 0 initially
	if blur_rect.material:
		blur_rect.material.set_shader_parameter("blur_amount", 0.0)

func _process(delta: float) -> void:
	if is_counting_down:
		auto_return_timer -= delta
		countdown_label.text = "Returning in " + str(int(auto_return_timer) + 1) + "s..."
		
		if auto_return_timer <= 0:
			is_counting_down = false
			_on_continue_pressed()

func show_summary(player_won: bool) -> void:
	# Set result text
	if player_won:
		result_label.text = "VICTORY!"
		result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	
	# Update player stats display
	_update_player_stats_display()
	
	# Get battle stats
	var stats = GameManager.get_battle_stats()
	
	# Create stat cards for each hero
	for hero_id in stats:
		var hero_stats = stats[hero_id]
		var card = hero_stat_card_scene.instantiate()
		
		if hero_stats.get("is_player", true):
			player_heroes_container.add_child(card)
		else:
			enemy_heroes_container.add_child(card)
		
		card.setup(hero_stats)
	
	# Animate blur in
	if blur_rect.material:
		var blur_tween = create_tween().set_ease(Tween.EASE_OUT)
		blur_tween.tween_method(
			func(val): blur_rect.material.set_shader_parameter("blur_amount", val),
			0.0, 5.0, 0.5
		)
	
	# Animate panel in
	await get_tree().create_timer(0.3).timeout
	
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate:a", 1.0, 0.4)
	tween.parallel().tween_property(panel, "scale", Vector2(1.0, 1.0), 0.4)
	
	await tween.finished
	
	# Animate stats counting up
	for card in player_heroes_container.get_children():
		if card.has_method("animate_stats"):
			card.animate_stats()
	for card in enemy_heroes_container.get_children():
		if card.has_method("animate_stats"):
			card.animate_stats()
	
	# Start countdown
	is_counting_down = true
	auto_return_timer = 10.0

func _on_continue_pressed() -> void:
	is_counting_down = false
	
	# Reset multiplayer flags in GameManager
	if has_node("/root/GameManager"):
		var gm = get_node("/root/GameManager")
		gm.is_multiplayer = false
		gm.is_host = false
		gm.opponent_client_id = -1
	
	# Fade out
	var tween = create_tween().set_ease(Tween.EASE_IN)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	
	await tween.finished
	
	# Transition to dashboard
	SceneTransition.change_scene("res://scenes/dashboard/dashboard.tscn")

func _update_player_stats_display() -> void:
	# Get stats from PlayerData autoload
	if not has_node("/root/PlayerData"):
		return
	
	var player_data = get_node("/root/PlayerData")
	var stats = player_data.get_stats_summary()
	
	if wins_label:
		wins_label.text = "Wins: " + str(stats.get("total_wins", 0))
	if losses_label:
		losses_label.text = "Losses: " + str(stats.get("total_losses", 0))
	if win_rate_label:
		var rate = stats.get("win_rate", 0.0)
		win_rate_label.text = "Win Rate: " + str(int(rate)) + "%"
	if streak_label:
		var streak = stats.get("current_streak", 0)
		if streak > 0:
			streak_label.text = "Streak: " + str(streak) + " 🔥"
			streak_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		else:
			streak_label.text = "Streak: 0"
			streak_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
