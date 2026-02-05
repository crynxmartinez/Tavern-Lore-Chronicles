class_name BuffState
extends RefCounted

## BuffState - Represents a buff or debuff on a hero
## Used for serialization and network sync

enum BuffType {
	BUFF,
	DEBUFF
}

# Buff/Debuff identifiers (matching existing hero.gd constants)
const BUFF_TYPES = ["shield", "empower", "taunt", "regen", "block", "bolster", "star", "equipped"]
const DEBUFF_TYPES = ["stun", "weak", "burn", "poison", "bleed", "frost", "chain", "entangle", "break", "bomb", "thunder", "marked"]

# Core properties
var type: String = ""  # e.g., "shield", "poison", "thunder"
var buff_type: BuffType = BuffType.BUFF  # BUFF or DEBUFF
var duration: int = 1  # Turns remaining (-1 = permanent)
var value: int = 0  # Effect value (damage, heal amount, etc.)
var source_atk: int = 10  # Source hero's attack (for scaling effects)
var source_hero_id: String = ""  # Who applied this buff/debuff
var stack_count: int = 1  # For stackable effects like Thunder

# Thunder-specific
var turns_remaining: int = 0  # For Thunder: turns until it triggers

# ============================================
# INITIALIZATION
# ============================================

static func create(buff_type_name: String, buff_duration: int = 1, atk: int = 10, source_id: String = "") -> BuffState:
	var state = BuffState.new()
	state.type = buff_type_name
	state.duration = buff_duration
	state.source_atk = atk
	state.source_hero_id = source_id
	state.stack_count = 1
	
	# Determine if buff or debuff
	if buff_type_name in DEBUFF_TYPES:
		state.buff_type = BuffType.DEBUFF
	else:
		state.buff_type = BuffType.BUFF
	
	# Special handling for Thunder
	if buff_type_name == "thunder":
		state.duration = -1  # Thunder doesn't expire by duration
		state.turns_remaining = 2  # Triggers after 2 turns
	
	return state

static func create_thunder(stacks: int, atk: int, source_id: String = "") -> BuffState:
	var state = BuffState.new()
	state.type = "thunder"
	state.buff_type = BuffType.DEBUFF
	state.duration = -1
	state.source_atk = atk
	state.source_hero_id = source_id
	state.stack_count = stacks
	state.turns_remaining = 2
	return state

# ============================================
# METHODS
# ============================================

func is_buff() -> bool:
	return buff_type == BuffType.BUFF

func is_debuff() -> bool:
	return buff_type == BuffType.DEBUFF

func is_permanent() -> bool:
	return duration == -1

func is_expired() -> bool:
	if is_permanent():
		return false
	return duration <= 0

func tick() -> bool:
	## Decrements duration by 1. Returns true if expired.
	if is_permanent():
		return false
	duration -= 1
	return duration <= 0

func tick_thunder() -> bool:
	## For Thunder: decrements turns_remaining. Returns true if ready to trigger.
	if type != "thunder":
		return false
	turns_remaining -= 1
	return turns_remaining <= 0

func add_stacks(amount: int) -> void:
	## Add stacks (for stackable effects like Thunder)
	stack_count += amount

func get_thunder_damage(base_multiplier: float = 1.0) -> int:
	## Calculate Thunder damage based on stacks and source attack
	if type != "thunder":
		return 0
	return int(stack_count * source_atk * base_multiplier)

func duplicate_state() -> BuffState:
	## Create a copy of this buff state
	var copy = BuffState.new()
	copy.type = type
	copy.buff_type = buff_type
	copy.duration = duration
	copy.value = value
	copy.source_atk = source_atk
	copy.source_hero_id = source_hero_id
	copy.stack_count = stack_count
	copy.turns_remaining = turns_remaining
	return copy

# ============================================
# SERIALIZATION (for network sync)
# ============================================

func serialize() -> Dictionary:
	## Convert to Dictionary for network transmission
	return {
		"type": type,
		"buff_type": buff_type,
		"duration": duration,
		"value": value,
		"source_atk": source_atk,
		"source_hero_id": source_hero_id,
		"stack_count": stack_count,
		"turns_remaining": turns_remaining
	}

static func deserialize(data: Dictionary) -> BuffState:
	## Create BuffState from Dictionary (received from network)
	var state = BuffState.new()
	state.type = data.get("type", "")
	state.buff_type = data.get("buff_type", BuffType.BUFF)
	state.duration = data.get("duration", 1)
	state.value = data.get("value", 0)
	state.source_atk = data.get("source_atk", 10)
	state.source_hero_id = data.get("source_hero_id", "")
	state.stack_count = data.get("stack_count", 1)
	state.turns_remaining = data.get("turns_remaining", 0)
	return state

# ============================================
# DEBUG
# ============================================

func _to_string() -> String:
	var type_str = "BUFF" if is_buff() else "DEBUFF"
	if type == "thunder":
		return "[%s] %s: stacks=%d, triggers_in=%d turns" % [type_str, type, stack_count, turns_remaining]
	return "[%s] %s: duration=%d, source_atk=%d" % [type_str, type, duration, source_atk]
