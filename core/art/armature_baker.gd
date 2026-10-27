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
## Three display features ride on top, each following the Cocos DragonBones
## runtime PVZGE ships (`cocos-js/_virtual_cc-*.js`):
##
## - A slot can show another armature instead of a picture - a sunflower's
##   costume, a mower's wheels, a seed packet's cooldown. It becomes a nested
##   Armature that plays its default action, and follows the parent into any
##   animation it also has (`inheritAnimation`).
## - A slot can show a mesh, deformed per frame (FFD). It becomes a Polygon2D
##   whose `polygon` is keyed every frame. Weighted (skinned) meshes are not
##   supported and are skipped with a warning.
## - An animation can reorder slots (a zOrder timeline). It becomes a method
##   track that restacks the slot nodes on the frames the order changes.
##
## The rules below follow the DragonBones 5.x runtime, which is what PVZGE
## plays these rigs with; where the editor and the runtime disagree the
## runtime wins, because that is what the original game shows.

## Each: {name, parent, raw, length, inherit_rotation, inherit_scale}
var bones: Array[Dictionary] = []
var bone_index: Dictionary = {}
## Each: {name, bone, displays: [choice], display (rest index), color (rest
##        Color), blend, socket}. A choice is {} when there is nothing to draw,
##        {region, xform} for a picture, {armature, xform} for a nested rig, or
##        {region, xform, mesh: {vertices, uvs, triangles}} for a mesh.
var slots: Array[Dictionary] = []
var slot_index: Dictionary = {}
## Each: {name, bone, root, target, chain, bend, weight}
var iks: Array[Dictionary] = []

var frame_rate: float = 30.0

var _armature: Dictionary = {}
var _set: ArmatureSet = null
var _sockets: Dictionary = {}
## bone index -> the IK constraints rooted on it, solved as soon as it is.
var _ik_by_root: Dictionary = {}
## What any animation in the rig touches, so every animation can key the
## same set and none inherits a pose another left behind.
var _moving_slots: Array = []
var _display_slots: Array = []
var _color_slots: Array = []
## [slot index, display choice] of every mesh some animation deforms.
var _mesh_displays: Array = []
## Every slot the export declares, drawable or not, in declaration order: a
## zOrder frame counts slots by this index.
var _declared: Array = []
## Whether any animation reorders the slots.
var _reorders: bool = false


## `sockets` maps a game-facing name to a bone - {"armor": "armorSOCKET"} -
## and each becomes a marker node animated like any slot, so the game can ask
## where a rig's mouth is at this instant without sampling anything itself.
## Every bone PopCap named as a socket (`...SOCKET`) gets a marker whether
## asked for or not, so a baked scene carries all of them.
func _init(source: ArmatureSet, armature_name: StringName,
		sockets: Dictionary = {}) -> void:
	_set = source
	_sockets = sockets
	_armature = source.armature(armature_name)
	frame_rate = float(_armature.get("frameRate", source.frame_rate))
	if frame_rate <= 0.0:
		frame_rate = source.frame_rate
	_read_bones()
	_read_iks()
	_read_slots()
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


func _read_slots() -> void:
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
		_declared.append(name)
		var options := (displays.get(name, {}) as Dictionary).get("display", []) as Array
		# Every display the slot can switch to, not just the one it starts
		# on: a blink is the eye slot moving to its second picture, and a
		# slot hidden at rest (index -1) is often the one an animation shows.
		var choices: Array = []
		var any := false
		for display in options:
			var choice := _read_display(display, name)
			if not choice.is_empty():
				any = true
			choices.append(choice)
		if not any:
			continue
		slot_index[name] = slots.size()
		slots.append({
			# The node's name, which is what tracks address. Godot refuses
			# '/', ':' and '.' in one, and PopCap names a slot "sun/sun_changing".
			"name": StringName(String(name).validate_node_name()),
			"bone": int(bone_index.get(StringName(entry.get("parent", "")), -1)),
			"displays": choices,
			"display": int(entry.get("displayIndex", 0)),
			"color": color_of(entry.get("color", {})),
			"blend": String(entry.get("blendMode", "normal")),
		})

	# Sockets ride along as slots with nothing to draw, one per bone, named
	# by the bone so a scene baked once serves every caller.
	var wanted := {}
	for bone in bones:
		if String(bone["name"]).to_lower().ends_with("socket"):
			wanted[bone["name"]] = true
	for alias in _sockets:
		var bone_name := StringName(_sockets[alias])
		if not bone_index.has(bone_name):
			push_warning("armature: no bone '%s' for socket '%s'" % [bone_name, alias])
			continue
		wanted[bone_name] = true
	for bone_name in wanted:
		slots.append({
			"name": socket_node_name(bone_name),
			"bone": int(bone_index[bone_name]),
			"displays": [],
			"display": -1,
			"color": Color.WHITE,
			"blend": "normal",
			"socket": bone_name,
		})


