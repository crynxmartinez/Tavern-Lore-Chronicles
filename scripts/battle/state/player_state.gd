class_name PlayerState
extends RefCounted

## PlayerState - Represents a player's state in battle
## Contains heroes, hand, deck info, and mana

# Identity
var player_index: int = 0  # 0 = host/player1, 1 = guest/player2
var client_id: int = -1  # Network client ID
var username: String = "Player"
var is_host: bool = false

# Mana
var mana: int = GameConstants.STARTING_MANA
var max_mana: int = GameConstants.STARTING_MANA

# Heroes (4 heroes per player)
var heroes: Array[HeroState] = []

# Hand and Deck (only visible to owner in PVP)
var hand: Array = []  # Array of card data dictionaries
var deck_count: int = 0  # Number of cards remaining in deck
var hand_count: int = 0  # For opponent display (they only see count, not cards)

# Turn state
var is_turn: bool = false
var actions_this_turn: int = 0

# ============================================
# INITIALIZATION
# ============================================

static func create(index: int, name: String, host: bool = false) -> PlayerState:
	var state = PlayerState.new()
	state.player_index = index
	state.username = name
	state.is_host = host
	state.mana = GameConstants.STARTING_MANA
	state.max_mana = GameConstants.STARTING_MANA
	return state

static func create_from_team(index: int, team_ids: Array, name: String, host: bool = false) -> PlayerState:
	## Create player state with heroes from team IDs
	var state = PlayerState.create(index, name, host)
	
	for i in range(team_ids.size()):
		var hero_id = team_ids[i]
		var hero_state = HeroState.create(hero_id, index, i)
		state.heroes.append(hero_state)
	
	return state

# ============================================
# MANA
# ============================================

func spend_mana(amount: int) -> bool:
	## Spend mana. Returns true if successful.
	if mana < amount:
		return false
	mana -= amount
	return true

func restore_mana() -> void:
	## Restore mana to max (called at turn start)
	mana = max_mana

func increase_max_mana() -> void:
	## Increase max mana by 1 (up to cap)
	if max_mana < GameConstants.MANA_CAP:
		max_mana += GameConstants.MANA_PER_TURN

func can_afford(cost: int) -> bool:
	return mana >= cost

# ============================================
# HEROES
# ============================================

func get_hero(hero_id: String) -> HeroState:
	## Get hero by ID
	for hero in heroes:
		if hero.hero_id == hero_id:
			return hero
	return null

func get_hero_at_position(pos: int) -> HeroState:
	## Get hero at position (0-3)
	for hero in heroes:
		if hero.position == pos:
			return hero
	return null

func get_alive_heroes() -> Array[HeroState]:
	## Get all living heroes
	var alive: Array[HeroState] = []
	for hero in heroes:
		if not hero.is_dead:
			alive.append(hero)
	return alive

func get_dead_heroes() -> Array[HeroState]:
	## Get all dead heroes
	var dead: Array[HeroState] = []
	for hero in heroes:
		if hero.is_dead:
			dead.append(hero)
	return dead

func has_alive_heroes() -> bool:
	for hero in heroes:
		if not hero.is_dead:
			return true
	return false

func get_front_hero() -> HeroState:
	## Get the frontmost alive hero (lowest position)
	var alive = get_alive_heroes()
	if alive.is_empty():
		return null
	
	var front = alive[0]
	for hero in alive:
		if hero.position < front.position:
			front = hero
	return front

func get_hero_with_taunt() -> HeroState:
	## Get hero with taunt buff (if any)
	for hero in heroes:
		if not hero.is_dead and hero.has_buff("taunt"):
			return hero
	return null

# ============================================
# HAND & DECK
# ============================================

func add_card_to_hand(card_data: Dictionary) -> void:
	hand.append(card_data)
	hand_count = hand.size()

func remove_card_from_hand(index: int) -> Dictionary:
	## Remove card at index from hand. Returns the card data.
	if index < 0 or index >= hand.size():
		return {}
	var card = hand[index]
	hand.remove_at(index)
	hand_count = hand.size()
	return card

func remove_card_by_id(card_id: String) -> Dictionary:
	## Remove card by ID from hand. Returns the card data.
	for i in range(hand.size()):
		if hand[i].get("id", "") == card_id:
			return remove_card_from_hand(i)
	return {}

