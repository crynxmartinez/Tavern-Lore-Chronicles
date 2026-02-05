extends CanvasLayer

signal rps_finished(player_goes_first: bool)

enum Choice { ROCK, SCISSORS, PAPER }

@onready var blur_overlay: ColorRect = $BlurOverlay
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleLabel
@onready var timer_label: Label = $Panel/TimerLabel
@onready var instruction_label: Label = $Panel/InstructionLabel
@onready var rock_button: TextureButton = $Panel/ChoicesContainer/RockButton
@onready var scissors_button: TextureButton = $Panel/ChoicesContainer/ScissorsButton
@onready var paper_button: TextureButton = $Panel/ChoicesContainer/PaperButton
@onready var player_choice_display: TextureRect = $Panel/ResultContainer/PlayerChoice
@onready var vs_label: Label = $Panel/ResultContainer/VSLabel
@onready var enemy_choice_display: TextureRect = $Panel/ResultContainer/EnemyChoice
@onready var result_label: Label = $Panel/ResultLabel
@onready var choices_container: HBoxContainer = $Panel/ChoicesContainer
@onready var result_container: HBoxContainer = $Panel/ResultContainer

var rps_texture: Texture2D
var countdown_timer: float = 5.0
var is_waiting_for_choice: bool = true
var player_choice: Choice = Choice.ROCK
var enemy_choice: Choice = Choice.ROCK

# Multiplayer support
var is_multiplayer: bool = false
var is_host: bool = false
var network_manager = null
var my_choice_made: bool = false
var opponent_choice_received: bool = false
var opponent_choice: Choice = Choice.ROCK

const CHOICE_REGIONS = {
	Choice.ROCK: Rect2(0, 0, 158, 158),
	Choice.SCISSORS: Rect2(158, 0, 158, 158),
	Choice.PAPER: Rect2(316, 0, 158, 158)
}

func _ready() -> void:
	rps_texture = load("res://asset/rock paper scissor.png")
	
	blur_overlay.modulate.a = 0
	panel.modulate.a = 0
	result_container.visible = false
	result_label.visible = false
	
	rock_button.pressed.connect(_on_rock_pressed)
	scissors_button.pressed.connect(_on_scissors_pressed)
	paper_button.pressed.connect(_on_paper_pressed)
	
	_setup_buttons()
	
	# Connect multiplayer signal if already set up
	if is_multiplayer and network_manager:
		if network_manager.has_signal("opponent_rps_choice_received"):
			if not network_manager.opponent_rps_choice_received.is_connected(_on_opponent_rps_choice):
				network_manager.opponent_rps_choice_received.connect(_on_opponent_rps_choice)
		print("RPS: Multiplayer mode active - is_host: ", is_host)
	
	await _animate_in()
	_start_countdown()

func setup_multiplayer(nm, host: bool) -> void:
	## Call this BEFORE adding to scene tree for multiplayer mode
	is_multiplayer = true
	is_host = host
	network_manager = nm
	print("RPS: setup_multiplayer called - is_host: ", is_host)

func _setup_buttons() -> void:
	var button_size = Vector2(120, 120)
	
	for button in [rock_button, scissors_button, paper_button]:
		button.custom_minimum_size = button_size
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	
	rock_button.texture_normal = _get_choice_texture(Choice.ROCK)
	scissors_button.texture_normal = _get_choice_texture(Choice.SCISSORS)
	paper_button.texture_normal = _get_choice_texture(Choice.PAPER)

func _get_choice_texture(choice: Choice) -> AtlasTexture:
	var atlas = AtlasTexture.new()
	atlas.atlas = rps_texture
	atlas.region = CHOICE_REGIONS[choice]
	return atlas

func _animate_in() -> void:
	var tween = create_tween()
	tween.tween_property(blur_overlay, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.3)
	await tween.finished

func _start_countdown() -> void:
	countdown_timer = 5.0
	is_waiting_for_choice = true
	_update_timer_display()

func _process(delta: float) -> void:
	if not is_waiting_for_choice:
		return
	
	countdown_timer -= delta
	_update_timer_display()
	
	if countdown_timer <= 0:
		_auto_select()

