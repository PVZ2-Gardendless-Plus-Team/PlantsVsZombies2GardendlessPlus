class_name App
extends Node
## The game's outer shell: main menu, world map, and the level in between.
##
## Exactly one screen is alive at a time; switching frees the old one, so a
## level never keeps running behind the map. Screens only raise signals - the
## App decides where each one leads.

const LEVEL_SCENE := preload("res://game/main.tscn")

## Screen to open with. Set before changing to this scene to land somewhere
## other than the title, as a level launched on its own does to get back.
static var start_screen: StringName = &"menu"
static var start_campaign: StringName = &""

var screen: Node = null


func _ready() -> void:
	var first := start_screen
	start_screen = &"menu"
	match first:
		&"map":
			show_world_map(start_campaign)
		&"zen":
			show_zen_garden()
		_:
			show_main_menu()


func show_main_menu() -> void:
	var menu := MainMenu.new()
	menu.play_requested.connect(show_world_map.bind(&""))
	menu.continue_requested.connect(play_level)
	menu.quit_requested.connect(get_tree().quit)
	_swap(menu)


func show_world_map(campaign_id: StringName = &"") -> void:
	var map := WorldMap.new()
	map.start_campaign = campaign_id
	map.level_chosen.connect(play_level)
	map.back_requested.connect(show_main_menu)
	map.zen_garden_requested.connect(show_zen_garden)
	_swap(map)


func show_zen_garden() -> void:
	var garden := ZenGardenScreen.new()
	garden.back_requested.connect(show_world_map.bind(&""))
	_swap(garden)


func play_level(level_id: StringName) -> void:
	var campaign := Data.campaign_for_level(level_id)
	var level := LEVEL_SCENE.instantiate()
	level.campaign_id = campaign.id if campaign != null else &""
	level.start_level = level_id
	# Clearing a level goes back to the map to pick the next, as in PvZ2.
	level.return_to_map = true
	level.exit_requested.connect(_on_level_exit.bind(
			campaign.id if campaign != null else &""))
	_swap(level)


func _on_level_exit(destination: StringName, campaign_id: StringName) -> void:
	if destination == &"menu":
		show_main_menu()
	else:
		show_world_map(campaign_id)


## Deferred, because the old screen is usually the one asking to be replaced,
## from inside its own signal.
func _swap(next: Node) -> void:
	if screen != null:
		screen.queue_free()
	screen = next
	add_child.call_deferred(next)
