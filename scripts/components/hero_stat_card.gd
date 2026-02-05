extends VBoxContainer
class_name HeroStatCard

@onready var portrait: TextureRect = $Portrait
@onready var damage_label: Label = $StatsContainer/DamageRow/DamageValue
@onready var shield_label: Label = $StatsContainer/ShieldRow/ShieldValue
@onready var heal_label: Label = $StatsContainer/HealRow/HealValue
@onready var ex_label: Label = $StatsContainer/EXRow/EXValue

func setup(stats: Dictionary) -> void:
	# Load portrait
	var portrait_path = stats.get("portrait", "")
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	
	# Set stat values
	damage_label.text = str(stats.get("damage_dealt", 0))
	shield_label.text = str(stats.get("shield_given", 0))
	heal_label.text = str(stats.get("healing_done", 0))
	ex_label.text = str(stats.get("ex_skills_used", 0))

func animate_stats() -> void:
	# Animate stats counting up from 0
	var final_damage = int(damage_label.text)
	var final_shield = int(shield_label.text)
	var final_heal = int(heal_label.text)
	var final_ex = int(ex_label.text)
	
	damage_label.text = "0"
	shield_label.text = "0"
	heal_label.text = "0"
	ex_label.text = "0"
	
	var duration = 0.8
	var tween = create_tween().set_parallel(true)
	
	tween.tween_method(func(val): damage_label.text = str(int(val)), 0.0, float(final_damage), duration)
	tween.tween_method(func(val): shield_label.text = str(int(val)), 0.0, float(final_shield), duration)
	tween.tween_method(func(val): heal_label.text = str(int(val)), 0.0, float(final_heal), duration)
	tween.tween_method(func(val): ex_label.text = str(int(val)), 0.0, float(final_ex), duration)
