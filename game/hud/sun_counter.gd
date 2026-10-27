class_name SunCounter
extends HBoxContainer
## The sun bank. Like PVZGE's SunCount it does not jump: the shown number
## closes a tenth of the gap per tick, and the icon plays its rising pose
## while it is still catching up.

## Share of the remaining gap closed per second.
const CATCH_UP := 10.0
## How long the not-enough-sun flash lasts, in seconds.
const WARN_TIME := 0.5

var target: int = 0
var shown: float = 0.0
var _icon: RigIcon
var _label: Label
var _warn_tween: Tween


func _init(font_size: int = 22) -> void:
	add_theme_constant_override("separation", 6)
	_icon = RigIcon.new(&"sun_counter", Vector2(48, 48))
	add_child(_icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.custom_minimum_size = Vector2(64, 0)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func _ready() -> void:
	if not _icon.has_art():
		_label.text = "Sun: %d" % target


## Sets the total. Spending snaps down at once - the price has been paid -
## while earning counts up.
func set_total(total: int, instant: bool = false) -> void:
	target = total
	if instant or float(total) < shown:
		shown = float(total)
	_refresh()


## PVZGE's `sunCountWarn`: picking a packet the bank cannot pay for flashes
## the number red and swells it, then lets both settle back.
func warn() -> void:
	if _warn_tween != null:
		_warn_tween.kill()
	_label.pivot_offset = _label.size * 0.5
	_label.scale = Vector2(1.2, 1.2)
	_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	_warn_tween = create_tween().set_parallel()
	_warn_tween.tween_property(_label, "scale", Vector2.ONE, WARN_TIME)
	_warn_tween.tween_method(func(c: Color): _label.add_theme_color_override("font_color", c),
			Color(1.0, 0.25, 0.25), Color.WHITE, WARN_TIME)


func is_warning() -> bool:
	return _warn_tween != null and _warn_tween.is_running()


func _process(delta: float) -> void:
	if is_equal_approx(shown, float(target)):
		_icon.play(&"idle")
		return
	var gap := float(target) - shown
	var step := gap * minf(delta * CATCH_UP, 1.0)
	step = ceilf(step) if gap > 0.0 else floorf(step)
	shown += step
	_icon.play(&"rising" if gap > 0.0 else &"idle")
	_refresh()


func _refresh() -> void:
	var n := roundi(shown)
	_label.text = str(n) if _icon.has_art() else "Sun: %d" % n
