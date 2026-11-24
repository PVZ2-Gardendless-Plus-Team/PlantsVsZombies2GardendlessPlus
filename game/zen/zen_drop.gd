class_name ZenDrop
extends Collectable
## A coin or gem a Zen Garden plant pays out as it grows (PVZGE's coinInZen
## and gemInZen). Tossed up out of the plant, picked up by hovering, and
## banked when it reaches its counter. One left lying for 20 seconds collects
## itself, and leaving the garden collects whatever is still on the ground,
## as PVZGE's onDisable does.

## PVZGE's existTime.
const EXIST_TIME := 20.0

## &"coins" or &"gems".
var kind: StringName = &"coins"
var value: int = ZenGarden.SILVER
var _age: float = 0.0


func _init() -> void:
	radius = 60.0
	hover_slack = 20.0
	lifetime = 1.0e9
	fade_out_time = 0.0


func art_id() -> StringName:
	return &""


func _ready() -> void:
	var id := &"gem" if kind == &"gems" else (&"coin_gold" if value >= ZenGarden.GOLD else &"coin_silver")
	art = Art.make(&"zen", id)
	if art != null:
		add_child(art)
		art.play(Art.animation_for(&"zen", id, &"idle"))
	queue_redraw()


func _process(delta: float) -> void:
	super(delta)
	_age += delta
	if _age >= EXIST_TIME and not is_collected():
		collect()


## Hover distance is in screen pixels, but this lives in the scaled garden.
func contains_point(point: Vector2) -> bool:
	return point.distance_to(global_position) <= (radius + hover_slack) * global_scale.x


func bank() -> void:
	Saves.add_currency(kind, value)


func _draw() -> void:
	if art != null:
		return
	var colour := Color("63d0ff") if kind == &"gems" else \
			(Color("f2c53d") if value >= ZenGarden.GOLD else Color("d9dde3"))
	draw_circle(Vector2(0, -radius), radius, Color(0.2, 0.2, 0.2))
	draw_circle(Vector2(0, -radius), radius - 8.0, colour)
