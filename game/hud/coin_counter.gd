class_name CoinCounter
extends HBoxContainer
## The player's coins, shown beside the seed bank once they have some or a
## coin bag is about to pay out. Counts up like the sun counter as coins land.

const CATCH_UP := 10.0

var target: int = 0
var shown: float = 0.0
var _icon: RigIcon
var _label: Label


func _init(font_size: int = 22) -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = RigIcon.new(&"coin_counter", Vector2(40, 40))
	add_child(_icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color("f2c53d"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.custom_minimum_size = Vector2(64, 0)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func _ready() -> void:
	set_total(Saves.currency(&"coins"), true)
	Saves.currency_changed.connect(_on_currency_changed)
	visible = target > 0


func set_total(total: int, instant: bool = false) -> void:
	target = total
	if instant or float(total) < shown:
		shown = float(total)
	_refresh()


## The point coins fly to, in canvas coordinates.
func collect_point() -> Vector2:
	return get_global_rect().get_center()


func _on_currency_changed(kind: StringName, total: int) -> void:
	if kind != &"coins":
		return
	set_total(total)
	if total > 0:
		show()


func _process(delta: float) -> void:
	if is_equal_approx(shown, float(target)):
		return
	var gap := float(target) - shown
	var step := gap * minf(delta * CATCH_UP, 1.0)
	shown += ceilf(step) if gap > 0.0 else floorf(step)
	_refresh()


func _refresh() -> void:
	var n := roundi(shown)
	_label.text = str(n) if _icon.has_art() else tr("Coins: %d") % n
