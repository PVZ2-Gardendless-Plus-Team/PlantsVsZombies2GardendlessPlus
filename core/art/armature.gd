class_name Armature
extends Node2D
## A rig on screen: flat sprites driven by Godot's own AnimationPlayer.
##
## All the DragonBones-specific work happens once, in ArmatureBaker, which
## turns a rig into `Animation` resources. Nothing samples a timeline here,
## eases a curve or blends two poses by hand - `AnimationPlayer.play()` does
## all of it, and does it in engine code.
##
## The sprites are flat rather than a bone tree because DragonBones bones can
## refuse their parent's rotation or scale and Godot's nodes cannot. Resolving
## the chain at bake time removes the difference, and leaves a shallow scene:
## a lane of zombies is wide, not deep.
##
## The baked animations and the atlas regions belong to a shared ArmatureSet,
## so entities cost nodes, not memory.

signal animation_finished(name: StringName)
## Fired when a baked animation reaches an event the rig declares - the
## peashooter's Shoot animation says "Shoot" fifteen frames in, which is when
## the pea actually leaves its mouth.
signal event(name: StringName)
## Fired when a baked animation reaches a sound the rig names - the basic
## zombie's Death says "fall" as it hits the ground.
signal sound(name: StringName)

## How long to ease from one animation into the next. Without it a zombie
## switching from Walk to Death cuts straight to the death pose.
const BLEND_TIME := 0.12

var playing: StringName = &""
var looping: bool = true
## Which way the art looks: +1 as authored, -1 mirrored.
var facing: int = 1
## The horizontal placement the library fitted, before any mirroring.
var fitted_x: float = 0.0

var _player: AnimationPlayer = null
var _slots: Dictionary = {}          ## slot name -> Sprite2D
var _sockets: Dictionary = {}        ## socket alias -> Node2D
var _names: Array = []


func setup(source: ArmatureSet, armature_name: StringName,
		sockets: Dictionary = {}) -> bool:
	if source == null or not source.has_armature(armature_name):
		return false
	var rig := source.rig(armature_name, sockets)
	if rig == null:
		return false

	# The setup pose, which is also what a slot keeps when no animation ever
	# touches it - those get no track at all.
	var rest := rig.rest_transforms()
	for i in rig.slots.size():
		var slot: Dictionary = rig.slots[i]
		# A slot is a node at its bone, holding one sprite per picture it can
		# show. Animations move the slot, switch which sprite is visible and
		# tint the slot, so a blink or a mouth opening is a visibility key and
		# never a texture swap mid-blend.
		var node := Node2D.new()
		node.name = ArmatureBaker.node_name(slot["name"])
		node.transform = rest[i]
		node.modulate = slot["color"]
		add_child(node)
		_slots[slot["name"]] = node
		# A socket has nothing to draw: it is a marker the game can read a
		# position off, animated like everything else.
		if slot.has("socket"):
			_sockets[slot["socket"]] = node
			continue
		var displays: Array = slot["displays"]
		for choice in displays.size():
			var display: Dictionary = displays[choice]
			if display.is_empty():
				continue
			var region: StringName = display["region"]
			var sprite := Sprite2D.new()
			sprite.name = str(choice)
			sprite.texture = source.region(region)
			sprite.centered = true
			sprite.offset = source.region_offset(region)
			sprite.transform = display["xform"]
			sprite.visible = choice == int(slot["display"])
			if slot["blend"] == "add":
				sprite.material = _additive()
			node.add_child(sprite)

	_player = AnimationPlayer.new()
	_player.name = "Animations"
	add_child(_player)
	# Immediate, not deferred: a rig's event says the pea leaves on THIS
	# frame, and a frame of latency is the difference between a shot that
	# comes out of the plant's mouth and one that trails it.
	_player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	_player.add_animation_library(&"", source.animations(armature_name, sockets))
	_player.animation_finished.connect(_on_finished)
	_names = _player.get_animation_list()
	return true


## Glows and flashes are drawn additively. One material serves every one.
static var _add_material: CanvasItemMaterial = null


static func _additive() -> CanvasItemMaterial:
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_material


## Playback speed, so a buffed or slowed entity animates to match.
func set_speed_scale(value: float) -> void:
	if _player != null:
		_player.speed_scale = maxf(value, 0.0)


func speed_scale() -> float:
	return _player.speed_scale if _player != null else 1.0


## How fast an animation carries the rig forward, in screen pixels per second
## at normal speed, or 0 for one that does not travel. A walk is drawn to
## move at this pace; anything else makes the feet skate.
func ground_speed(name: StringName) -> float:
	if _player == null or not _player.has_animation(name):
		return 0.0
	var travel := float(_player.get_animation(name).get_meta(&"ground_speed", 0.0))
	return travel * absf(scale.x)


