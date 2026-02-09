extends Node

const SAVE_PATH = "user://hero_data.save"
const DATA_PATH = "res://data/heroes.json"

var heroes: Dictionary = {}
var current_team: Array = ["priest", "markswoman", "craftswoman", "squire"]
var equipped_templates: Dictionary = {}  # hero_id -> template_id

# Role colors for UI borders
const ROLE_COLORS = {
	"tank": Color(1.0, 0.85, 0.0),      # Yellow/Gold
	"support": Color(0.2, 0.8, 0.2),    # Green
	"dps": Color(0.9, 0.2, 0.2),        # Red
	"mage": Color(0.4, 0.7, 1.0),       # Light Blue
	"scientist": Color(0.6, 0.2, 0.8),   # Violet/Purple
	"assassin": Color(0.2, 0.6, 1.0)    # Blue
}

func _ready() -> void:
	_load_heroes_from_json()
	load_data()

func _load_heroes_from_json() -> void:
	var file = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			heroes = json.get_data()
			print("HeroDatabase: Loaded " + str(heroes.size()) + " heroes from JSON")
		else:
			push_error("HeroDatabase: Failed to parse heroes.json - " + json.get_error_message())
			heroes = {}
	else:
		push_error("HeroDatabase: Could not open " + DATA_PATH)
		heroes = {}

func get_hero(hero_id: String) -> Dictionary:
	return heroes.get(hero_id, {})

func get_all_heroes() -> Dictionary:
	return heroes

func get_hero_cards(hero_id: String) -> Array:
	var hero = get_hero(hero_id)
	if hero.is_empty():
		return []
	
	var cards = []
	for card_id in hero.get("cards", []):
		var card = CardDatabase.get_card(card_id)
		if not card.is_empty():
			cards.append(card)
	return cards

func get_default_team() -> Array:
	return ["priest", "markswoman", "craftswoman", "squire"]

func get_current_team() -> Array:
	return current_team

func set_current_team(team: Array) -> void:
	current_team = team

func get_role_color(role: String) -> Color:
	return ROLE_COLORS.get(role, Color.WHITE)

func get_hero_template(hero_id: String) -> String:
	return equipped_templates.get(hero_id, "default")

func set_hero_template(hero_id: String, template_id: String) -> void:
	equipped_templates[hero_id] = template_id
	save_data()

# AI team for Train mode
var ai_enemy_team: Array = []

# Training mode settings
var training_player_first: bool = true  # true = player goes first, false = AI goes first
var training_custom_team: bool = false  # true = user picked enemy team, false = random

# Role categories for smart draft
const FRONTLINE_ROLES = ["tank", "dps"]
const SUSTAIN_ROLES = ["support", "scientist", "mage"]

func generate_ai_team() -> Array:
	var all_hero_ids = heroes.keys()
	if all_hero_ids.size() < 4:
		push_error("HeroDatabase: Not enough heroes to generate AI team")
		return all_hero_ids.duplicate()
	
	var team: Array = []
	var available = all_hero_ids.duplicate()
	
	# Step 1: Guarantee at least 1 frontline (tank or dps)
	var frontline_pool = available.filter(func(id):
		var role = heroes[id].get("role", "")
		return role in FRONTLINE_ROLES
	)
	if not frontline_pool.is_empty():
		var pick = frontline_pool[randi() % frontline_pool.size()]
		team.append(pick)
		available.erase(pick)
	
	# Step 2: Guarantee at least 1 sustain (support, scientist, or mage)
	var sustain_pool = available.filter(func(id):
		var role = heroes[id].get("role", "")
		return role in SUSTAIN_ROLES
	)
	if not sustain_pool.is_empty():
		var pick = sustain_pool[randi() % sustain_pool.size()]
		team.append(pick)
		available.erase(pick)
	
	# Step 3: Fill remaining slots randomly (no duplicates on AI team)
	while team.size() < 4 and not available.is_empty():
		var pick = available[randi() % available.size()]
		team.append(pick)
		available.erase(pick)
	
	# Shuffle so the guaranteed picks aren't always in slots 1-2
	team.shuffle()
	
	ai_enemy_team = team
	return team

func save_data() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"current_team": current_team,
			"equipped_templates": equipped_templates
		}
		file.store_string(JSON.stringify(data))
		file.close()
		print("HeroDatabase: Data saved to ", SAVE_PATH)

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("HeroDatabase: No save file found, using defaults")
		return
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			var data = json.get_data()
			if data.has("current_team"):
				current_team = data["current_team"]
			if data.has("equipped_templates"):
				equipped_templates = data["equipped_templates"]
			print("HeroDatabase: Data loaded from ", SAVE_PATH)
		else:
			print("HeroDatabase: Failed to parse save file")
