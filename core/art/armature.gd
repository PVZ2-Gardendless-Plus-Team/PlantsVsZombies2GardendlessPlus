class_name Armature
extends Node2D
## A rig on screen: flat sprites driven by Godot's own AnimationPlayer.
##
## A rig is an ordinary scene. `tools/bake_rigs.gd` converts each DragonBones
## armature PVZGE ships into `art/<bundle>/<armature>.tscn` once, and from
## then on it is Godot's: open it in the editor, scrub, re-key or add
## animations in the Animation panel, move or re-skin parts, and save. Nothing
## samples a timeline here, eases a curve or blends two poses by hand -
## `AnimationPlayer.play()` does all of it, in engine code.
##
## The tree is: one Node2D per slot (in draw order) holding one child per
## picture it can show, a `Socket_<bone>` marker per bone the game reads
## positions off, and an AnimationPlayer named `Animations`. A mod can ship a
## scene built by hand to the same shape and point its art mapping at it with
## `"scene"`; it never needs DragonBones at all. See docs/ART.md.
##
## The sprites are flat rather than a bone tree because DragonBones bones can
## refuse their parent's rotation or scale and Godot's nodes cannot. Resolving
## the chain at bake time removes the difference, and leaves a shallow scene:
## a lane of zombies is wide, not deep.
##
## Instances of one scene share its animations and atlas regions, so entities
## cost nodes, not memory.

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
## The AnimationPlayer every rig carries.
const PLAYER := &"Animations"

## The rig's bounding box in its own units, which fitting it to a lawn cell
## works from: the origin sits at the feet and the art is rarely centred on it.
@export var bounds: Rect2 = Rect2()
## What the rig plays by itself once it is in the tree, looping. Child rigs
## use it - a mower's wheels spin without anyone asking. Empty plays nothing.
@export var autoplay: StringName = &""
## Set on a baked scene you have edited by hand, so `tools/bake_rigs.gd`
## leaves it alone instead of converting the DragonBones export over it.
@export var keep: bool = false

var playing: StringName = &""
var looping: bool = true
## Which way the art looks: +1 as authored, -1 mirrored.
var facing: int = 1
## The horizontal placement the library fitted, before any mirroring.
var fitted_x: float = 0.0

var _player: AnimationPlayer = null
var _slots: Dictionary = {}          ## slot name -> Node2D
var _sockets: Dictionary = {}        ## socket alias -> Node2D
var _children: Array = []            ## nested Armatures, for inherited playback
var _rest_order: Array = []          ## slot names in their authored draw order
var _reordered: bool = false         ## whether a zOrder track has restacked it
var _names: Array = []


## Builds the rig from a DragonBones export at load time. The game prefers
## the baked scene (see `Art.make_from`); this is the path for a rig that has
## none, and what the baker itself runs.
func setup(source: ArmatureSet, armature_name: StringName,
		sockets: Dictionary = {}) -> bool:
	if not RigBuilder.populate(self, source, armature_name, sockets):
		return false
	return bind(sockets)


## Indexes a built or instanced rig: finds its slots, its player and the
## sockets the caller wants by name. `sockets` maps a game-facing alias to a
## bone ({"armor": "armorSOCKET"}). Returns false when the rig is missing the
## player or one of those sockets, so the caller can fall back to building it.
func bind(sockets: Dictionary = {}) -> bool:
	_player = get_node_or_null(NodePath(PLAYER)) as AnimationPlayer
	if _player == null:
		return false
	_slots.clear()
	_sockets.clear()
	_children.clear()
	_rest_order.clear()
	for child in get_children():
		if child == _player or not (child is Node2D):
			continue
		_slots[StringName(child.name)] = child
		_rest_order.append(StringName(child.name))
		if child.has_meta(&"socket"):
			continue
		for picture in child.get_children():
			if picture is Armature:
				var nested := picture as Armature
				if nested.bind():
					_children.append(nested)
					nested.event.connect(event.emit)
					nested.sound.connect(sound.emit)
	for alias in sockets:
		var marker: Node2D = _slots.get(ArmatureBaker.socket_node_name(StringName(sockets[alias])))
		if marker == null:
			return false
		_sockets[StringName(alias)] = marker
	# Immediate, not deferred: a rig's event says the pea leaves on THIS
	# frame, and a frame of latency is the difference between a shot that
	# comes out of the plant's mouth and one that trails it.
	_player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	if not _player.animation_finished.is_connected(_on_finished):
		_player.animation_finished.connect(_on_finished)
	_names = Array(_player.get_animation_list())
	return true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _player == null:
		bind()
	if autoplay != &"" and playing == &"":
		play(autoplay)


## Playback speed, so a buffed or slowed entity animates to match.
func set_speed_scale(value: float) -> void:
	if _player != null:
		_player.speed_scale = maxf(value, 0.0)
	# Child rigs keep the parent's clock (`_inheritTimeScale` in the runtime).
	for child in _children:
		(child as Armature).set_speed_scale(value)


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
	if _reordered and not _reorders(name):
		_set_draw_order(_rest_order)
		_reordered = false
	_player.play(name, blend)
	if restart:
		# Replaying the animation that just ended has to start it over, not
		# resume it at its last frame.
		_player.seek(0.0, true)
	# A child rig that has an animation of the same name plays it too
	# (`inheritAnimation`); one that does not keeps whatever it was doing.
	for child in _children:
		var nested := child as Armature
		if nested.has_animation(name):
			nested.play(name, loop, restart, blend)
	return true


## Whether an animation sets its own draw order. One that does not gets the
## authored order back, so a reorder never leaks into the next animation.
func _reorders(name: StringName) -> bool:
	var animation := _player.get_animation(name)
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_METHOD \
				and animation.track_get_key_count(track) > 0 \
				and animation.method_track_get_name(track, 0) == &"_set_draw_order":
			return true
	return false


## Called from a baked zOrder track: restacks the slots back to front. Slots
## it does not name (sockets, detached limbs' stand-ins) keep their place
## relative to the rest.
func _set_draw_order(names: Array) -> void:
	_reordered = true
	var index := 0
	for slot_name in names:
		var node: Node = _slots.get(StringName(slot_name))
		if node == null or node.get_parent() != self:
			continue
		move_child(node, index)
		index += 1


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
	var node: Node2D = _slot(name)
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
		var node: Node2D = _slot(StringName(slot_name))
		if node == null or not is_instance_valid(node):
			continue
		var where := node.transform
		var index := node.get_index()
		remove_child(node)
		freed.add_child(node)
		node.transform = where
		_slots.erase(StringName(node.name))
		# An empty stand-in keeps the name, so the rig's animations still
		# find a node to key and do not complain about the missing limb.
		var stand_in := RigSlot.new()
		stand_in.name = node.name
		stand_in.visible = false
		for picture in node.get_children():
			var blank := Node2D.new()
			blank.name = picture.name
			stand_in.add_child(blank)
		add_child(stand_in)
		move_child(stand_in, index)
	return freed


## A slot by the name the rig gives it. Node names cannot hold '/', ':' or
## '.', so a slot PopCap named with one is found under the cleaned name.
func _slot(name: StringName) -> Node2D:
	return _slots.get(StringName(String(name).validate_node_name()))


func slot_names() -> Array:
	var names := _slots.keys()
	names.sort()
	return names
