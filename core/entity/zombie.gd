class_name Zombie
extends Character
## A zombie walks along its lane, stopping to attack whatever blocks it.
##
## Allegiance decides both direction and prey. A hostile zombie walks left and
## eats plants; a charmed one (hypnotised, zomboid) walks right and attacks
## hostile zombies. Keeping this on the zombie rather than in a separate class
## means charming is a runtime state change, not a respawn.

signal reached_house(who: Zombie)
signal allegiance_changed(who: Zombie, allegiance: Allegiance)

enum Allegiance {
	HOSTILE,  ## the default: eats plants, walks toward the house
	CHARMED,  ## hypnotised: attacks hostile zombies, walks away from the house
}

@export_group("Allegiance")
@export var allegiance: Allegiance = Allegiance.HOSTILE

@export_group("Appearance")
@export var body_size := Vector2(44, 68)
@export var body_color: Color = Color("9aa6b2")
@export var metal_color: Color = Color("b9c2cc")
@export var charmed_color: Color = Color("b98ac6")
@export var head_color: Color = Color("d8cfa8")
@export var health_bar_color: Color = Color("d46a6a")
@export var frozen_color: Color = Color("8fc7e8")
@export var slowed_color: Color = Color("7f9bb5")
@export var armor_color: Color = Color("c98a3e")
@export var armor_metal_color: Color = Color("aeb6bf")

## Stats are filled from the entity definition on spawn; these are fallbacks
## used when a definition omits them.
@export_group("Fallback stats")
@export var speed: float = 0.5        ## squares per second
@export var eat_dps: float = 100.0

var target: Character = null
## Set when a component claims the attack, so this zombie stops to fight but
## does not bite - see EntityComponent.claims_attack.
var attack_claimed: bool = false
## Set when a component moves this zombie instead of the lane walk.
var movement_claimed: bool = false
## When positive, freezing chills for exactly this long instead of holding the
## zombie still. A boss sets it per stage.
var chill_override: float = 0.0

var _eat_accumulator: float = 0.0
## Counts down to the next chew sound while eating. PVZGE spaces its chews
## out the same way, so a row of zombies on one plant is not a drum roll.
var _chew_timer: float = 0.0
const CHEW_INTERVAL := 0.6
## Status effects, as remaining seconds. A slow also stores its factor so the
## original speed can be restored exactly rather than approximately.
var _stun_left: float = 0.0
var _slow_left: float = 0.0
var _slow_factor: float = 1.0
var _base_speed: float = 0.0
## From the definition: how long stuns last here (0 is immunity) and how
## differently this zombie moves over water.
var _stun_scale: float = 1.0
var _water_speed_scale: float = 1.0
## reached_house fires once; the board decides what happens next.
var _announced_house: bool = false
## The state the art is currently showing, so it is not restarted every frame.
var _art_state: StringName = &""
## Limbs already lost, by the name the art mapping gives them.
var _lost: Dictionary = {}
## How far off its lane's centre line this zombie stands, set at spawn.
var lane_offset: float = 0.0
## Damage over time, as damage per second and seconds left. Kept apart from
## the slow so a poisoned zombie still walks at full pace.
var _poison_dps: float = 0.0
var _poison_left: float = 0.0
var _poison_accumulator: float = 0.0
## A peaceful zombie walks but never stops to fight: a solar-sage convert
## wandering off the lawn, or a zombie being dragged somewhere.
var peaceful: bool = false


func art_kind() -> StringName:
	return &"zombie"


## Zombie art is authored facing the house, which is where a hostile zombie is
## already walking - so it is a charmed one, heading the other way, that needs
## mirroring. Flipping both ways over made them walk backwards.
## Keeps this zombie in its lane's drawing band. A boss changes rows, and a
## zombie that kept row 0's band while standing in row 4 would be drawn behind
## the plants it is walking past.
func _sync_layer() -> void:
	if board != null:
		var want: int = board.lane_z(row, board.LAYER_ZOMBIE)
		if z_index != want:
			z_index = want


func _face_art() -> void:
	if art != null:
		art.set_facing(-1 if is_charmed() else 1)


