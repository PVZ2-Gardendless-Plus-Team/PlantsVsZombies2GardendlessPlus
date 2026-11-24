class_name ZenPriceTag
extends Node2D
## The tag on a locked Zen Garden slot: PVZGE's ZenTag with the price on it,
## greyed while the player cannot afford it. Drawn in garden units; the
## screen buys the slot when it is clicked.

## PVZGE's SlotPriceTagUI: scale 0.8, the price 71 units right of centre.
const SCALE := 0.8
const TEXT_AT := Vector2(71.4, -7.9)
const TEXT_SIZE := 62

var price: int = 0
var affordable: bool = false

static var _texture: Texture2D = null


func _init(cost: int = 0) -> void:
	price = cost


func _draw() -> void:
	var tint := Color.WHITE if affordable else Color(0.48, 0.48, 0.48)
	if _texture == null:
		_texture = MenuUI.texture("ZenTag")
	var size := Vector2(329, 148) * SCALE
	if _texture != null:
		draw_texture_rect(_texture, Rect2(-size * 0.5, size), false, tint)
	else:
		draw_rect(Rect2(-size * 0.5, size), Color(0.2, 0.2, 0.22) * tint)
	var text := ZenGardenScreen.thousands(price)
	var font := ThemeDB.fallback_font
	var width := 180.0
	var at := TEXT_AT * SCALE + Vector2(-width * 0.5, TEXT_SIZE * 0.35)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width,
			TEXT_SIZE, 12, Color(0.1, 0.1, 0.1) * tint)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, TEXT_SIZE, tint)
