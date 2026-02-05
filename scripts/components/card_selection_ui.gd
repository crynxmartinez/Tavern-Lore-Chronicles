class_name CardSelectionUI
extends Control

signal card_selected(card_data: Dictionary)
signal selection_cancelled()

var revealed_cards: Array = []
var filter_type: String = "any"  # "any", "equipment", "attack", "heal", "buff"
var selected_card: Dictionary = {}
var card_scene = preload("res://scenes/components/card.tscn")

@onready var background: ColorRect = $Background
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleLabel
@onready var cards_container: HBoxContainer = $Panel/CardsContainer
@onready var confirm_button: Button = $Panel/ConfirmButton
@onready var cancel_button: Button = $Panel/CancelButton
@onready var info_label: Label = $Panel/InfoLabel

func _ready() -> void:
	visible = false
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	
	# Setup button hover effects
	_setup_button_hover(confirm_button)
	_setup_button_hover(cancel_button)

func _setup_button_hover(button: Button) -> void:
	button.mouse_entered.connect(func(): _on_button_hover(button, true))
	button.mouse_exited.connect(func(): _on_button_hover(button, false))

func _on_button_hover(button: Button, hovering: bool) -> void:
	if hovering:
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.1)
	else:
		var tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.1)

func show_cards(cards: Array, filter: String = "any", title: String = "Select a Card") -> void:
	revealed_cards = cards
	filter_type = filter
	selected_card = {}
	
	# Clear existing cards
	for child in cards_container.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	# Set title
	title_label.text = title
	
	# Count valid cards
	var valid_count = 0
	
	# Create card displays
	for card_data in cards:
		var card_instance = card_scene.instantiate()
		cards_container.add_child(card_instance)
		card_instance.setup(card_data)
		card_instance.scale = Vector2(0.8, 0.8)
		
		# Check if card matches filter
		var is_valid = _card_matches_filter(card_data, filter)
		
		if is_valid:
			valid_count += 1
			# Make card clickable
			card_instance.modulate = Color(1, 1, 1, 1)
			card_instance.mouse_filter = Control.MOUSE_FILTER_STOP
			card_instance.gui_input.connect(_on_card_input.bind(card_instance, card_data))
		else:
			# Dim invalid cards
			card_instance.modulate = Color(0.5, 0.5, 0.5, 0.8)
			card_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Update info label
	if valid_count > 0:
		info_label.text = "Click a highlighted card to select it"
		confirm_button.disabled = true  # Disabled until card is selected
	else:
		info_label.text = "No valid cards found. Click OK to continue."
		confirm_button.disabled = false
		confirm_button.text = "OK"
	
	# Show with animation
	visible = true
	modulate.a = 0
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	
	# Animate panel
	panel.scale = Vector2(0.8, 0.8)
	var panel_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	panel_tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.25)

func _card_matches_filter(card_data: Dictionary, filter: String) -> bool:
	if filter == "any":
		return true
	var card_type = card_data.get("type", "")
	return card_type == filter

func _on_card_input(event: InputEvent, card_instance: Control, card_data: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_card(card_instance, card_data)

func _select_card(card_instance: Control, card_data: Dictionary) -> void:
	# Deselect previous
	for child in cards_container.get_children():
		if _card_matches_filter(child.card_data if child.has_method("setup") else {}, filter_type):
			child.modulate = Color(1, 1, 1, 1)
			child.scale = Vector2(0.8, 0.8)
	
	# Select new card
	selected_card = card_data
	card_instance.modulate = Color(1.2, 1.2, 0.8, 1)  # Golden highlight
	
	# Animate selection
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(card_instance, "scale", Vector2(0.9, 0.9), 0.15)
	
	# Enable confirm button
	confirm_button.disabled = false
	confirm_button.text = "Confirm"
	info_label.text = "Selected: " + card_data.get("name", "Unknown")

func _on_confirm_pressed() -> void:
	_hide_ui()
	card_selected.emit(selected_card)

func _on_cancel_pressed() -> void:
	_hide_ui()
	selection_cancelled.emit()

func _hide_ui() -> void:
	var tween = create_tween().set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): visible = false)
