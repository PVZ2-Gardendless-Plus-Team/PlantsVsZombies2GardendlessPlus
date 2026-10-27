extends EntityComponent
## Periodically drops sun onto the board.
##
## Timing is data-driven; the amount is not - every sun is worth
## SunToken.VALUE.
##
## Config: interval, interval_jitter, first_delay, first_delay_jitter.

const PRODUCE_EVENTS := [&"Produce", &"produce", &"produce0"]

var _timer: float = 0.0
## A sun owed to the Produce animation's event, which is the frame the sun
## leaves the head.
var _pending: bool = false


func setup() -> void:
	_timer = cfg_jittered(&"first_delay", &"first_delay_jitter", 5.0)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = cfg_jittered(&"interval", &"interval_jitter", 24.0)
	# An animation cut short never fires its event; that sun is still owed.
	if _pending:
		_pending = false
		_produce()
	if host.play_art_once(&"attack") and _await_event():
		return
	_produce()


func _await_event() -> bool:
	var art: Armature = host.art
	if art == null or not art.announces(art.playing, PRODUCE_EVENTS):
		return false
	if not art.event.is_connected(_on_art_event):
		art.event.connect(_on_art_event)
	_pending = true
	return true


func _on_art_event(name: StringName) -> void:
	if not _pending or not PRODUCE_EVENTS.has(name) or host.is_dead:
		return
	_pending = false
	_produce()


## Where PVZGE puts it: out of the plant's `SunProducePoint`, tipped away from
## the stem, landing at the plant's feet. The point comes from the art mapping
## (`produce_point`, in rig units with y up, and `sun_direction`), so a plant
## without art or without the point just drops its sun as before.
func _produce() -> void:
	Audio.play_for(&"plant.produce", host)
	var art: Armature = host.art
	var entry := Art.mapping(host.art_kind(), host.def.id) if host.def != null else {}
	var point: Array = entry.get("produce_point", [])
	if art == null or point.size() < 2:
		host.board.drop_sun(host.position)
		return
	var rig_origin: Vector2 = host.position + art.position
	# A mirrored rig has a negative x scale, which flips the point with it.
	var from := rig_origin + Vector2(float(point[0]) * art.scale.x,
			-float(point[1]) * art.scale.y)
	var dir: Array = entry.get("sun_direction", [0.0, 1.0])
	host.board.pop_sun(from, rig_origin.y,
			Vector2(float(dir[0]) * art.facing, float(dir[1])))


## Plant food: a handful of sun at once.
func on_plantfood() -> bool:
	var count := int(cfg(&"plantfood_suns", 5))
	for i in count:
		# Spread them so they do not land exactly on top of each other.
		host.board.drop_sun(host.position + Vector2((i - count * 0.5) * 22.0, 0))
	_timer = cfg_jittered(&"interval", &"interval_jitter", 24.0)
	return count > 0
