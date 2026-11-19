class_name CoinCounter
extends HBoxContainer
## One of the player's currencies - coins by default, or gems, tickets or
## sprouts - shown on the lawn once there are some or a pickup is on its way.
## Counts up like the sun counter as pickups land. PVZGE's
## CoinCollecterInGame: it slides away again after a few quiet seconds.

const CATCH_UP := 10.0
## The icon sprite for each currency, from PVZGE's flat UI art.
const ICONS := {
	&"coins": "CoinIcon",
	&"gems": "GemIcon",
	&"tickets": "TicketIcon",
	&"sprouts": "SproutCounter",
}
const COLORS := {
	&"coins": Color("f2c53d"),
	&"gems": Color("7fe0ff"),
	&"tickets": Color("ff9e9e"),
	&"sprouts": Color("aee571"),
}

var kind: StringName = &"coins"
var target: int = 0
var shown: float = 0.0
var _icon: Control
var _has_icon := false
var _label: Label


func _init(font_size: int = 22, currency: StringName = &"coins") -> void:
	kind = currency
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := MenuUI.texture(ICONS.get(kind, "CoinIcon"))
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = Vector2(40, 40)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon = rect
		_has_icon = true
	else:
		var rig := RigIcon.new(StringName("%s_counter" % kind.trim_suffix("s")), Vector2(40, 40))
		_icon = rig
	add_child(_icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", COLORS.get(kind, Color("f2c53d")))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.custom_minimum_size = Vector2(64, 0)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


func _ready() -> void:
	set_total(Saves.currency(kind), true)
	Saves.currency_changed.connect(_on_currency_changed)
	visible = target > 0


func set_total(total: int, instant: bool = false) -> void:
	target = total
	if instant or float(total) < shown:
		shown = float(total)
	_refresh()


## The point pickups fly to, in canvas coordinates.
func collect_point() -> Vector2:
	return get_global_rect().get_center()


func _on_currency_changed(changed: StringName, total: int) -> void:
	if changed != kind:
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


func _has_art() -> bool:
	return _has_icon or (_icon is RigIcon and (_icon as RigIcon).has_art())


func _refresh() -> void:
	var n := roundi(shown)
	if _has_art():
		_label.text = str(n)
	else:
		_label.text = tr("%s: %d") % [tr(String(kind).capitalize()), n]
