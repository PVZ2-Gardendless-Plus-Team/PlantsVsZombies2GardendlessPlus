class_name MenuUI
extends RefCounted
## Shared building blocks for the menus and the HUD, drawn with PVZGE's own UI
## art: its purple and brown buttons, the brown rounded windows, the green
## volume bars. The art is the flat sprites `tools/extract_ui.py` pulls into
## `res://art/ui/`; without it every piece falls back to plain flat styling,
## so the screens still work from a clone that has no art.
##
## Sizes are PVZGE's. Its canvas is 1024x640 and ours is 1280x720, so a
## PVZGE pixel is `PX` of ours (720 / 640): a piece PVZGE draws at node
## scale 0.6 is drawn here at 0.6 * PX.

const TITLE_SIZE := 44
const HEADING_SIZE := 28
const BODY_SIZE := 18
const BUTTON_SIZE := Vector2(260, 48)

## One PVZGE canvas pixel, in ours.
const PX := 1.125
const UI_DIR := "res://art/ui"
const INDEX := "res://art/ui/_index.json"

## PVZGE's label colours.
const TEXT := Color.WHITE
const TITLE_GOLD := Color("ffcb5e")
const LEVEL_NAME := Color("fffcb3")
const TIP_YELLOW := Color("ffe78b")
const DESCRIPTION_BROWN := Color("743c00")

## Button looks: name -> [up sprite, down sprite]. The art has no hover
## frame, so hovering brightens the up one.
const BUTTONS := {
	&"purple": ["BtnPurpleSmallUp", "BtnPurpleSmallDown"],
	&"purple_big": ["BtnPurpleBigUp", "BtnPurpleBigDown"],
	&"brown": ["BtnBrownUp", "BtnBrownDown"],
	&"green": ["BtnGreenSmallUp", "BtnGreenSmallDown"],
	&"green_big": ["BtnGreenBigUp", "BtnGreenBigDown"],
	&"red": ["BtnRedSmallUp", "BtnRedSmallDown"],
	&"blue": ["BtnBlueBigUp", "BtnBlueBigDown"],
}

## name -> {size, original, offset, insets}, from the extractor.
static var _index: Dictionary = {}
static var _index_loaded := false
## "<name>@<scale>" -> Texture2D, resized once and shared.
static var _scaled: Dictionary = {}
static var _fonts: Dictionary = {}


## Whether the extracted UI art is there at all.
static func has_art() -> bool:
	return not _ui_index().is_empty()


static func _ui_index() -> Dictionary:
	if not _index_loaded:
		_index_loaded = true
		if FileAccess.file_exists(INDEX):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
			if parsed is Dictionary:
				_index = parsed
	return _index


static func has_sprite(sprite: String) -> bool:
	return _ui_index().has(sprite) and ResourceLoader.exists(_path(sprite))


static func _path(sprite: String) -> String:
	return UI_DIR.path_join(sprite + ".png")


## A UI sprite, drawn `scale` times its own size, or null without the art.
## Scaled copies are made once: nine-slice corners are drawn at texture
## size, so a window drawn smaller than PVZGE's source needs smaller pixels.
static func texture(sprite: String, scale: float = 1.0) -> Texture2D:
	if not has_sprite(sprite):
		return null
	var key := "%s@%.3f" % [sprite, scale]
	if _scaled.has(key):
		return _scaled[key]
	var source := load(_path(sprite)) as Texture2D
	var out: Texture2D = source
	if source != null and not is_equal_approx(scale, 1.0):
		var image := source.get_image()
		if image.is_compressed():
			image.decompress()
		var w := maxi(1, roundi(image.get_width() * scale))
		var h := maxi(1, roundi(image.get_height() * scale))
		image.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out = ImageTexture.create_from_image(image)
	_scaled[key] = out
	return out


## A sprite's size in our pixels at a PVZGE node scale.
static func sprite_size(sprite: String, node_scale: float = 1.0) -> Vector2:
	var entry: Dictionary = _ui_index().get(sprite, {})
	var s: Array = entry.get("size", [0, 0])
	return Vector2(s[0], s[1]) * node_scale * PX


