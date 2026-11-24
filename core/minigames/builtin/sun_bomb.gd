extends Minigame
## Sun Bomb challenge: the sky drops sun bombs instead of sun. Sweeping over
## one sets it off - a big blast for the zombies around it, a smaller one for
## the plants - so the player has to time their pickups with zombies close.
##
## Config (SunBombChallengeProperties): plant_bomb_explosion_radius,
## plant_damage, zombie_bomb_explosion_radius, zombie_damage. Radii are in
## PVZGE pixels.


func drop_from_sky() -> bool:
	var row: int = randi() % board.rows
	var col: int = randi() % board.cols
	board.drop_sun_bomb(board.grid_to_world(row, col), bomb_props())
	return true


## The bomb's settings, with the radii in this board's pixels.
func bomb_props() -> Dictionary:
	return {
		"zombie_damage": float(cfg(&"zombie_damage", 500)),
		"zombie_radius": board.pvzge_px(float(cfg(&"zombie_bomb_explosion_radius", 80))),
		"plant_damage": float(cfg(&"plant_damage", 1000)),
		"plant_radius": board.pvzge_px(float(cfg(&"plant_bomb_explosion_radius", 25))),
	}


func intro_text() -> String:
	return tr("Survive while Sun Bombs fall")