func get_card_in_hand(index: int) -> Dictionary:
	if index < 0 or index >= hand.size():
		return {}
	return hand[index]

func find_card_index(card_id: String) -> int:
	## Find card index by ID. Returns -1 if not found.
	for i in range(hand.size()):
		if hand[i].get("id", "") == card_id:
			return i
	return -1

func clear_hand() -> void:
	hand.clear()
	hand_count = 0

func set_deck_count(count: int) -> void:
	deck_count = count

func decrement_deck_count(amount: int = 1) -> void:
	deck_count = max(0, deck_count - amount)

# ============================================
# TURN MANAGEMENT
# ============================================

func start_turn() -> void:
	## Called when this player's turn starts
	is_turn = true
	actions_this_turn = 0
	
	# Restore mana
	restore_mana()
	
	# Trigger turn start effects on all heroes
	for hero in heroes:
		if not hero.is_dead:
			hero.on_turn_start()

func end_turn() -> Dictionary:
	## Called when this player's turn ends. Returns effects to apply.
	is_turn = false
	
	var results = {
		"hero_effects": []  # Array of {hero_id, effects}
	}
	
	# Trigger turn end effects on all heroes
	for hero in heroes:
		if not hero.is_dead:
			var hero_effects = hero.on_turn_end()
			if not hero_effects.is_empty():
				results["hero_effects"].append({
					"hero_id": hero.hero_id,
					"effects": hero_effects
				})
	
	# Add energy to all alive heroes
	for hero in heroes:
		if not hero.is_dead:
			hero.add_energy(GameConstants.ENERGY_ON_TURN_END)
	
	return results

func increment_action_count() -> void:
	actions_this_turn += 1

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	## Convert to Dictionary for network transmission
	var serialized_heroes = []
	for hero in heroes:
		serialized_heroes.append(hero.serialize())
	
	return {
		"player_index": player_index,
		"client_id": client_id,
		"username": username,
		"is_host": is_host,
		"mana": mana,
		"max_mana": max_mana,
		"heroes": serialized_heroes,
		"hand": hand.duplicate(true),
		"deck_count": deck_count,
		"hand_count": hand_count,
		"is_turn": is_turn,
		"actions_this_turn": actions_this_turn
	}

func serialize_for_opponent() -> Dictionary:
	## Serialize for opponent (hide hand contents)
	var serialized_heroes = []
	for hero in heroes:
		serialized_heroes.append(hero.serialize())
	
	return {
		"player_index": player_index,
		"client_id": client_id,
		"username": username,
		"is_host": is_host,
		"mana": mana,
		"max_mana": max_mana,
		"heroes": serialized_heroes,
		"hand": [],  # Hide hand contents from opponent
		"deck_count": deck_count,
		"hand_count": hand.size(),  # Only show count
		"is_turn": is_turn,
		"actions_this_turn": actions_this_turn
	}

static func deserialize(data: Dictionary) -> PlayerState:
	## Create PlayerState from Dictionary (received from network)
	var state = PlayerState.new()
	state.player_index = data.get("player_index", 0)
	state.client_id = data.get("client_id", -1)
	state.username = data.get("username", "Player")
	state.is_host = data.get("is_host", false)
	state.mana = data.get("mana", GameConstants.STARTING_MANA)
	state.max_mana = data.get("max_mana", GameConstants.STARTING_MANA)
	state.hand = data.get("hand", []).duplicate(true)
	state.deck_count = data.get("deck_count", 0)
	state.hand_count = data.get("hand_count", 0)
	state.is_turn = data.get("is_turn", false)
	state.actions_this_turn = data.get("actions_this_turn", 0)
	
	# Deserialize heroes
	state.heroes = []
	for hero_data in data.get("heroes", []):
		state.heroes.append(HeroState.deserialize(hero_data))
	
	return state

func duplicate_state() -> PlayerState:
	## Create a deep copy of this player state
	return PlayerState.deserialize(serialize())

# ============================================
# DEBUG
# ============================================

func _to_string() -> String:
	var alive_count = get_alive_heroes().size()
	return "[Player %d: %s] Mana:%d/%d Heroes:%d/%d alive Hand:%d Deck:%d Turn:%s" % [
		player_index, username, mana, max_mana, alive_count, heroes.size(), 
		hand.size(), deck_count, is_turn
	]
