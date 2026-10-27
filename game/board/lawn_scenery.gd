class_name LawnScenery
extends Node2D
## The lawn's own art: the ground under the grid and the layer drawn over it.
##
## PVZGE splits every lawn into a back rig, drawn under everything, and two
## upper rigs. The "there" rig - the far fence, the mailbox, the street the
## zombies walk in from - sits on the lawn under the characters; the "here"
## rig - the near hedge, the house's corner - is parented to a layer above
## them. All of it comes from one `lawn:<stage>` entry in the art mappings, and both are placed exactly where the original placed
## them relative to its grid, so a lane on the art is a lane on the board.
##
## When the stage has no art - nothing extracted, or a stage without an entry -
## nothing is built and the board keeps drawing its placeholder checkerboard.

## Where PVZGE puts things, in its own units, measured from the in-game scene
## (`LawnCommon/Squares/Square00` and `FrontYard/lawn`, relative to the canvas
## centre, y up). Only the differences matter: they say where the lawn's
## origin sits relative to the first cell, and the board does the rest.
const SQUARE_SIZE := Vector2(68.0, 80.77)
const SQUARE_00 := Vector2(-119.4, 110.8)
const LAWN_ORIGIN := Vector2(56.0, -4.3)
## `CharacterScale` in the original, which `FrontYard.changeLawn` also gives
## the lawn prefab.
const LAWN_SCALE := 0.42

## Under the board's own drawing and every lane band.
const BACK_Z := -100
## Over the ground, under every lane band - a lily pad's carrier band
## included - so a zombie walks in front of the fence and the mailbox.
const THERE_Z := -50
## Above every lane band, below collectables.
const FRONT_Z := 900

var stage: StringName = &""
## The sod animation picked for the open lanes, or empty for a lawn without.
var sod_animation: StringName = &""
var _back: Array[Armature] = []
var _there: Array[Armature] = []
var _front: Array[Armature] = []
var _entry: Dictionary = {}


func has_art() -> bool:
	return not _back.is_empty()


## Whether the art itself shows which lanes are open, as the tutorial's
## unsodded dirt does. Otherwise the board still shades locked lanes.
func shows_open_rows() -> bool:
	return _entry.has("open_rows")


## Builds the art for `stage_id` on `board`. `open_rows` is how many lanes are
## sodded, which only the tutorial lawn draws differently.
func show_stage(stage_id: StringName, board: Board, open_rows: int) -> bool:
	clear()
	stage = stage_id
	_entry = Art.mapping(&"lawn", stage_id)
	if _entry.is_empty():
		return false

	# One original unit is this many board pixels. The two axes differ by a
	# couple of percent because the port's cells are not quite the original's
	# shape; following both keeps the art's lanes on the board's lanes.
	var k := board.cell_size / SQUARE_SIZE
	var offset := LAWN_ORIGIN - SQUARE_00
	var at := board.grid_to_world(0, 0) + Vector2(offset.x * k.x, -offset.y * k.y)
	var size := LAWN_SCALE * k

	for name in (_entry.get("back", []) as Array):
		var rig := _place(StringName(name), at, size, BACK_Z)
		if rig != null:
			_back.append(rig)
	for name in (_entry.get("there", []) as Array):
		var rig := _place(StringName(name), at, size, THERE_Z)
		if rig != null:
			_there.append(rig)
	for name in (_entry.get("front", []) as Array):
		var rig := _place(StringName(name), at, size, FRONT_Z)
		if rig != null:
			_front.append(rig)
	set_open_rows(open_rows)
	return has_art()


## Sods as many lanes as are open. The tutorial lawn carries the dirt and the
## turf as separate slots and switches between them by animation.
func set_open_rows(count: int) -> void:
	if _back.is_empty():
		return
	var by_count: Dictionary = _entry.get("open_rows", {})
	if by_count.is_empty():
		_back[0].play_first(["Idle", "idle"])
		return
	# The nearest the art has, rounding up, so five open lanes on a lawn that
	# only knows 1/3/5 still shows all five.
	var best := ""
	var best_n := 1 << 30
	for key in by_count:
		var n := int(key)
		if n >= count and n < best_n:
			best_n = n
			best = String(by_count[key])
	if best == "":
		best = String(by_count.values().back())
	sod_animation = StringName(best)
	_back[0].play(sod_animation)


func clear() -> void:
	for rig in _back + _there + _front:
		if is_instance_valid(rig):
			rig.queue_free()
	_back.clear()
	_there.clear()
	_front.clear()
	_entry = {}
	stage = &""
	sod_animation = &""


func _place(armature_name: StringName, at: Vector2, size: Vector2, z: int) -> Armature:
	var rig := Art.make_from(_entry, armature_name)
	if rig == null:
		return null
	rig.name = String(armature_name)
	rig.scale = size
	rig.position = at
	rig.fitted_x = at.x
	rig.z_index = z
	add_child(rig)
	# Most lawns idle with a single looping animation - swaying grass, the
	# Dark Ages torches - and a lawn's armatures each have their own.
	rig.play_first(["Idle", "idle", "i"])
	return rig