func _on_initialized() -> void:
	speed = float(def.stat(&"speed", speed))
	eat_dps = float(def.stat(&"eat_dps", eat_dps))
	_base_speed = speed
	_stun_scale = float(def.stat(&"stun_scale", 1.0))
	damaged.connect(func(_w, _a, _r): _drop_limbs(false))
	_water_speed_scale = float(def.stat(&"water_speed_scale", 1.0))
	for c in components():
		if c.claims_attack():
			attack_claimed = true
		if c.claims_movement():
			movement_claimed = true
	_face_art()
	_show_state(&"walk")
	if art != null:
		art.seek_fraction(randf())
	_attach_armor_art()
	queue_redraw()


# --- armor art -----------------------------------------------------------

## armor component -> the rig worn for it, while it is worn.
var _armor_art: Dictionary = {}


## Puts each armor's own rig on the zombie's head. PVZGE hangs a cone or a
## bucket off the rig's `armorSOCKET` bone, so the socket marker is the
## parent: the armor then bobs, leans and turns with the head for free.
func _attach_armor_art() -> void:
	if art == null:
		return
	var socket := art.socket(&"armor")
	if socket == null:
		return
	for comp in components():
		if not comp.has_method("is_intact"):
			continue
		var rig := Art.make(&"armor", StringName(comp.cfg(&"armor", &"")))
		if rig == null:
			continue
		socket.add_child(rig)
		_armor_art[comp] = rig
	_sync_armor_art()


## Shows each armor's wear - the rig has three states, fresh, dented and
## nearly gone - and knocks it off once it breaks or is pulled away.
func _sync_armor_art() -> void:
	for comp in _armor_art.keys():
		var rig: Armature = _armor_art[comp]
		if not is_instance_valid(rig):
			_armor_art.erase(comp)
			continue
		if not comp.is_intact():
			_armor_art.erase(comp)
			_drop_armor(rig)
			continue
		var wear: float = comp.fraction()
		var state: StringName = &"intact" if wear > 2.0 / 3.0 \
				else (&"worn" if wear > 1.0 / 3.0 else &"broken")
		var name := Art.animation_for(&"armor", StringName(comp.cfg(&"armor", &"")), state)
		if name != &"" and rig.playing != name:
			rig.play(name)


func _drop_armor(rig: Armature) -> void:
	if board == null:
		rig.queue_free()
		return
	var piece := Node2D.new()
	piece.transform = rig.get_global_transform()
	rig.get_parent().remove_child(rig)
	rig.transform = Transform2D.IDENTITY
	piece.add_child(rig)
	_drop_piece(piece)


func has_armor_art() -> bool:
	return not _armor_art.is_empty()


# --- allegiance ----------------------------------------------------------

func is_charmed() -> bool:
	return allegiance == Allegiance.CHARMED


## Hypnotises this zombie so it fights for the player.
func charm() -> void:
	set_allegiance(Allegiance.CHARMED)


func set_allegiance(value: Allegiance) -> void:
	if allegiance == value:
		return
	allegiance = value
	target = null            # whatever it was chasing is no longer its enemy
	_face_art()
	set_runtime_tag(&"charmed", value == Allegiance.CHARMED)
	allegiance_changed.emit(self, value)
	queue_redraw()


## Lanes per second right now, after terrain. Water is the only terrain that
## changes a zombie's pace; a ducky-tube zombie swims faster than it walks,
## and a zombie without tubes would be getting its feet wet either way.
func current_speed() -> float:
	if _water_speed_scale != 1.0 and board != null:
		var terrain: StringName = board.terrain_at(row, col)
		if terrain == &"water" or terrain == &"deep_water":
			return speed * _water_speed_scale
	return speed


## PVZGE zombies walk on at triple pace (`walkSpeedScaleEnteringLawn`, 2,
## times 1.5) until their body reaches the lawn, so spawning well off-screen
## does not mean a long wait for the first one.
const ENTERING_SPEED := 3.0
var _entered_lawn: bool = false


