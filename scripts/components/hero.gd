extends Control
class_name Hero

signal hero_clicked(hero: Hero)
signal hero_died(hero: Hero)
signal energy_full(hero: Hero)
signal shield_broken(hero: Hero)
signal counter_triggered(defender: Hero, attacker: Hero, reflect_damage: int)

@export var hero_id: String = ""  # Template/type ID (e.g. "priest", "squire")
@export var is_player_hero: bool = true
var instance_id: String = ""  # Globally unique instance ID (e.g. "host_priest_0")
var owner_id: String = ""  # player_id of the player who owns this hero
var team_index: int = -1  # Original position in team (0=back, 3=front for player; 0=front, 3=back for enemy)

var hero_data: Dictionary = {}
var base_hp: int = 10
var hp_multiplier: int = 10
var max_hp: int = GameConstants.DEFAULT_MAX_HP
var current_hp: int = GameConstants.DEFAULT_MAX_HP
var base_attack: int = GameConstants.DEFAULT_BASE_ATTACK
var current_attack: int = GameConstants.DEFAULT_BASE_ATTACK
var base_def: int = 0
var current_def: int = 0  # base_def + item/buff bonuses
var energy: int = 0
var max_energy: int = GameConstants.MAX_ENERGY
var block: int = 0

var is_dead: bool = false
var is_flipped: bool = false
var regen_draw_triggered: bool = false

# Buff/Debuff system
var active_buffs: Dictionary = {}  # {buff_name: {duration: int, source_atk: int, instance_id: String}}
var active_debuffs: Dictionary = {}  # {debuff_name: {duration: int, source_atk: int, instance_id: String}}
var _buff_counter: int = 0  # Auto-incrementing counter for buff/debuff instance IDs

# Equipment system - tracks equipment cards played on this hero
var equipped_items: Array = []  # Array of equipment card data dictionaries

const BUFF_ICONS = {
	"shield": "res://asset/buff debuff/Shield-0.webp",
	"empower": "res://asset/buff debuff/Empower.webp",
	"taunt": "res://asset/buff debuff/Taunt-0.webp",
	"regen": "res://asset/buff debuff/regen.webp",
	"block": "res://asset/buff debuff/Block.webp",
	"bolster": "res://asset/buff debuff/Bolster.webp",
	"star": "res://asset/buff debuff/Star.webp",
	"equipped": "res://asset/buff debuff/Bolster.webp",  # Equipment indicator
	"dana_shield_draw": "res://asset/buff debuff/Shield-0.webp",  # Dana's shield-draw marker
	"counter_50": "res://asset/buff debuff/Shield-0.webp",  # Counter 50% Reflect
	"counter_100": "res://asset/buff debuff/Shield-0.webp",  # Counter 100% Reflect
	"crescent_moon": "res://asset/buff debuff/cresent moon.webp",  # Nyxara Crescent Moon stacks
	"eclipse_buff": "res://asset/buff debuff/eclipse.webp",  # Nyxara Eclipse (double EX damage)
	"redirect": "res://asset/buff debuff/redirect.webp",  # Kalasag Redirect (50% damage transferred)
	"empower_heal": "res://asset/buff debuff/Empower.webp",  # Empower Heal (+50% healing)
	"empower_shield": "res://asset/buff debuff/Empower.webp",  # Empower Shield (+50% shield)
	"regen_draw": "res://asset/buff debuff/regen.webp",  # Regen + Draw 1 when fires
	"damage_link": "res://asset/buff debuff/redirect.webp"  # Damage Link (share damage among linked allies)
}

const DEBUFF_ICONS = {
	"stun": "res://asset/buff debuff/Stun-0.webp",
	"weak": "res://asset/buff debuff/Weak.webp",
	"burn": "res://asset/buff debuff/Fire.webp",
	"poison": "res://asset/buff debuff/Decaying.webp",
	"bleed": "res://asset/buff debuff/Blood.webp",
	"frost": "res://asset/buff debuff/Frost.webp",
	"chain": "res://asset/buff debuff/Chain.webp",
	"entangle": "res://asset/buff debuff/Entangle.webp",
	"break": "res://asset/buff debuff/Break.webp",
	"bomb": "res://asset/buff debuff/Bomb.webp",
	"thunder": "res://asset/buff debuff/Thunder.webp",
	"marked": "res://asset/buff debuff/Target.webp",
	"time_bomb": "res://asset/buff debuff/Bomb.webp"
}

const BUFF_DESCRIPTIONS = {
	"shield": {"name": "Shield", "effect": "Absorbs damage before HP."},
	"empower": {"name": "Empower", "effect": "+50% damage dealt."},
	"taunt": {"name": "Taunt", "effect": "Enemies must target this hero."},
	"regen": {"name": "Regeneration", "effect": "Delayed heal at turn start. Stacks."},
	"block": {"name": "Block", "effect": "Reduces incoming damage."},
	"bolster": {"name": "Bolster", "effect": "Increased defense."},
	"star": {"name": "Blessed", "effect": "Enhanced abilities."},
	"equipped": {"name": "Equipped", "effect": "This hero has equipment attached."},
	"dana_shield_draw": {"name": "Smart Shield", "effect": "When Shield expires, draw 1 card."},
	"counter_50": {"name": "Counter", "effect": "Reflects 50% of damage back to the attacker."},
	"counter_100": {"name": "Counter+", "effect": "Reflects 100% of damage back to the attacker."},
	"crescent_moon": {"name": "Crescent Moon", "effect": "At 4 stacks: consume all, fill EX gauge to max."},
	"eclipse_buff": {"name": "Eclipse", "effect": "Next EX this turn deals double damage."},
	"redirect": {"name": "Redirect", "effect": "50% of damage taken is transferred to Kalasag."},
	"empower_heal": {"name": "Empower Heal", "effect": "+50% healing done."},
	"empower_shield": {"name": "Empower Shield", "effect": "+50% shield given."},
	"regen_draw": {"name": "Regen+", "effect": "Delayed heal at turn start + Draw 1 card."},
	"damage_link": {"name": "Damage Link", "effect": "Damage taken is shared among all linked allies."}
}

const DEBUFF_DESCRIPTIONS = {
	"stun": {"name": "Stun", "effect": "Cannot act next turn."},
	"weak": {"name": "Weak", "effect": "-50% damage dealt."},
	"burn": {"name": "Burn", "effect": "Takes damage at turn end."},
	"poison": {"name": "Poison", "effect": "Takes damage at turn start."},
	"bleed": {"name": "Bleed", "effect": "Takes damage when acting."},
	"frost": {"name": "Frost", "effect": "+1 mana cost to all cards."},
	"chain": {"name": "Chain", "effect": "Cannot use skills."},
	"entangle": {"name": "Entangle", "effect": "Cannot move or dodge."},
	"break": {"name": "Break", "effect": "+50% damage taken."},
	"bomb": {"name": "Bomb", "effect": "Explodes after duration."},
	"thunder": {"name": "Thunder", "effect": "Lightning strikes at turn end. Stacks."},
	"marked": {"name": "Marked", "effect": "Takes increased damage."},
	"time_bomb": {"name": "Time Bomb", "effect": "Detonates at end of turn: 10 damage + removes 1 card from hand."}
}

