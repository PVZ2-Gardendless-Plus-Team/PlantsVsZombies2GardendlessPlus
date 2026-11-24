extends Objective
## Destroy a number of zombies, optionally only of certain kinds.
##
## Config: count - how many; types - zombie ids that count (any if omitted);
## tags - tags a zombie must carry to count.

var count: int = 10

var _killed: int = 0
var _types: Array = []
var _tags: Array = []


func setup() -> void:
	count = int(cfg(&"count", 10))
	_types = cfg(&"types", []) as Array
	_tags = cfg(&"tags", []) as Array


func on_zombie_died(zombie: Node) -> void:
	if not _types.is_empty() and not _types.has(String(zombie.entity_id())):
		return
	if not _tags.is_empty() and not zombie.matches(_tags):
		return
	_killed += 1
	notify_progress()


func save_state() -> Dictionary:
	return {
		"killed": _killed,
		"failed": failed,
	}


func load_state(state: Dictionary) -> void:
	_killed = int(state.get("killed", _killed))
	failed = bool(state.get("failed", false))
	notify_progress()


func is_met() -> bool:
	return _killed >= count


func describe() -> String:
	return tr("Zombies destroyed: %d / %d") % [_killed, count]