func _entering_scale() -> float:
	if _entered_lawn or is_charmed() or board == null:
		return 1.0
	if position.x - board.cell_size.x * 0.5 <= board.lawn_right_x():
		_entered_lawn = true
		return 1.0
	return ENTERING_SPEED


## Permanently scales how fast this zombie moves and how hard it bites.
## Separate from apply_buff, which expires: an enraged zombie stays enraged.
func scale_aggression(speed_scale: float, damage_scale: float) -> void:
	_base_speed *= speed_scale
	speed = _base_speed * (_slow_factor if _slow_left > 0.0 else 1.0)
	eat_dps *= damage_scale
	queue_redraw()


## -1 walking toward the house, +1 walking away from it.
func direction() -> int:
	return 1 if is_charmed() else -1


# --- status effects ------------------------------------------------------

## Halts the zombie entirely for `seconds`. Freezing is a stun that also
## chills, so both routes end up here.
func apply_stun(seconds: float) -> void:
	var held := seconds * _stun_scale
	if held <= 0.0:
		# Not a silent no-op: the plant that tried still wants to know, and a
		# chili-proof mech reading "immune" is useful in a log.
		set_runtime_tag(&"stun_immune", true)
		return
	_stun_left = maxf(_stun_left, held)
	set_runtime_tag(&"stunned", true)
	queue_redraw()


## Scales speed by `factor` (0.5 = half speed) for `seconds`. Re-applying takes
## whichever is stronger and whichever lasts longer, so effects do not stack
## into a standstill.
func apply_slow(factor: float, seconds: float) -> void:
	_slow_factor = minf(_slow_factor if _slow_left > 0.0 else 1.0,
			clampf(factor, 0.05, 1.0))
	_slow_left = maxf(_slow_left, seconds)
	speed = _base_speed * _slow_factor
	set_runtime_tag(&"slowed", true)
	queue_redraw()


## Chilled and held in place at once, the usual effect of an ice plant.
##
## A `chill_only` zombie is slowed but never held: ice does not set a troglobite
## or a Hot Date in a block, it just cools them. The chill lasts the full freeze
## duration there rather than the usual double, since nothing thaws.
func apply_freeze(seconds: float) -> void:
	if chill_override > 0.0:
		apply_slow(0.5, chill_override)
		return
	if has_tag(&"chill_only"):
		apply_slow(0.5, seconds * 2.0)
		return
	apply_stun(seconds)
	apply_slow(0.5, seconds * 2.0)
	if is_stunned():
		set_runtime_tag(&"frozen", true)


func is_stunned() -> bool:
	return _stun_left > 0.0


## Pushes this zombie back the way it came by `cells`, never past the spawn
## line. Whatever it was chewing on is let go.
func knock_back(cells: float) -> void:
	if board == null or cells == 0.0:
		return
	position.x -= direction() * cells * board.cell_size.x
	position.x = clampf(position.x, board.house_x(), board.spawn_x())
	col = board.world_to_col(position.x)
	target = null
	queue_redraw()


## Poisons this zombie: `dps` damage every second for `seconds`. Re-applying
## keeps the stronger dose and the longer time, the same rule as a slow.
func apply_poison(dps: float, seconds: float) -> void:
	if dps <= 0.0 or seconds <= 0.0:
		return
	_poison_dps = maxf(_poison_dps if _poison_left > 0.0 else 0.0, dps)
	_poison_left = maxf(_poison_left, seconds)
	set_runtime_tag(&"poisoned", true)


func is_poisoned() -> bool:
	return _poison_left > 0.0


