class_name ArmatureBaker
extends RefCounted
## Converts one DragonBones armature into Godot's own animation system.
##
## This runs ONCE per armature and never again: everything DragonBones does
## differently from Godot is resolved here, at conversion time, so that
## playback is `AnimationPlayer.play()` and nothing else. Easing, blending,
## interpolation and timing are then the engine's problem rather than ours.
##
## Five things have to be resolved, and all five are why a bone tree of
## Node2Ds cannot simply be handed to Godot:
##
## 1. A transform is built from TWO skew angles. skX and skY are equal for a
##    rotation; where they differ they describe a mirror or a shear, which
##    Godot expresses as `skew` - the peashooter's stem is one.
## 2. A bone can refuse its parent's rotation or scale. The basic zombie's
##    head refuses both. Godot's node tree has no equivalent, so the chain is
##    resolved here and the sprites come out flat - every one a direct child,
##    which is also cheaper to transform.
## 3. Limbs are posed by IK. A zombie's shin and forearm are not keyed at all:
##    the rig keys where the foot and hand should be, and a two-bone solver
##    bends the knee or elbow to reach. Without it the legs come apart.
## 4. Slots are animated as well as bones. A slot swaps which picture it shows
##    (an eye blinking, a mouth opening, a plant food helmet appearing) and
##    fades in and out, so both are baked alongside the transforms.
## 5. Frames carry their own easing, as a cubic bezier or an easing factor.
##    Sampling at the source frame rate bakes that in, so Godot's linear
##    interpolation between samples reproduces it exactly.
##
## The rules below follow the DragonBones 5.x runtime, which is what PVZGE
## plays these rigs with; where the editor and the runtime disagree the
## runtime wins, because that is what the original game shows.

## Each: {name, parent, raw, length, inherit_rotation, inherit_scale}
var bones: Array[Dictionary] = []
var bone_index: Dictionary = {}
## Each: {name, bone, displays: [{region, xform} or {}], display (rest index),
##        color (rest Color), blend, socket}
var slots: Array[Dictionary] = []
var slot_index: Dictionary = {}
## Each: {name, bone, root, target, chain, bend, weight}
var iks: Array[Dictionary] = []

var frame_rate: float = 30.0

var _armature: Dictionary = {}
var _sockets: Dictionary = {}
## bone index -> the IK constraints rooted on it, solved as soon as it is.
var _ik_by_root: Dictionary = {}
## What any animation in the rig touches, so every animation can key the
## same set and none inherits a pose another left behind.
var _moving_slots: Array = []
var _display_slots: Array = []
var _color_slots: Array = []


## `sockets` maps a game-facing name to a bone - {"armor": "armorSOCKET"} -
## and each becomes a marker node animated like any slot, so the game can ask
## where a rig's mouth is at this instant without sampling anything itself.
func _init(source: ArmatureSet, armature_name: StringName,
		sockets: Dictionary = {}) -> void:
	_sockets = sockets
	_armature = source.armature(armature_name)
	frame_rate = float(_armature.get("frameRate", source.frame_rate))
	if frame_rate <= 0.0:
		frame_rate = source.frame_rate
	_read_bones()
	_read_iks()
	# The set is only asked which pictures exist, and not kept: it holds
	# this baker in turn, and the pair would never be freed.
	_read_slots(source)
	_find_animated()


# --- reading -------------------------------------------------------------

