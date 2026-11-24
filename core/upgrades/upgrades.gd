class_name Upgrades
extends RefCounted
## The player's permanent upgrades: PVZGE's fourteen perks, such as Sun Bonus,
## the extra seed slots, Shovel Bonus and Mower Launch.
##
## PVZGE has no per-plant levels; an "upgrade" there is one of these perks,
## won as a level's first reward or bought in the store, and switched on or off
## in the almanac's Upgrades page. Each is a file in `upgrades/`
## (data/native/upgrades/<id>.json), so a pack can add its own or change one:
##
##   id           the upgrade's id, as levels and the store name it
##   type         what it does - see the TYPES below
##   amount       how much one copy adds (25 sun, 0.25 of the sun cost...)
##   order        where the Upgrades page lists it
##   world        the world whose seed packet backing its card uses
##   sprite       PVZGE's UpgradeTrophy animation for its icon
##   name, description   per language, {"en": ..., "zh": ...}
##
## Owning one is the `upgrades` collection in Saves; switching one off puts it
## in `upgrades_disabled`. The whole system is optional: Settings'
## `upgrades_enabled` switches every upgrade off at once. Everything a level asks - how much extra sun, how
## many seed slots - goes through the type totals here, so two copies of a
## type stack the way PVZGE's getUpgradeProps adds them up.

const OWNED := &"upgrades"
const DISABLED := &"upgrades_disabled"

## What each type does, with PVZGE's amount for one copy when a file leaves
## `amount` out.
const STARTING_SUN := &"starting_sun"   ## sun added to the level's starting sun
const PF_SLOT := &"pf_slot"             ## one more plant food the bar holds
const FIRST_AID := &"firstaid"          ## replanting a damaged defender heals it
const REFRESH := &"refresh"             ## plant food on a packet ends its recharge
const SUN_SHOVEL := &"sunshovel"        ## share of the sun cost a shovel gives back
const SEED_SLOT := &"seedslot"          ## one more seed chooser slot
const MANUAL_MOWER := &"manual_mower"   ## mowers the player may launch by holding
const SKY_SHIELD := &"sky_shield"       ## extra toughness for a Sky City ship

const DEFAULT_AMOUNT := {
	STARTING_SUN: 25.0,
	PF_SLOT: 1.0,
	SUN_SHOVEL: 0.25,
	SEED_SLOT: 1.0,
	MANUAL_MOWER: 1.0,
	SKY_SHIELD: 0.5,
}

## PVZGE's caps: the plant food bar stops at 5, the chooser at 8 slots.
const MAX_PLANT_FOOD := 5


# --- the catalogue ---------------------------------------------------------

## Every upgrade, in the order the Upgrades page lists them.
static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in Data.upgrades:
		out.append(Data.upgrades[id])
	out.sort_custom(func(a, b):
		var oa := int(a.get("order", 999))
		var ob := int(b.get("order", 999))
		return oa < ob if oa != ob else String(a.get("id", "")) < String(b.get("id", "")))
	return out


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for def in all():
		out.append(StringName(def.get("id", "")))
	return out


static func def(id: StringName) -> Dictionary:
	return Data.upgrade(id)


static func exists(id: StringName) -> bool:
	return not Data.upgrade(id).is_empty()


static func type_of(id: StringName) -> StringName:
	return StringName(Data.upgrade(id).get("type", ""))


static func amount_of(id: StringName) -> float:
	var d := Data.upgrade(id)
	var kind := StringName(d.get("type", ""))
	return float(d.get("amount", DEFAULT_AMOUNT.get(kind, 1.0)))


static func display_name(id: StringName) -> String:
	return localized(Data.upgrade(id).get("name"), String(id))


static func description(id: StringName) -> String:
	return localized(Data.upgrade(id).get("description"), "")


## Picks the player's language from a {"en": ..., "zh": ...} entry, falling
## back to English, then to whatever is there.
static func localized(entry: Variant, fallback: String) -> String:
	if entry is String:
		return entry
	if not (entry is Dictionary) or (entry as Dictionary).is_empty():
		return fallback
	var locale := TranslationServer.get_locale()
	for key in [locale, locale.get_slice("_", 0), "en"]:
		if entry.has(key):
			return str(entry[key])
	return str(entry.values()[0])


# --- the player's --------------------------------------------------------

static func owns(id: StringName) -> bool:
	return Saves.has_item(OWNED, id)


## Gives the player an upgrade - a level reward or a store purchase. Returns
## false if they had it already.
static func grant(id: StringName) -> bool:
	if not exists(id):
		push_warning("Upgrades: unknown upgrade '%s'" % id)
	return Saves.grant_item(OWNED, id)


## Whether an owned upgrade is switched on. New ones are, as in PVZGE.
static func is_enabled(id: StringName) -> bool:
	return not Saves.has_item(DISABLED, id)


## The almanac's Enabled/Disabled toggle.
static func set_enabled(id: StringName, on: bool) -> void:
	if on:
		Saves.revoke_item(DISABLED, id)
	else:
		Saves.grant_item(DISABLED, id)


## Owned and switched on: the upgrades a level applies.
static func is_active(id: StringName) -> bool:
	return system_enabled() and owns(id) and is_enabled(id)


## The master switch: Settings' `upgrades_enabled`. Off, no upgrade applies
## and every level plays as if none were owned - ownership and the
## per-upgrade switches are kept for when it comes back on.
static func system_enabled() -> bool:
	return bool(Settings.get_value(&"upgrades_enabled"))


static func owned() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ids():
		if owns(id):
			out.append(id)
	return out


## What every active upgrade of `kind` adds up to.
static func total(kind: StringName) -> float:
	var sum := 0.0
	for id in Data.upgrades:
		if type_of(id) == kind and is_active(id):
			sum += amount_of(id)
	return sum


static func _any_active(kind: StringName) -> bool:
	for id in Data.upgrades:
		if type_of(id) == kind and is_active(id):
			return true
	return false


# --- what a level asks ---------------------------------------------------

## Sun added to every level's starting sun.
static func starting_sun_bonus() -> int:
	return roundi(total(STARTING_SUN))


## Plant food the bar holds: PVZGE's 3, one more per slot upgrade, at most 5.
static func plant_food_slots(base: int = 3) -> int:
	return mini(base + roundi(total(PF_SLOT)), maxi(base, MAX_PLANT_FOOD))


## Seed chooser slots: the base count plus the slot upgrades, under the cap.
static func seed_slots(base: int, cap: int) -> int:
	return mini(base + roundi(total(SEED_SLOT)), maxi(base, cap))


## Share of a plant's sun cost the shovel gives back. 0 without the upgrade.
static func shovel_refund_rate() -> float:
	return total(SUN_SHOVEL)


## Replanting a damaged defender on itself patches it up to full.
static func has_first_aid() -> bool:
	return _any_active(FIRST_AID)


## Plant food dropped on a recharging packet makes it ready.
static func has_instant_recharge() -> bool:
	return _any_active(REFRESH)


## Mowers the player may launch by hand in each level.
static func manual_mowers() -> int:
	return roundi(total(MANUAL_MOWER))


## Extra share of toughness for a Sky City ship's shield. The port has no ship
## yet; this is here for the level module that adds one.
static func sky_shield_bonus() -> float:
	return total(SKY_SHIELD)


static func summary() -> String:
	return "upgrades: %d known, %d owned" % [Data.upgrades.size(), owned().size()]