## Drops the pieces a zombie has lost. PopCap draws the stump as its own slot
## - the basic zombie's `arm_here_ARM` sits hidden under the intact arm - so
## losing a limb is: stop drawing the whole one, start drawing the stump, and
## hand what came off to the board to fall.
##
## When it happens is the game's call, which is why the thresholds live in the
## art mapping rather than in the rig.
func _drop_limbs(on_death: bool) -> void:
	if art == null or def == null:
		return
	for entry in (Art.mapping(&"zombie", def.id).get("limbs", []) as Array):
		var limb: Dictionary = entry
		var name := StringName(limb.get("name", ""))
		if name == &"" or _lost.has(name):
			continue
		if bool(limb.get("on_death", false)):
			if not on_death:
				continue
		elif health_fraction() > float(limb.get("at_health", 0.0)):
			continue
		_lost[name] = true
		for slot in (limb.get("show", []) as Array):
			art.hide_slot(StringName(slot), false)
		var piece := art.detach_slots(limb.get("detach", []))
		if piece.get_child_count() == 0 or board == null:
			piece.free()
			continue
		_drop_piece(piece)
		Audio.play(StringName(limb.get("sound", "zombie.limb")), position)


## Hands something that came off to the board to fall onto this lane's floor,
## which is where the rig's feet are.
func _drop_piece(piece: Node2D) -> void:
	var floor_y := position.y + (art.position.y if art != null else 0.0)
	var rig_scale := art.scale.y if art != null else 1.0
	var dropped := DetachedLimb.drop(piece, board, -direction(), floor_y,
			board.original_unit(), rig_scale)
	dropped.z_index = board.lane_z(row, board.LAYER_ZOMBIE)


func _tick_status(delta: float) -> void:
	if _poison_left > 0.0:
		_poison_left -= delta
		_poison_accumulator += _poison_dps * delta
		var whole := floorf(_poison_accumulator)
		if whole >= 1.0:
			_poison_accumulator -= whole
			take_damage(whole)
		if _poison_left <= 0.0:
			_poison_dps = 0.0
			set_runtime_tag(&"poisoned", false)
		if is_dead:
			return
	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0:
			set_runtime_tag(&"stunned", false)
			set_runtime_tag(&"frozen", false)
			queue_redraw()
	if _slow_left > 0.0:
		_slow_left -= delta
		if _slow_left <= 0.0:
			_slow_factor = 1.0
			speed = _base_speed
			set_runtime_tag(&"slowed", false)
			queue_redraw()


func _process(delta: float) -> void:
	super(delta)
	if is_dead or board == null:
		return
	_tick_status(delta)
	if is_dead:
		return
	if not _armor_art.is_empty():
		_sync_armor_art()
	# A stunned or encased zombie neither walks nor eats.
	if is_stunned() or is_encased():
		return
	if is_instance_valid(target) and not target.is_dead:
		_show_state(&"attack")
		_attack(delta)
	elif not movement_claimed:
		_show_state(&"walk")
		target = null
		_walk(delta)
	else:
		target = null


func _walk(delta: float) -> void:
	position.x += direction() * current_speed() * _entering_scale() \
			* board.cell_size.x * delta
	col = board.world_to_col(position.x)
	_sync_layer()

	var ahead := _find_target()
	if ahead != null:
		target = ahead
		_eat_accumulator = 0.0
		_chew_timer = 0.0

	if is_charmed():
		# A charmed zombie that walks off the lawn has done its job.
		if position.x > board.despawn_x():
			queue_free()
	elif position.x < board.house_x():
		# Stop on the threshold rather than removing itself: a lawn mower may
		# still be waiting there, and it needs something to catch.
		position.x = board.house_x()
		if not _announced_house:
			_announced_house = true
			reached_house.emit(self)
	queue_redraw()


## What this zombie should attack next, if anything is in reach.
func _find_target() -> Character:
	if peaceful:
		return null
	if is_charmed():
		# Charmed zombies fight the nearest hostile zombie in the lane.
		for z in board.hostile_zombies_in_row(row):
			if absf(z.position.x - position.x) <= board.cell_size.x * 0.5:
				return z
		return null

	var plant: Plant = board.plant_at(row, col)
	# A smashing zombie flattens plants it could never have eaten.
	if plant != null and not plant.is_dead and (attack_claimed or _can_eat(plant)):
		return plant
	# Graves and objects do not block a zombie, so nothing else is checked.
	return null


## A zombie only eats plants it is allowed to; a mod can block this by
## granting the plant a tag this zombie excludes.
func _can_eat(plant: Plant) -> bool:
	# The ice around a frozen plant is not food.
	return not plant.has_tag(&"uneatable") and not plant.is_encased()