func _read_bones() -> void:
	var raw := _armature.get("bone", []) as Array
	# An IK constraint reads its target's position, so the target has to be
	# composed before the bones it bends - treat it as one more parent.
	var waits_for := {}
	for entry in (_armature.get("ik", []) as Array):
		if not (entry is Dictionary):
			continue
		var bent := String(entry.get("bone", ""))
		var root := bent
		if int(entry.get("chain", 0)) > 0:
			for b in raw:
				if b is Dictionary and String(b.get("name", "")) == bent:
					root = String(b.get("parent", bent))
		waits_for[root] = String(entry.get("target", ""))

	# Parents first, so one pass composes the whole skeleton. The export is
	# usually already ordered, but a child declared early would otherwise
	# compose against a stale parent.
	var ordered: Array = []
	var placed := {}
	var pending := raw.duplicate()
	while not pending.is_empty():
		var progressed := false
		var still: Array = []
		for entry in pending:
			if not (entry is Dictionary):
				continue
			var name := String(entry.get("name", ""))
			var parent := String(entry.get("parent", ""))
			var target := String(waits_for.get(name, ""))
			if (parent == "" or placed.has(parent)) \
					and (target == "" or placed.has(target)):
				ordered.append(entry)
				placed[name] = true
				progressed = true
			else:
				still.append(entry)
		pending = still
		if not progressed:
			for entry in pending:
				if entry is Dictionary:
					ordered.append(entry)
			break

	for entry in ordered:
		var name := StringName(entry.get("name", ""))
		if name == &"":
			continue
		bone_index[name] = bones.size()
		bones.append({
			"name": name,
			"parent": int(bone_index.get(StringName(entry.get("parent", "")), -1)),
			"raw": entry.get("transform", {}) if entry.get("transform") is Dictionary else {},
			"length": float(entry.get("length", 0.0)),
			"inherit_rotation": bool(entry.get("inheritRotation", true)),
			"inherit_scale": bool(entry.get("inheritScale", true)),
		})


func _read_iks() -> void:
	for entry in (_armature.get("ik", []) as Array):
		if not (entry is Dictionary):
			continue
		var bone := int(bone_index.get(StringName(entry.get("bone", "")), -1))
		var target := int(bone_index.get(StringName(entry.get("target", "")), -1))
		if bone < 0 or target < 0:
			continue
		var chain := int(entry.get("chain", 0))
		var root := bone
		if chain > 0:
			root = bones[bone]["parent"]
			if root < 0:
				continue
		var ik := {
			"name": StringName(entry.get("name", "")),
			"bone": bone,
			"root": root,
			"target": target,
			"chain": chain,
			"bend": bool(entry.get("bendPositive", true)),
			"weight": float(entry.get("weight", 1.0)),
		}
		iks.append(ik)
		if not _ik_by_root.has(root):
			_ik_by_root[root] = []
		(_ik_by_root[root] as Array).append(iks.size() - 1)


func _read_slots(source: ArmatureSet) -> void:
	var skins := _armature.get("skin", []) as Array
	var displays := {}
	if not skins.is_empty():
		for entry in ((skins[0] as Dictionary).get("slot", []) as Array):
			if entry is Dictionary:
				displays[StringName(entry.get("name", ""))] = entry

	# Declaration order is draw order, so each slot goes in front of the last.
	for entry in (_armature.get("slot", []) as Array):
		if not (entry is Dictionary):
			continue
		var name := StringName(entry.get("name", ""))
		var options := (displays.get(name, {}) as Dictionary).get("display", []) as Array
		# Every display the slot can switch to, not just the one it starts
		# on: a blink is the eye slot moving to its second picture, and a
		# slot hidden at rest (index -1) is often the one an animation shows.
		var choices: Array = []
		var any := false
		for display in options:
			var choice := {}
			if display is Dictionary:
				# `name` names the display; `path` names the texture when
				# they differ, which is how one slot carries both mouth and
				# mouth_open.
				var region := StringName(display.get("path", display.get("name", "")))
				if source.region(region) != null:
					choice = {"region": region, "xform": matrix_of(display.get("transform", {}))}
					any = true
			choices.append(choice)
		if not any:
			continue
		slot_index[name] = slots.size()
		slots.append({
			"name": name,
			"bone": int(bone_index.get(StringName(entry.get("parent", "")), -1)),
			"displays": choices,
			"display": int(entry.get("displayIndex", 0)),
			"color": color_of(entry.get("color", {})),
			"blend": String(entry.get("blendMode", "normal")),
		})

	# Sockets ride along as slots with nothing to draw.
	for alias in _sockets:
		var bone := int(bone_index.get(StringName(_sockets[alias]), -1))
		if bone < 0:
			push_warning("armature: no bone '%s' for socket '%s'"
					% [_sockets[alias], alias])
			continue
		slots.append({
			"name": StringName("socket_%s" % alias),
			"bone": bone,
			"displays": [],
			"display": -1,
			"color": Color.WHITE,
			"blend": "normal",
			"socket": StringName(alias),
		})