@onready var sprite: TextureRect = $Sprite
@onready var hp_bar: ProgressBar = $StatsContainer/HPBar
@onready var hp_label: Label = $StatsContainer/HPBar/HPLabel
@onready var shield_overlay: ProgressBar = $StatsContainer/HPBar/ShieldOverlay
@onready var energy_bar: ProgressBar = $StatsContainer/EnergyBar
@onready var energy_label: Label = $StatsContainer/EnergyBar/EnergyLabel
@onready var click_area: Button = $ClickArea
@onready var aura: ColorRect = $Aura
@onready var shield_effect: TextureRect = $ShieldEffect
@onready var buff_container: HBoxContainer = $BuffContainerOverlay

var aura_tween: Tween = null
var shield_tween: Tween = null
var thunder_cloud: TextureRect = null  # Dark cloud for Thunder debuff

const HP_COLOR: Color = Color(0.8, 0.2, 0.2)
const ENERGY_COLOR: Color = Color(0.2, 0.4, 0.8)
const ENERGY_FULL_COLOR: Color = Color(1.0, 0.85, 0.2)
const SHIELD_COLOR: Color = Color(1.0, 0.85, 0.2)  # Yellow shield gauge
const DAMAGE_COLOR: Color = Color(1.0, 0.2, 0.2)
const HEAL_COLOR: Color = Color(0.2, 1.0, 0.3)
const SHIELD_ABSORB_COLOR: Color = Color(0.3, 0.6, 1.0)

func _ready() -> void:
	click_area.pressed.connect(_on_clicked)
	_setup_bar_colors()
	if not hero_id.is_empty():
		setup(hero_id)

func _setup_bar_colors() -> void:
	var hp_style = StyleBoxFlat.new()
	hp_style.bg_color = HP_COLOR
	hp_bar.add_theme_stylebox_override("fill", hp_style)
	
	var energy_style = StyleBoxFlat.new()
	energy_style.bg_color = ENERGY_COLOR
	energy_bar.add_theme_stylebox_override("fill", energy_style)
	
	# Shield overlay - green, transparent background
	var shield_style = StyleBoxFlat.new()
	shield_style.bg_color = SHIELD_COLOR
	shield_overlay.add_theme_stylebox_override("fill", shield_style)
	
	# Make shield overlay background transparent
	var shield_bg = StyleBoxFlat.new()
	shield_bg.bg_color = Color(0, 0, 0, 0)
	shield_overlay.add_theme_stylebox_override("background", shield_bg)

func setup(id: String) -> void:
	hero_id = id
	hero_data = HeroDatabase.get_hero(id)
	
	if hero_data.is_empty():
		push_error("Hero not found: " + id)
		return
	
	base_hp = hero_data.get("base_hp", 10)
	hp_multiplier = hero_data.get("hp_multiplier", 10)
	max_hp = hero_data.get("max_hp", base_hp * hp_multiplier)
	current_hp = max_hp
	base_attack = hero_data.get("base_attack", 10)
	current_attack = base_attack
	base_def = hero_data.get("base_def", 0)
	current_def = base_def
	energy = 0
	
	_load_sprite(hero_data.get("idle_sprite", ""))
	_update_ui()

func _load_sprite(path: String, use_flip_h: bool = false) -> void:
	if path.is_empty():
		return
	var texture = load(path)
	if texture and sprite:
		sprite.texture = texture
		sprite.flip_h = use_flip_h
		# Resize sprite to match texture size (no clipping)
		var tex_size = texture.get_size()
		sprite.custom_minimum_size = tex_size
		sprite.size = tex_size
		# Reposition based on alignment
		if is_flipped:
			_align_sprite_right()
		else:
			_align_sprite_left()

func _align_sprite_left() -> void:
	# Align sprite to LEFT edge of hero box (player heroes)
	if sprite and sprite.texture:
		var tex_size = sprite.texture.get_size()
		sprite.position = Vector2(0, 450 - tex_size.y - 50)

func _align_sprite_right() -> void:
	# Align sprite to RIGHT edge of hero box (enemy heroes)
	if sprite and sprite.texture:
		var tex_size = sprite.texture.get_size()
		sprite.position = Vector2(200 - tex_size.x, 450 - tex_size.y - 50)

func _update_ui() -> void:
	# HP bar shows current HP with smooth tween
	if hp_bar:
		hp_bar.max_value = max_hp
		var hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		hp_tween.tween_property(hp_bar, "value", current_hp, 0.3)
	
	# Shield overlay shows on top of HP (green portion) with smooth tween
	if shield_overlay:
		shield_overlay.max_value = max_hp
		var shield_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		shield_tween.tween_property(shield_overlay, "value", block, 0.2)
	
	# Show HP + Shield in label if shield exists
	if hp_label:
		if block > 0:
			hp_label.text = str(current_hp) + "+" + str(block)
		else:
			hp_label.text = str(current_hp)
	
	# Ensure shield effect overlay matches block state
	if block > 0:
		if shield_effect and not shield_effect.visible:
			_show_shield_effect()
	else:
		if shield_effect and shield_effect.visible:
			_hide_shield_effect()
	
	# Energy bar with smooth tween
	if energy_bar:
		energy_bar.max_value = max_energy
		var energy_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		energy_tween.tween_property(energy_bar, "value", energy, 0.25)
		
		var energy_style = StyleBoxFlat.new()
		if energy >= max_energy:
			energy_style.bg_color = ENERGY_FULL_COLOR
		else:
			energy_style.bg_color = ENERGY_COLOR
		energy_bar.add_theme_stylebox_override("fill", energy_style)
	
	# Energy label shows current/max
	if energy_label:
		energy_label.text = str(energy) + "/" + str(max_energy)

func get_def() -> int:
	## Returns current effective DEF (base + items/buffs)
	return current_def

func get_damage_reduction_percent() -> float:
	## DEF damage reduction: every 1 DEF = 2%, max 30%
	return min(get_def() * 2.0, 30.0)

func apply_def_reduction(raw_damage: int) -> int:
	## Apply DEF-based damage reduction to raw damage
	var reduction = get_damage_reduction_percent() / 100.0
	return max(1, int(raw_damage * (1.0 - reduction)))

func calculate_heal(hp_mult: float) -> int:
	## Heal scales off caster's max HP
	return max(1, int(max_hp * hp_mult))

func calculate_shield(card_base_shield: int, def_mult: float) -> int:
	## Shield = card_base + (DEF × def_multiplier)
	return max(0, card_base_shield + int(get_def() * def_mult))