func _attack(delta: float) -> void:
	if attack_claimed:
		return
	_chew_timer -= delta
	if _chew_timer <= 0.0:
		_chew_timer = CHEW_INTERVAL
		Audio.play(&"zombie.eat", position)
	_eat_accumulator += eat_dps * delta
	var whole := floorf(_eat_accumulator)
	if whole >= 1.0:
		_eat_accumulator -= whole
		target.take_damage(whole, self)


## A cone sitting on the head, so an armored zombie reads at a glance. It
## shrinks as the armor is chewed through and disappears when it breaks.
func _draw_armor(head: Vector2) -> void:
	var armor := component(&"armor")
	if armor == null or not armor.is_intact() or _armor_art.has(armor):
		return
	var wear: float = 0.35 + 0.65 * armor.fraction()
	var half := 12.0
	var tip := head + Vector2(0, -12.0 - 12.0 * wear)
	var points := PackedVector2Array([
		Vector2(head.x - half, head.y - 6.0),
		Vector2(head.x + half, head.y - 6.0),
		tip,
	])
	var tint: Color = armor_metal_color if armor.is_metal else armor_color
	draw_colored_polygon(points, tint)
	draw_polyline(points + PackedVector2Array([points[0]]), tint.darkened(0.45), 2.0)


## Keeps the art in step with what the zombie is doing. Animations are named
## per entity in its art mapping, so this says "attack", not "Eat".
func _show_state(state: StringName) -> void:
	if art == null or _art_state == state:
		return
	if play_art(state):
		_art_state = state


## A walk plays at whatever pace keeps the planted foot planted: the rig says
## how far one cycle carries it, and the zombie's real speed says how far it
## actually goes. Anything else skates - a slowed zombie used to moonwalk at
## full animation speed. Everything but walking keeps the zombie's own rate,
## slowed with it, and a stunned or frozen zombie holds still.
func art_speed() -> float:
	if is_stunned():
		return 0.0
	var slowed := _slow_factor if _slow_left > 0.0 else 1.0
	if art == null or board == null or _art_state != &"walk" or movement_claimed:
		return art_rate * slowed
	var stride := art.ground_speed(art.playing)
	if stride <= 0.0:
		return art_rate * slowed
	return current_speed() * _entering_scale() * board.cell_size.x / stride


func _on_death() -> void:
	Audio.play(&"zombie.die", position)
	_drop_limbs(true)
	if art != null:
		# The death plays out on its own now, at the rig's own pace.
		art.set_speed_scale(1.0)
	# The death animation outlives the zombie, so it is handed to the board
	# to finish on its own rather than freed with the body.
	if art != null and play_art(&"die", false):
		var corpse := art
		art = null
		remove_child(corpse)
		if board != null:
			corpse.position = position + corpse.position
			board.add_child(corpse)
			corpse.animation_finished.connect(
					func(_name: StringName) -> void: corpse.queue_free())
	super()


func _draw() -> void:
	var size := body_size
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y * 0.75), size)
	var body := body_color
	if is_charmed():
		body = charmed_color
	elif has_tag(&"frozen"):
		body = frozen_color
	elif has_tag(&"slowed"):
		body = slowed_color
	elif has_tag(&"metal"):
		body = metal_color
	if art == null:
		draw_rect(rect, body, true)
		draw_rect(rect, body.darkened(0.45), false, 2.0)
	# Head offset shows which way it is facing. The placeholder armor only
	# draws for armor without a rig of its own.
	var head := Vector2(6 * direction(), -size.y * 0.75 - 10)
	if art == null:
		draw_circle(head, 11.0, head_color)
	_draw_armor(head)

	if health < max_health:
		var bar := Rect2(Vector2(-size.x * 0.5, -size.y * 0.75 - 34), Vector2(size.x, 4))
		draw_rect(bar, Color(0, 0, 0, 0.5), true)
		bar.size.x *= health_fraction()
		draw_rect(bar, health_bar_color, true)
