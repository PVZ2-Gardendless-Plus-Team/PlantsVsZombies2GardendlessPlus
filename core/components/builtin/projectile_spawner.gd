extends EntityComponent
## A seed packet that is a projectile, not a plant: placing it rolls the
## ball down the lane and the packet's plant is gone at once. This is how
## Wall-nut Bowling deals its nuts and bulbs (PVZGE's ProjectileSpawnerPlant).
##
## The ball glances off zombies into the next lane over and keeps rolling,
## as bowling nuts do. One whose projectile carries SplashDamage (the
## explode-o-nut) blows up on the first zombie instead.
##
## Config: projectile, speed_x (PVZGE units per frame at 60 fps), pierce.

var _fired: bool = false


func _process(_delta: float) -> void:
	if _fired or host.board == null:
		return
	_fired = true
	var id := StringName(cfg(&"projectile", &"bowling_wallnut"))
	var ball: Projectile = host.board.spawn_projectile(id, host.row, host.position, host)
	if ball != null:
		ball.speed = host.board.pvzge_px(float(cfg(&"speed_x", 5.0)) * 60.0)
		var def := Data.projectile(id)
		if def != null and not (def.extra.get("SplashDamage", []) as Array).is_empty():
			ball.explodes = true
		else:
			ball.bounces = true
			ball.pierce = int(cfg(&"pierce", 999))
	Audio.play_for(&"plant.shoot", host)
	host.board.remove_plant(host.row, host.col, host)
	host.queue_free()