func take_damage(amount: int, attacker: Hero = null, ignore_shield: bool = false) -> void:
	if is_dead:
		return
	
	# Apply DEF damage reduction first
	var after_def = apply_def_reduction(amount)
	# Apply Break debuff multiplier (increases damage taken)
	var modified_amount = int(after_def * get_damage_taken_multiplier())
	
	var actual_damage = modified_amount
	var shield_absorbed = 0
	var had_shield = block > 0
	if block > 0 and not ignore_shield:
		if block >= modified_amount:
			shield_absorbed = modified_amount
			block -= modified_amount
			actual_damage = 0
		else:
			shield_absorbed = block
			actual_damage = modified_amount - block
			block = 0
	
	# Hide shield effect if shield is depleted
	if had_shield and block == 0:
		_hide_shield_effect()
		# VFX Library: shield break effect on hero sprite
		if VFX:
			var sprite_center = global_position
			if sprite:
				sprite_center = sprite.global_position + sprite.size / 2
			VFX.spawn_shield_break(sprite_center)
		shield_broken.emit(self)
	
	current_hp = max(0, current_hp - actual_damage)
	
	# Energy gain when being hit
	if actual_damage > 0:
		add_energy(GameConstants.ENERGY_ON_HIT)
	
	# Show shield absorb effect
	if shield_absorbed > 0:
		_show_shield_absorb_effect(shield_absorbed)
	
	# Show damage number
	if actual_damage > 0:
		_spawn_floating_number(actual_damage, DAMAGE_COLOR)
		# VFX Library: spawn damage particles on the hero sprite
		if VFX:
			var sprite_center = global_position
			if sprite:
				sprite_center = sprite.global_position + sprite.size / 2
			VFX.spawn_particles(sprite_center, Color(1.0, 0.3, 0.3), 10)
	
	_play_hit_animation()
	_update_ui()
	
	# Counter (Reflect): iterate all counter_* buffs and sum reflect %
	# Only triggers on direct attacks (attacker != null), not delayed damage (thunder, burn, etc.)
	if attacker != null and modified_amount > 0:
		var total_reflect_pct = 0
		for buff_name in active_buffs:
			if buff_name.begins_with("counter_"):
				var pct_str = buff_name.substr(8)  # e.g. "50" from "counter_50"
				total_reflect_pct += int(pct_str)
		if total_reflect_pct > 0:
			var reflect_damage = int(modified_amount * total_reflect_pct / 100.0)
			if reflect_damage > 0 and not attacker.is_dead:
				counter_triggered.emit(self, attacker, reflect_damage)
				print(hero_data.get("name", "Hero") + " Counter! Reflecting " + str(total_reflect_pct) + "% (" + str(reflect_damage) + " damage) to " + attacker.hero_data.get("name", "Attacker"))
	
	if current_hp <= 0:
		die()

func heal(amount: int) -> void:
	if is_dead:
		return
	# Empower Heal: +50% healing
	var modified_amount = amount
	if has_buff("empower_heal"):
		modified_amount = int(amount * GameConstants.EMPOWER_HEAL_MULT)
	var actual_heal = min(modified_amount, max_hp - current_hp)
	current_hp = min(max_hp, current_hp + modified_amount)
	
	# Show heal effect
	if actual_heal > 0:
		_show_heal_effect(actual_heal)
		_spawn_heal_sparkles()
		# VFX Library: spawn heal particles on the hero sprite
		if VFX:
			var sprite_center = global_position
			if sprite:
				sprite_center = sprite.global_position + sprite.size / 2
			VFX.spawn_heal_effect(sprite_center)
	
	_update_ui()

func add_energy(amount: int) -> void:
	if is_dead:
		return
	energy = min(max_energy, energy + amount)
	_update_ui()
	
	if energy >= max_energy:
		energy_full.emit(self)

func use_ex_skill() -> bool:
	if energy < max_energy or is_dead:
		return false
	
	energy = 0
	# VFX Library: EX skill activation with energy burst on hero sprite
	if VFX:
		var sprite_center = global_position
		if sprite:
			sprite_center = sprite.global_position + sprite.size / 2
		VFX.spawn_energy_burst(sprite_center, Color(1.0, 0.85, 0.2))
	_play_cast_animation()
	_update_ui()
	return true

func add_block(amount: int) -> void:
	# Empower Shield: +50% shield
	var modified_amount = amount
	if has_buff("empower_shield"):
		modified_amount = int(amount * GameConstants.EMPOWER_SHIELD_MULT)
	var had_no_shield = block == 0
	block += modified_amount
	_update_ui()
	
	# Spawn shield sparkles effect
	_spawn_shield_sparkles()
	
	# Show shield effect overlay if we now have shield
	if had_no_shield and block > 0:
		_show_shield_effect()

func on_turn_start() -> void:
	current_attack = base_attack
	# Apply regeneration healing at turn start, then consume (delayed heal)
	if has_buff("regen"):
		var regen_data = active_buffs["regen"]
		var heal_amount = regen_data.get("heal_amount", 0)
		if heal_amount > 0:
			heal(heal_amount)
		remove_buff("regen")
	# Regen Draw: same as regen but also draws 1 card (draw handled by battle.gd)
	if has_buff("regen_draw"):
		var regen_draw_data = active_buffs["regen_draw"]
		var heal_amount = regen_draw_data.get("heal_amount", 0)
		if heal_amount > 0:
			heal(heal_amount)
		remove_buff("regen_draw")
		regen_draw_triggered = true

func on_turn_end() -> void:
	# DEPRECATED - use on_own_turn_end() and on_opponent_turn_end() instead
	# Kept for backwards compatibility, calls own_turn_end
	on_own_turn_end()

func on_own_turn_end() -> void:
	## Called when THIS hero's owner ends their turn.
	## Removes buffs/debuffs with expire_on = "own_turn_end"
	var buffs_to_remove = []
	for buff_name in active_buffs:
		var expire_on = active_buffs[buff_name].get("expire_on", "")
		if expire_on == "own_turn_end":
			buffs_to_remove.append(buff_name)
	for buff_name in buffs_to_remove:
		remove_buff(buff_name)
	
	var debuffs_to_remove = []
	for debuff_name in active_debuffs:
		if debuff_name == "thunder":
			continue  # Thunder is handled separately via tick_thunder()
		var expire_on = active_debuffs[debuff_name].get("expire_on", "")
		if expire_on == "own_turn_end":
			debuffs_to_remove.append(debuff_name)
	for debuff_name in debuffs_to_remove:
		remove_debuff(debuff_name)

func on_opponent_turn_end() -> void:
	## Called when the OPPONENT of this hero's owner ends their turn.
	## Removes buffs/debuffs with expire_on = "opponent_turn_end"
	var buffs_to_remove = []
	for buff_name in active_buffs:
		var expire_on = active_buffs[buff_name].get("expire_on", "")
		if expire_on == "opponent_turn_end":
			buffs_to_remove.append(buff_name)
	for buff_name in buffs_to_remove:
		remove_buff(buff_name)
	
	var debuffs_to_remove = []
	for debuff_name in active_debuffs:
		if debuff_name == "thunder":
			continue
		var expire_on = active_debuffs[debuff_name].get("expire_on", "")
		if expire_on == "opponent_turn_end":
			debuffs_to_remove.append(debuff_name)
	for debuff_name in debuffs_to_remove:
		remove_debuff(debuff_name)

# ============================================
# BUFF/DEBUFF SYSTEM
# ============================================

func _generate_buff_instance_id(name: String) -> String:
	_buff_counter += 1
	return instance_id + "_" + name + "_" + str(_buff_counter)

func apply_buff(buff_name: String, duration: int = 1, source_atk: int = 10, expire_on: String = "") -> void:
	## Apply a buff. expire_on can be:
	##   "own_turn_end" - removed when this hero's owner ends their turn
	##   "opponent_turn_end" - removed when the opponent ends their turn
	##   "permanent" or duration < 0 - never expires
	##   "" (empty) - uses legacy duration countdown (deprecated)
	
	# Regen stacks: each application adds heal_amount to existing total
	if buff_name == "regen" or buff_name == "regen_draw":
		var new_heal = int(source_atk * GameConstants.REGEN_HEAL_MULT)
		if active_buffs.has(buff_name):
			active_buffs[buff_name]["heal_amount"] = active_buffs[buff_name].get("heal_amount", 0) + new_heal
			active_buffs[buff_name]["source_atk"] = source_atk
		else:
			active_buffs[buff_name] = {
				"duration": -1,
				"expire_on": "permanent",
				"source_atk": source_atk,
				"heal_amount": new_heal,
				"instance_id": _generate_buff_instance_id(buff_name)
			}
		_update_buff_icons()
		print(hero_data.get("name", "Hero") + " gained " + buff_name + " (heal: " + str(active_buffs[buff_name]["heal_amount"]) + ")")
		return
	
	var resolved_expire = expire_on
	if resolved_expire.is_empty() and duration < 0:
		resolved_expire = "permanent"
	active_buffs[buff_name] = {
		"duration": duration,
		"expire_on": resolved_expire,
		"source_atk": source_atk,
		"instance_id": _generate_buff_instance_id(buff_name)
	}
	_update_buff_icons()
	var expire_str = resolved_expire if not resolved_expire.is_empty() else str(duration) + " turn(s)"
	print(hero_data.get("name", "Hero") + " gained buff: " + buff_name + " (" + expire_str + ")")

