class_name AwardScreen
extends Control
## The screen after a prize is picked up: "You got a new plant!", the prize,
## and a button to carry on. PVZGE's awardScene: the swirling world map sky,
## the title above a brown window whose lime panel names the prize and shows
## it standing on its world's tile, and CONTINUE on the window's lower edge.
##
## Coin bags never get here; they pay out on the lawn.

signal continued

## Sizes from PVZGE's awardScene, in this game's pixels.
const WINDOW_SIZE := Vector2(615, 352)
const DISPLAY_SIZE := Vector2(212, 212)
const BUTTON_SIZE := Vector2(167, 65)

var reward: LevelReward
var _title: Label
var _name: Label
var _detail: Label
var _display: Panel
var _display_art: Node2D
var _packet: SeedPacketView
var _button: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func _build() -> void:
	add_child(MenuUI.space_backdrop())

	_title = MenuUI.label("", 54)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 60
	_title.offset_bottom = 132
	add_child(_title)

	var window := MenuUI.window(0.4, 17.0)
	window.custom_minimum_size = WINDOW_SIZE
	window.size = WINDOW_SIZE
	window.position = (Vector2(1280, 720) - WINDOW_SIZE) * 0.5
	add_child(window)

	var lime := PanelContainer.new()
	var box: StyleBox = MenuUI.stylebox("windowLime", 0.4)
	if box == null:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0.35, 0.5, 0.2)
		flat.set_corner_radius_all(8)
		box = flat
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 4
	box.content_margin_bottom = 14
	lime.add_theme_stylebox_override("panel", box)
	window.add_child(lime)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	lime.add_child(col)
	_name = MenuUI.label("", 50)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# PD: the prize on its world's tile, framed, behind display glass.
	_display = Panel.new()
	_display.custom_minimum_size = DISPLAY_SIZE
	_display.clip_contents = true
	var frame := MenuUI.stylebox("frame", 0.34, Color("146300"))
	var glass := MenuUI.texture("plantDisplayGlass", 0.4)
	_display.draw.connect(func() -> void:
		var rect := Rect2(Vector2.ZERO, _display.size)
		if frame != null:
			frame.draw(_display.get_canvas_item(), rect)
		if glass != null:
			_display.draw_texture_rect(glass, rect, false))
	body.add_child(_display)

	# Plants without art show their packet instead.
	_packet = SeedPacketView.new()
	_packet.custom_minimum_size = Vector2(120, 64)
	_packet.focus_mode = Control.FOCUS_NONE
	_packet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(_packet)

	_detail = MenuUI.label("")
	MenuUI.style_label(_detail, 32, MenuUI.DESCRIPTION_BROWN, 0, false)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail.size_flags_vertical = Control.SIZE_FILL
	body.add_child(_detail)

	_button = MenuUI.button("CONTINUE", _on_continue, BUTTON_SIZE, &"purple", 0.5)
	_button.add_theme_font_size_override("font_size", 39)
	_button.position = Vector2(640, 360 + 174) - BUTTON_SIZE * 0.5
	add_child(_button)


func open(prize: LevelReward) -> void:
	reward = prize
	if _title == null:
		_build()
	_title.text = prize.title()
	_name.text = prize.item_name()
	var is_plant := prize.type == &"unlock_plant"
	_detail.text = ""
	_show_prize(prize.param if is_plant else &"")
	if is_plant:
		var def := Data.plant(prize.param)
		var cost := int(def.stat(&"sun_cost", 0)) if def != null else 0
		_packet.setup(&"plant", prize.param, cost, "")
		_packet.disabled = true
		_packet.visible = _display_art == null
		_detail.text = "Costs %d sun. You can pick it before levels where you choose your seeds." % cost
	else:
		_packet.hide()
		if prize.type == &"gems":
			_detail.text = "Gems: %d" % Saves.currency(&"gems")
	show()
	_button.grab_focus()


## Stands the plant on the tile of the world PVZGE files it under.
func _show_prize(plant: StringName) -> void:
	if _display_art != null:
		_display_art.queue_free()
		_display_art = null
	var def := Data.plant(plant) if plant != &"" else null
	var rig: Node2D = Art.make(&"plant", plant) if def != null else null
	_display.visible = rig != null
	if rig == null:
		return
	var world := String(def.world) if def.world != &"" else "frontyard"
	var tile := MenuUI.stylebox(world if MenuUI.has_sprite(world) else "frontyard", 0.34)
	if tile != null:
		_display.add_theme_stylebox_override("panel", tile)
	rig.position = Vector2(DISPLAY_SIZE.x * 0.5, DISPLAY_SIZE.y * 0.8)
	rig.scale *= 1.7
	var idle := Art.animation_for(&"plant", plant, &"idle")
	if idle != &"":
		rig.play(idle)
	_display.add_child(rig)
	_display_art = rig


func _on_continue() -> void:
	hide()
	continued.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_on_continue()
