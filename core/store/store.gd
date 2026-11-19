class_name Store
extends RefCounted
## The store: what is on sale, what it costs, and buying it. PVZGE's Store and
## StoreCommodity, over the wares in `store.json`.
##
## Plants are sold until owned, and only once their `unlock_level` is won.
## Upgrades are sold until owned (the `upgrades` collection in Saves). Packs of
## coins, gems or sprouts never sell out.
##
## Ticket plants take turns as plant of the week, PVZGE's TicketCount: each
## week (from Saturday midnight, local time) one of them is picked, not
## repeating until all have had a turn, and sells at its `weekly_discount`.
## A new week also empties the ticket wallet, as PVZGE's does. The week's
## state lives in the `store` section of Saves.

const SECTION := &"store"
const SECONDS_PER_DAY := 86400
## 1970-01-01 was a Thursday; with Sunday as 0 that is day 4.
const EPOCH_WEEKDAY := 4
const SATURDAY := 6

## Overrides the clock, in local seconds since the epoch, for tests. Zero uses
## the system clock.
static var now_override: int = 0
static var rng := RandomNumberGenerator.new()


# --- catalog --------------------------------------------------------------

## The tabs, in order, as {id, title, icon}.
static func pages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in Data.store_pages:
		out.append(Data.store_pages[id])
	return out


static func page_title(page: Dictionary) -> String:
	var t: Variant = page.get("title", page.get("id", ""))
	if t is Dictionary:
		var lang := TranslationServer.get_locale().get_slice("_", 0)
		return str(t.get(lang, t.get("en", "")))
	return str(t)


static func item(id: StringName) -> StoreItem:
	var d: Variant = Data.store_items.get(id)
	return StoreItem.from_dict(d) if d is Dictionary else null


static func all_items() -> Array[StoreItem]:
	var out: Array[StoreItem] = []
	for id in Data.store_items:
		out.append(StoreItem.from_dict(Data.store_items[id]))
	return out


## What a page has on its shelf right now, in catalog order.
static func on_sale(page: StringName) -> Array[StoreItem]:
	var out: Array[StoreItem] = []
	for it in all_items():
		if it.page == page and is_offered(it):
			out.append(it)
	return out


## Whether `it` is on the shelf: not owned already, and opened up.
static func is_offered(it: StoreItem) -> bool:
	match it.type:
		&"plant":
			if Data.plant(it.param) == null or Saves.owns_plant(it.param):
				return false
			return it.unlock_level == &"" or Saves.is_cleared(it.unlock_level)
		&"upgrade":
			return not Saves.has_item(&"upgrades", it.param)
		&"currency":
			return it.count > 0
	return false


## True for wares that go away once bought.
static func sells_out(it: StoreItem) -> bool:
	return it.type != &"currency"


# --- prices and buying ----------------------------------------------------

## What `it` costs today: its price, cut for the plant of the week.
static func price(it: StoreItem) -> int:
	if it.is_weekly_plant() and weekly_plant() == it.param:
		return floori(it.base_price * it.weekly_discount)
	return it.base_price


static func can_buy(it: StoreItem) -> bool:
	return is_offered(it) and Saves.can_afford(it.currency, price(it))


## Pays for `it` and hands it over. False, and nothing spent, when it is not
## on sale or the player is short.
static func buy(it: StoreItem) -> bool:
	if not is_offered(it):
		return false
	if not Saves.spend_currency(it.currency, price(it)):
		return false
	match it.type:
		&"plant":
			Saves.unlock_plant(it.param)
		&"upgrade":
			Saves.grant_item(&"upgrades", it.param)
		&"currency":
			Saves.add_currency(it.param, it.count)
	return true


# --- plant of the week ----------------------------------------------------

static func _now() -> int:
	if now_override != 0:
		return now_override
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return int(Time.get_unix_time_from_system()) + bias * 60


## The local day the current week started on: the last Saturday.
static func week_start_day(now: int = 0) -> int:
	var day := floori((now if now != 0 else _now()) / float(SECONDS_PER_DAY))
	var weekday := posmod(day + EPOCH_WEEKDAY, 7)
	return day - posmod(weekday - SATURDAY, 7)


## Seconds until the next week starts.
static func seconds_left_in_week(now: int = 0) -> int:
	var t := now if now != 0 else _now()
	return (week_start_day(t) + 7) * SECONDS_PER_DAY - t


## "2d 5h", "3h 12m" or "45s": what is left of the week.
static func time_left_text(now: int = 0) -> String:
	var left := seconds_left_in_week(now)
	var days := left / SECONDS_PER_DAY
	var hours := (left % SECONDS_PER_DAY) / 3600
	var minutes := (left % 3600) / 60
	if days > 0:
		return "%dd %dh" % [days, hours]
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm %ds" % [minutes, left % 60]


## The ticket plants that take turns as plant of the week.
static func weekly_candidates() -> Array[StringName]:
	var out: Array[StringName] = []
	for it in all_items():
		if it.is_weekly_plant() and Data.plant(it.param) != null:
			out.append(it.param)
	return out


## This week's plant, picking a new one when the week has turned.
static func weekly_plant() -> StringName:
	refresh_week()
	return StringName(str(Saves.section(SECTION).get("weekly_plant", "")))


## Rolls the week over if it has turned since the store last looked: a new
## plant of the week, and the ticket wallet emptied (but not the first time
## the store is ever opened, which only picks a plant).
static func refresh_week(now: int = 0) -> void:
	var state := Saves.section(SECTION)
	var week := week_start_day(now)
	var had_week := state.has("week")
	if had_week and int(state["week"]) == week and str(state.get("weekly_plant", "")) != "":
		return
	if had_week and int(state["week"]) != week:
		Saves.set_currency(&"tickets", 0)
	state["week"] = week
	state["weekly_plant"] = String(_pick_weekly(state))
	Saves.set_section(SECTION, state)


## PVZGE's getNewWeeklyPlants: a plant not shown yet; once every one has had
## a turn, any but the most recent third.
static func _pick_weekly(state: Dictionary) -> StringName:
	var all := weekly_candidates()
	if all.is_empty():
		return &""
	var shown: Array = state.get("weekly_shown", [])
	var fresh := all.filter(func(p): return not shown.has(String(p)))
	if fresh.is_empty():
		var keep := floori(shown.size() / 3.0)
		var recent := shown.slice(maxi(shown.size() - keep - 1, 0))
		shown = recent
		fresh = all.filter(func(p): return not shown.has(String(p)))
		if fresh.is_empty():
			fresh = all
	var pick: StringName = fresh[rng.randi() % fresh.size()]
	shown.append(String(pick))
	state["weekly_shown"] = shown
	return pick
