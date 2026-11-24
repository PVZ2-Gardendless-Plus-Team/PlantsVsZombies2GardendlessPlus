extends EntityComponent
## Eats the gravestone it was planted on, and is spent - grave buster. It can
## only be planted onto a stone (its `on_grave:gravebuster_plantable` tag).
##
## This follows PVZGE's GraveBusterPlant step for step. It chomps as it lands
## and digs in (Spawn). On the rig's `bust` event the stone sinks out of
## sight - nothing can aim at it any more - and it chews (Busting), played at
## whatever speed makes the chewing last `bust_time`. On `finish` the stone
## breaks, paying out whatever it holds, and from then on the buster cannot
## be hurt or eaten; on `die` it is gone. A zombie can still eat it while it
## chews, and if one does, the stone comes back up. Plant food does nothing.
##
## A rig that says none of this - or a buster drawn without art - runs the
## same steps on the rig's own timings, so it behaves the same either way.
##
## Config: bust_time.

## The GraveBuster rig's timings at its 30 fps, for a buster that has no rig
## to announce them: Spawn's `bust` lands on frame 21, and Busting is 130
## frames long with `finish` on frame 115. Busting runs at 4 / bust_time.
const SPAWN_LENGTH := 21.0 / 30.0
const BUSTING_LENGTH := 130.0 / 30.0
const FINISH_AT := 115.0 / 30.0
const RIG_EVENTS: Array[StringName] = [&"bust", &"finish", &"die"]

enum Phase { START, DIGGING, BUSTING, FINISHED }

var bust_time: float = 4.0

var _phase := Phase.START
var _stone: Grave = null
## Whether the rig announces the steps itself. When it does, the clock below
## is not used.
var _rig_driven := false
## Rig seconds into the current animation, for a buster without a rig.
var _clock := 0.0


func setup() -> void:
	bust_time = maxf(0.1, float(cfg(&"bust_time", 4.0)))
	var stone = host.board.object_at(host.row, host.col)
	if stone is Grave:
		_stone = stone
	host.died.connect(_on_host_died)
	Audio.play(&"plant.chomp", host.position)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _phase == Phase.START:
		# The rig is attached after the components, so it is looked at here.
		_start()
	if _rig_driven:
		return
	_clock += delta * host.art_speed()
	match _phase:
		Phase.DIGGING:
			if _clock >= SPAWN_LENGTH:
				_bust()
		Phase.BUSTING:
			if _clock >= FINISH_AT:
				_finish()
		Phase.FINISHED:
			if _clock >= BUSTING_LENGTH:
				host.die()


func _start() -> void:
	_phase = Phase.DIGGING
	var art: Armature = host.art
	if art == null:
		return
	var spawn := Art.animation_for(host.art_kind(), host.def.id, &"spawn")
	var busting := Art.animation_for(host.art_kind(), host.def.id, &"busting")
	if art.announces(spawn, [&"bust"]) and art.announces(busting, [&"finish"]) \
			and art.announces(busting, [&"die"]):
		_rig_driven = true
		art.event.connect(_on_art_event)
		# The plant already started its Spawn on being planted.
		host.play_art(&"spawn", false)


func _on_art_event(name: StringName) -> void:
	if host.is_dead or not RIG_EVENTS.has(name):
		return
	match name:
		&"bust":
			# Spawn repeats the event on each of its last frames; only the first
			# one starts the chewing.
			if _phase == Phase.DIGGING:
				_bust()
		&"finish":
			if _phase == Phase.BUSTING:
				_finish()
		&"die":
			if _phase == Phase.FINISHED:
				host.die()


## The stone sinks and the chewing starts, stretched to last bust_time.
func _bust() -> void:
	_phase = Phase.BUSTING
	_clock = 0.0
	if is_instance_valid(_stone) and not _stone.is_dead:
		_stone.sunk = true
	host.art_tempo = 4.0 / bust_time
	# Anything that sends the plant back to idle - its Spawn ending - lands
	# on the chewing instead.
	host.idle_state = &"busting"
	host.play_art(&"busting", false)


## The stone is gone, and the buster is out of reach until it vanishes.
func _finish() -> void:
	_phase = Phase.FINISHED
	host.set_runtime_tag(&"uneatable", true)
	if is_instance_valid(_stone) and not _stone.is_dead:
		_stone.die()
	_stone = null


## Invincible once the stone is broken, as PVZGE's buster is.
func absorb_damage(amount: float) -> float:
	return 0.0 if _phase == Phase.FINISHED else amount


## Eaten before it finished: the stone comes back up where it was.
func _on_host_died(_who: Character) -> void:
	if is_instance_valid(_stone) and not _stone.is_dead:
		_stone.sunk = false