func remove_buff(buff_name: String) -> void:
	if active_buffs.has(buff_name):
		active_buffs.erase(buff_name)
		_update_buff_icons()
		print(hero_data.get("name", "Hero") + " lost buff: " + buff_name)

func has_buff(buff_name: String) -> bool:
	return active_buffs.has(buff_name)

func apply_debuff(debuff_name: String, duration: int = 1, source_atk: int = 10, expire_on: String = "") -> void:
	## Apply a debuff. expire_on can be:
	##   "own_turn_end" - removed when this hero's owner ends their turn
	##   "opponent_turn_end" - removed when the opponent ends their turn
	##   "permanent" or duration < 0 - never expires (until triggered)
	##   "" (empty) - uses legacy duration countdown (deprecated)
	# Thunder stacks instead of refreshing
	if debuff_name == "thunder":
		if active_debuffs.has("thunder"):
			active_debuffs["thunder"]["stacks"] += 1
			active_debuffs["thunder"]["source_atk"] = source_atk
			active_debuffs["thunder"]["turns_remaining"] = 2
		else:
			active_debuffs["thunder"] = {
				"duration": -1,
				"expire_on": "permanent",
				"source_atk": source_atk,
				"stacks": 1,
				"turns_remaining": 2,
				"instance_id": _generate_buff_instance_id("thunder")
			}
		_update_buff_icons()
		print(hero_data.get("name", "Hero") + " gained Thunder stack (total: " + str(active_debuffs["thunder"]["stacks"]) + ")")
		return
	
	var resolved_expire = expire_on
	if resolved_expire.is_empty() and duration < 0:
		resolved_expire = "permanent"
	active_debuffs[debuff_name] = {
		"duration": duration,
		"expire_on": resolved_expire,
		"source_atk": source_atk,
		"instance_id": _generate_buff_instance_id(debuff_name)
	}
	_update_buff_icons()
	var expire_str = resolved_expire if not resolved_expire.is_empty() else str(duration) + " turn(s)"
	print(hero_data.get("name", "Hero") + " gained debuff: " + debuff_name + " (" + expire_str + ")")

func remove_debuff(debuff_name: String) -> void:
	if active_debuffs.has(debuff_name):
		active_debuffs.erase(debuff_name)
		_update_buff_icons()
		print(hero_data.get("name", "Hero") + " lost debuff: " + debuff_name)

func remove_random_debuff() -> void:
	if active_debuffs.is_empty():
		return
	var debuff_names = active_debuffs.keys()
	var random_debuff = debuff_names[randi() % debuff_names.size()]
	remove_debuff(random_debuff)

func has_debuff(debuff_name: String) -> bool:
	return active_debuffs.has(debuff_name)

# ============================================
# EQUIPMENT SYSTEM
# ============================================

func has_equipment() -> bool:
	return not equipped_items.is_empty()

func add_equipment(equip_data: Dictionary) -> void:
	# Ensure equipment has an instance_id
	if not equip_data.has("instance_id"):
		equip_data["instance_id"] = "equip_" + equip_data.get("id", "unknown") + "_" + str(randi())
	equipped_items.append(equip_data)
	# Show equipment indicator as a buff icon
	if not active_buffs.has("equipped"):
		active_buffs["equipped"] = {"duration": -1, "source_atk": 0, "instance_id": _generate_buff_instance_id("equipped")}  # Permanent until removed
	_update_buff_icons()
	print(hero_data.get("name", "Hero") + " equipped: " + equip_data.get("name", "Unknown") + " iid=" + equip_data.get("instance_id", "?"))

func remove_equipment(equip_id: String) -> void:
	## Remove equipment by id or instance_id
	for i in range(equipped_items.size()):
		if equipped_items[i].get("instance_id", "") == equip_id or equipped_items[i].get("id", "") == equip_id:
			var removed = equipped_items[i]
			equipped_items.remove_at(i)
			print(hero_data.get("name", "Hero") + " unequipped: " + removed.get("name", "Unknown"))
			break
	# Remove equipped buff if no more equipment
	if equipped_items.is_empty() and active_buffs.has("equipped"):
		active_buffs.erase("equipped")
	_update_buff_icons()

func get_equipped_items() -> Array:
	return equipped_items

func clear_equipment() -> void:
	equipped_items.clear()
	if active_buffs.has("equipped"):
		active_buffs.erase("equipped")
	_update_buff_icons()

func get_thunder_stacks() -> int:
	if active_debuffs.has("thunder"):
		return active_debuffs["thunder"].get("stacks", 0)
	return 0

func add_thunder_stacks(amount: int, source_atk: int = 10) -> void:
	if active_debuffs.has("thunder"):
		active_debuffs["thunder"]["stacks"] += amount
		active_debuffs["thunder"]["source_atk"] = source_atk
		# Reset turns remaining when adding more stacks
		active_debuffs["thunder"]["turns_remaining"] = 2
	else:
		active_debuffs["thunder"] = {
			"duration": -1,
			"source_atk": source_atk,
			"stacks": amount,
			"turns_remaining": 2  # Triggers after 2 turns
		}
	_update_buff_icons()
	print(hero_data.get("name", "Hero") + " gained " + str(amount) + " Thunder stacks (total: " + str(get_thunder_stacks()) + ", triggers in " + str(active_debuffs["thunder"]["turns_remaining"]) + " turns)")

func get_thunder_turns_remaining() -> int:
	if active_debuffs.has("thunder"):
		return active_debuffs["thunder"].get("turns_remaining", 0)
	return 0

func tick_thunder() -> int:
	# Decrements turn counter and triggers if ready. Returns damage dealt (0 if not ready)
	if not active_debuffs.has("thunder"):
		return 0
	
	active_debuffs["thunder"]["turns_remaining"] -= 1
	var turns_left = active_debuffs["thunder"]["turns_remaining"]
	
	if turns_left <= 0:
		# Time to strike!
		var stacks = active_debuffs["thunder"].get("stacks", 0)
		var source_atk = active_debuffs["thunder"].get("source_atk", GameConstants.DEFAULT_BASE_ATTACK)
		var damage = stacks * int(source_atk * GameConstants.THUNDER_DAMAGE_MULT)
		print("[Thunder tick_thunder] " + hero_data.get("name", "Hero") + " - stacks: " + str(stacks) + ", source_atk: " + str(source_atk) + ", damage: " + str(damage))
		remove_debuff("thunder")
		return damage
	else:
		_update_buff_icons()
		print(hero_data.get("name", "Hero") + " Thunder: " + str(turns_left) + " turn(s) until strike")
		return 0

