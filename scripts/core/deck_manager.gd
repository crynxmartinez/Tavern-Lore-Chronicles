class_name DeckManager
extends RefCounted

signal deck_shuffled()

var deck: Array = []
var hand: Array = []
var discard_pile: Array = []
var dead_hero_cards: Dictionary = {}

var id_prefix: String = ""  # "" for player, "enemy_" for enemy

func _init(prefix: String = "") -> void:
	id_prefix = prefix

func clear() -> void:
	deck.clear()
	hand.clear()
	discard_pile.clear()
	dead_hero_cards.clear()

func build_from_heroes(heroes: Array, include_equipment: bool = false) -> void:
	clear()
	
	for hero_data in heroes:
		var hero_cards = HeroDatabase.get_hero_cards(hero_data.id)
		for card in hero_cards:
			var card_copy = card.duplicate()
			if not id_prefix.is_empty():
				card_copy["id"] = id_prefix + card_copy.get("id", "")
			card_copy["hero_id"] = hero_data.id
			deck.append(card_copy)
		
		# Build attack card image path from hero folder
		var portrait_path = hero_data.get("portrait", "")
		var attack_image = _get_attack_image_path(portrait_path)
		
		# Add basic attack cards per hero
		for i in range(GameConstants.ATTACK_CARDS_PER_HERO):
			var attack_card = {
				"id": id_prefix + hero_data.id + "_attack_" + str(i),
				"name": hero_data.name + " Attack",
				"cost": 0,
				"type": "basic_attack",
				"atk_multiplier": 1.0,
				"hero_id": hero_data.id,
				"hero_color": hero_data.color,
				"description": "Deal 10 damage to target enemy.",
				"art": attack_image,
				"image": attack_image
			}
			deck.append(attack_card)
	
	# Add equipped items to deck (player only)
	if include_equipment:
		var equipped_items = EquipmentDatabase.get_equipped_items()
		for equip_id in equipped_items:
			var equip_data = EquipmentDatabase.get_equipment(equip_id)
			if not equip_data.is_empty():
				var equip_card = equip_data.duplicate()
				equip_card["id"] = equip_id + "_" + str(randi())
				deck.append(equip_card)
	
	shuffle_deck()

func _get_attack_image_path(portrait_path: String) -> String:
	if portrait_path.is_empty():
		return ""
	var folder_path = portrait_path.get_base_dir()
	var png_path = folder_path + "/attack.png"
	var webp_path = folder_path + "/attack.webp"
	if ResourceLoader.exists(png_path):
		return png_path
	elif ResourceLoader.exists(webp_path):
		return webp_path
	return ""

func shuffle_deck() -> void:
	deck.shuffle()

func draw_cards(count: int) -> Array:
	var drawn = []
	for i in range(count):
		if deck.is_empty():
			reshuffle_discard_into_deck()
		if not deck.is_empty():
			var card = deck.pop_back()
			hand.append(card)
			drawn.append(card)
	return drawn

func reshuffle_discard_into_deck() -> void:
	deck = discard_pile.duplicate()
	discard_pile.clear()
	deck.shuffle()
	deck_shuffled.emit()

func play_card(card_data: Dictionary) -> bool:
	var card_index = _find_card_in_hand(card_data.get("id", ""))
	
	if card_index != -1:
		hand.remove_at(card_index)
		# Equipment cards are consumed - don't add to discard
		if card_data.get("type", "") != "equipment":
			discard_pile.append(card_data)
		return true
	return false

func _find_card_in_hand(card_id: String) -> int:
	for i in range(hand.size()):
		if hand[i].get("id", "") == card_id:
			return i
	return -1

func mulligan(cards_to_replace: Array) -> void:
	for card in cards_to_replace:
		var index = hand.find(card)
		if index != -1:
			hand.remove_at(index)
			deck.append(card)
	
	deck.shuffle()
	draw_cards(cards_to_replace.size())

func random_mulligan(count: int) -> void:
	var indices_to_replace = []
	var available_indices = range(hand.size())
	
	for i in range(min(count, hand.size())):
		if available_indices.is_empty():
			break
		var rand_idx = randi() % available_indices.size()
		indices_to_replace.append(available_indices[rand_idx])
		available_indices.remove_at(rand_idx)
	
	# Sort in reverse to remove from end first
	indices_to_replace.sort()
	indices_to_replace.reverse()
	
	for idx in indices_to_replace:
		var card = hand[idx]
		hand.remove_at(idx)
		deck.append(card)
	
	deck.shuffle()
	draw_cards(count)

func on_hero_died(hero_id: String, hero_color: String) -> void:
	dead_hero_cards[hero_id] = []
	
	# Hand cards: Convert to mana cards
	for i in range(hand.size()):
		var card = hand[i]
		if _card_belongs_to_hero(card, hero_id, hero_color):
			dead_hero_cards[hero_id].append(card.duplicate())
			hand[i] = _create_mana_card(hero_id, hero_color)
	
	# Deck cards: Remove completely
	var cards_to_remove = []
	for card in deck:
		if _card_belongs_to_hero(card, hero_id, hero_color):
			dead_hero_cards[hero_id].append(card.duplicate())
			cards_to_remove.append(card)
	for card in cards_to_remove:
		deck.erase(card)
	
	# Discard pile: Remove completely
	cards_to_remove.clear()
	for card in discard_pile:
		if _card_belongs_to_hero(card, hero_id, hero_color):
			dead_hero_cards[hero_id].append(card.duplicate())
			cards_to_remove.append(card)
	for card in cards_to_remove:
		discard_pile.erase(card)

func _card_belongs_to_hero(card: Dictionary, hero_id: String, hero_color: String) -> bool:
	var card_color = card.get("hero_color", "")
	var card_id = card.get("id", "")
	return card_color == hero_color or card_id.find(hero_id) != -1

func on_hero_revived(hero_id: String) -> void:
	if not dead_hero_cards.has(hero_id):
		return
	
	var cards_to_restore = dead_hero_cards[hero_id]
	for card in cards_to_restore:
		deck.append(card)
	
	deck.shuffle()
	dead_hero_cards.erase(hero_id)

func _create_mana_card(hero_id: String, hero_color: String) -> Dictionary:
	return {
		"id": "mana_" + str(randi()),
		"name": "Manastone",
		"cost": 0,
		"type": "mana",
		"hero_color": hero_color,
		"from_hero_id": hero_id,
		"description": "Gain 1 mana this turn.",
		"image": "res://asset/Others/manastone.png"
	}

func get_hand_size() -> int:
	return hand.size()

func get_deck_size() -> int:
	return deck.size()

func get_hand() -> Array:
	return hand

func get_deck() -> Array:
	return deck
