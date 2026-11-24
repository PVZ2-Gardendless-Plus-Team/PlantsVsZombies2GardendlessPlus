extends Objective
## Destroy a number of zombies within a few seconds of each other, at least
## once before the level ends.
##
## Config: count - how many; seconds - the window they must all fall within.

var count: int = 10
var seconds: float = 10.0

## Game time of each recent kill, oldest first.
var _kills: Array[float] = []
var _clock: float = 0.0
var _done: bool = false


func setup() -> void:
	count = int(cfg(&"count", 10))
	seconds = float(cfg(&"seconds", 10.0))


func _process(delta: float) -> void:
	_clock += delta
	if not _done and not failed and level_over():
		fail()


func on_zombie_died(_zombie: Node) -> void:
	if _done:
		return
	_kills.append(_clock)
	while not _kills.is_empty() and _clock - _kills[0] > seconds:
		_kills.pop_front()
	if _kills.size() >= count:
		_done = true
	notify_progress()


func save_state() -> Dictionary:
	return {"done": _done, "failed": failed}


func load_state(state: Dictionary) -> void:
	_done = bool(state.get("done", false))
	failed = bool(state.get("failed", false))
	notify_progress()


func is_met() -> bool:
	return _done


func describe() -> String:
	if _done:
		return tr("Destroyed %d zombies in %ss") % [count, str(seconds)]
	return tr("Destroy %d zombies within %ss: %d") % [count, str(seconds), _kills.size()]
