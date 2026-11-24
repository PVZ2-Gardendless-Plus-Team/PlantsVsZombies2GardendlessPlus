class_name StoreItem
extends RefCounted
## One ware in the store: a plant, an upgrade, or a pack of coins, gems or
## sprouts. PVZGE's StoreCommodityProps, read from `store.json`.

var id: StringName = &""
var page: StringName = &""
## &"plant", &"upgrade" or &"currency".
var type: StringName = &"plant"
## The plant id, upgrade id, or for a pack the currency it holds.
var param: StringName = &""
## How much a pack holds.
var count: int = 1
## What it costs, and how much.
var currency: StringName = &"coins"
var base_price: int = 0
## A plant stays off the shelf until this level is won.
var unlock_level: StringName = &""
## Below 1 for a plant that can be plant of the week: its price that week.
var weekly_discount: float = 1.0
## Which pile picture a pack shows (PVZGE's StackLevel).
var stack: int = 0
## {en, zh...} name for packs; plants and upgrades are named by what they are.
var names: Dictionary = {}
var source_mod: StringName = &"base"


static func from_dict(d: Dictionary) -> StoreItem:
	var item := StoreItem.new()
	item.id = StringName(str(d.get("id", "")))
	item.page = StringName(str(d.get("page", "plants")))
	item.type = StringName(str(d.get("type", "plant")))
	item.param = StringName(str(d.get("param", "")))
	item.count = int(d.get("count", 1))
	item.currency = StringName(str(d.get("currency", "coins")))
	item.base_price = int(d.get("price", 0))
	item.unlock_level = StringName(str(d.get("unlock_level", "")))
	item.weekly_discount = float(d.get("weekly_discount", 1.0))
	item.stack = int(d.get("stack", 0))
	var n: Variant = d.get("name", {})
	if n is Dictionary:
		item.names = n
	elif n is String:
		item.names = {"en": n}
	item.source_mod = StringName(str(d.get("__mod", "base")))
	return item


## Whether this can ever be plant of the week.
func is_weekly_plant() -> bool:
	return type == &"plant" and weekly_discount < 1.0


## The name shown on its card, in the player's language where it has one.
func display_name() -> String:
	if not names.is_empty():
		return Upgrades.localized(names, String(id))
	match type:
		&"plant":
			return String(param).capitalize()
		&"upgrade":
			return Upgrades.display_name(param)
	return "%d %s" % [count, String(param).capitalize()]
