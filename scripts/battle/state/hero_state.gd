class_name HeroState
extends RefCounted

## HeroState - Represents the state of a hero in battle
## Pure data class - no UI logic, fully serializable for network sync

# Identity
var hero_id: String = ""  # e.g., "priest", "caelum"
var owner_index: int = 0  # 0 = host/player1, 1 = guest/player2
var position: int = 0  # 0-3, position in team (left to right)

# Stats
var hp: int = 100
var max_hp: int = 100
var attack: int = 10
var base_attack: int = 10
var energy: int = 0
var max_energy: int = GameConstants.MAX_ENERGY
var block: int = 0  # Shield/block amount

# Status
var is_dead: bool = false

# Buffs and Debuffs
var buffs: Array[BuffState] = []
var debuffs: Array[BuffState] = []

# Equipment
var equipped_items: Array = []  # Array of equipment card data dictionaries

# ============================================
# INITIALIZATION
# ============================================

static func create(id: String, owner: int, pos: int) -> HeroState:
	var state = HeroState.new()
	state.hero_id = id
	state.owner_index = owner
	state.position = pos
	
	# Load base stats from HeroDatabase
	if HeroDatabase:
		var hero_data = HeroDatabase.get_hero(id)
		if not hero_data.is_empty():
			state.max_hp = hero_data.get("max_hp", 100)
			state.hp = state.max_hp
			state.base_attack = hero_data.get("base_attack", 10)
			state.attack = state.base_attack
	
	return state

static func create_from_hero_data(hero_data: Dictionary, owner: int, pos: int) -> HeroState:
	var state = HeroState.new()
	state.hero_id = hero_data.get("id", "")
	state.owner_index = owner
	state.position = pos
	state.max_hp = hero_data.get("max_hp", 100)
	state.hp = state.max_hp
	state.base_attack = hero_data.get("base_attack", 10)
	state.attack = state.base_attack
	return state

# ============================================
# DAMAGE & HEALING
# ============================================

func take_damage(amount: int) -> Dictionary:
	## Apply damage to this hero. Returns result dictionary.
	if is_dead:
		return {"actual_damage": 0, "shield_absorbed": 0, "caused_death": false}
	
	# Apply damage modifiers (Break debuff increases damage taken)
	var modified_amount = int(amount * get_damage_taken_multiplier())
	
	var actual_damage = modified_amount
	var shield_absorbed = 0
	
	# Shield absorbs damage first
	if block > 0:
		if block >= modified_amount:
			shield_absorbed = modified_amount
			block -= modified_amount
			actual_damage = 0
		else:
			shield_absorbed = block
			actual_damage = modified_amount - block
			block = 0
	
	# Apply damage to HP
	var hp_before = hp
	hp = max(0, hp - actual_damage)
	
	# Check for death
	var caused_death = false
	if hp <= 0 and not is_dead:
		is_dead = true
		caused_death = true
	
	return {
		"actual_damage": actual_damage,
		"shield_absorbed": shield_absorbed,
		"hp_before": hp_before,
		"hp_after": hp,
		"caused_death": caused_death,
		"shield_broken": shield_absorbed > 0 and block == 0
	}

func heal(amount: int) -> Dictionary:
	## Heal this hero. Returns result dictionary.
	if is_dead:
		return {"actual_heal": 0}
	
	var hp_before = hp
	var actual_heal = min(amount, max_hp - hp)
	hp = min(max_hp, hp + amount)
	
	return {
		"actual_heal": actual_heal,
		"hp_before": hp_before,
		"hp_after": hp
	}

func add_block(amount: int) -> void:
	## Add shield/block to this hero
	block += amount

func clear_block() -> void:
	## Remove all block
	block = 0

# ============================================
# ENERGY
# ============================================

func add_energy(amount: int) -> Dictionary:
	## Add energy to this hero. Returns result dictionary.
	if is_dead:
		return {"energy_added": 0, "is_full": false}
	
	var energy_before = energy
	energy = min(max_energy, energy + amount)
	var is_full = energy >= max_energy
	
	return {
		"energy_added": energy - energy_before,
		"energy_before": energy_before,
		"energy_after": energy,
		"is_full": is_full
	}

func use_energy() -> bool:
	## Use all energy (for EX skill). Returns true if successful.
	if energy < max_energy or is_dead:
		return false
	energy = 0
	return true

func is_ex_ready() -> bool:
	return energy >= max_energy and not is_dead

# ============================================
# BUFFS & DEBUFFS
# ============================================

