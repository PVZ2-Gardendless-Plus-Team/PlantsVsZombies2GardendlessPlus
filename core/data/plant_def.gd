class_name PlantDef
extends EntityDef
## A plant's typed stats, editable in the inspector or authored as JSON.

@export_group("Stats")
@export var sun_cost: int = 100
@export var toughness: float = 300.0
## Seconds before the seed packet can be used again.
@export var cooldown: float = 5.0
## Share of the cooldown already elapsed when the level starts.
@export_range(0.0, 1.0) var cooldown_from: float = 1.0
@export var beghouled_cost: int = 0

@export_group("Classification")
## PopCap's Family: Peashooter, Sun, Defence, Lobber, Melee, Explosive, ...
@export var family: StringName = &""
## The world PVZGE files the plant under (`frontyard`, `egypt`, `market`, ...).
## It picks the seed packet's backing; empty gets the plain one.
@export var world: StringName = &""

@export_group("Zen Garden")
## Where it grows in the Zen Garden (PVZGE's ZENGARDEN.PlantPlace): &"dirt"
## fits any slot, &"fly" any slot too, &"solid" only bare ground, &"float"
## only water, &"none" never comes out of a sprout.
@export var zen_place: StringName = &"dirt"
## Fixed odds of a sprout growing into it (PVZGE's FixedWeight). -1 leaves the
## odds to how many the player already has.
@export var zen_weight: int = -1
## How far its art is lifted in the garden, in rig units (Tangle Kelp's 40).
@export var zen_height: float = 0.0

@export_group("Seed packet")
## The picture on the packet, when it is not named after the plant.
@export var packet_portrait: StringName = &""


func stat(name: StringName, fallback: Variant = 0.0) -> Variant:
	match name:
		&"sun_cost": return sun_cost
		&"toughness": return toughness
		&"cooldown": return cooldown
		&"cooldown_from": return cooldown_from
		&"beghouled_cost": return beghouled_cost
	return custom_stats.get(name, fallback)


func set_stat(name: StringName, value: Variant) -> bool:
	match name:
		&"sun_cost": sun_cost = int(value)
		&"toughness": toughness = float(value)
		&"cooldown": cooldown = float(value)
		&"cooldown_from": cooldown_from = float(value)
		&"beghouled_cost": beghouled_cost = int(value)
		_: return false
	return true


func stat_names() -> Array[StringName]:
	return [&"sun_cost", &"toughness", &"cooldown", &"cooldown_from",
			&"beghouled_cost"]


func _copy_stats_to(target: EntityDef) -> void:
	if target is PlantDef:
		target.sun_cost = sun_cost
		target.toughness = toughness
		target.cooldown = cooldown
		target.cooldown_from = cooldown_from
		target.beghouled_cost = beghouled_cost
		target.family = family
		target.world = world
		target.zen_place = zen_place
		target.zen_weight = zen_weight
		target.zen_height = zen_height
		target.packet_portrait = packet_portrait