## The marker node a socket bone becomes.
static func socket_node_name(bone: StringName) -> StringName:
	return StringName(("Socket_%s" % bone).validate_node_name())


## One display a slot can show, or {} when it has nothing drawable.
func _read_display(display: Variant, slot: StringName) -> Dictionary:
	if not (display is Dictionary):
		return {}
	var kind := String(display.get("type", "image"))
	var xform := matrix_of(display.get("transform", {}))
	# `name` names the display; `path` names what it shows when they differ,
	# which is how one slot carries both mouth and mouth_open.
	var path := StringName(display.get("path", display.get("name", "")))
	match kind:
		"armature":
			if _set.has_armature(path) and path != StringName(_armature.get("name", "")):
				return {"armature": path, "xform": xform, "name": StringName(display.get("name", ""))}
			return {}
		"mesh":
			if display.has("weights") or display.has("bonePose"):
				push_warning("armature: skinned mesh '%s' in slot '%s' is not supported"
						% [path, slot])
				return {}
			var region := _set.region(path)
			if region == null:
				return {}
			return {"region": path, "xform": xform, "name": StringName(display.get("name", "")),
					"mesh": _read_mesh(display, region)}
	if _set.region(path) == null:
		return {}
	return {"region": path, "xform": xform, "name": StringName(display.get("name", ""))}


## A mesh as Polygon2D wants it: vertices in slot space, UVs in pixels of the
## whole atlas page (a Polygon2D draws from its texture, not from a region),
## and the triangles.
func _read_mesh(display: Dictionary, region: AtlasTexture) -> Dictionary:
	var raw_vertices := display.get("vertices", []) as Array
	var raw_uvs := display.get("uvs", []) as Array
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var box := region.region
	for i in range(0, raw_vertices.size() - 1, 2):
		vertices.append(Vector2(float(raw_vertices[i]), float(raw_vertices[i + 1])))
		var u := float(raw_uvs[i]) if i < raw_uvs.size() else 0.0
		var v := float(raw_uvs[i + 1]) if i + 1 < raw_uvs.size() else 0.0
		uvs.append(box.position + Vector2(u, v) * box.size)
	var triangles := PackedInt32Array()
	for index in (display.get("triangles", []) as Array):
		triangles.append(int(index))
	return {"vertices": vertices, "uvs": uvs, "triangles": triangles}


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
	var deformed: Array = []
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
		for timeline in (entry.get("ffd", []) as Array):
			if not (timeline is Dictionary):
				continue
			var which := _mesh_choice(timeline)
			if not which.is_empty() and not deformed.has(which):
				deformed.append(which)
		if entry.get("zOrder") is Dictionary:
			_reorders = true
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
	_mesh_displays = deformed


## The [slot, choice] an FFD timeline deforms, or [] when it is not a mesh
## this rig draws. A timeline names its slot and the display by name.
func _mesh_choice(timeline: Dictionary) -> Array:
	var slot := int(slot_index.get(StringName(timeline.get("slot", "")), -1))
	if slot < 0:
		return []
	var display := StringName(timeline.get("name", ""))
	var choices: Array = slots[slot]["displays"]
	for choice in choices.size():
		var shown: Dictionary = choices[choice]
		if shown.has("mesh") and (display == &"" or shown.get("name") == display
				or shown.get("region") == display):
			return [slot, choice]
	return []


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
			_add_track(animation, "%s:%s" % [name, property], values)

	for index in _display_slots:
		var slot: Dictionary = slots[index]
		var line: Array = (slot_lines.get(index, {}) as Dictionary).get("display", [])
		var shown: Array = []
		for frame in range(frames + 1):
			shown.append(int(_sample(line, float(frame) / frame_rate, slot["display"])))
		_add_discrete(animation, "%s:display" % slot["name"], shown)

	for index in _color_slots:
		var slot: Dictionary = slots[index]
		var line: Array = (slot_lines.get(index, {}) as Dictionary).get("color", [])
		var values: Array = []
		for frame in range(frames + 1):
			values.append(_sample(line, float(frame) / frame_rate, slot["color"]))
		_add_track(animation, "%s:modulate" % slot["name"], values)

	var deforms := _read_ffd_timelines(source)
	for which in _mesh_displays:
		var slot: Dictionary = slots[which[0]]
		var rest: PackedVector2Array = slot["displays"][which[1]]["mesh"]["vertices"]
		var line: Array = deforms.get(which, [])
		var values: Array = []
		for frame in range(frames + 1):
			values.append(_deformed(rest, _sample(line, float(frame) / frame_rate,
					PackedFloat32Array())))
		_add_track(animation, "%s/%d:polygon" % [slot["name"], which[1]], values)

	if _reorders:
		_add_draw_order(animation, source)
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


