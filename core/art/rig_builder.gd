class_name RigBuilder
extends RefCounted
## Turns one DragonBones armature into a tree of ordinary Godot nodes.
##
## The tree is the whole rig: a Node2D per slot at its bone, a Sprite2D (or a
## Polygon2D for a mesh, or a nested Armature for a child rig) per picture the
## slot can show, a marker per socket bone, and an AnimationPlayer holding the
## baked animations. Nothing in it needs DragonBones to play, so it can be
## saved as a scene and opened, edited and re-saved in the Godot editor.
##
## `tools/bake_rigs.gd` saves these trees as `art/<bundle>/<armature>.tscn`,
## which is what the game loads. When a rig has no scene - a mod shipping only
## a DragonBones export, or art extracted since the last bake - `Art` builds
## the same tree here at load time instead, so both paths draw identically.

## How deep child armatures may nest. PopCap nests two levels at most (a seed
## packet's card holds a plant rig); this only stops a rig that names itself.
const MAX_DEPTH := 4
## Where extracted bundles live; matches `Art.ART_ROOT`.
const ART_ROOT := "res://art"


## Builds the rig into `root`, which must be empty. Returns false when the
## set has no such armature.
##
## `child_scene`, when given, maps a child armature's name to its baked
## PackedScene; the child is then an instance of that scene rather than a copy
## of it, which is how the baker keeps a seed packet's card from carrying the
## whole plant-picture rig inline.
static func populate(root: Armature, source: ArmatureSet, armature_name: StringName,
		sockets: Dictionary = {}, depth: int = 0, child_scene: Callable = Callable()) -> bool:
	if source == null or not source.has_armature(armature_name):
		return false
	var rig := source.rig(armature_name, sockets)
	if rig == null:
		return false
	root.bounds = source.bounds(armature_name)
	# Only a child rig starts itself; a top-level one waits for the game.
	if depth > 0:
		root.autoplay = default_animation(source.armature(armature_name))

	# The setup pose, which is also what a slot keeps when no animation ever
	# touches it - those get no track at all.
	var rest := rig.rest_transforms()
	for i in rig.slots.size():
		var slot: Dictionary = rig.slots[i]
		# A slot is a RigSlot at its bone, holding one child per picture it
		# can show; animations move it, tint it and key its `display`.
		# A socket has nothing to draw: it is a marker the game can read a
		# position off, animated like everything else.
		if slot.has("socket"):
			var marker := Node2D.new()
			marker.name = String(slot["name"])
			marker.transform = rest[i]
			marker.set_meta(&"socket", slot["socket"])
			root.add_child(marker)
			continue
		var node := RigSlot.new()
		node.name = String(slot["name"])
		node.transform = rest[i]
		node.modulate = slot["color"]
		root.add_child(node)
		var displays: Array = slot["displays"]
		for choice in displays.size():
			var display: Dictionary = displays[choice]
			if display.is_empty():
				continue
			var drawn := _display_node(source, display, slot, depth, child_scene)
			if drawn == null:
				continue
			drawn.name = str(choice)
			node.add_child(drawn)
		node.display = int(slot["display"])

	var player := AnimationPlayer.new()
	player.name = Armature.PLAYER
	root.add_child(player)
	player.add_animation_library(&"", source.animations(armature_name, sockets))
	return true


static func _display_node(source: ArmatureSet, display: Dictionary, slot: Dictionary,
		depth: int, child_scene: Callable) -> Node2D:
	if display.has("armature"):
		if depth >= MAX_DEPTH:
			return null
		var child: Armature = null
		var baked: PackedScene = child_scene.call(display["armature"]) \
				if child_scene.is_valid() else null
		if baked != null:
			child = baked.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Armature
		if child != null:
			child.autoplay = default_animation(source.armature(display["armature"]))
		else:
			child = Armature.new()
			if not populate(child, source, display["armature"], {}, depth + 1):
				child.free()
				return null
		# A child rig is placed by its display transform alone: the runtime
		# skips the pivot for armatures (`Slot._updateTransform`).
		child.transform = display["xform"]
		return child
	var region: StringName = display["region"]
	var drawn: Node2D = null
	if display.has("mesh"):
		var mesh: Dictionary = display["mesh"]
		var polygon := Polygon2D.new()
		# A Polygon2D samples its whole texture, so it takes the atlas page and
		# UVs already in that page's pixels.
		polygon.texture = source.texture
		polygon.polygon = mesh["vertices"]
		polygon.uv = mesh["uvs"]
		var triangles: PackedInt32Array = mesh["triangles"]
		var faces: Array = []
		for t in range(0, triangles.size() - 2, 3):
			faces.append(PackedInt32Array([triangles[t], triangles[t + 1], triangles[t + 2]]))
		polygon.polygons = faces
		drawn = polygon
	else:
		var sprite := Sprite2D.new()
		sprite.texture = source.region(region)
		sprite.centered = true
		sprite.offset = source.region_offset(region)
		drawn = sprite
	drawn.transform = display["xform"]
	if slot["blend"] == "add":
		drawn.material = additive()
	return drawn


## The animation a rig starts on by itself: its first `gotoAndPlay` default
## action, else its first animation - what `Animation.play()` with no name
## does in the runtime. Child rigs rely on it; nothing tells them what to play.
static func default_animation(armature: Dictionary) -> StringName:
	for action in (armature.get("defaultActions", []) as Array):
		if action is Dictionary and action.has("gotoAndPlay"):
			return StringName(action["gotoAndPlay"])
	var animations := armature.get("animation", []) as Array
	if not animations.is_empty() and animations[0] is Dictionary:
		return StringName((animations[0] as Dictionary).get("name", ""))
	return &""


## Glows and flashes are drawn additively. One material serves every one.
static var _add_material: CanvasItemMaterial = null


static func additive() -> CanvasItemMaterial:
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_material


## Sets `owner` through a built tree, which is what PackedScene.pack saves.
## An instanced child scene is owned as one node; its insides stay its own.
static func own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if child.scene_file_path == "":
			own(child, owner)


## Where a bundle's baked scene for an armature lives. Names keep letters,
## digits, '-' and '_' so every rig name makes a valid file name.
static func scene_path(bundle: StringName, armature_name: StringName) -> String:
	var safe := ""
	for c in String(armature_name):
		safe += c if (c.is_valid_identifier() or c == "-" or (c >= "0" and c <= "9")) else "_"
	return ART_ROOT.path_join(String(bundle)).path_join(safe + ".tscn")