func _update_timer_display() -> void:
	timer_label.text = str(ceil(countdown_timer))

func _auto_select() -> void:
	if not is_waiting_for_choice:
		return
	
	var last_choice = GameManager.get("last_rps_choice")
	if last_choice == null:
		player_choice = Choice.ROCK
	else:
		player_choice = last_choice
	
	_make_choice(player_choice)

func _on_rock_pressed() -> void:
	if is_waiting_for_choice:
		_make_choice(Choice.ROCK)

func _on_scissors_pressed() -> void:
	if is_waiting_for_choice:
		_make_choice(Choice.SCISSORS)

func _on_paper_pressed() -> void:
	if is_waiting_for_choice:
		_make_choice(Choice.PAPER)

func _make_choice(choice: Choice) -> void:
	is_waiting_for_choice = false
	player_choice = choice
	GameManager.last_rps_choice = choice
	my_choice_made = true
	
	if is_multiplayer:
		# Send our choice to opponent
		if network_manager:
			network_manager.send_rps_choice(int(choice))
			print("RPS: Sent my choice: ", choice)
		
		# Update UI to show waiting
		instruction_label.text = "Waiting for opponent..."
		instruction_label.visible = true
		choices_container.visible = false
		timer_label.visible = false
		
		# Check if we can show result
		await _check_both_choices_ready()
	else:
		# Single player: random enemy choice
		enemy_choice = randi() % 3 as Choice
		await _show_result()

func _on_opponent_rps_choice(choice: int) -> void:
	## Called when opponent's choice is received
	opponent_choice = choice as Choice
	opponent_choice_received = true
	print("RPS: Received opponent choice: ", opponent_choice)
	
	await _check_both_choices_ready()

func _check_both_choices_ready() -> void:
	## Check if both players have made their choice
	if my_choice_made and opponent_choice_received:
		print("RPS: Both choices ready - mine: ", player_choice, " opponent: ", opponent_choice)
		enemy_choice = opponent_choice
		await _show_result()

func _show_result() -> void:
	choices_container.visible = false
	instruction_label.visible = false
	timer_label.visible = false
	
	result_container.visible = true
	player_choice_display.texture = _get_choice_texture(player_choice)
	enemy_choice_display.texture = _get_choice_texture(enemy_choice)
	
	player_choice_display.modulate.a = 0
	vs_label.modulate.a = 0
	enemy_choice_display.modulate.a = 0
	
	var reveal_tween = create_tween()
	reveal_tween.tween_property(player_choice_display, "modulate:a", 1.0, 0.2)
	reveal_tween.tween_interval(0.3)
	reveal_tween.tween_property(vs_label, "modulate:a", 1.0, 0.2)
	reveal_tween.tween_interval(0.3)
	reveal_tween.tween_property(enemy_choice_display, "modulate:a", 1.0, 0.2)
	await reveal_tween.finished
	
	await get_tree().create_timer(0.3).timeout
	
	var winner = _determine_winner()
	
	if winner == 0:
		result_label.text = "TIE! GO AGAIN!"
		result_label.visible = true
		await get_tree().create_timer(1.0).timeout
		_reset_for_retry()
	else:
		var player_wins = winner == 1
		if player_wins:
			result_label.text = "YOU GO FIRST!"
			result_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		else:
			result_label.text = "ENEMY GOES FIRST!"
			result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		
		result_label.visible = true
		await get_tree().create_timer(1.5).timeout
		await _animate_out()
		rps_finished.emit(player_wins)
		queue_free()

func _determine_winner() -> int:
	if player_choice == enemy_choice:
		return 0
	
	if (player_choice == Choice.ROCK and enemy_choice == Choice.SCISSORS) or \
	   (player_choice == Choice.SCISSORS and enemy_choice == Choice.PAPER) or \
	   (player_choice == Choice.PAPER and enemy_choice == Choice.ROCK):
		return 1
	
	return -1

func _reset_for_retry() -> void:
	result_container.visible = false
	result_label.visible = false
	choices_container.visible = true
	instruction_label.visible = true
	timer_label.visible = true
	_start_countdown()

func _animate_out() -> void:
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(blur_overlay, "modulate:a", 0.0, 0.3)
	await tween.finished
