extends Objective
## Never have more than a set number of plants on the lawn at once. Rather
## than failing the level for one too many, the extra plant is refused.
##
## Config: max - how many plants may stand at once.

var maximum: int = 15


func setup() -> void:
	maximum = int(cfg(&"max", 15))
	board.placement_checks.append(_refuse)
	board.plant_placed.connect(func(_p): notify_progress())
	board.plant_died.connect(func(_p): notify_progress())


func _refuse(kind: StringName, _id: StringName, _row: int, _col: int) -> String:
	return "no more than %d plants at once" % maximum \
			if kind != &"zombie" and board.plant_count() >= maximum else ""


func describe() -> String:
	return tr("Plants: %d / %d at once") % [board.plant_count(), maximum]