## Which slots any animation moves, swaps or tints.
##
## Every animation keys all of them, the untouched ones at rest. DragonBones
## resets a part an animation does not mention to its setup pose; Godot
## leaves it wherever the last animation put it, so a zombie that ate and
## then walked kept its eating arms.
func _find_animated() -> void:
	var driven := {}
	var displayed := {}
	var tinted := {}
	for entry in (_armature.get("animation", []) as Array):
		if not (entry is Dictionary):
			continue
		for timeline in (entry.get("bone", []) as Array):
			if timeline is Dictionary:
				var index := int(bone_index.get(StringName(timeline.get("name", "")), -1))
				if index >= 0:
					driven[index] = true
		for timeline in (entry.get("slot", []) as Array):
			if not (timeline is Dictionary):
				continue
			var name := StringName(timeline.get("name", ""))
			if not slot_index.has(name):
				continue
			if not (timeline.get("displayFrame", []) as Array).is_empty():
				displayed[slot_index[name]] = true
			if not (timeline.get("colorFrame", []) as Array).is_empty():
				tinted[slot_index[name]] = true
	# An IK chain moves whenever its target does, and the target is usually
	# what the animation keys.
	for ik in iks:
		driven[ik["root"]] = true
		driven[ik["bone"]] = true
	# A driven bone moves everything under it.
	for i in bones.size():
		var parent: int = bones[i]["parent"]
		if parent >= 0 and driven.has(parent):
			driven[i] = true
	for i in slots.size():
		if driven.has(int(slots[i]["bone"])):
			_moving_slots.append(i)
	_display_slots = displayed.keys()
	_display_slots.sort()
	_color_slots = tinted.keys()
	_color_slots.sort()


# --- DragonBones transform rules ----------------------------------------

## The matrix DragonBones builds from one transform. Two skew angles, not one
## rotation: the X axis comes from skY and the Y axis from skX, so equal
## angles give a rotation and unequal ones a mirror or a shear. A missing
## angle is zero, as the runtime reads it.
static func matrix_of(raw: Variant, offset: Dictionary = {}) -> Transform2D:
	return _matrix(_parts(raw, offset))


## A transform as the runtime holds it: a rotation (skY), a skew on top of it
## (skX - skY), a scale and a position, with the animation's offset applied -
## rotation and position add, scale multiplies.
static func _parts(raw: Variant, offset: Dictionary = {}) -> Dictionary:
	var t: Dictionary = raw if raw is Dictionary else {}
	var sk_x := deg_to_rad(float(t.get("skX", 0.0)))
	var sk_y := deg_to_rad(float(t.get("skY", 0.0)))
	var parts := {
		"pos": Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0))),
		"rot": sk_y,
		"skew": sk_x - sk_y,
		"scale": Vector2(float(t.get("scX", 1.0)), float(t.get("scY", 1.0))),
	}
	if not offset.is_empty():
		parts["pos"] += offset["pos"] as Vector2
		parts["rot"] += deg_to_rad(float(offset["rot"]))
		parts["scale"] *= offset["scale"] as Vector2
	return parts


## `Transform.toMatrix` in the runtime.
static func _matrix(parts: Dictionary) -> Transform2D:
	var rot: float = parts["rot"]
	var turn: float = rot + float(parts["skew"])
	var size: Vector2 = parts["scale"]
	return Transform2D(
			Vector2(cos(rot) * size.x, sin(rot) * size.x),
			Vector2(-sin(turn) * size.y, cos(turn) * size.y),
			parts["pos"])


## A slot's colour transform as a Godot modulate. DragonBones states each
## channel as a percentage multiplier; the additive offsets PopCap never uses.
static func color_of(raw: Variant) -> Color:
	var c: Dictionary = raw if raw is Dictionary else {}
	return Color(float(c.get("rM", 100.0)) / 100.0,
			float(c.get("gM", 100.0)) / 100.0,
			float(c.get("bM", 100.0)) / 100.0,
			float(c.get("aM", 100.0)) / 100.0)