## A mesh's vertices with one frame's FFD offsets added. DragonBones keys
## deformation as offsets from the rest mesh, x and y interleaved.
static func _deformed(rest: PackedVector2Array, offsets: PackedFloat32Array) -> PackedVector2Array:
	var out := rest.duplicate()
	for i in out.size():
		if i * 2 + 1 < offsets.size():
			out[i] += Vector2(offsets[i * 2], offsets[i * 2 + 1])
	return out


## Bakes a zOrder timeline as calls that restack the slots, on each frame
## the order changes. Every animation of a rig that reorders anywhere starts
## with the order it wants - the declared one if it has no timeline - so an
## order never leaks from one animation into the next. This is
## `ZOrderTimelineState` and `Armature._sortZOrder` from the runtime.
func _add_draw_order(animation: Animation, source: Dictionary) -> void:
	var track := animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(track, NodePath("."))
	var line: Variant = source.get("zOrder")
	var frames: Array = (line as Dictionary).get("frame", []) if line is Dictionary else []
	var at := 0.0
	var last: Array = []
	var keyed_start := false
	for frame in frames:
		if not (frame is Dictionary):
			continue
		var order := _draw_order(frame.get("zOrder", []))
		if order != last or not keyed_start:
			animation.track_insert_key(track, minf(at / frame_rate, animation.length),
					{"method": &"_set_draw_order", "args": [order]})
			last = order
			keyed_start = true
		at += float(frame.get("duration", 1))
	if not keyed_start:
		animation.track_insert_key(track, 0.0,
				{"method": &"_set_draw_order", "args": [_draw_order([])]})


## One zOrder frame as the names of the drawn slots, back to front.
func _draw_order(pairs: Variant) -> Array:
	var names: Array = []
	for i in _draw_order_of(_declared, pairs):
		var name: StringName = _declared[i]
		if slot_index.has(name):
			names.append(slots[slot_index[name]]["name"])
	return names


## The order of `declared` slots, as indices, after one zOrder frame. The
## frame lists pairs of (declared slot index, how many places it moves);
## slots not named keep their relative order around the moved ones. This is
## `_parseZOrderFrame` from the runtime.
static func _draw_order_of(declared: Array, pairs: Variant) -> Array:
	var count := declared.size()
	var order: Array = []
	if not (pairs is Array) or (pairs as Array).is_empty():
		for i in count:
			order.append(i)
		return order
	var moves := pairs as Array
	order.resize(count)
	order.fill(-1)
	var rest: Array = []
	var cursor := 0
	for i in range(0, moves.size() - 1, 2):
		var slot := int(moves[i])
		var shift := int(moves[i + 1])
		while cursor != slot and cursor < count:
			rest.append(cursor)
			cursor += 1
		if cursor + shift >= 0 and cursor + shift < count:
			order[cursor + shift] = cursor
		cursor += 1
	while cursor < count:
		rest.append(cursor)
		cursor += 1
	var from_rest := rest.size()
	for i in range(count - 1, -1, -1):
		if order[i] == -1:
			from_rest -= 1
			order[i] = rest[from_rest] if from_rest >= 0 else 0
	return order


## How far a dropped key may sit from the line its neighbours draw, per
## property: a hundredth of a rig unit, a few hundredths of a degree. Below
## anything a screen shows at the 0.512 the lawn draws rigs at, and it keeps
## a baked rig small enough to commit - most of a walk is straight lines
## between DragonBones' own keys.
const TOLERANCE := {
	"position": 0.01,
	"rotation": 0.0005,
	"scale": 0.0005,
	"skew": 0.0005,
	"modulate": 0.002,
}


