class_name DetachedLimb
extends Node2D
## A piece that has come off something: an arm knocked loose, a head on death.
##
## It is handed the sprites the rig was drawing, already at the transform they
## had, so the moment of separation is seamless - nothing pops or jumps. From
## there it moves the way PVZGE's `zombieDrop` does: tossed up and out from
## where it came off, spinning about its own middle, bouncing on the lane's
## floor until it settles, then fading.
##
## PVZGE counts velocities in its own world units per 60th of a second. They
## are kept in those units here and turned into board pixels by `unit`, so the
## numbers can be read straight against the original.

## PVZGE's `zombieDrop` gravity, per frame per frame.
const GRAVITY := 0.6666
## The resting height of the piece's middle above the floor: PVZGE gives every
## drop a 30 unit box and stops it when its middle is half that up, at the
## character's scale - rig units, then, as the rig is drawn at that scale.
const REST_HALF_HEIGHT := 15.0
## A bounce slower than this (squared, in units per frame) is the last one.
const SETTLE_SPEED_SQUARED := 3.0
## Seconds after first touching down before it fades whether settled or not.
const FADE_DELAY := 3.0
const FADE_TIME := 0.5

## Across the lawn, in PVZGE units per frame.
var velocity_x: float = 0.0
## Upward, in PVZGE units per frame.
var velocity_up: float = 0.0
## Degrees per frame, as PVZGE's `bodyOmega`.
var spin: float = 0.0
## The middle's height above the floor, in board pixels.
var height: float = 0.0
## The lane's floor, in board pixels.
var floor_y: float = 0.0
## One PVZGE unit in board pixels, per axis.
var unit := Vector2.ONE

var _rest_height: float = 0.0
var _landed := false
var _fade_in: float = FADE_DELAY
var _fading := false
var _fade_left: float = FADE_TIME


## `piece` is what Armature.detach_slots handed back, at its world transform.
## It goes onto `into` (the board) spinning about its own middle. `toward` is
## the way it flies off (-1 left, 1 right); 0 lets it go either way, as PVZGE
## does with no hit to push it. `rig_scale` is the scale the character's rig
## is drawn at on the board.
static func drop(piece: Node2D, into: Node2D, toward: int, floor_y: float,
		unit: Vector2, rig_scale: float) -> DetachedLimb:
	var limb := DetachedLimb.new()
	var placed := into.get_global_transform().affine_inverse() * piece.transform
	var middle := placed * _middle_of(piece)
	limb.position = middle
	# Keep the piece's own scale, flip and angle; only its pivot moves.
	piece.transform = Transform2D(placed.x, placed.y, placed.origin - middle)
	limb.add_child(piece)
	limb.floor_y = floor_y
	limb.height = floor_y - middle.y
	limb.unit = unit
	limb._rest_height = REST_HALF_HEIGHT * absf(rig_scale)
	# PVZGE's default direction, (5 - 10r, 15), at 0.55 and +-10%.
	var across := 5.0 - 10.0 * randf()
	if toward != 0:
		across = absf(across) * signf(toward)
	var push := 0.55 * (1.0 + 0.1 * (1.0 - 2.0 * randf()))
	limb.velocity_x = across * push
	limb.velocity_up = 15.0 * push
	limb.spin = (1.0 if randf() < 0.5 else -1.0) * (2.0 * randf() + 1.0)
	into.add_child(limb)
	return limb


## The middle of everything the piece draws, in the piece's own space, so it
## turns about itself rather than about the rig's feet.
static func _middle_of(piece: Node2D) -> Vector2:
	var box := Rect2()
	var found := false
	for sprite in piece.find_children("*", "Sprite2D", true, false):
		var picture := sprite as Sprite2D
		if picture.texture == null:
			continue
		# The piece is not on the board yet, so its transforms are walked by
		# hand rather than asked of the tree.
		var to_piece := Transform2D.IDENTITY
		var shown := true
		var node: Node = picture
		while node != piece and node is CanvasItem:
			shown = shown and (node as CanvasItem).visible
			to_piece = (node as Node2D).transform * to_piece
			node = node.get_parent()
		if not shown:
			continue
		var rect := picture.get_rect()
		for corner in [rect.position, rect.end,
				Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			var at: Vector2 = to_piece * corner
			if found:
				box = box.expand(at)
			else:
				box = Rect2(at, Vector2.ZERO)
				found = true
	return box.get_center() if found else Vector2.ZERO


func _process(delta: float) -> void:
	var frames := delta * 60.0
	if not _landed or velocity_up != 0.0 or velocity_x != 0.0:
		var was_up := velocity_up
		velocity_up -= GRAVITY * frames
		position.x += velocity_x * frames * unit.x
		height += (was_up + velocity_up) * 0.5 * frames * unit.y
		if height <= _rest_height and velocity_up <= 0.0:
			height = _rest_height
			_bounce(frames)
	rotation_degrees -= spin * frames
	position.y = floor_y - height

	if _landed and not _fading:
		_fade_in -= delta
		if _fade_in <= 0.0:
			_fading = true
	if _fading:
		_fade_left -= delta
		modulate.a = clampf(_fade_left / FADE_TIME, 0.0, 1.0)
		if _fade_left <= 0.0:
			queue_free()


## PVZGE's `zombieDrop.hitFloor`: half the speed across, half the fall back
## up, until a bounce is too small to matter and it lies still.
func _bounce(frames: float) -> void:
	_landed = true
	velocity_x *= 0.5
	velocity_up = -0.5 * velocity_up - GRAVITY * frames
	if velocity_up * velocity_up + velocity_x * velocity_x <= SETTLE_SPEED_SQUARED:
		velocity_x = 0.0
		velocity_up = 0.0
		spin = 0.0
		_fading = true
