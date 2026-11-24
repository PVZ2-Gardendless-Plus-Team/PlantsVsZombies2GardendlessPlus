extends Objective
## A mold colony: cells where nothing can be planted for the whole level.
##
## The cells are painted as `mold` terrain, so they look and refuse planting
## the same way any unplantable ground does. A cell that already has terrain
## (water, say) is left as it is.
##
## Config: cells - [{row, col}], 0-based.


func setup() -> void:
	for c in (cfg(&"cells", []) as Array):
		if not (c is Dictionary):
			continue
		var row := int(c.get("row", 0))
		var col := int(c.get("col", 0))
		if board.in_bounds(row, col) and board.terrain_at(row, col) == &"":
			board.set_terrain(row, col, &"mold")


func describe() -> String:
	return tr("Mold: some ground can't be planted")
