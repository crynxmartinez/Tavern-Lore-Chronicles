extends Node

const SAVE_PATH = "user://equipment_data.save"
const DATA_PATH = "res://data/equipment.json"

var equipments: Dictionary = {}
var equipped_items: Array = []  # 4 equipment slots for deck

func _ready() -> void:
	_load_equipment_from_json()
	load_data()

func _load_equipment_from_json() -> void:
	var file = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			equipments = json.get_data()
			print("EquipmentDatabase: Loaded " + str(equipments.size()) + " equipment from JSON")
		else:
			push_error("EquipmentDatabase: Failed to parse equipment.json - " + json.get_error_message())
			equipments = {}
	else:
		push_error("EquipmentDatabase: Could not open " + DATA_PATH)
		equipments = {}

func get_equipment(equipment_id: String) -> Dictionary:
	return equipments.get(equipment_id, {})

func get_all_equipments() -> Dictionary:
	return equipments

func get_equipped_items() -> Array:
	return equipped_items

func set_equipped_items(items: Array) -> void:
	equipped_items = items

func save_data() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"equipped_items": equipped_items
		}
		file.store_string(JSON.stringify(data))
		file.close()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			var data = json.get_data()
			if data.has("equipped_items"):
				equipped_items = data["equipped_items"]
