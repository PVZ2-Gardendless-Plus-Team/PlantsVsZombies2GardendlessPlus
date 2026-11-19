class_name StoreScreen
extends Control
## The store: PVZGE's storeScene. Tabs along the top (plants, upgrades, coins,
## gems, Zen Garden), the wares of the open tab on a shelf that scrolls
## sideways, the player's wallets top right, and Back to leave.
##
## A ware is bought with one press, as in PVZGE; a plant or upgrade then shows
## as sold out until the shelf is next filled. Everything it sells and charges
## comes from `Store`, so this only lays it out.

signal back_requested

const CARD_SIZE := Vector2(220, 330)
const DISPLAY_SIZE := Vector2(190, 170)
## How far the arrows scroll the shelf, as PVZGE's scrowL/scrowR.
const SCROLL_STEP := 500.0
const CURRENCY_ICONS := {
	&"coins": "CoinIcon",
	&"gems": "GemIcon",
	&"tickets": "TicketIcon",
	&"sprouts": "SproutCounter",
}
const COUNTERS := [
	[&"coins", "CoinCounter", Vector2(157, 51)],
	[&"gems", "GemCounter", Vector2(137, 53)],
	[&"tickets", "TicketCounter", Vector2(137, 53)],
	[&"sprouts", "SproutCounter", Vector2(137, 53)],
]

var page: StringName = &""

var _tabs: Dictionary = {}       ## page id -> Button
var _wallets: Dictionary = {}    ## currency -> Label
var _shelf: HBoxContainer
var _scroll: ScrollContainer
var _weekly: Label
var _empty: Label
## Ware id -> {item, button, card}, for the cards on the shelf.
var _cards: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Store.refresh_week()
	_build()
	Saves.currency_changed.connect(_on_currency_changed)
	var all := Store.pages()
	if not all.is_empty():
		show_page(StringName(str(all[0].get("id", ""))))
	MenuUI.music(&"music.store")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()


# --- building -----------------------------------------------------------

func _build() -> void:
	add_child(MenuUI.space_backdrop())

	var back := MenuUI.icon_button("ReturnUp", "ReturnDown", Vector2(67, 67),
			back_requested.emit, "Back")
	back.name = "Back"
	back.position = Vector2(45, 43) - back.custom_minimum_size * 0.5
	add_child(back)

	var title := MenuUI.title("Store", MenuUI.TITLE_SIZE)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 14
	title.offset_bottom = 70
	add_child(title)

	# The wallets, right to left from the top-right corner.
	var wallets := HBoxContainer.new()
	wallets.add_theme_constant_override("separation", 8)
	wallets.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	wallets.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wallets.offset_top = 84
	wallets.offset_right = -16
	add_child(wallets)
	for entry in COUNTERS:
		wallets.add_child(_wallet(entry[0], entry[1], entry[2]))

	# The tabs, PVZGE's square icons, in the top-left under Back.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.position = Vector2(24, 84)
	add_child(tabs)
	for p in Store.pages():
		var id := StringName(str(p.get("id", "")))
		var b := MenuUI.button(Store.page_title(p), show_page.bind(id),
				Vector2(150, 50), &"brown", 0.45)
		b.name = "Tab_%s" % id
		b.toggle_mode = true
		var icon := MenuUI.texture(str(p.get("icon", "")))
		if icon != null:
			b.icon = icon
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 30)
		tabs.add_child(b)
		_tabs[id] = b

	_weekly = MenuUI.label("", 20)
	_weekly.add_theme_color_override("font_color", MenuUI.TIP_YELLOW)
	_weekly.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weekly.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_weekly.offset_top = -56
	_weekly.offset_bottom = -20
	add_child(_weekly)

	_scroll = ScrollContainer.new()
	_scroll.name = "Shelf"
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 70
	_scroll.offset_right = -70
	_scroll.offset_top = 156
	_scroll.offset_bottom = -64
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	_shelf = HBoxContainer.new()
	_shelf.add_theme_constant_override("separation", 18)
	center.add_child(_shelf)

	_empty = MenuUI.label("Sold out! Come back when you have won more levels.", 24)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_empty.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_empty.visible = false
	add_child(_empty)

	add_child(_arrow(true))
	add_child(_arrow(false))


func _wallet(kind: StringName, sprite: String, size: Vector2) -> Control:
	var value := MenuUI.label(_thousands(Saves.currency(kind)), 24)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wallets[kind] = value
	var back := MenuUI.texture(sprite)
	if back == null:
		value.text = "%s %s" % [_thousands(Saves.currency(kind)), tr(String(kind).capitalize())]
		value.add_theme_color_override("font_color", CoinCounter.COLORS.get(kind, Color.WHITE))
		value.custom_minimum_size = size
		return value
	var frame := TextureRect.new()
	frame.texture = back
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.custom_minimum_size = size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value.offset_left = 38
	frame.add_child(value)
	return frame


func _arrow(left: bool) -> Button:
	var b := MenuUI.button("<" if left else ">", _scroll_by.bind(
			-SCROLL_STEP if left else SCROLL_STEP), Vector2(48, 96), &"purple_big", 0.3)
	b.name = "ScrollLeft" if left else "ScrollRight"
	b.set_anchors_preset(Control.PRESET_CENTER_LEFT if left else Control.PRESET_CENTER_RIGHT)
	b.offset_left = 12.0 if left else -60.0
	b.offset_right = b.offset_left + 48.0
	b.offset_top = -20
	b.offset_bottom = 76
	return b


func _scroll_by(amount: float) -> void:
	var tween := create_tween()
	tween.tween_property(_scroll, "scroll_horizontal",
			int(_scroll.scroll_horizontal + amount), 0.2)


