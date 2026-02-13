extends Control
class_name Card

signal card_clicked(card: Card)

@export var card_data: Dictionary = {}

var is_selected: bool = false
var original_position: Vector2 = Vector2.ZERO
var base_y: float = 0.0
var has_saved_base: bool = false
var can_interact: bool = true
var is_playable: bool = true
var tween: Tween = null

const RAISE_AMOUNT: float = 50.0
const ANIM_DURATION: float = 0.15

@onready var skill_art: TextureRect = $SkillArt
@onready var template_frame: TextureRect = $TemplateFrame
@onready var card_art: TextureRect = $CardArt  # Fallback for legacy cards
@onready var cost_label: Label = $CostLabel
@onready var name_label: Label = $NameLabel
@onready var description_label: RichTextLabel = $DescriptionLabel
@onready var highlight: Control = $Highlight

var current_template_id: String = "default"

var hover_timer: float = 0.0
var is_hovered: bool = false
var is_zoomed: bool = false
var zoom_tween: Tween = null
const HOVER_ZOOM_DELAY: float = 2.0
const ZOOM_SCALE: float = 1.5

const KEYWORD_COLOR = "[color=#FFD700]"  # Gold color for keywords
const KEYWORDS = ["damage", "heal", "shield", "block", "attack", "restore"]

func _ready() -> void:
	highlight.visible = false
	if not card_data.is_empty():
		setup(card_data)

func _process(delta: float) -> void:
	if is_hovered and not is_zoomed and not is_selected:
		hover_timer += delta
		if hover_timer >= HOVER_ZOOM_DELAY:
			_zoom_in()

func setup(data: Dictionary, template_id: String = "") -> void:
	card_data = data
	
	# Ensure nodes are ready (in case setup is called before _ready)
	if not is_node_ready():
		await ready
	
	# Check if this is an EX skill card (no mana cost)
	var is_ex_card = data.get("is_ex", false)
	
	if cost_label:
		if is_ex_card:
			cost_label.visible = false
		else:
			cost_label.visible = true
			var cost = data.get("cost", 0)
			# X-cost cards (like Mana Surge) show "X" instead of -1
			if cost == -1:
				cost_label.text = "X"
			else:
				cost_label.text = str(int(cost))
	
	if name_label:
		name_label.text = data.get("name", "Unknown")
	
	# Compute real values then apply keyword highlighting
	var description = _compute_description(data)
	if description_label:
		description_label.text = _highlight_keywords(description)
	
	# Check for separate skill art (new layered system)
	var art_path = data.get("art", "")
	var image_path = data.get("image", "")
	
	if not art_path.is_empty() and ResourceLoader.exists(art_path):
		# New layered system: use template + skill art
		_setup_layered_card(art_path, template_id)
	elif not image_path.is_empty() and ResourceLoader.exists(image_path):
		# Legacy system: use full card image
		_setup_legacy_card(image_path)

func _setup_layered_card(art_path: String, template_id: String = "") -> void:
	# Use layered rendering: template frame + skill art
	if template_frame:
		template_frame.visible = true
	if skill_art:
		skill_art.visible = true
	if card_art:
		card_art.visible = false
	
	# Load skill art
	if skill_art and ResourceLoader.exists(art_path):
		skill_art.texture = load(art_path)
	
	# Determine template: use provided template_id, or card's template field, or hero_color
	var final_template_id = template_id
	if final_template_id.is_empty():
		# Check if card has explicit template field (for equipment)
		final_template_id = card_data.get("template", "")
	if final_template_id.is_empty():
		# Derive hero_color from hero_id (single source of truth), fallback to card_data
		var hero_id = card_data.get("hero_id", "")
		var hero_color = ""
		if not hero_id.is_empty():
			var hero_data = HeroDatabase.get_hero(hero_id)
			hero_color = hero_data.get("color", "")
		if hero_color.is_empty():
			hero_color = card_data.get("hero_color", "")
		final_template_id = _get_template_for_color(hero_color)
	
	apply_template(final_template_id)

func _get_template_for_color(hero_color: String) -> String:
	match hero_color:
		"purple":
			return "violet"
		"yellow":
			return "yellow"
		"green":
			return "green"
		"red":
			return "red"
		"blue":
			return "blue"
		_:
			return "default"

func _setup_legacy_card(image_path: String) -> void:
	# Legacy: use full card image (template baked in)
	if template_frame:
		template_frame.visible = false
	if skill_art:
		skill_art.visible = false
	if card_art:
		card_art.visible = true
		card_art.texture = load(image_path)