## A nine-slice box from a sprite, its corners drawn at `node_scale` as PVZGE
## draws them. Null without the art.
static func stylebox(sprite: String, node_scale: float = 1.0,
		tint := Color.WHITE) -> StyleBoxTexture:
	var factor := node_scale * PX
	var tex := texture(sprite, factor)
	if tex == null:
		return null
	var box := StyleBoxTexture.new()
	box.texture = tex
	var insets: Array = _ui_index()[sprite].get("insets", [0, 0, 0, 0])
	box.texture_margin_left = roundf(float(insets[0]) * factor)
	box.texture_margin_top = roundf(float(insets[1]) * factor)
	box.texture_margin_right = roundf(float(insets[2]) * factor)
	box.texture_margin_bottom = roundf(float(insets[3]) * factor)
	box.modulate_color = tint
	return box


## PVZGE's text face for a role, from the `font:<role>` art mapping:
## &"ui" is the one on every label (also the default theme font, which
## `Art` applies), &"warning" the HouseofTerror face of "PLANT!" and the
## zombie warnings. Null when the file is missing.
static func font(role: StringName = &"ui") -> Font:
	if _fonts.has(role):
		return _fonts[role]
	var file := String(Art.mapping(&"font", role).get("file", ""))
	var path := Art.ART_ROOT.path_join(file)
	var f: Font = null
	if file != "" and ResourceLoader.exists(path):
		f = load(path) as Font
	_fonts[role] = f
	return f


static func label(text: String, size: int = BODY_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	style_label(l, size)
	return l


## PVZGE's label look: white, a thin black outline and a drop shadow.
static func style_label(l: Label, size: int, color := TEXT,
		outline: int = 4, shadow: bool = true) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", outline)
	else:
		l.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)


## A window title in PVZGE's gold.
static func title(text: String, size: int = 40) -> Label:
	var l := label(text)
	style_label(l, size, TITLE_GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A text button. `look` picks one of `BUTTONS`; PVZGE draws these at node
## scale 0.6, and `node_scale` sizes the corners to match.
static func button(text: String, on_pressed: Callable,
		min_size: Vector2 = BUTTON_SIZE, look: StringName = &"purple",
		node_scale: float = 0.6) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", BODY_SIZE + 4)
	skin_button(b, look, node_scale)
	b.pressed.connect(click)
	b.pressed.connect(on_pressed)
	return b


## Gives any Button one of PVZGE's looks. Without the art it stays a
## standard button.
static func skin_button(b: Button, look: StringName = &"purple",
		node_scale: float = 0.6) -> void:
	var sprites: Array = BUTTONS.get(look, BUTTONS[&"purple"])
	var up := stylebox(sprites[0], node_scale)
	if up == null:
		return
	var down := stylebox(sprites[1], node_scale)
	if down == null:
		down = up
	var hover := up.duplicate() as StyleBoxTexture
	hover.modulate_color = Color(1.15, 1.15, 1.15)
	var disabled := up.duplicate() as StyleBoxTexture
	disabled.modulate_color = Color(0.55, 0.55, 0.55)
	var focus := StyleBoxEmpty.new()
	for box in [up, down, hover, disabled]:
		# Room for the bevel: the label sits on the face, not the rim.
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 6
		box.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", up)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("hover_pressed", down)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", _focus_ring())
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.75, 0.75, 0.75))
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 5)


## Keyboard focus shows as a thin light rim, kept for gamepad and keys.
static func _focus_ring() -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color(1, 1, 0.75, 0.8)
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(10)
	ring.set_expand_margin_all(2)
	return ring


## A button that is just a picture: PVZGE's square settings, close and pause
## buttons. `down` may be empty. Falls back to a text button.
static func icon_button(up: String, down: String, size: Vector2,
		on_pressed: Callable, fallback_text: String = "") -> BaseButton:
	var normal := texture(up)
	if normal == null:
		var b := Button.new()
		b.text = fallback_text
		b.custom_minimum_size = size
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(click)
		b.pressed.connect(on_pressed)
		return b
	var t := TextureButton.new()
	t.texture_normal = normal
	var pressed := texture(down) if down != "" else null
	if pressed != null:
		t.texture_pressed = pressed
	t.ignore_texture_size = true
	t.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = size
	t.size = size
	t.focus_mode = Control.FOCUS_NONE
	t.tooltip_text = fallback_text
	t.mouse_entered.connect(func() -> void: t.modulate = Color(1.12, 1.12, 1.12))
	t.mouse_exited.connect(func() -> void: t.modulate = Color.WHITE)
	t.pressed.connect(click)
	t.pressed.connect(on_pressed)
	return t