## A bone can opt out of its parent's rotation or scale, and several do: the
## basic zombie's head sets both false, so it keeps its own size and angle
## however the body leans. Position always inherits - that is what a skeleton
## is for. This is `Bone._updateGlobalTransformMatrix` from the runtime, rule
## for rule, because the shortcuts all go wrong somewhere visible:
##
## - Refusing only rotation still takes the parent's whole matrix, skew and
##   all; the bone's own angle is just measured against the parent's.
## - Refusing only scale under a mirrored parent mirrors the bone's own angle
##   and flips its skew. The peashooter's stem is mirrored, and its neck hangs
##   off it this way - get this wrong and the neck points the other way.
static func inherit(parent: Transform2D, parts: Dictionary,
		rot: bool, size: bool) -> Transform2D:
	var local := parts.duplicate()
	var parent_angle := parent.x.angle()
	if size:
		if not rot:
			local["rot"] = float(local["rot"]) - parent_angle
		return parent * _matrix(local)
	var origin := parent * (local["pos"] as Vector2)
	if rot:
		var own: float = local["rot"]
		var turned := own + parent_angle
		if parent.determinant() < 0.0:
			turned -= own * 2.0
			local["skew"] = float(local["skew"]) + PI
		local["rot"] = turned
	var out := _matrix(local)
	out.origin = origin
	return out


## Composes every bone at one moment. `offsets` is the animation's
## contribution per bone index, empty for the setup pose; `ik_state` maps a
## constraint's index to {weight, bend} where an animation keys them.
func world_at(offsets: Dictionary, ik_state: Dictionary = {}) -> Array[Transform2D]:
	var out: Array[Transform2D] = []
	out.resize(bones.size())
	var done := {}
	for i in bones.size():
		if done.has(i):
			continue
		out[i] = _compose(i, out, offsets)
		done[i] = true
		for which in (_ik_by_root.get(i, []) as Array):
			var ik: Dictionary = iks[which]
			var state: Dictionary = ik_state.get(which, ik)
			var weight := float(state.get("weight", 1.0))
			var bent: int = ik["bone"]
			if int(ik["chain"]) > 0:
				# The bent bone hangs off the root just solved, so compose it
				# now, solve both together, and leave its children to compose
				# against the solved result.
				out[bent] = _compose(bent, out, offsets)
				done[bent] = true
			if weight <= 0.0:
				continue
			if int(ik["chain"]) > 0:
				_solve_two(ik, bool(state.get("bend", true)), weight, out)
			else:
				_solve_one(ik, weight, out)
	return out


func _compose(i: int, world: Array[Transform2D], offsets: Dictionary) -> Transform2D:
	var bone: Dictionary = bones[i]
	var parts := _parts(bone["raw"], offsets.get(i, {}))
	var parent: int = bone["parent"]
	if parent < 0:
		return _matrix(parts)
	return inherit(world[parent], parts, bone["inherit_rotation"], bone["inherit_scale"])


## Turns a bone's whole basis to face `angle`, keeping its scale and skew,
## which is what the runtime's rotation-then-toMatrix amounts to.
static func _turned(xform: Transform2D, angle: float) -> Transform2D:
	var by := wrapf(angle - xform.x.angle(), -PI, PI)
	return Transform2D(xform.x.rotated(by), xform.y.rotated(by), xform.origin)


## One-bone IK: aim the bone at its target.
func _solve_one(ik: Dictionary, weight: float, world: Array[Transform2D]) -> void:
	var root: int = ik["root"]
	var g := world[root]
	var aim := (world[ik["target"]].origin - g.origin).angle()
	var now := g.x.angle()
	world[root] = _turned(g, now + wrapf(aim - now, -PI, PI) * weight)