## Writes one property's samples as a track, keeping only the keys linear
## interpolation cannot reproduce: a run of samples that lies on the line
## between its ends, to within TOLERANCE, keeps just the ends. A hold stays a
## hold, since a flat run is a line too.
##
## A track whose value never changes still gets its single key. Dropping it
## entirely leaves the part wherever the previous animation left it.
func _add_track(animation: Animation, path: String, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	var property := path.get_slice(":", 1)
	var angle := property == "rotation"
	# Rotation wraps at +-PI, and a mirrored part sits right on that seam;
	# plain linear interpolation would spin it the long way round. Every
	# rotation track uses the same mode, constant ones included, or Godot
	# cannot blend one animation into the next consistently.
	animation.track_set_interpolation_type(track,
			Animation.INTERPOLATION_LINEAR_ANGLE if angle
			else Animation.INTERPOLATION_LINEAR)
	var tolerance := float(TOLERANCE.get(property, 0.0))
	var kept: Array = [0]
	var anchor := 0
	var i := 1
	while i < values.size():
		# Stretch the line from the anchor as far as every sample under it
		# stays on it; the last sample that did becomes the next anchor.
		var end := i
		while end + 1 < values.size() and _on_line(values, anchor, end + 1, tolerance, angle):
			end += 1
		if end == values.size() - 1 and _on_line(values, anchor, end, tolerance, angle) \
				and _same_within(values[anchor], values[end], tolerance, angle):
			# A flat tail needs no closing key: Godot holds the last one.
			break
		kept.append(end)
		anchor = end
		i = end + 1
	for k in kept:
		animation.track_insert_key(track, float(k) / frame_rate, values[k])


## Whether every sample strictly between `from` and `to` lies within
## `tolerance` of the straight line between them.
func _on_line(values: Array, from: int, to: int, tolerance: float, angle: bool) -> bool:
	for k in range(from + 1, to):
		var t := float(k - from) / float(to - from)
		if not _same_within(_mix(values[from], values[to], t, angle), values[k], tolerance, angle):
			return false
	return true


static func _mix(a: Variant, b: Variant, t: float, angle: bool) -> Variant:
	if a is Vector2:
		return (a as Vector2).lerp(b, t)
	if a is Color:
		return (a as Color).lerp(b, t)
	if a is PackedVector2Array:
		var pa := a as PackedVector2Array
		var pb := b as PackedVector2Array
		var out := pa.duplicate()
		for k in mini(pa.size(), pb.size()):
			out[k] = pa[k].lerp(pb[k], t)
		return out
	if angle:
		return lerp_angle(float(a), float(b), t)
	return lerpf(float(a), float(b), t)


func _same_within(a: Variant, b: Variant, tolerance: float, angle: bool) -> bool:
	if tolerance <= 0.0:
		return _same(a, b)
	if a is Vector2:
		return (a as Vector2).distance_to(b) <= tolerance
	if a is Color:
		var ca := a as Color
		var cb := b as Color
		return maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)),
				maxf(absf(ca.b - cb.b), absf(ca.a - cb.a))) <= tolerance
	if angle:
		return absf(angle_difference(float(a), float(b))) <= tolerance
	return absf(float(a) - float(b)) <= tolerance


## A track that switches rather than blends: which picture a slot shows.
func _add_discrete(animation: Animation, path: String, values: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	for i in values.size():
		if i == 0 or values[i] != values[i - 1]:
			animation.track_insert_key(track, float(i) / frame_rate, values[i])


func _same(a: Variant, b: Variant) -> bool:
	if a is PackedVector2Array:
		var pa := a as PackedVector2Array
		var pb := b as PackedVector2Array
		if pa.size() != pb.size():
			return false
		for i in pa.size():
			if not pa[i].is_equal_approx(pb[i]):
				return false
		return true
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


## FFD keys, per [slot, choice]: each frame's offsets laid out over the whole
## vertex buffer. A frame lists only a run of it, starting `offset` floats in;
## the rest of the buffer is zero.
func _read_ffd_timelines(source: Dictionary) -> Dictionary:
	var out := {}
	for entry in (source.get("ffd", []) as Array):
		if not (entry is Dictionary):
			continue
		var which := _mesh_choice(entry)
		if which.is_empty():
			continue
		var size: int = (slots[which[0]]["displays"][which[1]]["mesh"]["vertices"]
				as PackedVector2Array).size() * 2
		out[which] = _timeline(entry.get("frame", []),
				func(f: Dictionary) -> Variant:
					var offsets := PackedFloat32Array()
					offsets.resize(size)
					var start := int(f.get("offset", 0))
					var run := f.get("vertices", []) as Array
					for i in run.size():
						if start + i < size:
							offsets[start + i] = float(run[i])
					return offsets)
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
			if from is PackedFloat32Array:
				var mixed := (from as PackedFloat32Array).duplicate()
				var target := to as PackedFloat32Array
				for k in mini(mixed.size(), target.size()):
					mixed[k] = lerpf(mixed[k], target[k], t)
				return mixed
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