func trigger_thunder() -> int:
	# Force trigger thunder immediately (for backwards compatibility)
	if not active_debuffs.has("thunder"):
		return 0
	var stacks = active_debuffs["thunder"].get("stacks", 0)
	var source_atk = active_debuffs["thunder"].get("source_atk", GameConstants.DEFAULT_BASE_ATTACK)
	var damage = stacks * int(source_atk * GameConstants.THUNDER_DAMAGE_MULT)
	remove_debuff("thunder")
	return damage

func is_stunned() -> bool:
	return has_debuff("stun")

func clear_all_debuffs() -> void:
	active_debuffs.clear()
	_update_buff_icons()
	print(hero_data.get("name", "Hero") + " cleansed all debuffs")

func clear_all_buffs() -> void:
	active_buffs.clear()
	_update_buff_icons()

func clear_all_buffs_and_debuffs() -> void:
	active_buffs.clear()
	active_debuffs.clear()
	_update_buff_icons()

func get_damage_multiplier() -> float:
	var multiplier = 1.0
	if has_buff("empower"):
		multiplier *= GameConstants.EMPOWER_DAMAGE_MULT
	if has_debuff("weak"):
		multiplier *= GameConstants.WEAK_DAMAGE_MULT
	return multiplier

func get_damage_taken_multiplier() -> float:
	# Break debuff increases damage taken
	var multiplier = 1.0
	if has_debuff("break"):
		multiplier *= GameConstants.BREAK_DAMAGE_MULT
	return multiplier

func _update_buff_icons() -> void:
	if not buff_container:
		return
	
	# Clear existing icons
	for child in buff_container.get_children():
		child.queue_free()
	
	# Add buff icons (includes "equipped" buff if hero has equipment)
	for buff_name in active_buffs:
		var icon_path = BUFF_ICONS.get(buff_name, "")
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			# Special handling for equipment icon - show detailed tooltip
			if buff_name == "equipped" and not equipped_items.is_empty():
				var icon = _create_equipment_icon(icon_path, equipped_items)
				buff_container.add_child(icon)
			else:
				var icon = _create_status_icon(icon_path, buff_name, true)
				buff_container.add_child(icon)
	
	# Add debuff icons
	var has_thunder = false
	for debuff_name in active_debuffs:
		var icon_path = DEBUFF_ICONS.get(debuff_name, "")
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			var icon = _create_status_icon(icon_path, debuff_name, false)
			icon.modulate = Color(1.0, 0.5, 0.5)  # Tint debuffs reddish
			# Add stack count label for Thunder
			if debuff_name == "thunder":
				has_thunder = true
				var stacks = get_thunder_stacks()
				if stacks > 1:
					var stack_label = Label.new()
					stack_label.text = str(stacks)
					stack_label.add_theme_font_size_override("font_size", 12)
					stack_label.add_theme_color_override("font_color", Color.WHITE)
					stack_label.add_theme_color_override("font_outline_color", Color.BLACK)
					stack_label.add_theme_constant_override("outline_size", 2)
					stack_label.position = Vector2(12, 8)
					icon.add_child(stack_label)
			buff_container.add_child(icon)
	
	# Show/hide thunder cloud based on Thunder debuff
	if has_thunder:
		_update_thunder_cloud(true)
	else:
		_update_thunder_cloud(false)

func _create_status_icon(icon_path: String, status_name: String, is_buff: bool) -> TextureRect:
	var icon = TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Get description
	var desc_dict = BUFF_DESCRIPTIONS if is_buff else DEBUFF_DESCRIPTIONS
	var status_info = desc_dict.get(status_name, {"name": status_name.capitalize(), "effect": "Unknown effect"})
	var duration = 0
	if is_buff and active_buffs.has(status_name):
		duration = active_buffs[status_name].get("duration", 0)
	elif not is_buff and active_debuffs.has(status_name):
		duration = active_debuffs[status_name].get("duration", 0)
	
	# Create tooltip
	var tip = status_info.get("name", status_name) + "\n" + status_info.get("effect", "")
	var expire_on = ""
	if is_buff and active_buffs.has(status_name):
		expire_on = active_buffs[status_name].get("expire_on", "")
	elif not is_buff and active_debuffs.has(status_name):
		expire_on = active_debuffs[status_name].get("expire_on", "")
	if expire_on == "own_turn_end":
		tip += "\nUntil end of turn"
	elif expire_on == "opponent_turn_end":
		tip += "\nUntil end of opponent's turn"
	elif expire_on == "permanent":
		pass  # No duration text for permanent
	elif duration > 0:
		tip += "\nDuration: " + str(duration) + " turn(s)"
	# Show Regen heal amount in tooltip
	if status_name == "regen" and active_buffs.has("regen"):
		var heal_amount = active_buffs["regen"].get("heal_amount", 0)
		tip += "\nHeals " + str(heal_amount) + " at turn start"
	# Show Thunder stacks in tooltip
	if status_name == "thunder" and active_debuffs.has("thunder"):
		var stacks = active_debuffs["thunder"].get("stacks", 1)
		var source_atk = active_debuffs["thunder"].get("source_atk", 10)
		var damage = stacks * int(source_atk * 2.0)
		tip += "\nStacks: " + str(stacks) + " (" + str(damage) + " damage)"
	icon.tooltip_text = tip
	
	return icon

func _create_equipment_icon(icon_path: String, equipped_items: Array) -> TextureRect:
	var icon = TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Build tooltip with equipment details
	var tip = "[EQUIPMENT]\n"
	for item in equipped_items:
		var item_name = item.get("name", "Unknown")
		var item_effect = item.get("effect", "")
		var item_trigger = item.get("trigger", "")
		var item_value = item.get("value", 0)
		tip += item_name + "\n"
		# Add effect description based on effect type
		match item_effect:
			"lifesteal":
				tip += "Heal " + str(int(item_value * 100)) + "% of damage dealt"
			"energy_gain":
				tip += "Gain +" + str(int(item_value)) + " energy on damage"
			"apply_weak":
				tip += "Apply Weak on damage"
			"reflect":
				tip += "Reflect " + str(int(item_value * 100)) + "% damage"
			"mana_gain":
				tip += "Gain +" + str(int(item_value)) + " mana on kill"
			"empower_all":
				tip += "Empower all allies on kill"
			"auto_revive":
				tip += "Revive with " + str(int(item_value * 100)) + "% HP (once)"
			"empower":
				tip += "Gain Empower below " + str(int(item_value * 100)) + "% HP"
			"cleanse":
				tip += "Remove " + str(int(item_value)) + " debuff at turn start"
			"damage_reduction":
				tip += "Reduce adjacent ally damage by " + str(int(item_value))
	icon.tooltip_text = tip.strip_edges()
	
	return icon

func _update_thunder_cloud(show: bool) -> void:
	if show:
		if thunder_cloud != null:
			return  # Already showing
		
		var cloud_path = "res://asset/Others/Skill Sprite VFX/dark cloud.png"
		if not ResourceLoader.exists(cloud_path):
			return
		
		thunder_cloud = TextureRect.new()
		thunder_cloud.texture = load(cloud_path)
		thunder_cloud.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		thunder_cloud.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thunder_cloud.custom_minimum_size = Vector2(80, 40)
		thunder_cloud.size = Vector2(80, 40)
		thunder_cloud.z_index = 50
		add_child(thunder_cloud)
		
		# Position above the hero sprite
		if sprite:
			thunder_cloud.position = Vector2(sprite.position.x + sprite.size.x / 2 - 40, sprite.position.y - 50)
		else:
			thunder_cloud.position = Vector2(60, -20)
		
		# Fade in
		thunder_cloud.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(thunder_cloud, "modulate:a", 0.9, 0.3)
		
		# Continuous floating animation
		var float_tween = create_tween().set_loops()
		float_tween.tween_property(thunder_cloud, "position:y", thunder_cloud.position.y - 5, 1.0).set_ease(Tween.EASE_IN_OUT)
		float_tween.tween_property(thunder_cloud, "position:y", thunder_cloud.position.y + 5, 1.0).set_ease(Tween.EASE_IN_OUT)
	else:
		if thunder_cloud == null:
			return
		
		var cloud = thunder_cloud
		thunder_cloud = null
		
		var tween = create_tween()
		tween.tween_property(cloud, "modulate:a", 0.0, 0.2)
		tween.tween_callback(cloud.queue_free)

