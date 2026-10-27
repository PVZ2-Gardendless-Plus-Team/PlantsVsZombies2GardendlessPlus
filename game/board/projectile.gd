class_name Projectile
extends Node2D
## A pea or similar shot travelling along one lane.
##
## `direction` decides both which way it goes and what it can hit, since
## nothing shoots past its own side: a plant's pea travels right into zombies,
## a boss's missile travels left into plants.
##
## Collision is swept rather than sampled: at 380 px/s a projectile moves
## further in one frame than a zombie is wide, so testing only the current
## position lets shots tunnel straight through targets on a slow frame.

## Pixels per second travelled down the lane.
@export var speed: float = 380.0
## Damage dealt to the first valid target hit.
@export var damage: float = 20.0
## Half-width of the hit window, in pixels, around the target's centre.
@export var hit_radius: float = 22.0
@export var draw_radius: float = 8.0
@export var color: Color = Color("7ad17a")

## +1 travels right (a plant's shot), -1 travels left (a zombie's).
@export var direction: int = 1

var row: int = 0
## The projectile's id, which picks its hit sound.
var kind: StringName = &""
var source: Node = null
var board: Node = null
## Artwork, when some is mapped for this projectile; null keeps the drawn dot.
var art: Armature = null

## Targets it passes through before it is spent. A pea stops at the first;
## a bloomerang's boomerang goes through three.
var pierce: int = 1
## Which side fired it, and so what it may hit. Not read off `direction`: a
## split pea fires backwards and a boomerang comes home, and neither turns on
## its own side.
var from_zombie: bool = false
## A boomerang turns round at the far end, or once it has pierced its fill,
## and flies back over the lane hitting everything again.
var returns: bool = false
## A bowling bulb glances off what it hits into a neighbouring lane.
var bounces: bool = false
## Chance per hit of pushing the target back, and how far (squares).
var knockback_chance: float = 0.0
var knockback_distance: float = 0.0

var _hit: Array = []
var _returning: bool = false
var _home_x: float = 0.0

## Tags a target must have for this shot to affect it. Mods use these to make
## a projectile selective without touching zombie data.
@export var required_tags: Array[StringName] = []
@export var excluded_tags: Array[StringName] = []


## Gives this shot its artwork. Called by the board once the id is known,
## since a projectile has no definition of its own to read it from.
func attach_art(id: StringName) -> void:
	var built := Art.make(&"projectile", id)
	if built == null:
		return
	art = built
	art.set_facing(direction)
	add_child(art)
	art.play(Art.animation_for(&"projectile", id, &"idle"))
	_hit_effect = StringName(Art.mapping(&"projectile", id).get("hit_effect", ""))
	queue_redraw()


## The splat a shot leaves where it lands, as its art mapping names it.
var _hit_effect: StringName = &""
const HIT_STATES: Array[StringName] = [&"hit", &"hit1", &"hit2"]


## PVZGE pops one of the splat's variants at random (Play, Play1, Play2), so
## a stream of peas does not burst identically every time.
func _splat() -> void:
	if _hit_effect == &"" or get_parent() == null:
		return
	var states: Array[StringName] = []
	for state in HIT_STATES:
		if Art.animation_for(&"effect", _hit_effect, state) != &"":
			states.append(state)
	if states.is_empty():
		return
	var fx := Effect.spawn(get_parent(), _hit_effect, states.pick_random(),
			position, z_index + 1)
	if fx != null:
		fx.art.set_facing(direction)


func _ready() -> void:
	_home_x = position.x


func _process(delta: float) -> void:
	var from_x := position.x
	position.x += direction * speed * delta
	if _check_hit(from_x, position.x):
		return
	if board == null:
		return
	if _returning and (position.x - _home_x) * direction >= 0.0:
		queue_free()
		return
	if position.x > board.despawn_x() or position.x < board.house_x() - board.cell_size.x:
		if returns and not _returning:
			_turn_back()
		else:
			queue_free()


func _turn_back() -> void:
	_returning = true
	_hit.clear()
	direction = -direction
	if art != null:
		art.set_facing(direction)


## Hits the nearest valid target whose centre lies in the swept span.
## Returns true if the projectile was consumed.
func _check_hit(from_x: float, to_x: float) -> bool:
	if board == null:
		return false
	var lo := minf(from_x, to_x) - hit_radius
	var hi := maxf(from_x, to_x) + hit_radius

	var best: Node = null
	var best_x := INF * direction
	for t in _candidates():
		if t.is_dead or t.position.x < lo or t.position.x > hi or _hit.has(t):
			continue
		if not t.matches(required_tags, excluded_tags):
			continue
		# Whichever is nearest along the way it is going gets hit first.
		if (t.position.x - best_x) * direction < 0.0:
			best_x = t.position.x
			best = t
	if best == null:
		return false
	# The shooter may have been eaten or dug up while this was in flight.
	best.take_damage(damage, source if is_instance_valid(source) else null)
	if knockback_chance > 0.0 and best is Zombie and randf() < knockback_chance \
			and best.has_tag(&"knockbackable"):
		best.knock_back(knockback_distance)
	_hit.append(best)
	_splat()
	Audio.play_variant(&"projectile.hit", kind, position)
	if bounces:
		_bounce()
	if _hit.size() < pierce:
		return false
	if returns and not _returning:
		_turn_back()
		return false
	queue_free()
	return true


## Glances into a neighbouring lane, picked at random where there is a
## choice, keeping on down the lawn.
func _bounce() -> void:
	var options: Array[int] = []
	for r in [row - 1, row + 1]:
		if r >= 0 and r < board.rows:
			options.append(r)
	if options.is_empty():
		return
	var to: int = options[randi() % options.size()]
	position.y += (to - row) * board.cell_size.y
	row = to
	z_index = board.lane_z(row, board.LAYER_PROJECTILE)


## What this shot can hit: its own side is never a target. A plant's shot
## also breaks gravestones and ice blocks in its way.
func _candidates() -> Array:
	if from_zombie:
		return board.plants_in_row(row)
	return board.plant_targets_in_row(row)


func _draw() -> void:
	if art != null:
		return
	draw_circle(Vector2.ZERO, draw_radius, color)
	draw_circle(Vector2(-2, -2), draw_radius * 0.38, color.lightened(0.4))
