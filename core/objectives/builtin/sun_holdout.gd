extends Objective
## Go a stretch of time without spending any sun, at least once before the
## level ends. Every purchase starts the count again.
##
## Config: seconds - how long to hold out.

var seconds: float = 60.0

var _left: float = 60.0
var _done: bool = false


func setup() -> void:
	seconds = float(cfg(&"seconds", 60.0))
	_left = seconds
	board.sun_spent.connect(func(_amount):
		if not _done:
			_left = seconds
			notify_progress())


func _process(delta: float) -> void:
	if _done or failed:
		return
	_left -= delta
	if _left <= 0.0:
		_done = true
		notify_progress()
	elif level_over():
		fail()


func save_state() -> Dictionary:
	return {"left": _left, "done": _done, "failed": failed}


func load_state(state: Dictionary) -> void:
	_left = float(state.get("left", _left))
	_done = bool(state.get("done", false))
	failed = bool(state.get("failed", false))
	notify_progress()


func is_met() -> bool:
	return _done


func describe() -> String:
	return tr("Held out without spending sun") if _done \
			else tr("Spend no sun for %ds: %ds left") % [int(seconds), ceili(_left)]
