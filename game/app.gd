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
		&"minigames":
			show_minigames()
		_:
			show_main_menu()


func show_main_menu() -> void:
	var menu := MainMenu.new()
	menu.play_requested.connect(show_world_map.bind(&""))
	menu.minigames_requested.connect(show_minigames.bind(&""))
	menu.continue_requested.connect(play_level)
	menu.quit_requested.connect(get_tree().quit)
	_swap(menu)


func show_world_map(campaign_id: StringName = &"") -> void:
	var map := WorldMap.new()
	map.start_campaign = campaign_id
	map.level_chosen.connect(play_level)
	map.back_requested.connect(show_main_menu)
	map.almanac_requested.connect(func() -> void:
		var world := map.current_world()
		show_almanac(world.id if world != null else campaign_id))
	_swap(map)


<<<<<<< HEAD
## The minigames screen, opened on `mode` (or the first mode).
func show_minigames(mode: StringName = &"") -> void:
	var menu := MinigameMenu.new()
	menu.start_mode = mode
	menu.level_chosen.connect(_play_minigame.bind(menu))
	menu.back_requested.connect(show_main_menu)
	_swap(menu)


## A minigame level, which leads back to the minigames screen on the same
## mode rather than to the map.
func _play_minigame(level_id: StringName, menu: MinigameMenu) -> void:
	var mode := StringName(menu.current_mode().get("id", ""))
	play_level(level_id, func(): show_minigames(mode))


## Plays a level. `back` is where leaving it for the map goes; by default
## the level's world on the map.
func play_level(level_id: StringName, back: Callable = Callable()) -> void:
=======
## PVZGE's almanac is reached from the world map and returns to it.
func show_almanac(campaign_id: StringName = &"") -> void:
	var almanac := AlmanacScreen.new()
	almanac.back_requested.connect(show_world_map.bind(campaign_id))
	_swap(almanac)


func play_level(level_id: StringName) -> void:
>>>>>>> origin/master
	var campaign := Data.campaign_for_level(level_id)
	var level := LEVEL_SCENE.instantiate()
	level.campaign_id = campaign.id if campaign != null else &""
	level.start_level = level_id
	# Clearing a level goes back to the map to pick the next, as in PvZ2.
	level.return_to_map = true
	if not back.is_valid():
		back = show_world_map.bind(campaign.id if campaign != null else &"")
	level.exit_requested.connect(_on_level_exit.bind(back))
	_swap(level)


func _on_level_exit(destination: StringName, back: Callable) -> void:
	if destination == &"menu":
		show_main_menu()
	else:
		back.call()


## Deferred, because the old screen is usually the one asking to be replaced,
## from inside its own signal.
func _swap(next: Node) -> void:
	if screen != null:
		screen.queue_free()
	screen = next
	add_child.call_deferred(next)
