extends SceneTree
## Renders a rig's animations to a contact sheet, through the same Armature
## node the game uses, so what the sheet shows is what the lawn shows.
##
##     godot --rendering-driver opengl3 -s tools/armature_sheet.gd -- \
##         <bundle> <armature> <out.png> [animation ...] [--frames N] [--export]
##
## Draws the baked scene (`art/<bundle>/<armature>.tscn`) when there is one;
## `--export` converts the DragonBones export instead, which is how the two are
## compared frame by frame.
##
## Needs a display (xvfb-run works); the headless driver draws nothing. One row
## per animation, N evenly spaced frames across it, so a part that pops, a foot
## that slides or a slot that never shows up is visible at a glance.

const CELL := Vector2i(220, 260)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: <bundle> <armature> <out.png> [animation ...] [--frames N]")
		quit(2)
		return
	_run(args)


func _run(args: PackedStringArray) -> void:
	var frames := 8
	var names: Array = []
	var from_export := false
	var i := 3
	while i < args.size():
		if args[i] == "--export":
			from_export = true
			i += 1
			continue
		if args[i] == "--frames" and i + 1 < args.size():
			frames = int(args[i + 1])
			i += 2
			continue
		names.append(StringName(args[i]))
		i += 1

	var bundle := args[0]
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/_index.json"))
	var texture := String(((index as Dictionary).get(bundle, {}) as Dictionary).get("textures", [""])[0])
	var source := ArmatureSet.load_from("res://art/" + bundle, "res://art/_textures/" + texture)
	if source == null:
		push_error("no bundle " + bundle)
		quit(1)
		return

	var viewport := SubViewport.new()
	viewport.size = CELL
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.55, 0.75, 0.45)
	backdrop.size = CELL
	viewport.add_child(backdrop)

	var rig: Armature = null
	var baked := RigBuilder.scene_path(StringName(bundle), StringName(args[1]))
	if not from_export and ResourceLoader.exists(baked):
		rig = (load(baked) as PackedScene).instantiate() as Armature
		rig.bind()
		print("drawing " + baked)
	else:
		rig = Armature.new()
		if not rig.setup(source, StringName(args[1])):
			push_error("no armature " + args[1])
			quit(1)
			return
	var box := source.bounds(StringName(args[1]))
	var fit := minf((CELL.y - 20) / maxf(box.size.y, 1.0), (CELL.x - 20) / maxf(box.size.x, 1.0))
	rig.scale = Vector2(fit, fit)
	rig.position = Vector2(CELL.x * 0.5 - (box.position.x + box.size.x * 0.5) * fit,
			CELL.y - 10 - (box.position.y + box.size.y) * fit)
	viewport.add_child(rig)
	if names.is_empty():
		names = rig.animation_names()

	var sheet := Image.create(CELL.x * frames, CELL.y * names.size(), false, Image.FORMAT_RGBA8)
	var player: AnimationPlayer = rig._player
	# Posed only by seeking, so the sheet does not depend on frame timing and
	# two runs - or a scene and its export - compare pixel for pixel.
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for row in names.size():
		var anim: Animation = player.get_animation(names[row])
		if anim == null:
			continue
		player.play(names[row])
		for col in frames:
			var at := anim.length * float(col) / float(maxi(frames - 1, 1))
			player.seek(at, true)
			await process_frame
			await RenderingServer.frame_post_draw
			var shot := viewport.get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		print("%s: %d frames over %.2fs" % [names[row], frames, anim.length])
	sheet.save_png(args[2])
	print("wrote " + args[2])
	quit(0)