func apply_buff(buff_type: String, duration: int = 1, source_atk: int = 10, source_id: String = "") -> void:
	## Apply a buff to this hero
	# Check if buff already exists - refresh duration
	for buff in buffs:
		if buff.type == buff_type:
			buff.duration = max(buff.duration, duration)
			buff.source_atk = source_atk
			return
	
	# Add new buff
	var new_buff = BuffState.create(buff_type, duration, source_atk, source_id)
	buffs.append(new_buff)

func apply_debuff(debuff_type: String, duration: int = 1, source_atk: int = 10, source_id: String = "") -> void:
	## Apply a debuff to this hero
	# Special handling for Thunder (stacks)
	if debuff_type == "thunder":
		apply_thunder(1, source_atk, source_id)
		return
	
	# Check if debuff already exists - refresh duration
	for debuff in debuffs:
		if debuff.type == debuff_type:
			debuff.duration = max(debuff.duration, duration)
			debuff.source_atk = source_atk
			return
	
	# Add new debuff
	var new_debuff = BuffState.create(debuff_type, duration, source_atk, source_id)
	debuffs.append(new_debuff)

func apply_thunder(stacks: int, source_atk: int, source_id: String = "") -> void:
	## Apply Thunder debuff (stacks)
	for debuff in debuffs:
		if debuff.type == "thunder":
			debuff.add_stacks(stacks)
			debuff.source_atk = source_atk
			debuff.turns_remaining = 2  # Reset timer
			return
	
	# Add new Thunder debuff
	var thunder = BuffState.create_thunder(stacks, source_atk, source_id)
	debuffs.append(thunder)

func remove_buff(buff_type: String) -> bool:
	## Remove a buff by type. Returns true if removed.
	for i in range(buffs.size()):
		if buffs[i].type == buff_type:
			buffs.remove_at(i)
			return true
	return false

func remove_debuff(debuff_type: String) -> bool:
	## Remove a debuff by type. Returns true if removed.
	for i in range(debuffs.size()):
		if debuffs[i].type == debuff_type:
			debuffs.remove_at(i)
			return true
	return false

func has_buff(buff_type: String) -> bool:
	for buff in buffs:
		if buff.type == buff_type:
			return true
	return false

func has_debuff(debuff_type: String) -> bool:
	for debuff in debuffs:
		if debuff.type == debuff_type:
			return true
	return false

func get_buff(buff_type: String) -> BuffState:
	for buff in buffs:
		if buff.type == buff_type:
			return buff
	return null

func get_debuff(debuff_type: String) -> BuffState:
	for debuff in debuffs:
		if debuff.type == debuff_type:
			return debuff
	return null

func tick_buffs() -> Array[String]:
	## Tick all buff durations. Returns array of expired buff types.
	var expired: Array[String] = []
	var to_remove: Array[int] = []
	
	for i in range(buffs.size()):
		if buffs[i].tick():
			expired.append(buffs[i].type)
			to_remove.append(i)
	
	# Remove expired buffs (reverse order to maintain indices)
	for i in range(to_remove.size() - 1, -1, -1):
		buffs.remove_at(to_remove[i])
	
	return expired

func tick_debuffs() -> Array[String]:
	## Tick all debuff durations (except Thunder). Returns array of expired debuff types.
	var expired: Array[String] = []
	var to_remove: Array[int] = []
	
	for i in range(debuffs.size()):
		if debuffs[i].type == "thunder":
			continue  # Thunder is handled separately
		if debuffs[i].tick():
			expired.append(debuffs[i].type)
			to_remove.append(i)
	
	# Remove expired debuffs (reverse order)
	for i in range(to_remove.size() - 1, -1, -1):
		debuffs.remove_at(to_remove[i])
	
	return expired

func tick_thunder() -> int:
	## Tick Thunder debuff. Returns damage to deal (0 if not ready).
	var thunder = get_debuff("thunder")
	if thunder == null:
		return 0
	
	if thunder.tick_thunder():
		var damage = thunder.get_thunder_damage(GameConstants.THUNDER_DAMAGE_MULT)
		remove_debuff("thunder")
		return damage
	
	return 0

func get_thunder_stacks() -> int:
	var thunder = get_debuff("thunder")
	return thunder.stack_count if thunder else 0

# ============================================
# DAMAGE MODIFIERS
# ============================================

func get_damage_dealt_multiplier() -> float:
	## Get multiplier for damage this hero deals
	var mult = 1.0
	if has_buff("empower"):
		mult *= GameConstants.EMPOWER_DAMAGE_MULT
	if has_debuff("weak"):
		mult *= GameConstants.WEAK_DAMAGE_MULT
	return mult

