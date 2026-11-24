class_name UpgradesPage
extends Control
## The almanac's Upgrades page, as PVZGE's AlmanacUpgradePage: a card per
## upgrade with its trophy on its world's tile, its name and what it does,
## and an Enabled/Disabled switch. Upgrades the player has not won yet are
## greyed out and have no switch.
##
## Self-contained: it fills whatever it is put in and builds itself, so the
## almanac only has to add it as a tab.

## Emitted when the player switches an upgrade on or off.
signal toggled(id: StringName, enabled: bool)

const COLUMNS := 2
const CARD_SIZE := Vector2(580, 112)
const ICON_SIZE := Vector2(96, 96)
const TOGGLE_SIZE := Vector2(150, 46)
## PVZGE dims a locked card to 150/255.
const LOCKED_TINT := Color(150 / 255.0, 150 / 255.0, 150 / 255.0)

var _grid: GridContainer
## Upgrade id -> its card's toggle button.
var _toggles: Dictionary = {}
var _cards: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 12)
	center.add_child(_grid)
	refresh()
	Saves.progress_changed.connect(_on_progress_changed)


## Rebuilds every card from the catalogue and the player's saves.
func refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_toggles.clear()
	_cards.clear()
	for def in Upgrades.all():
		var id := StringName(def.get("id", ""))
		var card := _make_card(id, def)
		_grid.add_child(card)
		_cards[id] = card


func card_count() -> int:
	return _cards.size()


## The switch on an upgrade's card, or null when it is locked.
func toggle_for(id: StringName) -> Button:
	var b: Button = _toggles.get(id)
	return b if b != null and b.visible else null


func _make_card(id: StringName, def: Dictionary) -> Control:
	var owned := Upgrades.owns(id)
	var card := PanelContainer.new()
	card.name = String(id)
	card.custom_minimum_size = CARD_SIZE
	card.add_theme_stylebox_override("panel", MenuUI.row_box())
	if not owned:
		card.modulate = LOCKED_TINT

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	# The trophy stands on the tile of the world PVZGE files it under.
	var tile := Panel.new()
	tile.custom_minimum_size = ICON_SIZE
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var world := String(def.get("world", "frontyard"))
	var box := MenuUI.stylebox(world if MenuUI.has_sprite(world) else "frontyard", 0.3)
	if box != null:
		tile.add_theme_stylebox_override("panel", box)
	row.add_child(tile)
	var trophy := RigIcon.new(&"upgrade_trophy", ICON_SIZE)
	trophy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(trophy)
	var sprite := StringName(def.get("sprite", ""))
	trophy.ready.connect(func() -> void:
		if not trophy.play(sprite):
			# Deferred: the page is still adding its cards.
			_fallback_icon.call_deferred(tile, sprite))

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var title := MenuUI.label(Upgrades.display_name(id), MenuUI.BODY_SIZE + 4)
	MenuUI.style_label(title, MenuUI.BODY_SIZE + 4, MenuUI.TITLE_GOLD, 4)
	text.add_child(title)
	var blurb := Label.new()
	blurb.text = Upgrades.description(id)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.x = 260
	blurb.add_theme_font_size_override("font_size", MenuUI.BODY_SIZE - 2)
	blurb.add_theme_color_override("font_color",
			MenuUI.DESCRIPTION_BROWN if MenuUI.has_art() else MenuUI.TEXT)
	text.add_child(blurb)

	var toggle := MenuUI.button("", _toggle.bind(id), TOGGLE_SIZE)
	toggle.name = "Toggle"
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.visible = owned
	row.add_child(toggle)
	_toggles[id] = toggle
	_style_toggle(toggle, Upgrades.is_enabled(id))

	if not owned:
		var locked := MenuUI.label("Locked", MenuUI.BODY_SIZE)
		locked.custom_minimum_size.x = TOGGLE_SIZE.x
		locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		locked.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(locked)
	return card


## Without the art the icon is the upgrade's initials on its tile.
func _fallback_icon(tile: Control, sprite: StringName) -> void:
	var l := MenuUI.label(String(sprite).capitalize(), MenuUI.BODY_SIZE - 4)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile.add_child(l)


## PVZGE's switch: green "Enabled", red "Disabled".
func _style_toggle(b: Button, enabled: bool) -> void:
	b.text = "Enabled" if enabled else "Disabled"
	MenuUI.skin_button(b, &"green" if enabled else &"red")


func _toggle(id: StringName) -> void:
	var on := not Upgrades.is_enabled(id)
	Upgrades.set_enabled(id, on)
	toggled.emit(id, on)


## Keeps every card in step with the saves: a switch flipped here, an upgrade
## won or bought elsewhere.
func _on_progress_changed() -> void:
	for id in _cards:
		var owned := Upgrades.owns(id)
		var card: Control = _cards[id]
		if owned != _toggles[id].visible:
			# Won while the page was open: rebuild to drop the lock.
			refresh()
			return
		card.modulate = Color.WHITE if owned else LOCKED_TINT
		_style_toggle(_toggles[id], Upgrades.is_enabled(id))
