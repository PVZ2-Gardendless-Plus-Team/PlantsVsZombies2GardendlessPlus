extends Objective
## Don't let the zombies trample the flowers: a line of flowers stands
## `distance` columns from the house, and a zombie crossing it loses the level.
##
## Config: distance - in columns from the house edge; fractions are allowed.

var distance: float = 4.0


func setup() -> void:
	distance = float(cfg(&"distance", 4.0))


## Where the flowers stand, in board coordinates.
func line_x() -> float:
	return board.origin.x + distance * board.cell_size.x


func _process(_delta: float) -> void:
	if failed or board == null:
		return
	var x := line_x()
	for row in board.rows:
		for z in board.hostile_zombies_in_row(row):
			if z.position.x < x:
				fail()
				return


func save_state() -> Dictionary:
	return {"failed": failed}


func load_state(state: Dictionary) -> void:
	failed = bool(state.get("failed", false))
	notify_progress()


func describe() -> String:
	return tr("Don't let zombies past column %s") % str(snappedf(distance, 0.1))
