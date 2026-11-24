class_name CampaignDef
extends Resource
## An ordered run of levels, and the thread that ties one level to the next.
##
## Kept as data rather than hardcoded so a pack can add its own campaign, or
## insert levels into an existing one, without touching game code.

@export var id: StringName = &""
@export var display_name: String = ""
## Level ids, played in this order.
@export var levels: Array[StringName] = []
## Shown when the last level is cleared.
@export var completion_message: String = "Campaign complete!"

@export_group("World map")
## Position among the worlds on the map; lower comes first.
@export var order: int = 0
## Campaign that must be finished before this one opens. Empty means open
## from the start.
@export var unlock_after: StringName = &""
## Line shown under the world's name.
@export var description: String = ""
## Tint for the world's page when it has no island map.
@export var map_color: Color = Color(0.25, 0.45, 0.2)
## The floating-island map the world is drawn on: a PVZGE world's codename
## (`egypt`, `modern`...) for one of data/native/worldmaps/, or a path to a
## layout file of a pack's own. Empty draws the plain path of level nodes.
@export var world_map: String = ""
## Hidden from the world map, for campaigns that are only reached by id
## (test runs, a pack's internal sequences).
@export var hidden: bool = false

var source_mod: StringName = &"base"
var source_path: String = ""


static func from_dict(d: Dictionary) -> CampaignDef:
	var c := CampaignDef.new()
	c.id = StringName(d.get("id", &""))
	c.display_name = String(d.get("name", d.get("id", "")))
	c.completion_message = String(d.get("completion_message", c.completion_message))
	c.order = int(d.get("order", c.order))
	c.unlock_after = StringName(d.get("unlock_after", &""))
	c.description = String(d.get("description", ""))
	c.hidden = bool(d.get("hidden", false))
	c.world_map = String(d.get("world_map", ""))
	if d.has("map_color"):
		c.map_color = Color.from_string(String(d["map_color"]), c.map_color)
	for level_id in (d.get("levels", []) as Array):
		c.levels.append(StringName(level_id))
	return c


func first_level() -> StringName:
	return levels[0] if not levels.is_empty() else &""


func index_of(level_id: StringName) -> int:
	return levels.find(level_id)


## The level after `level_id`, or &"" when that was the last one.
func next_after(level_id: StringName) -> StringName:
	var i := index_of(level_id)
	if i < 0 or i + 1 >= levels.size():
		return &""
	return levels[i + 1]


func is_last(level_id: StringName) -> bool:
	return index_of(level_id) == levels.size() - 1


## Whether every level has been cleared. `is_cleared` takes a level id.
func is_complete(is_cleared: Callable) -> bool:
	if levels.is_empty():
		return false
	for level_id in levels:
		if not is_cleared.call(level_id):
			return false
	return true


## Levels open in order: the first is always playable, each later one once
## the level before it is cleared. A cleared level stays open for replays.
func is_level_unlocked(level_id: StringName, is_cleared: Callable) -> bool:
	var i := index_of(level_id)
	if i < 0:
		return false
	return i == 0 or is_cleared.call(levels[i - 1]) or is_cleared.call(level_id)


## The level the player would most likely play next: the first uncleared one,
## or the last level when all are done.
func next_unplayed(is_cleared: Callable) -> StringName:
	for level_id in levels:
		if not is_cleared.call(level_id):
			return level_id
	return levels[-1] if not levels.is_empty() else &""