func die() -> void:
	is_dead = true
	# Clear all buffs and debuffs on death
	clear_all_buffs_and_debuffs()
	# VFX Library: death particles on hero sprite
	if VFX:
		var sprite_center = global_position
		if sprite:
			sprite_center = sprite.global_position + sprite.size / 2
		VFX.spawn_particles(sprite_center, Color(0.3, 0.3, 0.3), 15)
	_play_death_animation()
	hero_died.emit(self)
	GameManager.check_game_over()

func _play_death_animation() -> void:
	# Fade to gray and shrink
	var death_tween = create_tween().set_ease(Tween.EASE_IN)
	death_tween.tween_property(sprite, "modulate", Color(0.3, 0.3, 0.3), 0.3)
	death_tween.parallel().tween_property(sprite, "scale", Vector2(0.8, 0.8), 0.3)
	await death_tween.finished
	
	# Show RIP image with slide in effect
	_show_rip_image()

func _show_rip_image() -> void:
	var rip_path = "res://asset/Others/Rip.png"
	if ResourceLoader.exists(rip_path):
		var rip_texture = load(rip_path)
		if rip_texture and sprite:
			# Reset sprite properties for RIP (RIP image should not be flipped)
			sprite.modulate = Color.WHITE
			sprite.scale = Vector2(1, 1)  # Reset scale (RIP image is not flipped)
			sprite.texture = rip_texture
			sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			
			# Slide in from below
			var original_pos = sprite.position
			sprite.position.y += 30
			sprite.modulate.a = 0
			
			var slide_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			slide_tween.tween_property(sprite, "position:y", original_pos.y, 0.3)
			slide_tween.parallel().tween_property(sprite, "modulate:a", 1.0, 0.2)
		else:
			print("ERROR: Failed to load RIP texture")
	else:
		print("ERROR: RIP file not found at: ", rip_path)
	modulate.a = 0.8

func revive(heal_amount: int) -> void:
	if not is_dead:
		return
	is_dead = false
	current_hp = min(max_hp, heal_amount)
	modulate.a = 1.0
	
	# Reset sprite properties that were changed during death
	sprite.scale = Vector2(1, 1)
	sprite.position = Vector2.ZERO  # Reset position (was moved during RIP animation)
	sprite.modulate = Color.WHITE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	var idle = _resolve_flip_sprite("idle_sprite")
	_load_sprite(idle.path, idle.flip_h)
	_update_ui()
	if is_player_hero:
		GameManager.on_hero_revived(hero_id)

func _play_hit_animation() -> void:
	if is_dead:
		return
	
	# Spawn impact sparks
	_spawn_impact_sparks()
	
	var resolved = _resolve_flip_sprite("hit_sprite")
	if not resolved.path.is_empty():
		_load_sprite(resolved.path, resolved.flip_h)
		await get_tree().create_timer(0.5).timeout
		if not is_dead:
			var idle = _resolve_flip_sprite("idle_sprite")
			_load_sprite(idle.path, idle.flip_h)

func _play_attack_animation() -> void:
	if is_dead:
		return
	var resolved = _resolve_flip_sprite("attack_sprite")
	if not resolved.path.is_empty():
		_load_sprite(resolved.path, resolved.flip_h)
		await get_tree().create_timer(0.5).timeout
		if not is_dead:
			var idle = _resolve_flip_sprite("idle_sprite")
			_load_sprite(idle.path, idle.flip_h)

func _play_cast_animation() -> void:
	if is_dead:
		return
	var resolved = _resolve_flip_sprite("cast_sprite")
	if not resolved.path.is_empty():
		_load_sprite(resolved.path, resolved.flip_h)

func _resolve_flip_sprite(base_key: String) -> Dictionary:
	if is_flipped:
		var flip_path = hero_data.get(base_key + "_flip", "")
		if not flip_path.is_empty() and ResourceLoader.exists(flip_path):
			return {"path": flip_path, "flip_h": false}
		# No dedicated flip sprite — use normal sprite + flip_h
		var normal_path = hero_data.get(base_key, "")
		if not normal_path.is_empty() and ResourceLoader.exists(normal_path):
			return {"path": normal_path, "flip_h": true}
		return {"path": "", "flip_h": false}
	return {"path": hero_data.get(base_key, ""), "flip_h": false}

func _on_clicked() -> void:
	hero_clicked.emit(self)

func get_color() -> String:
	return hero_data.get("color", "yellow")

func flip_sprite() -> void:
	is_flipped = true
	
	# Use dedicated flip sprite if available, otherwise flip_h
	var resolved = _resolve_flip_sprite("idle_sprite")
	if not resolved.path.is_empty():
		_load_sprite(resolved.path, resolved.flip_h)
	
	# Reposition sprite to align RIGHT for enemy heroes (after texture is loaded)
	_align_sprite_right()

func play_attack_anim_with_callback(callback: Callable) -> void:
	var original_pos = position
	var original_z = z_index
	var attack_offset = Vector2(-30, 0) if is_flipped else Vector2(30, 0)
	
	# Bring to front during action
	z_index = 50
	
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "position", original_pos + attack_offset, 0.2)
	tween.tween_callback(_play_attack_animation)
	tween.tween_interval(0.35)
	tween.tween_property(self, "position", original_pos, 0.25)
	tween.tween_callback(func():
		z_index = original_z
		callback.call()
	)

func play_cast_anim_with_callback(callback: Callable) -> void:
	var original_z = z_index
	
	# Bring to front during action
	z_index = 50
	
	# Play cast animation (no movement, just sprite change)
	_play_cast_animation()
	
	# Wait for cast animation to complete
	await get_tree().create_timer(0.6).timeout
	
	# Revert to idle sprite
	if not is_dead:
		var idle = _resolve_flip_sprite("idle_sprite")
		_load_sprite(idle.path, idle.flip_h)
	
	z_index = original_z
	callback.call()

func play_hit_anim() -> void:
	if is_dead:
		return
	var original_pos = position
	var hit_offset = Vector2(15, 0) if is_flipped else Vector2(-15, 0)
	
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(self, "position", original_pos + hit_offset, 0.1)
	tween.tween_property(self, "position", original_pos, 0.35)
	_play_hit_animation()

func get_hero_color() -> Color:
	var hero_color_name = hero_data.get("color", "yellow")
	match hero_color_name:
		"yellow":
			return Color(1.0, 0.9, 0.3, 1.0)
		"red":
			return Color(1.0, 0.3, 0.2, 1.0)
		"green":
			return Color(0.3, 1.0, 0.4, 1.0)
		"purple", "violet":
			return Color(0.8, 0.3, 1.0, 1.0)
		"blue":
			return Color(0.3, 0.5, 1.0, 1.0)
		_:
			return Color(1.0, 0.9, 0.3, 1.0)

