extends Minigame
## Wall-nut Bowling: nuts and bulbs come down a conveyor and are rolled from
## behind a red foul line. Nothing can be planted past the line, and there is
## no shovel or plant food - every packet is a ball.
##
## Config: bowling_foul_line - the last column a ball may be set down in,
## 0-based (PVZGE's BowlingFoulLine).

const LINE_COLOR := Color(0.85, 0.12, 0.1, 0.85)

var foul_line: int = 2
var _line: Node2D


func setup() -> void:
	foul_line = int(cfg(&"bowling_foul_line", 2))
	_line = Node2D.new()
	_line.name = "FoulLine"
	_line.z_index = -5
	_line.draw.connect(_draw_line)
	board.add_child(_line)


func _exit_tree() -> void:
	if is_instance_valid(_line):
		_line.queue_free()


func _draw_line() -> void:
	var top: Vector2 = board.grid_to_world(0, foul_line + 1) - board.cell_size * 0.5
	var bottom := top + Vector2(0, board.cell_size.y * board.rows)
	_line.draw_line(top, bottom, LINE_COLOR, 6.0)


func placement_refusal(kind: StringName, _id: StringName, _row: int, col: int) -> String:
	if kind == &"plant" and col > foul_line:
		return "balls are rolled from behind the line"
	return ""


func allows_shovel() -> bool:
	return false


func allows_plant_food() -> bool:
	return false


func drops_sky_sun() -> bool:
	return false


func start_word() -> String:
	return tr("ROLL!")


func intro_text() -> String:
	return tr("Deliver bowling balls to grind the zombies")
