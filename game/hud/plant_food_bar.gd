class_name PlantFoodBar
extends HBoxContainer
## Banked plant food: PVZGE's leaf button and a slot per charge, each slot
## filling with its Collecting animation when a charge arrives and emptying
## when one is spent.

signal pressed

## PVZGE's slot spacing along its bar, and how far the bar reaches past
## the leaf on the left.
const SLOT_STEP := 21.0
const BACKING_LEFT := 14.0

var _button: Button
var _icon: RigIcon
var _slots: Array[RigIcon] = []
var _label: Label
var _count: int = 0
var _active: bool = false
var _backing: StyleBox = null


func _init(slots: int = 3, font_size: int = 18) -> void:
	# PVZGE's teal plantFoodSlots bar, drawn behind the leaf and the slots
	# the way its slotParent sits behind them.
	_backing = MenuUI.stylebox("plantFoodSlots", 0.4)
	add_theme_constant_override("separation", 0 if _backing != null else 2)
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(52, 52)
	_button.pressed.connect(func(): pressed.emit())
	add_child(_button)
	_icon = RigIcon.new(&"plant_food_button", Vector2(52, 52))
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.add_child(_icon)
	for i in slots:
		var slot := RigIcon.new(&"plant_food_slot",
				Vector2(SLOT_STEP if _backing != null else 40.0, 52))
		if _backing == null:
			# The well a charge sits in; PVZGE's bar has them drawn in.
			slot.draw.connect(func():
				slot.draw_circle(slot.size * 0.5, 17.0, Color(0, 0, 0, 0.35)))
		add_child(slot)
		_slots.append(slot)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_child(_label)


func _ready() -> void:
	var art := _icon.has_art()
	_button.flat = art
	_button.text = "" if art else "Food"
	for slot in _slots:
		slot.visible = slot.has_art()
	_label.visible = not art
	set_count(_count)


func _draw() -> void:
	if _backing == null:
		return
	var h := 77.0
	var w := BACKING_LEFT + size.x + 10.0
	draw_style_box(_backing, Rect2(-BACKING_LEFT, (size.y - h) * 0.5, w, h))


func set_count(total: int) -> void:
	var before := _count
	_count = total
	for i in _slots.size():
		if i < total:
			# Only the slot that just filled plays the fill; older ones rest full.
			if i >= before:
				_slots[i].play(&"collecting", false)
			elif _slots[i].state != &"collecting":
				_slots[i].play(&"filled")
		else:
			_slots[i].play(&"empty")
	_label.text = "Food: %d" % total
	_button.disabled = total <= 0 and not _active


func set_active(active: bool) -> void:
	_active = active
	if not _icon.play(&"chosen" if active else &"idle"):
		_button.modulate = Color(0.7, 1.0, 0.7) if active else Color.WHITE
	_button.disabled = _count <= 0 and not active
