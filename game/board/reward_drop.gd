class_name RewardDrop
extends Collectable
## The prize a won level drops where its last zombie fell: a seed packet, a
## trophy, a note, or a coin bag. PVZGE's levelPrize.
##
## It leaps to the middle of the lawn and waits there - it never expires,
## since the level cannot end without it. Sweeping over it collects it: a coin
## bag bursts into coins, anything else rises to the centre of the screen to
## be shown off, and `collected` fires once that has played out.

## Fires the moment the player touches it, before the show plays.
signal picked_up(source: RewardDrop)

var reward: LevelReward

@export_group("Leap")
## Seconds for the leap from where it dropped to its resting spot.
@export var leap_time: float = 1.5
## Peak of the arc, in pixels.
@export var leap_height: float = 180.0

@export_group("Show")
## Seconds a prize takes to rise to the centre of the screen.
@export var present_time: float = 2.0
## How much it grows on the way.
@export var present_scale: float = 1.6
## Seconds a coin bag takes to burst.
@export var burst_time: float = 0.5

@export_group("Appearance")
@export var glow_color: Color = Color(1.0, 0.95, 0.55, 0.45)
@export var packet_color: Color = Color("8cc63f")
@export var bag_color: Color = Color("9a6b3a")
@export var trophy_color: Color = Color("f2c53d")
@export var note_color: Color = Color("f3ead2")

var _time: float = 0.0
var _leap: Tween
## A plant prize shows the plant inside its packet when the plant has art.
var _plant_art: Armature


func _init() -> void:
	radius = 34.0
	lifetime = INF
	fade_out_time = 0.0
	# It travels by leap, not by falling.
	_falling = false


func art_id() -> StringName:
	if reward == null:
		return &""
	match reward.type:
		&"unlock_plant":
			return &"seedpacket"
		&"worldtrophy", &"upgrade":
			return &"trophy"
		&"note":
			return &"note"
		&"coins", &"gems", LevelReward.COIN_BAG:
			return &"coinbag"
	return &""


func _ready() -> void:
	super._ready()
	if art == null and reward != null and reward.type == &"unlock_plant":
		_plant_art = Art.make(&"plant", reward.param)
		if _plant_art != null:
			_plant_art.scale = Vector2.ONE * 0.45
			_plant_art.position = Vector2(0, 14)
			add_child(_plant_art)


## Arcs from where it is to `to`, in the parent's coordinates.
func leap_to(to: Vector2) -> void:
	var from := position
	if _leap != null:
		_leap.kill()
	_leap = create_tween()
	_leap.tween_method(func(t: float) -> void:
		position = from.lerp(to, t) + Vector2(0, -sin(t * PI) * leap_height),
		0.0, 1.0, leap_time)
	_leap.finished.connect(func() -> void:
		Audio.play_variant(&"reward.land", sound_variant(), position))


## Which prize's sounds this plays: PVZGE gives the coin bag, the seed packet
## and the note their own, and every trophy shares the rest.
func sound_variant() -> StringName:
	return reward.type if reward != null else &""


func is_leaping() -> bool:
	return _leap != null and _leap.is_running()


func _process(delta: float) -> void:
	_time += delta
	if not _collected:
		queue_redraw()
	super._process(delta)


func collect() -> void:
	if _collected:
		return
	_collected = true
	if _leap != null:
		_leap.kill()
	Audio.play_variant(&"reward.collect", sound_variant(), position)
	picked_up.emit(self)
	var tween := create_tween()
	if reward == null or not reward.is_award():
		tween.tween_property(self, "scale", Vector2.ZERO, burst_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tween.set_parallel(true)
		tween.tween_property(self, "global_position", collect_target, present_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(self, "scale", Vector2.ONE * present_scale, present_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_bank)
	queue_redraw()


func _draw() -> void:
	if not _collected:
		# The pulsing halo that says "pick me up".
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		var halo := glow_color
		halo.a *= 0.6 + 0.4 * pulse
		draw_circle(Vector2.ZERO, radius + 10.0 + pulse * 4.0, halo)
	if art != null or reward == null:
		return
	var font := ThemeDB.fallback_font
	match art_id():
		&"seedpacket":
			var box := Rect2(-26, -34, 52, 68)
			draw_rect(box, packet_color)
			draw_rect(box, Color.BLACK, false, 2.0)
			if _plant_art == null:
				draw_string(font, Vector2(-26, 4), reward.item_name(),
						HORIZONTAL_ALIGNMENT_CENTER, 52, 11, Color.BLACK)
		&"trophy":
			draw_rect(Rect2(-18, -26, 36, 30), trophy_color)
			draw_rect(Rect2(-5, 4, 10, 14), trophy_color)
			draw_rect(Rect2(-14, 18, 28, 8), trophy_color.darkened(0.3))
		&"note":
			draw_rect(Rect2(-24, -30, 48, 60), note_color)
			for i in 4:
				draw_line(Vector2(-16, -18 + i * 12), Vector2(16, -18 + i * 12),
						Color(0.4, 0.35, 0.3), 1.5)
		_:
			draw_circle(Vector2(0, 6), 24.0, bag_color)
			draw_rect(Rect2(-10, -26, 20, 12), bag_color.darkened(0.2))
			draw_string(font, Vector2(-24, 14), "$", HORIZONTAL_ALIGNMENT_CENTER,
					48, 24, Color("f2c53d"))
