class_name SunToken
extends Collectable
## A collectable sun.

## Every sun is worth the same amount, deliberately fixed rather than
## configurable. The original game drops 25; this is 50.
const VALUE := 50

@export var core_color: Color = Color("ffd83d")
@export var glow_color: Color = Color("ffee8a")


func _init() -> void:
	# The art is PVZGE's sun at its own scale, about a sunflower's head
	# across; the hover area follows it.
	radius = 30.0


func art_id() -> StringName:
	return &"sun"


func _draw() -> void:
	if art != null:
		return
	draw_circle(Vector2.ZERO, radius, core_color)
	draw_circle(Vector2.ZERO, radius * 0.62, glow_color)