## Jumps somewhere into the current animation, so a row of identical plants
## does not bob in lockstep.
func seek_fraction(fraction: float) -> void:
	if _player == null or playing == &"":
		return
	var length := _player.get_animation(playing).length
	_player.seek(clampf(fraction, 0.0, 1.0) * length, true)


func animation_names() -> Array:
	return _names.duplicate()


func has_animation(name: StringName) -> bool:
	return _player != null and _player.has_animation(name)


## Plays `name`, easing out of whatever was playing. Returns false if this
## armature has no such animation, so a caller can fall back rather than
## silently freeze.
##
## Looping is the caller's call, not the rig's: PopCap marks every animation
## as looping, including the death ones, and it is the game that knows an
## entity only dies once. A one-shot simply is not restarted when it ends.
##
## `blend` is how long to fade in. Characters pass PVZGE's own fade for each
## state; UI and scenery keep the default.
func play(name: StringName, loop: bool = true, restart: bool = false,
		blend: float = BLEND_TIME) -> bool:
	if not has_animation(name):
		return false
	if playing == name and not restart and _player.is_playing():
		looping = loop
		return true
	playing = name
	looping = loop
	_player.play(name, blend)
	if restart:
		# Replaying the animation that just ended has to start it over, not
		# resume it at its last frame.
		_player.seek(0.0, true)
	return true


## The first of `candidates` this armature actually has. Lets an entity ask
## for a walk and settle for an idle without knowing which rig it got.
func play_first(candidates: Array, loop: bool = true) -> bool:
	for name in candidates:
		if play(StringName(name), loop):
			return true
	return false


## Whether an animation announces any of these events, so a caller can tell
## a rig that will say "now" from one that will not.
func announces(name: StringName, events: Array) -> bool:
	if _player == null or not _player.has_animation(name):
		return false
	var animation := _player.get_animation(name)
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_METHOD:
			continue
		for key in animation.track_get_key_count(track):
			var args: Array = animation.method_track_get_params(track, key)
			if not args.is_empty() and events.has(StringName(args[0])):
				return true
	return false


## Where a named socket is right now, in world space. Null when the rig has
## no such socket, so a caller falls back to its own guess.
func socket(alias: StringName) -> Node2D:
	return _sockets.get(alias)


## Called from a baked method track. Named with a leading underscore because
## nothing outside the animation should call it; listen to `event` instead.
func _fire_event(name: StringName) -> void:
	event.emit(name)


func _fire_sound(name: StringName) -> void:
	sound.emit(name)


func _on_finished(name: StringName) -> void:
	if looping and name == playing:
		_player.play(name)
		return
	playing = &""
	animation_finished.emit(name)


## Mirrors the art. The flip is about this node's own origin, so the fitted
## offset has to flip with it - otherwise a mirrored entity slides to the
## wrong side of itself by twice that offset.
func set_facing(direction: int) -> void:
	var want: int = -1 if direction < 0 else 1
	if facing == want:
		return
	facing = want
	scale.x = absf(scale.x) * want
	position.x = fitted_x * want


## Slots the rig draws but the game should not, until something turns them
## on. PvZ rigs carry a detached-limb variant in its own slot - the basic
## zombie's `arm_here_ARM` is the broken stump, sitting on top of the intact
## arm - because the game decides when a limb comes off, not the rig.
func hide_slot(name: StringName, hidden: bool = true) -> void:
	var node: Node2D = _slots.get(name)
	if node != null:
		node.visible = not hidden


## Takes slots off the rig and hands them back as one free-standing node,
## already at the world transform they had. That is how a limb comes off: the
## zombie stops drawing its arm and the caller is given the arm to drop.
func detach_slots(names: Array) -> Node2D:
	var freed := Node2D.new()
	freed.name = "Detached"
	freed.transform = global_transform
	for slot_name in names:
		var node: Node2D = _slots.get(StringName(slot_name))
		if node == null or not is_instance_valid(node):
			continue
		var where := node.transform
		var index := node.get_index()
		remove_child(node)
		freed.add_child(node)
		node.transform = where
		_slots.erase(StringName(slot_name))
		# An empty stand-in keeps the name, so the rig's animations still
		# find a node to key and do not complain about the missing limb.
		var stand_in := Node2D.new()
		stand_in.name = ArmatureBaker.node_name(slot_name)
		stand_in.visible = false
		for picture in node.get_children():
			var blank := Node2D.new()
			blank.name = picture.name
			stand_in.add_child(blank)
		add_child(stand_in)
		move_child(stand_in, index)
	return freed


func slot_names() -> Array:
	var names := _slots.keys()
	names.sort()
	return names
