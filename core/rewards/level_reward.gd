class_name LevelReward
extends RefCounted
## What winning a level hands the player.
##
## PVZGE's LevelDefinition names a FirstRewardType and FirstRewardParam: the
## prize dropped the first time a level is won. Every later win, and any level
## without one, drops a coin bag instead. The prize is granted the moment it
## drops - as PVZGE's specialPrizeOnEnable does - so quitting before picking
## it up cannot lose it; collecting it only plays it out.
##
## A level writes it as `"reward": {"type": ..., "param": ...}`. Types:
##
##   unlock_plant  param is a plant id; it becomes choosable
##   upgrade       param is an upgrade id, kept in the `upgrades` collection
##   worldtrophy   param is a trophy id (map, sauce, powerupgadget...), kept in
##                 `trophies`; `worldkey` adds a world key instead
##   note          param is a note id (note_egypt...), kept in `notes`
##   coins         a coin bag worth `amount`
##   gems          `amount` gems, straight into the wallet
##   coinbag       the default: a bag of five silver coins
##
## Anything else (PVZGE's pinata, giftbox, collectable) falls back to a coin
## bag, as PVZGE's spawnPrize does for a type it has no prize for.

const COIN_BAG := &"coinbag"
## Coins a bag bursts into, and what each is worth: PVZGE's coinbag drops five
## silver coins.
const COIN_BAG_COINS := 5
const SILVER_COIN := 10

const KNOWN_TYPES := [&"unlock_plant", &"upgrade", &"worldtrophy", &"note",
		&"coins", &"gems", COIN_BAG]

var type: StringName = COIN_BAG
var param: StringName = &""
## What a coin bag or a gem reward is worth.
var amount: int = 0


static func coin_bag() -> LevelReward:
	var r := LevelReward.new()
	r.amount = COIN_BAG_COINS * SILVER_COIN
	return r


## Reads a level's `reward` entry; a missing, unknown or empty one is a coin bag.
static func from_value(value: Variant) -> LevelReward:
	if not (value is Dictionary):
		return coin_bag()
	var r := LevelReward.new()
	r.type = StringName(value.get("type", COIN_BAG))
	r.param = StringName(str(value.get("param", "")))
	r.amount = int(value.get("amount", 0))
	if not KNOWN_TYPES.has(r.type) or r.type == COIN_BAG:
		return coin_bag()
	if r.type in [&"coins", &"gems"]:
		if r.amount <= 0:
			return coin_bag()
		if r.type == &"coins":
			var bag := coin_bag()
			bag.amount = r.amount
			return bag
	elif r.param == &"" or r.param == &"none":
		return coin_bag()
	if r.type == &"unlock_plant" and Data.plant(r.param) == null:
		push_warning("LevelReward: unknown plant '%s', dropping a coin bag" % r.param)
		return coin_bag()
	return r


## The prize `level` drops when won: its own reward the first time, a coin bag
## once it has been cleared before.
static func for_level(level: Dictionary, first_win: bool) -> LevelReward:
	if not first_win:
		return coin_bag()
	return from_value(level.get("reward"))


## True for prizes that get the award screen; coin bags and gems just bank.
func is_award() -> bool:
	return not (type in [COIN_BAG, &"gems"])


## Hands the prize over. Coin bags are paid coin by coin as they are picked
## up, so this grants nothing for them.
func grant() -> void:
	match type:
		&"unlock_plant":
			Saves.unlock_plant(param)
		&"upgrade":
			Upgrades.grant(param)
		&"worldtrophy":
			if param == &"worldkey":
				Saves.add_currency(&"worldkeys", 1)
			else:
				Saves.grant_item(&"trophies", param)
		&"note":
			Saves.grant_item(&"notes", param)
		&"gems":
			Saves.add_currency(&"gems", amount)


## Heading on the award screen.
func title() -> String:
	match type:
		&"unlock_plant":
			return tr("You got a new PLANT!")
		&"upgrade":
			return tr("You got a new UPGRADE!")
		&"worldtrophy":
			return tr("You've earned a World Key!") if param == &"worldkey" else tr("You got a new TROPHY!")
		&"note":
			return tr("You found a note!")
		&"gems":
			return tr("You got %d gems!") % amount
	return tr("You got %d coins!") % amount


## The prize's own name, for the award screen and the drop's label.
func item_name() -> String:
	if type == &"unlock_plant":
		return String(param).capitalize()
	if type == &"upgrade" and Upgrades.exists(param):
		return Upgrades.display_name(param)
	if type == &"note":
		return tr("Note: %s") % String(param).trim_prefix("note_").capitalize()
	if param != &"":
		return String(param).capitalize()
	return title()


func describe() -> String:
	return "%s %s" % [type, param] if param != &"" else "%s x%d" % [type, amount]
