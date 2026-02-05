extends Node

const DATA_PATH = "res://data/templates.json"

var templates: Dictionary = {}

func _ready() -> void:
	_load_templates_from_json()

func _load_templates_from_json() -> void:
	var file = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			templates = json.get_data()
			print("TemplateDatabase: Loaded " + str(templates.size()) + " templates from JSON")
		else:
			push_error("TemplateDatabase: Failed to parse templates.json - " + json.get_error_message())
			templates = {}
	else:
		push_error("TemplateDatabase: Could not open " + DATA_PATH)
		templates = {}

func get_template(template_id: String) -> Dictionary:
	return templates.get(template_id, templates.get("default", {}))

func get_all_templates() -> Dictionary:
	return templates

func get_global_templates() -> Array:
	var result = []
	for id in templates.keys():
		var template = templates[id]
		if template.get("type", "") == "global":
			result.append(template)
	return result

func get_hero_templates(hero_id: String) -> Array:
	var result = []
	for id in templates.keys():
		var template = templates[id]
		if template.get("type", "") == "hero_specific" and template.get("hero", "") == hero_id:
			result.append(template)
	return result

func get_available_templates(hero_id: String) -> Array:
	# Returns all templates available for a hero (global + hero-specific)
	var result = get_global_templates()
	result.append_array(get_hero_templates(hero_id))
	return result