func get_damage_taken_multiplier() -> float:
	## Get multiplier for damage this hero takes
	var mult = 1.0
	if has_debuff("break"):
		mult *= GameConstants.BREAK_DAMAGE_MULT
	if has_debuff("marked"):
		mult *= 1.25  # Marked increases damage taken by 25%
	return mult

# ============================================
# EQUIPMENT
# ============================================

func add_equipment(equip_data: Dictionary) -> void:
	equipped_items.append(equip_data)

func remove_equipment(equip_id: String) -> bool:
	for i in range(equipped_items.size()):
		if equipped_items[i].get("id", "") == equip_id:
			equipped_items.remove_at(i)
			return true
	return false

func has_equipment() -> bool:
	return not equipped_items.is_empty()

func clear_equipment() -> void:
	equipped_items.clear()

# ============================================
# TURN EVENTS
# ============================================

func on_turn_start() -> Dictionary:
	## Called at the start of this hero's owner's turn. Returns effects to apply.
	var results = {
		"regen_heal": 0
	}
	
	# Reset attack to base
	attack = base_attack
	
	# Regeneration healing
	if has_buff("regen"):
		var regen = get_buff("regen")
		results["regen_heal"] = int(regen.source_atk * GameConstants.REGEN_HEAL_MULT)
	
	return results

func on_turn_end() -> Dictionary:
	## Called at the end of this hero's owner's turn. Returns effects to apply.
	var results = {
		"expired_buffs": [],
		"expired_debuffs": [],
		"thunder_damage": 0,
		"burn_damage": 0,
		"poison_damage": 0
	}
	
	# Tick buffs and debuffs
	results["expired_buffs"] = tick_buffs()
	results["expired_debuffs"] = tick_debuffs()
	
	# Thunder damage
	results["thunder_damage"] = tick_thunder()
	
	# Burn damage (at turn end)
	if has_debuff("burn"):
		var burn = get_debuff("burn")
		results["burn_damage"] = int(burn.source_atk * 0.5)  # 50% of source ATK
	
	return results

# ============================================
# SERIALIZATION
# ============================================

func serialize() -> Dictionary:
	## Convert to Dictionary for network transmission
	var serialized_buffs = []
	for buff in buffs:
		serialized_buffs.append(buff.serialize())
	
	var serialized_debuffs = []
	for debuff in debuffs:
		serialized_debuffs.append(debuff.serialize())
	
	return {
		"hero_id": hero_id,
		"owner_index": owner_index,
		"position": position,
		"hp": hp,
		"max_hp": max_hp,
		"attack": attack,
		"base_attack": base_attack,
		"energy": energy,
		"max_energy": max_energy,
		"block": block,
		"is_dead": is_dead,
		"buffs": serialized_buffs,
		"debuffs": serialized_debuffs,
		"equipped_items": equipped_items.duplicate(true)
	}

static func deserialize(data: Dictionary) -> HeroState:
	## Create HeroState from Dictionary (received from network)
	var state = HeroState.new()
	state.hero_id = data.get("hero_id", "")
	state.owner_index = data.get("owner_index", 0)
	state.position = data.get("position", 0)
	state.hp = data.get("hp", 100)
	state.max_hp = data.get("max_hp", 100)
	state.attack = data.get("attack", 10)
	state.base_attack = data.get("base_attack", 10)
	state.energy = data.get("energy", 0)
	state.max_energy = data.get("max_energy", GameConstants.MAX_ENERGY)
	state.block = data.get("block", 0)
	state.is_dead = data.get("is_dead", false)
	state.equipped_items = data.get("equipped_items", []).duplicate(true)
	
	# Deserialize buffs
	state.buffs = []
	for buff_data in data.get("buffs", []):
		state.buffs.append(BuffState.deserialize(buff_data))
	
	# Deserialize debuffs
	state.debuffs = []
	for debuff_data in data.get("debuffs", []):
		state.debuffs.append(BuffState.deserialize(debuff_data))
	
	return state

func duplicate_state() -> HeroState:
	## Create a deep copy of this hero state
	return HeroState.deserialize(serialize())

# ============================================
# DEBUG
# ============================================

func _to_string() -> String:
	return "[Hero %s] HP:%d/%d Energy:%d/%d Block:%d Dead:%s Buffs:%d Debuffs:%d" % [
		hero_id, hp, max_hp, energy, max_energy, block, is_dead, buffs.size(), debuffs.size()
	]