## Two-bone IK, the DragonBones solver: the root swings so the joint lands on
## one of the two circle intersections, `bend` picks which, and the bent bone
## then aims at the target. Out of reach, the chain straightens toward it.
func _solve_two(ik: Dictionary, bend: bool, weight: float,
		world: Array[Transform2D]) -> void:
	var root: int = ik["root"]
	var bent: int = ik["bone"]
	var parent := world[root]
	var g := world[bent]
	var target := world[ik["target"]].origin

	var reach := (g.x * float(bones[bent]["length"])).length()
	var to_joint := g.origin - parent.origin
	var upper := to_joint.length()
	var raw_bent := g.x.angle()
	var raw_root := parent.x.angle()
	var raw_a := to_joint.angle()
	var to_target := target - parent.origin
	var span := to_target.length()

	var angle_a := 0.0
	if reach + upper <= span or span + reach <= upper or span + upper <= reach \
			or span <= 0.0:
		angle_a = to_target.angle()
		if not (reach + upper <= span) and upper < reach:
			angle_a += PI
	else:
		var h := (upper * upper - reach * reach + span * span) / (2.0 * span * span)
		var r := sqrt(maxf(upper * upper - h * h * span * span, 0.0)) / span
		var foot := parent.origin + to_target * h
		var side := Vector2(-to_target.y * r, to_target.x * r)
		# A mirrored grandparent flips which way "positive" bends.
		var mirrored := false
		var above: int = bones[root]["parent"]
		if above >= 0:
			mirrored = world[above].x.cross(world[above].y) < 0.0
		var joint := foot - side if mirrored != bend else foot + side
		angle_a = (joint - parent.origin).angle()

	var swing := wrapf(angle_a - raw_a, -PI, PI)
	world[root] = _turned(parent, raw_root + swing * weight)
	var at := parent.origin + Vector2.from_angle(raw_a + swing * weight) * upper
	var aim := (target - at).angle()
	var turned := _turned(g, raw_bent + swing * weight
			+ wrapf(aim - swing - raw_bent, -PI, PI) * weight)
	turned.origin = at
	world[bent] = turned


# --- baking to Godot animations -----------------------------------------

## Properties Godot needs to reproduce a Transform2D exactly.
const TRACKS := ["position", "rotation", "scale", "skew"]


## The setup pose: each slot's bone transform, which is also what a slot
## keeps when nothing animates it.
func rest_transforms() -> Array[Transform2D]:
	var world := world_at({})
	var out: Array[Transform2D] = []
	for slot in slots:
		var bone: int = slot["bone"]
		out.append(world[bone] if bone >= 0 else Transform2D.IDENTITY)
	return out


## Bakes every animation into Godot `Animation` resources.
##
## Sampling at the source frame rate rather than copying keyframes is what
## lets the easing go: a frame's cubic bezier is already in the sampled
## values, so Godot's linear interpolation between samples reproduces it.
## Keys that repeat are dropped.
func bake_animations() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for entry in (_armature.get("animation", []) as Array):
		if not (entry is Dictionary and entry.has("name")):
			continue
		var animation := _bake_one(entry)
		if animation != null:
			library.add_animation(StringName(entry["name"]), animation)
	return library


func _bake_one(source: Dictionary) -> Animation:
	# A zero-length animation is a pose, not a mistake: lawn and UI rigs
	# switch state by playing one that only sets which pictures show. It
	# bakes as a single sample held for one frame.
	var frames := maxi(int(source.get("duration", 0)), 0)
	var bone_lines := _read_bone_timelines(source)
	var slot_lines := _read_slot_timelines(source)
	var ik_lines := _read_ik_timelines(source)

	var animation := Animation.new()
	animation.length = float(maxi(frames, 1)) / frame_rate
	animation.step = 1.0 / frame_rate

	var sampled: Array = []
	for frame in range(frames + 1):
		var time := float(frame) / frame_rate
		var offsets := {}
		for index in bone_lines:
			offsets[index] = _offset_at(bone_lines[index], time)
		var ik_state := {}
		for index in ik_lines:
			var line: Dictionary = ik_lines[index]
			ik_state[index] = {
				"weight": _sample(line["weight"], time, 1.0),
				"bend": _sample(line["bend"], time, true),
			}
		var world := world_at(offsets, ik_state)
		var row: Array = []
		for slot in slots:
			var bone: int = slot["bone"]
			row.append(world[bone] if bone >= 0 else Transform2D.IDENTITY)
		sampled.append(row)

	for slot_index_ in _moving_slots:
		var name: StringName = slots[slot_index_]["name"]
		for property in TRACKS:
			var values: Array = []
			for row in sampled:
				values.append(_component(row[slot_index_], property))
			_add_track(animation, "%s:%s" % [node_name(name), property], values)

	for index in _display_slots:
		var slot: Dictionary = slots[index]
		var line: Array = (slot_lines.get(index, {}) as Dictionary).get("display", [])
		var shown: Array = []
		for frame in range(frames + 1):
			shown.append(int(_sample(line, float(frame) / frame_rate, slot["display"])))
		for choice in (slot["displays"] as Array).size():
			if (slot["displays"][choice] as Dictionary).is_empty():
				continue
			var values: Array = []
			for value in shown:
				values.append(value == choice)
			_add_discrete(animation, "%s/%d:visible" % [node_name(slot["name"]), choice], values)

	for index in _color_slots:
		var slot: Dictionary = slots[index]
		var line: Array = (slot_lines.get(index, {}) as Dictionary).get("color", [])
		var values: Array = []
		for frame in range(frames + 1):
			values.append(_sample(line, float(frame) / frame_rate, slot["color"]))
		_add_track(animation, "%s:modulate" % node_name(slot["name"]), values)

	_add_events(animation, source)
	_measure_ground(animation, source, frames)
	return animation


