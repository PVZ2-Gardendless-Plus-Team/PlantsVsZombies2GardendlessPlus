extends Minigame
## Pirate Seas' "Cannon Away": coconut cannons stand in the second column and
## the player fires them by tapping. Every zombie a shot kills scores points,
## and a shot that takes out many at once scores them multiplied. The level
## is won only if the score reaches the target by the end.
##
## Config (CannonMinigameProperties): min_score, base_zombie_kill_score,
## combo_brackets [{zombies_killed, score_multiplier}], row_has_cannon [0/1
## per row]. PVZGE also walks the zombies down zig-zag splines (lanes);
## here they keep to their rows.

const CANNON := &"coconutcannon"
## Kills this close together from one cannon count as one shot.
const SHOT_WINDOW := 0.4

var score: int = 0
## cannon -> [kills, seconds left in the window]
var _shots: Dictionary = {}


func setup() -> void:
	var rows: Array = cfg(&"row_has_cannon", [1, 1, 1, 1, 1])
	for row in mini(rows.size(), board.rows):
		if int(rows[row]) != 0 and board.plant_at(row, 1) == null:
			board.place_preset_plant(CANNON, row, 1)
	board.zombie_died.connect(_on_zombie_died)


func _on_zombie_died(z: Zombie) -> void:
	var by: Node = z.last_damage_source
	if by is Projectile:
		by = by.source
	if not (by is Plant) or by.def == null or by.def.id != CANNON:
		return
	var shot: Array = _shots.get(by, [0, 0.0])
	shot[0] += 1
	shot[1] = SHOT_WINDOW
	_shots[by] = shot


func tick(delta: float) -> void:
	for cannon in _shots.keys():
		var shot: Array = _shots[cannon]
		shot[1] -= delta
		if shot[1] <= 0.0:
			_shots.erase(cannon)
			add_score(shot_score(int(shot[0])))


## Points for one shot that killed `kills` zombies, with the best combo
## bracket it reached.
func shot_score(kills: int) -> int:
	var points := float(cfg(&"base_zombie_kill_score", 100)) * kills
	var multiplier := 1.0
	for bracket in (cfg(&"combo_brackets", []) as Array):
		if bracket is Dictionary and kills >= int(bracket.get("zombies_killed", 0)):
			multiplier = float(bracket.get("score_multiplier", 1))
	return int(points * multiplier)


func add_score(points: int) -> void:
	score += points
	notify_progress()


func min_score() -> int:
	return int(cfg(&"min_score", 0))


## Nothing else goes on the lawn: the cannons are the whole arsenal.
func skips_seed_chooser() -> bool:
	return true


func allows_shovel() -> bool:
	return false


func allows_plant_food() -> bool:
	return false


func is_met() -> bool:
	return score >= min_score()


## Out of zombies short of the target.
func is_failed() -> bool:
	return started and runner._finished_spawning and board.zombie_count() == 0 \
			and _shots.is_empty() and score < min_score()


func start_word() -> String:
	return tr("FIRE!")


func intro_text() -> String:
	return tr("Reach the target score")


func describe() -> String:
	var text := tr("Score: ") + str(score)
	if score < min_score():
		text += "  " + tr("Target: ") + str(min_score())
	return text


func save_state() -> Dictionary:
	return {"score": score}


func load_state(state: Dictionary) -> void:
	score = int(state.get("score", 0))
	notify_progress()
