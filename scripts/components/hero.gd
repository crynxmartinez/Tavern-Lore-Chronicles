extends Control
class_name Hero

signal hero_clicked(hero: Hero)
signal hero_died(hero: Hero)
signal energy_full(hero: Hero)

@export var hero_id: String = ""
@export var is_player_hero: bool = true
var owner_id: String = ""  # player_id of the player who owns this hero

var hero_data: Dictionary = {}
var max_hp: int = GameConstants.DEFAULT_MAX_HP
var current_hp: int = GameConstants.DEFAULT_MAX_HP
var base_attack: int = GameConstants.DEFAULT_BASE_ATTACK
var current_attack: int = GameConstants.DEFAULT_BASE_ATTACK
var energy: int = 0
var max_energy: int = GameConstants.MAX_ENERGY
var block: int = 0

var is_dead: bool = false
var is_flipped: bool = false

# Buff/Debuff system
var active_buffs: Dictionary = {}  # {buff_name: {duration: int, source_atk: int}}
var active_debuffs: Dictionary = {}  # {debuff_name: {duration: int, source_atk: int}}

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
	"equipped": "res://asset/buff debuff/Bolster.webp"  # Equipment indicator
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
	"marked": "res://asset/buff debuff/Target.webp"
}

const BUFF_DESCRIPTIONS = {
	"shield": {"name": "Shield", "effect": "Absorbs damage before HP."},
	"empower": {"name": "Empower", "effect": "+50% damage dealt."},
	"taunt": {"name": "Taunt", "effect": "Enemies must target this hero."},
	"regen": {"name": "Regeneration", "effect": "Heals 50% ATK at turn start."},
	"block": {"name": "Block", "effect": "Reduces incoming damage."},
	"bolster": {"name": "Bolster", "effect": "Increased defense."},
	"star": {"name": "Blessed", "effect": "Enhanced abilities."},
	"equipped": {"name": "Equipped", "effect": "This hero has equipment attached."}
}