## How far a walk carries the rig, in its own units per second.
##
## PopCap walks are cycles in place with one bone that slides the whole body
## forward at a constant rate - the basic zombie's `zombie` bone travels
## 129.9 across its 90 frames - while the planted foot counter-slides by the
## same amount. That rate is the speed the art was drawn to walk at, so
## matching playback to the entity's real speed keeps the feet planted
## instead of skating.
func _measure_ground(animation: Animation, source: Dictionary, frames: int) -> void:
	for entry in (source.get("bone", []) as Array):
		if not (entry is Dictionary):
			continue
		var line := entry.get("translateFrame", []) as Array
		if line.size() != 2 or not (line[0] is Dictionary and line[1] is Dictionary):
			continue
		var first: Dictionary = line[0]
		var last: Dictionary = line[1]
		if int(first.get("duration", 0)) != frames \
				or float(first.get("tweenEasing", NAN)) != 0.0 \
				or not is_zero_approx(float(first.get("x", 0.0))):
			continue
		var travel := absf(float(last.get("x", 0.0)))
		if travel > 1.0:
			animation.set_meta(&"ground_speed", travel / animation.length)
			return


## A rig says when it does the thing: the peashooter's Shoot animation carries
## a "Shoot" event fifteen frames in, which is when the pea actually leaves
## its mouth. Baking those as method tracks lets Godot fire them, so the game
## spawns the pea on the frame the art throws it rather than on the frame the
## animation started. A frame's `sound` goes out the same way, as its own
## call, so audio can follow the art without the art knowing about audio.
func _add_events(animation: Animation, source: Dictionary) -> void:
	var at := 0.0
	var track := -1
	for frame in (source.get("frame", []) as Array):
		if not (frame is Dictionary):
			continue
		var calls: Array = []
		for event in (frame.get("events", []) as Array):
			if event is Dictionary and event.has("name"):
				calls.append({"method": &"_fire_event", "args": [StringName(event["name"])]})
		if frame.has("event"):
			calls.append({"method": &"_fire_event", "args": [StringName(frame["event"])]})
		if frame.has("sound"):
			calls.append({"method": &"_fire_sound", "args": [StringName(frame["sound"])]})
		for call in calls:
			# One track per call: a method track holds one key per instant,
			# and the peashooter fires two events on the same frame.
			track = animation.add_track(Animation.TYPE_METHOD)
			animation.track_set_path(track, NodePath("."))
			animation.track_insert_key(track, minf(at / frame_rate, animation.length), call)
		at += float(frame.get("duration", 1))