## A full-screen backdrop that also swallows clicks meant for what is behind.
static func backdrop(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## PVZGE's world map sky, the teal swirl behind the world map and the award
## screen, as a backdrop. Its WorldmapBG rig nests the turning swirl as a
## child armature, drawn in teal twice over; the rig itself
## adds the dust and darkens the top and bottom. Without the art it is a
## flat teal.
static func space_backdrop() -> ColorRect:
	var r := backdrop(Color(0.01, 0.09, 0.11))
	var swirl := RigIcon.new(&"worldmap_swirl", Vector2.ZERO)
	swirl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Twice the teal: the second copy is added onto the first.
	swirl.modulate = Color(0, 2, 1.84)
	r.add_child(swirl)
	var sky := RigIcon.new(&"worldmap_bg", Vector2.ZERO)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.add_child(sky)
	return r


## A centred window holding a vertical stack, returned as [centre, stack]:
## PVZGE's brown windowCommon with its windowCommonBorder rim drawn over the
## edge. `node_scale` is PVZGE's for the window (0.6 for the pause menu,
## 0.4 for settings and the seed chooser).
static func panel(min_width: float = 360.0, node_scale: float = 0.6) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := window(node_scale)
	p.custom_minimum_size.x = min_width
	center.add_child(p)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	p.add_child(stack)
	return [center, stack]


## Just the window: a PanelContainer in PVZGE's brown frame.
static func window(node_scale: float = 0.6, padding: float = 26.0) -> PanelContainer:
	var p := PanelContainer.new()
	var fill: StyleBox = stylebox("windowCommon", node_scale)
	var rim := stylebox("windowCommonBorder", node_scale)
	if fill == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.12, 0.16, 0.12)
		flat.border_color = Color(0.45, 0.6, 0.35)
		flat.set_border_width_all(3)
		flat.set_corner_radius_all(12)
		fill = flat
	fill.content_margin_left = padding
	fill.content_margin_right = padding
	fill.content_margin_top = padding
	fill.content_margin_bottom = padding
	p.add_theme_stylebox_override("panel", fill)
	if rim != null:
		# The rim is a separate sprite in PVZGE too, laid over the fill.
		p.draw.connect(func() -> void:
			rim.draw(p.get_canvas_item(), Rect2(Vector2.ZERO, p.size)))
	return p


## A row panel from PVZGE's settings list: cream, or tinted green/red for
## an on/off setting.
static func row_box(tint := Color.WHITE) -> StyleBox:
	var box: StyleBox = stylebox("settingElement", 0.4, tint)
	if box == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.2, 0.25, 0.2) * tint
		flat.set_corner_radius_all(6)
		box = flat
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


## PVZGE's volume bar: a dark trough, a green fill and the gear handle,
## `handle` pixels across (30 in the settings list, 45 in the pause menu).
static func skin_slider(s: HSlider, handle: float = 30.0) -> void:
	var trough := stylebox("audioBg", 0.28)
	var fill := stylebox("audioFill", 0.28)
	var gear := texture("slider", handle / maxf(sprite_size("slider").x / PX, 1.0))
	if trough == null or fill == null:
		return
	trough.content_margin_top = 8
	trough.content_margin_bottom = 8
	s.add_theme_stylebox_override("slider", trough)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	if gear != null:
		s.add_theme_icon_override("grabber", gear)
		s.add_theme_icon_override("grabber_highlight", gear)
		s.add_theme_icon_override("grabber_disabled", gear)


## Plays a UI cue only when the catalog has it, so screens can name the
## sounds they want before the audio side defines them.
static func cue(id: StringName) -> void:
	if Audio.has_event(id):
		Audio.play(id)


static func music(id: StringName) -> void:
	if Audio.has_event(id):
		Audio.play_music(id)


static func click() -> void:
	cue(&"ui.button.click")