const DEBUFF_DESCRIPTIONS = {
	"stun": {"name": "Stun", "effect": "Cannot act next turn."},
	"weak": {"name": "Weak", "effect": "-50% damage dealt."},
	"burn": {"name": "Burn", "effect": "Takes damage at turn end."},
	"poison": {"name": "Poison", "effect": "Takes damage at turn start."},
	"bleed": {"name": "Bleed", "effect": "Takes damage when acting."},
	"frost": {"name": "Frost", "effect": "Slowed actions."},
	"chain": {"name": "Chain", "effect": "Cannot use skills."},
	"entangle": {"name": "Entangle", "effect": "Cannot move or dodge."},
	"break": {"name": "Break", "effect": "+50% damage taken."},
	"bomb": {"name": "Bomb", "effect": "Explodes after duration."},
	"thunder": {"name": "Thunder", "effect": "Lightning strikes at turn end. Stacks."},
	"marked": {"name": "Marked", "effect": "Takes increased damage."}
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
	
	max_hp = hero_data.get("max_hp", 100)
	current_hp = max_hp
	base_attack = hero_data.get("base_attack", 10)
	current_attack = base_attack
	energy = 0
	
	_load_sprite(hero_data.get("idle_sprite", ""))
	_update_ui()

func _load_sprite(path: String) -> void:
	if path.is_empty():
		return
	var texture = load(path)
	if texture and sprite:
		sprite.texture = texture
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

func take_damage(amount: int) -> void:
	if is_dead:
		return
	
	# Apply Break debuff multiplier (increases damage taken)
	var modified_amount = int(amount * get_damage_taken_multiplier())
	
	var actual_damage = modified_amount
	var shield_absorbed = 0
	var had_shield = block > 0
	if block > 0:
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
	
	if current_hp <= 0:
		die()

func heal(amount: int) -> void:
	if is_dead:
		return
	var actual_heal = min(amount, max_hp - current_hp)
	current_hp = min(max_hp, current_hp + amount)
	
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
	var had_no_shield = block == 0
	block += amount
	_update_ui()
	
	# Spawn shield sparkles effect
	_spawn_shield_sparkles()
	
	# Show shield effect overlay if we now have shield
	if had_no_shield and block > 0:
		_show_shield_effect()

func on_turn_start() -> void:
	current_attack = base_attack
	# Apply regeneration healing at turn start
	if has_buff("regen"):
		var regen_data = active_buffs["regen"]
		var heal_amount = int(regen_data.get("source_atk", GameConstants.DEFAULT_BASE_ATTACK) * GameConstants.REGEN_HEAL_MULT)
		heal(heal_amount)

func on_turn_end() -> void:
	# Tick down buff durations
	var buffs_to_remove = []
	for buff_name in active_buffs:
		active_buffs[buff_name].duration -= 1
		if active_buffs[buff_name].duration <= 0:
			buffs_to_remove.append(buff_name)
	for buff_name in buffs_to_remove:
		remove_buff(buff_name)
	
	# Tick down debuff durations (skip Thunder - it uses turns_remaining instead)
	var debuffs_to_remove = []
	for debuff_name in active_debuffs:
		if debuff_name == "thunder":
			continue  # Thunder is handled separately via tick_thunder()
		active_debuffs[debuff_name].duration -= 1
		if active_debuffs[debuff_name].duration <= 0:
			debuffs_to_remove.append(debuff_name)
	for debuff_name in debuffs_to_remove:
		remove_debuff(debuff_name)

# ============================================
# BUFF/DEBUFF SYSTEM
# ============================================

func apply_buff(buff_name: String, duration: int = 1, source_atk: int = 10) -> void:
	active_buffs[buff_name] = {
		"duration": duration,
		"source_atk": source_atk
	}
	_update_buff_icons()
	print(hero_data.get("name", "Hero") + " gained buff: " + buff_name + " for " + str(duration) + " turn(s)")

func remove_buff(buff_name: String) -> void:
	if active_buffs.has(buff_name):
		active_buffs.erase(buff_name)
		_update_buff_icons()
		print(hero_data.get("name", "Hero") + " lost buff: " + buff_name)

func has_buff(buff_name: String) -> bool:
	return active_buffs.has(buff_name)

func apply_debuff(debuff_name: String, duration: int = 1, source_atk: int = 10) -> void:
	# Thunder stacks instead of refreshing
	if debuff_name == "thunder":
		if active_debuffs.has("thunder"):
			active_debuffs["thunder"]["stacks"] += 1
			active_debuffs["thunder"]["source_atk"] = source_atk  # Update source ATK
			active_debuffs["thunder"]["turns_remaining"] = 2  # Reset timer
		else:
			active_debuffs["thunder"] = {
				"duration": -1,  # Thunder doesn't expire by duration, only by triggering
				"source_atk": source_atk,
				"stacks": 1,
				"turns_remaining": 2  # Triggers after 2 turns
			}
		_update_buff_icons()
		print(hero_data.get("name", "Hero") + " gained Thunder stack (total: " + str(active_debuffs["thunder"]["stacks"]) + ")")
		return
	
	active_debuffs[debuff_name] = {
		"duration": duration,
		"source_atk": source_atk
	}
	_update_buff_icons()
	print(hero_data.get("name", "Hero") + " gained debuff: " + debuff_name + " for " + str(duration) + " turn(s)")

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
	equipped_items.append(equip_data)
	# Show equipment indicator as a buff icon
	if not active_buffs.has("equipped"):
		active_buffs["equipped"] = {"duration": -1, "source_atk": 0}  # Permanent until removed
	_update_buff_icons()
	print(hero_data.get("name", "Hero") + " equipped: " + equip_data.get("name", "Unknown"))

func remove_equipment(equip_id: String) -> void:
	for i in range(equipped_items.size()):
		if equipped_items[i].get("id", "") == equip_id:
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
	if duration > 0:
		tip += "\nDuration: " + str(duration) + " turn(s)"
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
		
		var cloud_path = "res://asset/Others/dark cloud.png"
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
	if is_player_hero:
		GameManager.on_hero_died(hero_id, get_color())
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
	
	_load_sprite(_get_idle_sprite_path())
	_update_ui()
	if is_player_hero:
		GameManager.on_hero_revived(hero_id)

func _play_hit_animation() -> void:
	if is_dead:
		return
	
	# Spawn impact sparks
	_spawn_impact_sparks()
	
	var hit_sprite_path = hero_data.get("hit_sprite_flip" if is_flipped else "hit_sprite", "")
	if hit_sprite_path.is_empty() or not ResourceLoader.exists(hit_sprite_path):
		hit_sprite_path = hero_data.get("hit_sprite", "")
	if not hit_sprite_path.is_empty():
		_load_sprite(hit_sprite_path)
		await get_tree().create_timer(0.5).timeout
		if not is_dead:
			_load_sprite(_get_idle_sprite_path())

func _play_attack_animation() -> void:
	if is_dead:
		return
	var atk_sprite_path = hero_data.get("attack_sprite_flip" if is_flipped else "attack_sprite", "")
	if atk_sprite_path.is_empty() or not ResourceLoader.exists(atk_sprite_path):
		atk_sprite_path = hero_data.get("attack_sprite", "")
	if not atk_sprite_path.is_empty():
		_load_sprite(atk_sprite_path)
		await get_tree().create_timer(0.5).timeout
		if not is_dead:
			_load_sprite(_get_idle_sprite_path())

func _play_cast_animation() -> void:
	if is_dead:
		return
	var cast_sprite_path = hero_data.get("cast_sprite_flip" if is_flipped else "cast_sprite", "")
	if cast_sprite_path.is_empty() or not ResourceLoader.exists(cast_sprite_path):
		cast_sprite_path = hero_data.get("cast_sprite", "")
	if not cast_sprite_path.is_empty() and ResourceLoader.exists(cast_sprite_path):
		_load_sprite(cast_sprite_path)

func _get_idle_sprite_path() -> String:
	if is_flipped:
		var flip_path = hero_data.get("idle_sprite_flip", "")
		if not flip_path.is_empty() and ResourceLoader.exists(flip_path):
			return flip_path
	return hero_data.get("idle_sprite", "")

func _on_clicked() -> void:
	hero_clicked.emit(self)

func get_color() -> String:
	return hero_data.get("color", "yellow")

func flip_sprite() -> void:
	is_flipped = true
	
	# Load the flipped idle sprite instead of using flip_h
	var flip_path = hero_data.get("idle_sprite_flip", "")
	if not flip_path.is_empty() and ResourceLoader.exists(flip_path):
		_load_sprite(flip_path)
	else:
		# Fallback to flip_h if no flipped sprite exists
		sprite.flip_h = true
	
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
		_load_sprite(_get_idle_sprite_path())
	
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
		"squire", "craftswoman", "makash":
			_spawn_slash_effect(effect_color)
		"markswoman":
			_spawn_arrow_impact_effect(effect_color)
		"priest":
			_spawn_magic_circle_effect(effect_color)
		"raizel":
			_spawn_lightning_effect()
			skip_sparks = true  # Lightning effect is complete on its own
		"caelum":
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
	
	# Load Classic Slash Sprite frames
	var slash_frames: Array[Texture2D] = []
	for i in range(1, 7):
		var frame_path = "res://asset/Others/Classic Slash Sprite/Classic_0%d.png" % i
		var frame = load(frame_path)
		if frame:
			slash_frames.append(frame)
	
	if slash_frames.size() > 0:
		var slash_sprite = Sprite2D.new()
		slash_sprite.texture = slash_frames[0]
		slash_sprite.top_level = true
		slash_sprite.z_index = 99
		slash_sprite.scale = Vector2(0.8, 0.8)
		# Tint to hero color
		slash_sprite.modulate = color
		get_tree().root.add_child(slash_sprite)
		slash_sprite.global_position = center
		
		# Animate through frames
		var frame_duration = 0.08
		var tween = create_tween()
		for i in range(slash_frames.size()):
			tween.tween_callback(func(): slash_sprite.texture = slash_frames[i])
			tween.tween_interval(frame_duration)
		tween.tween_property(slash_sprite, "modulate:a", 0.0, 0.15)
		tween.tween_callback(slash_sprite.queue_free)
	else:
		# Fallback to X-shaped ColorRect slash
		for i in range(2):
			var slash = ColorRect.new()
			slash.size = Vector2(100, 8)
			slash.color = color
			slash.top_level = true
			slash.z_index = 99
			slash.pivot_offset = slash.size / 2.0
			get_tree().root.add_child(slash)
			
			slash.global_position = center - slash.size / 2.0
			if i == 0:
				slash.rotation_degrees = -45
			else:
				slash.rotation_degrees = 45
			
			slash.scale = Vector2(0.1, 1.0)
			slash.modulate.a = 1.0
			
			var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
			tween.tween_property(slash, "scale:x", 1.5, 0.1)
			tween.tween_property(slash, "modulate:a", 0.0, 0.2)
			tween.tween_callback(slash.queue_free)

func _spawn_lightning_effect() -> void:
	# Position at hero's feet area (just above status icons)
	var center = global_position + Vector2(size.x / 2, size.y * 0.7)
	
	# Load lightning sprite sheet (same format as magic attack: 4 columns x 2 rows = 8 frames)
	var lightning_texture = load("res://asset/Others/lightning sprite sheet.png")
	
	if lightning_texture:
		var lightning_sprite = Sprite2D.new()
		lightning_sprite.texture = lightning_texture
		lightning_sprite.hframes = 4  # 4 columns
		lightning_sprite.vframes = 2  # 2 rows
		lightning_sprite.frame = 0
		lightning_sprite.top_level = true
		lightning_sprite.z_index = 100
		lightning_sprite.scale = Vector2(0.6, 0.6)
		get_tree().root.add_child(lightning_sprite)
		lightning_sprite.global_position = center
		
		# Animate through all 8 frames
		var tween = create_tween()
		tween.tween_property(lightning_sprite, "frame", 0, 0.0)
		tween.tween_interval(0.08)
		tween.tween_property(lightning_sprite, "frame", 1, 0.0)
		tween.tween_interval(0.08)
		tween.tween_property(lightning_sprite, "frame", 2, 0.0)
		tween.tween_interval(0.08)
		tween.tween_property(lightning_sprite, "frame", 3, 0.0)
		tween.tween_interval(0.08)
		tween.tween_property(lightning_sprite, "frame", 4, 0.0)
		tween.tween_interval(0.08)
		tween.tween_property(lightning_sprite, "frame", 5, 0.0)
		tween.tween_interval(0.08)
		tween.tween_property(lightning_sprite, "frame", 6, 0.0)
		tween.tween_interval(0.08)
		tween.tween_property(lightning_sprite, "frame", 7, 0.0)
		tween.tween_interval(0.1)
		tween.tween_property(lightning_sprite, "modulate:a", 0.0, 0.15)
		tween.tween_callback(lightning_sprite.queue_free)
	else:
		# Fallback to simple lightning lines
		var lightning_color = Color(0.6, 0.8, 1.0, 1.0)
		for i in range(3):
			var bolt = Line2D.new()
			bolt.top_level = true
			bolt.z_index = 100
			bolt.width = 3.0
			bolt.default_color = lightning_color
			get_tree().root.add_child(bolt)
			
			var start = Vector2(center.x + randf_range(-30, 30), center.y - 150)
			var points: PackedVector2Array = [start]
			var current = start
			for j in range(5):
				current = Vector2(
					current.x + randf_range(-20, 20),
					current.y + 40
				)
				points.append(current)
			bolt.points = points
			
			var tween = create_tween()
			tween.tween_property(bolt, "modulate:a", 0.0, 0.3)
			tween.tween_callback(bolt.queue_free)

func _spawn_arrow_impact_effect(color: Color) -> void:
	var center = global_position + Vector2(size.x / 2, size.y * 0.45)
	
	# Load arrow shot sprite sheet
	var shot_texture = load("res://asset/Others/shot sprite sheet - Arrow.png")
	
	if shot_texture:
		var shot_sprite = Sprite2D.new()
		shot_sprite.texture = shot_texture
		shot_sprite.hframes = 3  # 3 columns (direct hit frames)
		shot_sprite.vframes = 1  # 1 row
		shot_sprite.frame = 0
		shot_sprite.top_level = true
		shot_sprite.z_index = 99
		shot_sprite.scale = Vector2(0.5, 0.5)
		# Tint to hero color
		shot_sprite.modulate = color
		get_tree().root.add_child(shot_sprite)
		shot_sprite.global_position = center
		
		# Animate: direct hit explosion - 3 frames
		var tween = create_tween()
		tween.tween_property(shot_sprite, "frame", 0, 0.0)
		tween.tween_interval(0.12)
		tween.tween_property(shot_sprite, "frame", 1, 0.0)
		tween.tween_interval(0.12)
		tween.tween_property(shot_sprite, "frame", 2, 0.0)
		tween.tween_interval(0.15)
		tween.tween_property(shot_sprite, "modulate:a", 0.0, 0.18)
		tween.tween_callback(shot_sprite.queue_free)
	else:
		# Fallback to ColorRect arrows
		for i in range(3):
			var arrow = ColorRect.new()
			arrow.size = Vector2(30, 4)
			arrow.color = color
			arrow.top_level = true
			arrow.z_index = 99
			arrow.pivot_offset = Vector2(arrow.size.x, arrow.size.y / 2.0)
			get_tree().root.add_child(arrow)
			
			var offset_y = (i - 1) * 25
			var start_pos = center + Vector2(-80, offset_y)
			arrow.global_position = start_pos
			arrow.rotation_degrees = 0
			arrow.modulate.a = 0.9
			
			var end_pos = center + Vector2(0, offset_y)
			
			var delay = i * 0.05
			var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tween.tween_interval(delay)
			tween.tween_property(arrow, "global_position", end_pos, 0.1)
			tween.tween_property(arrow, "modulate:a", 0.0, 0.15)
			tween.tween_callback(arrow.queue_free)

func _spawn_magic_circle_effect(color: Color) -> void:
	var center = global_position + Vector2(size.x / 2, size.y * 0.45)
	
	# Load magic attack sprite sheet
	var magic_texture = load("res://asset/Others/magic attack sprite sheet.png")
	
	if magic_texture:
		var magic_sprite = Sprite2D.new()
		magic_sprite.texture = magic_texture
		magic_sprite.hframes = 4  # 4 columns
		magic_sprite.vframes = 2  # 2 rows
		magic_sprite.frame = 0
		magic_sprite.top_level = true
		magic_sprite.z_index = 99
		magic_sprite.scale = Vector2(0.6, 0.6)
		# Tint to hero color
		magic_sprite.modulate = color
		get_tree().root.add_child(magic_sprite)
		magic_sprite.global_position = center
		
		# Animate through first row frames (magic circle forming)
		var tween = create_tween()
		tween.tween_property(magic_sprite, "frame", 0, 0.0)
		tween.tween_interval(0.12)
		tween.tween_property(magic_sprite, "frame", 1, 0.0)
		tween.tween_interval(0.12)
		tween.tween_property(magic_sprite, "frame", 2, 0.0)
		tween.tween_interval(0.12)
		tween.tween_property(magic_sprite, "frame", 3, 0.0)
		tween.tween_interval(0.15)
		tween.tween_property(magic_sprite, "modulate:a", 0.0, 0.2)
		tween.tween_callback(magic_sprite.queue_free)
	else:
		# Fallback to ColorRect ring
		var circle = Control.new()
		circle.size = Vector2(100, 100)
		circle.top_level = true
		circle.z_index = 99
		circle.pivot_offset = circle.size / 2.0
		get_tree().root.add_child(circle)
		circle.global_position = center - circle.size / 2.0
		
		for i in range(16):
			var segment = ColorRect.new()
			segment.size = Vector2(14, 5)
			segment.color = color
			segment.pivot_offset = Vector2(segment.size.x / 2, segment.size.y / 2)
			circle.add_child(segment)
			
			var angle = (float(i) / 16.0) * TAU
			var radius = 40.0
			segment.position = Vector2(50 + cos(angle) * radius - segment.size.x / 2, 
									   50 + sin(angle) * radius - segment.size.y / 2)
			segment.rotation = angle + PI / 2
		
		circle.scale = Vector2(0.2, 0.2)
		circle.modulate.a = 1.0
		
		var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(circle, "scale", Vector2(1.4, 1.4), 0.25)
		tween.parallel().tween_property(circle, "rotation_degrees", 60.0, 0.25)
		tween.tween_property(circle, "modulate:a", 0.0, 0.2)
		tween.tween_callback(circle.queue_free)

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