func play_ex_skill_anim(callback: Callable) -> void:
	var original_z = z_index
	z_index = 50
	
	var original_scale = scale
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", original_scale * 1.15, 0.2)
	tween.tween_interval(0.3)
	tween.tween_property(self, "scale", original_scale, 0.15)
	tween.tween_callback(func():
		z_index = original_z
		callback.call()
	)

# Combat effect animations
func _spawn_floating_number(value: int, color: Color) -> void:
	var label = Label.new()
	label.text = str(value)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	
	add_child(label)
	label.position = Vector2(size.x / 2 - 20, size.y * 0.3)
	
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 50, 0.8)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.tween_callback(label.queue_free)

func _show_heal_effect(amount: int) -> void:
	# Green flash on sprite
	var original_modulate = sprite.modulate if sprite else Color.WHITE
	if sprite:
		var flash_tween = create_tween()
		flash_tween.tween_property(sprite, "modulate", HEAL_COLOR, 0.1)
		flash_tween.tween_property(sprite, "modulate", original_modulate, 0.2)
	
	# Spawn green floating number with + prefix
	var label = Label.new()
	label.text = "+" + str(amount)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", HEAL_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	
	add_child(label)
	label.position = Vector2(size.x / 2 - 20, size.y * 0.3)
	
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 40, 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.tween_callback(label.queue_free)

func _show_shield_absorb_effect(amount: int) -> void:
	# Blue flash on sprite
	var original_modulate = sprite.modulate if sprite else Color.WHITE
	if sprite:
		var flash_tween = create_tween()
		flash_tween.tween_property(sprite, "modulate", SHIELD_ABSORB_COLOR, 0.08)
		flash_tween.tween_property(sprite, "modulate", original_modulate, 0.15)
	
	# Spawn blue floating number showing blocked damage
	var label = Label.new()
	label.text = "-" + str(amount) + " blocked"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", SHIELD_ABSORB_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	
	add_child(label)
	label.position = Vector2(size.x / 2 - 40, size.y * 0.5)
	
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 30, 0.6)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tween.tween_callback(label.queue_free)

# Particle effect functions
func _spawn_impact_sparks() -> void:
	var spark_count = 12
	var center = global_position + Vector2(size.x / 2, size.y * 0.45)
	
	for i in range(spark_count):
		var spark = ColorRect.new()
		spark.size = Vector2(14, 14)
		spark.color = Color(1.0, 0.6, 0.1, 1.0)  # Orange/yellow
		spark.top_level = true
		spark.z_index = 100
		add_child(spark)
		spark.global_position = center
		
		# Random direction
		var angle = randf() * TAU
		var distance = randf_range(50, 100)
		var target_pos = center + Vector2(cos(angle), sin(angle)) * distance
		
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(spark, "global_position", target_pos, 0.4)
		tween.parallel().tween_property(spark, "modulate:a", 0.0, 0.4)
		tween.parallel().tween_property(spark, "size", Vector2(4, 4), 0.4)
		tween.tween_callback(spark.queue_free)

func _spawn_heal_sparkles() -> void:
	var sparkle_count = 8
	var center = global_position + Vector2(size.x / 2, size.y * 0.5)
	
	for i in range(sparkle_count):
		var sparkle = ColorRect.new()
		sparkle.size = Vector2(6, 6)
		sparkle.color = Color(0.3, 1.0, 0.5, 1.0)  # Green
		sparkle.top_level = true
		sparkle.z_index = 100
		add_child(sparkle)
		
		# Start at random position around hero
		var start_x = center.x + randf_range(-30, 30)
		var start_pos = Vector2(start_x, center.y + randf_range(-10, 20))
		sparkle.global_position = start_pos
		
		# Float upward
		var target_y = start_pos.y - randf_range(50, 90)
		var delay = randf_range(0, 0.2)
		
		var tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.tween_interval(delay)
		tween.tween_property(sparkle, "global_position:y", target_y, 0.7)
		tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 0.7).set_delay(0.2)
		tween.tween_callback(sparkle.queue_free)

func _set_aura_color() -> void:
	if not aura or not aura.material:
		return
	
	var hero_color_name = hero_data.get("color", "yellow")
	var glow_color: Color
	
	match hero_color_name:
		"yellow":
			glow_color = Color(1.0, 0.9, 0.3, 1.0)
		"violet", "purple":
			glow_color = Color(0.8, 0.4, 1.0, 1.0)
		"red":
			glow_color = Color(1.0, 0.4, 0.3, 1.0)
		"blue":
			glow_color = Color(0.4, 0.7, 1.0, 1.0)
		"green":
			glow_color = Color(0.4, 1.0, 0.5, 1.0)
		_:
			glow_color = Color(1.0, 0.9, 0.3, 1.0)
	
	aura.material.set_shader_parameter("glow_color", glow_color)

func _spawn_shield_sparkles() -> void:
	var center = global_position + size / 2.0
	
	for i in range(12):
		var particle = ColorRect.new()
		particle.size = Vector2(8, 8)
		particle.color = Color(1.0, 0.95, 0.5, 0.9)  # Yellow/gold sparkle
		particle.top_level = true
		get_tree().root.add_child(particle)
		
		# Start from outside, moving inward toward hero center
		var angle = randf() * TAU
		var start_distance = randf_range(80, 120)
		var start_pos = center + Vector2(cos(angle), sin(angle)) * start_distance
		particle.global_position = start_pos - particle.size / 2.0
		
		var end_pos = center + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		
		var delay = randf_range(0, 0.15)
		var duration = randf_range(0.3, 0.5)
		
		var tween = create_tween().set_ease(Tween.EASE_IN)
		tween.tween_interval(delay)
		tween.tween_property(particle, "global_position", end_pos, duration)
		tween.parallel().tween_property(particle, "modulate:a", 0.0, duration).set_delay(duration * 0.5)
		tween.parallel().tween_property(particle, "size", Vector2(2, 2), duration)
		tween.tween_callback(particle.queue_free)

func _show_shield_effect() -> void:
	if not shield_effect:
		return
	
	shield_effect.visible = true
	shield_effect.modulate.a = 0.0
	
	# Flip shield horizontally for enemy heroes (face left instead of right)
	if is_player_hero:
		shield_effect.scale = Vector2(1.2, 1.2)
	else:
		shield_effect.scale = Vector2(-1.2, 1.2)
		shield_effect.pivot_offset = shield_effect.size / 2.0
	
	# Fade in and scale down
	var target_scale = Vector2(1.0, 1.0) if is_player_hero else Vector2(-1.0, 1.0)
	var tween = create_tween().set_ease(Tween.EASE_OUT)
	tween.tween_property(shield_effect, "modulate:a", 0.7, 0.3)
	tween.parallel().tween_property(shield_effect, "scale", target_scale, 0.3)
	
	# Start pulsing animation
	_start_shield_pulse()

