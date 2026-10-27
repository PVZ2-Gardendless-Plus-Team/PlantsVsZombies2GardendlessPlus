class_name GroundShade
extends Sprite2D
## The dark oval a character casts on the lawn, the way PVZGE draws it.
##
## PVZGE gives every plant, zombie and mower a `shade`: one image from its
## Particles atlas, a soft black ellipse 233 by 122, laid on the ground under
## the character's `shadeSocket` (a prefab node, sometimes pinned to a bone
## of the rig) and drawn in a layer of its own under every character. Its
## size is the prefab's `originalShadeScale`, times twice the CharacterScale,
## shrunk as the socket rises - a shadow is gone by 600 units up. The layer
## as a whole darkens the grass by about a third.
##
## The ellipse is drawn here rather than taken from the atlas, so a rig needs
## nothing extracted for it: only the mapping's `shade` numbers.
##
##     "shade": {"scale": 0.25, "socket": "shade"}
##     "shade": {"scale": 0.35, "point": [0, -24.26], "drop": 23.81}
##
## The socket sets the shadow's x and, by its height, its size. Some plants
## pin theirs to a bone - the Peashooter's neck, the Sunflower's mouth - so
## the shadow sways with the head; `socket` names that one of the mapping's
## `sockets`. Others give a fixed `point`, in rig units with y up like
## `projectile_origin`, and with neither it is the rig's origin. `drop` is
## how far below the origin the ground is, in rig units: zombies stand
## PVZGE's 10 units (23.8 here) above their feet.

const SIZE := Vector2i(233, 122)
## How many pixels the ellipse's edge takes to fade in, measured off PVZGE's.
const EDGE := 22.0
## PVZGE's `_maxShowShadeHeight`.
const MAX_HEIGHT := 600.0
## Rig units to PVZGE world units - the CharacterScale.
const CHARACTER_SCALE := 0.42
## Every shadow sits in this one band, over the lawn (-100) and the far
## fence (-50) and under row 0's plants (0), as PVZGE's shade layer does.
const Z := -20
const ALPHA := 0.33

static var _texture: ImageTexture = null

var _art: Node2D = null
var _socket: Node2D = null
var _spec: Dictionary = {}


## A shade for `art` as `spec` describes it, or null when there is none.
static func make(art: Node2D, spec: Dictionary) -> GroundShade:
	var size := float(spec.get("scale", 0.0))
	if size <= 0.0:
		return null
	var shade := GroundShade.new()
	shade.texture = ellipse()
	shade.z_as_relative = false
	shade.z_index = Z
	shade.modulate = Color(1, 1, 1, ALPHA)
	shade._art = art
	shade._spec = spec
	if art.has_method(&"socket") and spec.has("socket"):
		shade._socket = art.socket(StringName(spec["socket"]))
	shade.set_process(shade._socket != null)
	shade.fit()
	return shade


func _process(_delta: float) -> void:
	fit()


## Places and sizes the shade under its art, a child of the same character.
func fit() -> void:
	if _art == null or not is_instance_valid(_art):
		return
	var point := Vector2.ZERO
	if _socket != null and is_instance_valid(_socket):
		point = Vector2(_socket.position.x, -_socket.position.y)
	else:
		var fixed: Array = _spec.get("point", [0.0, 0.0])
		point = Vector2(float(fixed[0]), float(fixed[1]))
	var drop := float(_spec.get("drop", 0.0))
	var rig_scale := absf(_art.scale.y)
	# A mirrored rig has a negative x scale, which flips the socket with it.
	position = _art.position + Vector2(point.x * _art.scale.x, drop * rig_scale)
	var height := point.y * CHARACTER_SCALE
	var factor := (MAX_HEIGHT - height) / MAX_HEIGHT if height < MAX_HEIGHT else 0.0
	var s := factor * 2.0 * rig_scale * float(_spec.get("scale", 0.0))
	scale = Vector2(s, s)


## The soft ellipse, built once: black, opaque inside, fading to nothing
## over its last EDGE pixels, as the atlas image does.
static func ellipse() -> ImageTexture:
	if _texture != null:
		return _texture
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var a := SIZE.x * 0.5
	var b := SIZE.y * 0.5
	for y in SIZE.y:
		for x in SIZE.x:
			var px := (x + 0.5 - a) / a
			var py := (y + 0.5 - b) / b
			var d := sqrt(px * px + py * py)
			var g := sqrt(px * px / (a * a) + py * py / (b * b))
			# Distance to the edge in pixels, from the implicit ellipse's slope.
			var inside := (1.0 - d) * d / g if g > 0.0 else EDGE
			image.set_pixel(x, y, Color(0, 0, 0, smoothstep(0.0, EDGE, inside)))
	_texture = ImageTexture.create_from_image(image)
	return _texture