## Writes one property's samples as a track, keeping only the keys that
## matter: a value that differs from its neighbour on either side. A held
## value keeps the key before it changes, so a hold stays a hold.
##
## A track whose value never changes still gets its single key. Dropping it
## entirely leaves the part wherever the previous animation left it.
func _add_track(animation: Animation, path: String, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	# Rotation wraps at +-PI, and a mirrored part sits right on that seam;
	# plain linear interpolation would spin it the long way round. Every
	# rotation track uses the same mode, constant ones included, or Godot
	# cannot blend one animation into the next consistently.
	animation.track_set_interpolation_type(track,
			Animation.INTERPOLATION_LINEAR_ANGLE if path.ends_with(":rotation")
			else Animation.INTERPOLATION_LINEAR)
	for i in values.size():
		var keep := i == 0
		if not keep and i < values.size() - 1:
			keep = not _same(values[i], values[i - 1]) \
					or not _same(values[i], values[i + 1])
		elif not keep:
			keep = not _same(values[i], values[i - 1])
		if keep:
			animation.track_insert_key(track, float(i) / frame_rate, values[i])


## The node a slot becomes. Slot names are free text and some carry a path
## separator (the sun's "sun/sun_changing"), which Godot strips from a node
## name; a track keyed on the raw name would then point at nothing.
static func node_name(slot_name: String) -> String:
	return slot_name.validate_node_name()


## A track that switches rather than blends: which picture a slot shows.
func _add_discrete(animation: Animation, path: String, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	for i in values.size():
		if i == 0 or values[i] != values[i - 1]:
			animation.track_insert_key(track, float(i) / frame_rate, values[i])


func _same(a: Variant, b: Variant) -> bool:
	if a is Vector2:
		return (a as Vector2).is_equal_approx(b)
	if a is Color:
		return (a as Color).is_equal_approx(b)
	return is_equal_approx(float(a), float(b))


func _component(xform: Transform2D, property: String) -> Variant:
	match property:
		"position": return xform.origin
		"rotation": return xform.get_rotation()
		"scale": return xform.get_scale()
		"skew": return xform.get_skew()
	return 0.0


# --- timelines ------------------------------------------------------------

func _read_bone_timelines(source: Dictionary) -> Dictionary:
	var out := {}
	for entry in (source.get("bone", []) as Array):
		if not (entry is Dictionary):
			continue
		var index := int(bone_index.get(StringName(entry.get("name", "")), -1))
		if index < 0:
			continue
		out[index] = {
			"translate": _timeline(entry.get("translateFrame", []),
					func(f: Dictionary) -> Variant:
						return Vector2(float(f.get("x", 0.0)), float(f.get("y", 0.0)))),
			# The rotation key is `rotate`, not `angle`.
			"rotate": _rotation_timeline(entry.get("rotateFrame", [])),
			"scale": _timeline(entry.get("scaleFrame", []),
					func(f: Dictionary) -> Variant:
						return Vector2(float(f.get("x", 1.0)), float(f.get("y", 1.0)))),
		}
	return out


func _read_slot_timelines(source: Dictionary) -> Dictionary:
	var out := {}
	for entry in (source.get("slot", []) as Array):
		if not (entry is Dictionary):
			continue
		var index := int(slot_index.get(StringName(entry.get("name", "")), -1))
		if index < 0:
			continue
		out[index] = {
			# A display frame names a picture and never tweens; -1 hides.
			"display": _timeline(entry.get("displayFrame", []),
					func(f: Dictionary) -> Variant: return int(f.get("value", 0)),
					false),
			"color": _timeline(entry.get("colorFrame", []),
					func(f: Dictionary) -> Variant: return color_of(f.get("value", {}))),
		}
	return out


## IK keys say how hard the solver pulls and which way the joint bends. A
## frame that omits either means the default - full weight, bending positive
## - not the constraint's own setting, which is how the runtime reads them.
func _read_ik_timelines(source: Dictionary) -> Dictionary:
	var out := {}
	for entry in (source.get("ik", []) as Array):
		if not (entry is Dictionary):
			continue
		var name := StringName(entry.get("name", ""))
		for i in iks.size():
			if iks[i]["name"] != name:
				continue
			var frames: Variant = entry.get("frame", [])
			out[i] = {
				"weight": _timeline(frames,
						func(f: Dictionary) -> Variant: return float(f.get("weight", 1.0))),
				"bend": _timeline(frames,
						func(f: Dictionary) -> Variant: return bool(f.get("bendPositive", true)),
						false),
			}
	return out


## Reads a timeline's keyframes. Each one tweens into the next by its own
## curve - a cubic bezier's two control points, or a `tweenEasing` factor -
## and a frame with neither holds its value, which DragonBones uses for
## switches like a hand vanishing for a few frames.
func _timeline(frames: Variant, read: Callable, tweens: bool = true) -> Array:
	var out: Array = []
	if not (frames is Array):
		return out
	var at := 0.0
	for frame in (frames as Array):
		if not (frame is Dictionary):
			continue
		var curve: Variant = frame.get("curve")
		out.append({
			"time": at / frame_rate,
			"value": read.call(frame),
			"curve": curve if tweens and curve is Array and (curve as Array).size() == 4 else null,
			"tween": float(frame["tweenEasing"]) if tweens and frame.has("tweenEasing") else NAN,
		})
		at += float(frame.get("duration", 1))
	return out


## Rotation keys, unwrapped the way the runtime unwraps them: each key turns
## the short way from the one before, unless the frame before says how many
## whole turns to make (`clockwise`). Read raw, -170 after 170 would spin a
## part almost a full circle backwards.
func _rotation_timeline(frames: Variant) -> Array:
	var out := _timeline(frames,
			func(f: Dictionary) -> Variant: return float(f.get("rotate", 0.0)))
	if not (frames is Array):
		return out
	var raw: Array = []
	for frame in (frames as Array):
		if frame is Dictionary:
			raw.append(frame)
	var previous := 0.0
	var turns := 0.0
	for i in out.size():
		var value := float(out[i]["value"])
		if i > 0:
			if turns == 0.0:
				value = previous + wrapf(value - previous, -180.0, 180.0)
			else:
				if (value >= previous) if turns > 0.0 else (value <= previous):
					turns += -1.0 if turns > 0.0 else 1.0
				value = value + 360.0 * turns
		turns = float((raw[i] as Dictionary).get("clockwise", 0.0))
		previous = value
		out[i]["value"] = value
	return out


func _offset_at(timeline: Dictionary, time: float) -> Dictionary:
	return {
		"pos": _sample(timeline["translate"], time, Vector2.ZERO),
		"rot": _sample(timeline["rotate"], time, 0.0),
		"scale": _sample(timeline["scale"], time, Vector2.ONE),
	}


func _sample(track: Array, time: float, fallback: Variant) -> Variant:
	if track.is_empty():
		return fallback
	var first: Dictionary = track[0]
	if time <= float(first["time"]) or track.size() == 1:
		return first["value"]
	for i in range(track.size() - 1):
		var a: Dictionary = track[i]
		var b: Dictionary = track[i + 1]
		var ta := float(a["time"])
		var tb := float(b["time"])
		if time < tb:
			var t: float = 0.0 if tb <= ta else (time - ta) / (tb - ta)
			t = _ease(a, t)
			if t <= 0.0:
				return a["value"]
			var from: Variant = a["value"]
			var to: Variant = b["value"]
			if from is Color:
				return (from as Color).lerp(to, t)
			if from is Vector2:
				return (from as Vector2).lerp(to, t)
			if from is float:
				return lerpf(from, float(to), t)
			return from
	return (track[track.size() - 1] as Dictionary)["value"]


## The runtime's easing: 0 is linear, negative eases in, up to 1 eases out
## and above 1 eases in and out, each blended toward linear by how far the
## factor is from it. No factor and no curve holds the frame.
func _ease(frame: Dictionary, progress: float) -> float:
	var curve: Variant = frame.get("curve")
	if curve != null:
		return _bezier(curve as Array, progress)
	var tween: float = frame.get("tween", NAN)
	if is_nan(tween):
		return 0.0      # no tween: hold this frame's value
	if is_zero_approx(tween):
		return progress
	var eased := progress
	var amount := tween
	if tween < 0.0:
		eased = progress * progress
		amount = -tween
	elif tween <= 1.0:
		eased = 1.0 - (1.0 - progress) * (1.0 - progress)
	else:
		eased = 0.5 * (1.0 - cos(progress * PI))
		amount = tween - 1.0
	return (eased - progress) * amount + progress


## Cubic bezier from (0,0) to (1,1). Solved for t by bisection: a handful of
## steps is exact enough for animation and has no trouble near flat tangents.
func _bezier(points: Array, x: float) -> float:
	var x1 := float(points[0])
	var y1 := float(points[1])
	var x2 := float(points[2])
	var y2 := float(points[3])
	var low := 0.0
	var high := 1.0
	var t := x
	for _i in 12:
		t = (low + high) * 0.5
		var u := 1.0 - t
		var at := 3.0 * u * u * t * x1 + 3.0 * u * t * t * x2 + t * t * t
		if at < x:
			low = t
		else:
			high = t
	var u2 := 1.0 - t
	return 3.0 * u2 * u2 * t * y1 + 3.0 * u2 * t * t * y2 + t * t * t
