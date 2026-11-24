extends Objective
## Finish without any lawn mower going off.


func setup() -> void:
	board.mower_triggered.connect(func(_row): fail())


func save_state() -> Dictionary:
	return {"failed": failed}


func load_state(state: Dictionary) -> void:
	failed = bool(state.get("failed", false))
	notify_progress()


func describe() -> String:
	return tr("Don't lose any lawn mowers")