# --- pages ----------------------------------------------------------------

## Fills the shelf with `id`'s wares.
func show_page(id: StringName) -> void:
	page = id
	for tab_id in _tabs:
		(_tabs[tab_id] as Button).set_pressed_no_signal(tab_id == id)
	for child in _shelf.get_children():
		child.queue_free()
	_cards.clear()
	var wares := Store.on_sale(id)
	for it in wares:
		_shelf.add_child(_card(it))
	_empty.visible = wares.is_empty()
	_scroll.scroll_horizontal = 0
	_refresh_weekly()
	_refresh_buttons()
	MenuUI.cue(&"ui.store.switch")


func _refresh_weekly() -> void:
	var plant := Store.weekly_plant()
	if page != &"plants" or plant == &"" or Saves.owns_plant(plant):
		_weekly.text = ""
		return
	_weekly.text = tr("Plant of the week: %s - %s left") % [
			String(plant).capitalize(), Store.time_left_text()]


func _card(it: StoreItem) -> Control:
	var card := MenuUI.window(0.4, 14.0)
	card.name = "Ware_%s" % it.id
	card.custom_minimum_size = CARD_SIZE
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	card.add_child(stack)

	var name_label := MenuUI.label(it.display_name(), 18)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CARD_SIZE.x - 30, 48)
	stack.add_child(name_label)

	var display := Control.new()
	display.custom_minimum_size = DISPLAY_SIZE
	display.clip_contents = true
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(display)
	_fill_display(display, it)

	var count := MenuUI.label("x%s" % _thousands(it.count) if it.type == &"currency" else "", 20)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(count)

	var discount := Store.price(it) < it.base_price
	if discount:
		var tag := MenuUI.label(tr("%d%% off!") % roundi(100.0 * (1.0 - it.weekly_discount)), 18)
		tag.add_theme_color_override("font_color", Color("ff6b6b"))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(tag)

	var buy := MenuUI.button(_thousands(Store.price(it)), _on_buy.bind(it.id),
			Vector2(170, 52), &"green", 0.45)
	buy.name = "Buy"
	buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var icon := MenuUI.texture(CURRENCY_ICONS.get(it.currency, ""))
	if icon != null:
		buy.icon = icon
		buy.expand_icon = true
		buy.add_theme_constant_override("icon_max_width", 28)
	else:
		buy.text = "%s %s" % [_thousands(Store.price(it)), tr(String(it.currency).capitalize())]
	stack.add_child(buy)
	_cards[it.id] = {"item": it, "button": buy, "card": card, "sold": false}
	return card


## The picture on a card: the plant itself, the upgrade's trophy, or a pile
## of what the pack holds. Plain text when the art is missing.
func _fill_display(display: Control, it: StoreItem) -> void:
	var rig: Armature = null
	match it.type:
		&"plant":
			rig = Art.make(&"plant", it.param)
			if rig != null:
				rig.scale *= 1.2
				rig.position = Vector2(DISPLAY_SIZE.x * 0.5, DISPLAY_SIZE.y * 0.85)
				rig.play(Art.animation_for(&"plant", it.param, &"idle"))
		&"upgrade":
			rig = Art.make(&"store", &"upgrade")
			if rig != null:
				rig.position = DISPLAY_SIZE * Vector2(0.5, 0.8)
				rig.play(Art.animation_for(&"store", &"upgrade", _upgrade_state(it.param)))
		&"currency":
			rig = Art.make(&"store", it.param)
			if rig != null:
				rig.position = DISPLAY_SIZE * Vector2(0.5, 0.6)
				rig.play(Art.animation_for(&"store", it.param, &"idle"))
	if rig != null:
		display.add_child(rig)
		return
	var tex := MenuUI.texture(CURRENCY_ICONS.get(it.param, "MedalIcon" if it.type == &"upgrade" else ""))
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		display.add_child(rect)
		return
	var l := MenuUI.label(it.display_name(), 22)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	display.add_child(l)


## Which state of the Upgrades rig pictures `upgrade_id`.
static func _upgrade_state(upgrade_id: StringName) -> StringName:
	var s := String(upgrade_id)
	for key in ["starting_sun", "sunshovel", "pf_slots", "pf_refresh",
			"manual_mowers", "wallnut", "shield", "slots"]:
		if s.contains(key):
			return StringName(key)
	return &"idle"


# --- buying ---------------------------------------------------------------

## Buys ware `id`. Returns whether it went through.
func buy(id: StringName) -> bool:
	var entry: Dictionary = _cards.get(id, {})
	if entry.is_empty() or entry["sold"]:
		return false
	var it: StoreItem = entry["item"]
	if not Store.buy(it):
		MenuUI.cue(&"ui.store.denied")
		return false
	Audio.play_variant(&"coin.collect", it.currency)
	if Store.sells_out(it):
		entry["sold"] = true
		var b: Button = entry["button"]
		b.text = tr("SOLD OUT")
		b.icon = null
	_refresh_buttons()
	_refresh_weekly()
	return true


func _on_buy(id: StringName) -> void:
	buy(id)


func _refresh_buttons() -> void:
	for id in _cards:
		var entry: Dictionary = _cards[id]
		(entry["button"] as Button).disabled = entry["sold"] or not Store.can_buy(entry["item"])


func _on_currency_changed(kind: StringName, total: int) -> void:
	var l: Label = _wallets.get(kind)
	if l != null:
		l.text = _thousands(total) if MenuUI.has_sprite("CoinCounter") \
				else "%s %s" % [_thousands(total), tr(String(kind).capitalize())]
	_refresh_buttons()


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
