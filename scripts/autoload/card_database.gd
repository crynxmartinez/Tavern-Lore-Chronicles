extends Node

const DATA_PATH = "res://data/cards.json"

var cards: Dictionary = {}

func _ready() -> void:
	_load_cards_from_json()

func _load_cards_from_json() -> void:
	var file = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			cards = json.get_data()
			print("CardDatabase: Loaded " + str(cards.size()) + " cards from JSON")
		else:
			push_error("CardDatabase: Failed to parse cards.json - " + json.get_error_message())
			cards = {}
	else:
		push_error("CardDatabase: Could not open " + DATA_PATH)
		cards = {}

func get_card(card_id: String) -> Dictionary:
	return cards.get(card_id, {})

func get_all_cards() -> Dictionary:
	return cards