func _start_shield_pulse() -> void:
	if shield_tween:
		shield_tween.kill()
	
	# Set pivot to center for scale animation
	shield_effect.pivot_offset = shield_effect.size / 2.0
	
	# Use negative X scale for enemy heroes to keep shield flipped
	var base_scale = Vector2(1.0, 1.0) if is_player_hero else Vector2(-1.0, 1.0)
	var pulse_scale = Vector2(1.05, 1.05) if is_player_hero else Vector2(-1.05, 1.05)
	
	shield_tween = create_tween().set_loops()
	# Alpha pulse
	shield_tween.tween_property(shield_effect, "modulate:a", 0.4, 0.6).set_ease(Tween.EASE_IN_OUT)
	shield_tween.parallel().tween_property(shield_effect, "scale", pulse_scale, 0.6).set_ease(Tween.EASE_IN_OUT)
	shield_tween.tween_property(shield_effect, "modulate:a", 0.7, 0.6).set_ease(Tween.EASE_IN_OUT)
	shield_tween.parallel().tween_property(shield_effect, "scale", base_scale, 0.6).set_ease(Tween.EASE_IN_OUT)

func _hide_shield_effect() -> void:
	if not shield_effect:
		return
	
	if shield_tween:
		shield_tween.kill()
		shield_tween = null
	
	var tween = create_tween().set_ease(Tween.EASE_IN)
	tween.tween_property(shield_effect, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): shield_effect.visible = false)

# Attack effect functions
func spawn_attack_effect(attacker_hero_id: String, attacker_color: String) -> void:
	var effect_color = _get_hero_effect_color(attacker_color)
	
	var skip_sparks = false
	match attacker_hero_id:
		"squire", "gavran", "dana", "nyra", "kalasag", "makash", "dax", "cinder":
			_spawn_slash_effect(effect_color)
		"markswoman", "stony", "ysolde", "scrap":
			_spawn_shot_effect(effect_color)
		"raizel":
			_spawn_lightning_effect()
			skip_sparks = true
		"caelum", "valen", "priest", "amihan", "nyxara":
			_spawn_magic_circle_effect(effect_color)
		_:
			_spawn_generic_impact(effect_color)
	
	# Spawn impact sparkles with hero color (skip for some effects)
	if not skip_sparks:
		_spawn_colored_impact_sparks(effect_color)

func _get_hero_effect_color(hero_color: String) -> Color:
	match hero_color:
		"yellow":
			return Color(1.0, 0.85, 0.2, 1.0)  # Gold
		"violet", "purple":
			return Color(0.7, 0.3, 1.0, 1.0)  # Purple
		"red":
			return Color(1.0, 0.3, 0.2, 1.0)  # Red
		"green":
			return Color(0.3, 1.0, 0.5, 1.0)  # Green
		"blue":
			return Color(0.3, 0.6, 1.0, 1.0)  # Blue
		_:
			return Color(1.0, 0.6, 0.1, 1.0)  # Default orange

func _spawn_colored_impact_sparks(color: Color) -> void:
	var spark_count = 10
	var center = global_position + Vector2(size.x / 2, size.y * 0.45)
	
	for i in range(spark_count):
		var spark = ColorRect.new()
		spark.size = Vector2(12, 12)
		spark.color = color
		spark.top_level = true
		spark.z_index = 100
		get_tree().root.add_child(spark)
		spark.global_position = center
		
		var angle = randf() * TAU
		var distance = randf_range(40, 90)
		var target_pos = center + Vector2(cos(angle), sin(angle)) * distance
		
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(spark, "global_position", target_pos, 0.35)
		tween.parallel().tween_property(spark, "modulate:a", 0.0, 0.35)
		tween.parallel().tween_property(spark, "size", Vector2(3, 3), 0.35)
		tween.tween_callback(spark.queue_free)

func _spawn_slash_effect(color: Color) -> void:
	var center = global_position + Vector2(size.x / 2, size.y * 0.45)
	var texture = load("res://asset/Others/Skill Sprite VFX/Sword Slash.png")
	if texture:
		_play_spritesheet_effect(texture, 4, center, 0.08, color, Vector2(0.8, 0.8))
	else:
		_spawn_generic_impact(color)

func _spawn_lightning_effect() -> void:
	# Position lightning at the HP bar area (hero's feet)
	var center: Vector2
	if hp_bar:
		center = hp_bar.global_position + Vector2(hp_bar.size.x / 2, 0)
	else:
		center = sprite.global_position + Vector2(sprite.size.x / 2, sprite.size.y)
	var texture = load("res://asset/Others/Skill Sprite VFX/blue lightning.png")
	if texture:
		_play_spritesheet_effect(texture, 5, center, 0.08, Color(1, 1, 1, 1), Vector2(0.8, 0.8), 100)
	else:
		_spawn_generic_impact(Color(0.3, 0.6, 1.0))

func _spawn_thunder_explode_effect() -> void:
	# Position lightning at the HP bar area (hero's feet)
	var center: Vector2
	if hp_bar:
		center = hp_bar.global_position + Vector2(hp_bar.size.x / 2, 0)
	else:
		center = sprite.global_position + Vector2(sprite.size.x / 2, sprite.size.y)
	var texture = load("res://asset/Others/Skill Sprite VFX/lightning explode.png")
	if texture:
		_play_spritesheet_effect(texture, 7, center, 0.08, Color(1, 1, 1, 1), Vector2(1.2, 1.2), 100)
	else:
		_spawn_generic_impact(Color(0.3, 0.6, 1.0))

func _spawn_shot_effect(color: Color) -> void:
	var center = global_position + Vector2(size.x / 2, size.y * 0.45)
	var texture = load("res://asset/Others/Skill Sprite VFX/shot sprite.png")
	if texture:
		_play_spritesheet_effect(texture, 3, center, 0.12, color, Vector2(0.5, 0.5))
	else:
		_spawn_generic_impact(color)

func _spawn_magic_circle_effect(color: Color) -> void:
	var center = global_position + Vector2(size.x / 2, size.y * 0.45)
	var texture = load("res://asset/Others/Skill Sprite VFX/magic attack.png")
	if texture:
		_play_spritesheet_effect(texture, 8, center, 0.08, color, Vector2(0.7, 0.7))
	else:
		_spawn_generic_impact(color)

func _play_spritesheet_effect(texture: Texture2D, frame_count: int, center: Vector2, frame_duration: float = 0.08, color: Color = Color(1, 1, 1, 1), effect_scale: Vector2 = Vector2(0.6, 0.6), z: int = 99) -> void:
	var spr = Sprite2D.new()
	spr.texture = texture
	spr.hframes = frame_count
	spr.vframes = 1
	spr.frame = 0
	spr.top_level = true
	spr.z_index = z
	spr.scale = effect_scale
	spr.modulate = color
	get_tree().root.add_child(spr)
	spr.global_position = center
	
	var tween = create_tween()
	for i in range(frame_count):
		tween.tween_callback(func(): spr.frame = i)
		tween.tween_interval(frame_duration)
	tween.tween_property(spr, "modulate:a", 0.0, 0.15)
	tween.tween_callback(spr.queue_free)

func _spawn_generic_impact(color: Color) -> void:
	var center = global_position + Vector2(size.x / 2, size.y * 0.45)
	
	# Simple burst effect
	var burst = ColorRect.new()
	burst.size = Vector2(60, 60)
	burst.color = color
	burst.top_level = true
	burst.z_index = 99
	burst.pivot_offset = burst.size / 2.0
	get_tree().root.add_child(burst)
	burst.global_position = center - burst.size / 2.0
	
	burst.scale = Vector2(0.2, 0.2)
	burst.modulate.a = 0.8
	
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(burst, "scale", Vector2(1.0, 1.0), 0.15)
	tween.tween_property(burst, "modulate:a", 0.0, 0.2)
	tween.tween_callback(burst.queue_free)

# Targeting circle - removed, just use empty functions
func show_targeting_circle() -> void:
	pass

func hide_targeting_circle() -> void:
	pass