func apply_template(template_id: String) -> void:
	current_template_id = template_id
	var template = _get_template(template_id)
	
	if template.is_empty():
		template = _get_template("default")
	
	# Load template frame
	var frame_path = template.get("frame", "")
	if template_frame and not frame_path.is_empty() and ResourceLoader.exists(frame_path):
		template_frame.texture = load(frame_path)
	
	# Position skill art based on template's art_region
	var art_region = template.get("art_region", {})
	if skill_art and not art_region.is_empty():
		skill_art.position = Vector2(art_region.get("x", 12), art_region.get("y", 25))
		skill_art.size = Vector2(art_region.get("width", 136), art_region.get("height", 95))
	
	# Apply text styling
	var text_style = template.get("text_style", {})
	_apply_text_style(text_style)

func _get_template(template_id: String) -> Dictionary:
	# Load templates directly from JSON
	var templates = _load_templates()
	return templates.get(template_id, templates.get("default", {}))

var _cached_templates: Dictionary = {}

func _load_templates() -> Dictionary:
	if not _cached_templates.is_empty():
		return _cached_templates
	
	var file = FileAccess.open("res://data/templates.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_cached_templates = json.get_data()
			return _cached_templates
	
	# Fallback default
	_cached_templates = {"default": {"frame": "res://asset/card template/new template grey.png", "art_region": {"x": 8, "y": 18, "width": 144, "height": 88}}}
	return _cached_templates

func _apply_text_style(style: Dictionary) -> void:
	if style.is_empty():
		return
	
	# Apply name color
	var name_color_str = style.get("name_color", "#FFFFFF")
	if name_label:
		name_label.add_theme_color_override("font_color", Color.html(name_color_str))
	
	# Apply description color
	var desc_color_str = style.get("desc_color", "#CCCCCC")
	if description_label:
		description_label.add_theme_color_override("default_color", Color.html(desc_color_str))
	
	# Apply shadow if enabled
	if style.get("name_shadow", false) and name_label:
		name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		name_label.add_theme_constant_override("shadow_offset_x", 1)
		name_label.add_theme_constant_override("shadow_offset_y", 1)

func _compute_description(data: Dictionary) -> String:
	var desc = data.get("description", "")
	if desc.is_empty():
		return desc
	
	# Get hero stats for computation
	var hero_id = data.get("hero_id", "")
	var hero_data = HeroDatabase.get_hero(hero_id) if not hero_id.is_empty() else {}
	var base_atk = hero_data.get("base_attack", 10)
	var base_hp = hero_data.get("base_hp", 10)
	var hp_mult = hero_data.get("hp_multiplier", 10)
	var max_hp = hero_data.get("max_hp", base_hp * hp_mult)
	var base_def = hero_data.get("base_def", 0)
	
	# Replace ATK multiplier formulas: (150% ATK) -> computed damage
	var atk_multiplier = data.get("atk_multiplier", 0.0)
	if atk_multiplier > 0:
		var damage = int(base_atk * atk_multiplier)
		var pct_str = str(int(atk_multiplier * 100))
		var patterns = ["(" + pct_str + "% ATK)", pct_str + "% ATK"]
		for pattern in patterns:
			if desc.find(pattern) >= 0:
				desc = desc.replace(pattern, str(damage))
				break
	
	# Replace HP multiplier formulas: (8% max HP) -> computed heal
	var card_hp_mult = data.get("hp_multiplier", 0.0)
	if card_hp_mult > 0:
		var heal_amount = int(max_hp * card_hp_mult)
		var pct_str = str(int(card_hp_mult * 100))
		var patterns = ["(" + pct_str + "% max HP)", pct_str + "% max HP"]
		for pattern in patterns:
			if desc.find(pattern) >= 0:
				desc = desc.replace(pattern, str(heal_amount) + " HP")
				break
	
	# Replace Shield formulas: (N + DEF×M) or (DEF×M) -> computed shield
	var card_base_shield = data.get("base_shield", 0)
	var card_def_mult = data.get("def_multiplier", 0.0)
	# Also check self_shield_def_multiplier (e.g. Kalasag SK1)
	if card_def_mult == 0.0:
		card_def_mult = data.get("self_shield_def_multiplier", 0.0)
	if card_base_shield > 0 or card_def_mult > 0:
		var shield_amount = card_base_shield + int(base_def * card_def_mult)
		var def_int = str(int(card_def_mult))
		var base_str = str(int(card_base_shield))
		print("[Shield Desc] hero_id=", hero_id, " base_def=", base_def, " base_shield=", card_base_shield, " def_mult=", card_def_mult, " shield=", shield_amount)
		print("[Shield Desc] desc bytes: ", desc.to_utf8_buffer().hex_encode())
		# Try all separator variants × x X *
		var seps = ["\u00d7", "x", "X", "*"]
		var replaced_shield = false
		for sep in seps:
			if replaced_shield:
				break
			# Build all possible formula strings and try each
			var formulas = [
				"(" + base_str + " + DEF" + sep + def_int + ")",
				"(" + base_str + " +DEF" + sep + def_int + ")",
				"(" + base_str + "+DEF" + sep + def_int + ")",
				base_str + " + DEF" + sep + def_int,
				"(DEF" + sep + def_int + ")",
				"DEF" + sep + def_int
			]
			for formula in formulas:
				var found = desc.find(formula)
				print("[Shield Desc] trying: '", formula, "' -> found=", found)
				if found >= 0:
					desc = desc.replace(formula, str(shield_amount))
					replaced_shield = true
					print("[Shield Desc] REPLACED with ", shield_amount)
					break
	
	return desc

func _highlight_keywords(text: String) -> String:
	var result = text
	for keyword in KEYWORDS:
		# Case insensitive replacement
		var regex = RegEx.new()
		regex.compile("(?i)\\b(" + keyword + ")\\b")
		result = regex.sub(result, KEYWORD_COLOR + "$1[/color]", true)
	return result

func _gui_input(event: InputEvent) -> void:
	if not can_interact:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			accept_event()
			if is_zoomed:
				_zoom_out()
			card_clicked.emit(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		is_hovered = true
		hover_timer = 0.0
	elif what == NOTIFICATION_MOUSE_EXIT:
		is_hovered = false
		hover_timer = 0.0
		if is_zoomed:
			_zoom_out()

func _zoom_in() -> void:
	if is_zoomed:
		return
	is_zoomed = true
	
	if zoom_tween:
		zoom_tween.kill()
	
	# Store original z_index and raise it
	z_index = 200
	
	# Set pivot to bottom center so card scales upward
	pivot_offset = Vector2(size.x / 2, size.y)
	
	zoom_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	zoom_tween.tween_property(self, "scale", Vector2(ZOOM_SCALE, ZOOM_SCALE), 0.2)

func _zoom_out() -> void:
	if not is_zoomed:
		return
	is_zoomed = false
	hover_timer = 0.0
	
	if zoom_tween:
		zoom_tween.kill()
	
	zoom_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	zoom_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)
	zoom_tween.tween_callback(func(): 
		z_index = 0 if not is_selected else 100
		pivot_offset = Vector2.ZERO
	)

func set_selected(selected: bool) -> void:
	is_selected = selected
	# No highlight on selection - just raise the card
	
	if tween:
		tween.kill()
	tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	if selected:
		# Only save base position on FIRST select (when not already raised)
		if not has_saved_base:
			base_y = position.y
			has_saved_base = true
		tween.tween_property(self, "position:y", base_y - RAISE_AMOUNT, ANIM_DURATION)
		z_index = 100
	else:
		# Always return to base position
		tween.tween_property(self, "position:y", base_y, ANIM_DURATION)
		has_saved_base = false  # Reset flag so next select captures fresh base
		z_index = 0

func set_highlight(enabled: bool, color: Color = Color(1, 1, 0, 0.3)) -> void:
	highlight.visible = enabled
	highlight.color = color

func set_playable(playable: bool) -> void:
	is_playable = playable
	can_interact = playable
	
	if playable:
		# Playable: full brightness
		modulate = Color(1, 1, 1, 1)
	else:
		# Not playable: dimmed
		modulate = Color(0.5, 0.5, 0.5, 1)

var extra_cost: int = 0

func update_display_cost(extra: int) -> void:
	extra_cost = extra
	var is_ex_card = card_data.get("is_ex", false)
	if cost_label and not is_ex_card:
		var base = card_data.get("cost", 0)
		if base == -1:
			cost_label.text = "X"
		else:
			cost_label.text = str(int(base + extra))

func can_play(current_mana: int) -> bool:
	var cost = card_data.get("cost", 0)
	# Mana Surge (cost = -1) requires at least 1 mana
	if cost == -1:
		return current_mana >= 1
	return (cost + extra_cost) <= current_mana

func reset_position() -> void:
	if tween:
		tween.kill()
	tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "position:y", base_y, ANIM_DURATION)
	has_saved_base = false
	z_index = 0
	is_selected = false
	highlight.visible = false

func get_cost() -> int:
	return card_data.get("cost", 0) + extra_cost

func get_card_type() -> String:
	return card_data.get("type", "")

func get_atk_multiplier() -> float:
	return card_data.get("atk_multiplier", 1.0)

func get_heal_multiplier() -> float:
	return card_data.get("heal_multiplier", 1.0)

func get_shield_multiplier() -> float:
	return card_data.get("shield_multiplier", 0.0)
