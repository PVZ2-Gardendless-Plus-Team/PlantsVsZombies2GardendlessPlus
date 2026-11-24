extends Minigame
## The Wild West corral: each wave walks into the lawn and then stands still,
## waiting, until the player puts down a plant from the conveyor. Only once
## every zombie of a wave is gone does the next one come.
##
## Config (CowboyMinigameProperties): begin_string, unused here.

## True while a wave stands waiting for the player's move.
var waiting: bool = false
var _waves_seen: int = 0


func setup() -> void:
	runner.wave_started.connect(_on_wave_started)
	board.plant_placed.connect(_on_plant_placed)


func _on_wave_started(_index: int, _total: int) -> void:
	_waves_seen += 1
	waiting = true
	notify_progress()


func _on_plant_placed(_plant: Plant) -> void:
	if not waiting or not started:
		return
	waiting = false
	for z in board.all_hostile_zombies():
		z.held = false
	notify_progress()


func tick(_delta: float) -> void:
	if not waiting:
		return
	# Zombies of the waiting wave come in after the signal, a few at a time.
	# Each steps two squares into view and stands there, as in PVZGE.
	for z in board.all_hostile_zombies():
		if not z.held and not z.has_meta(&"corralled"):
			z.set_meta(&"corralled", true)
			z.position.x -= board.cell_size.x * 2.0
		z.held = true


## The next wave waits for this one to be cleared, and for the player.
func holds_waves() -> bool:
	return waiting or (_waves_seen > 0 and board.zombie_count() > 0)


func intro_text() -> String:
	return tr("Survive the zombie attack")


func describe() -> String:
	return tr("Plant to start the wave") if waiting else ""


func save_state() -> Dictionary:
	return {"waiting": waiting, "waves": _waves_seen}


func load_state(state: Dictionary) -> void:
	waiting = bool(state.get("waiting", false))
	_waves_seen = int(state.get("waves", 0))
	notify_progress()
