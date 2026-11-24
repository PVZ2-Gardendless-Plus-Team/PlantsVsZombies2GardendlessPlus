class_name CoinToken
extends Collectable
## A pickup that pays into the wallet: a silver or gold coin, a gem, a ticket
## or a sprout - PVZGE's droppings. Coin bags, zombies, unused mowers and
## marigolds drop them; each is banked into `currency` when it reaches its
## counter.

## PVZGE's silver and gold coins.
const SILVER := 10
const GOLD := 50

## Which `loot.json` drop this is; it is also the `collectable:<id>` art.
var drop_id: StringName = &"coin_silver"
var currency: StringName = &"coins"
var value: int = SILVER

@export var silver_color: Color = Color("d9dde3")
@export var gold_color: Color = Color("f2c53d")
@export var gem_color: Color = Color("4fc3f7")
@export var ticket_color: Color = Color("e57373")
@export var sprout_color: Color = Color("7cb342")
@export var rim_color: Color = Color("8a8f96")


func _init() -> void:
	radius = 14.0
	lifetime = 8.0


## Makes this the `loot.json` drop `id`; a coin keeps its value as given.
func set_drop(id: StringName) -> void:
	drop_id = id
	var info := Loot.info(id)
	currency = StringName(str(info.get("currency", "coins")))
	value = int(info.get("value", value))


func art_id() -> StringName:
	if drop_id == &"coin_silver" or drop_id == &"coin_gold" or drop_id == &"":
		# A coin bag splits its total into coins of any value.
		return &"coin_gold" if value >= GOLD else &"coin_silver"
	return drop_id


func _draw() -> void:
	if art != null:
		return
	match currency:
		&"gems":
			var pts := PackedVector2Array([Vector2(0, -radius), Vector2(radius, 0),
					Vector2(0, radius), Vector2(-radius, 0)])
			draw_colored_polygon(pts, gem_color)
		&"tickets":
			draw_rect(Rect2(-radius, -radius * 0.6, radius * 2.0, radius * 1.2), ticket_color)
		&"sprouts":
			draw_circle(Vector2(0, radius * 0.4), radius * 0.6, Color("6d4c41"))
			draw_circle(Vector2(-4, -2), radius * 0.45, sprout_color)
			draw_circle(Vector2(4, -4), radius * 0.45, sprout_color)
		_:
			draw_circle(Vector2.ZERO, radius, rim_color)
			draw_circle(Vector2.ZERO, radius - 2.5, gold_color if value >= GOLD else silver_color)
			draw_rect(Rect2(-2.0, -radius * 0.5, 4.0, radius), rim_color)
