class_name ConveyorSeedBank
extends SeedBank
## A belt of free seed packets that arrive over time.
##
## Nothing here costs sun and nothing recharges: a packet is either on the belt
## or it is not. Placing one takes it off the belt, and a replacement arrives
## after a delay that grows as the belt fills - so an empty belt refills
## quickly and a full one nearly stops.

signal packet_arrived(id: StringName)

## Most packets the belt can hold at once.
@export var capacity: int = 10

## Weighted pool entries: {type, weight, max}.
var pool: Array[Dictionary] = []
## {delay, max_packets}, sorted by threshold.
var drop_delays: Array[Dictionary] = []
## {speed, max_packets}, sorted by threshold. Belt speed is presentational.
var speeds: Array[Dictionary] = []

var _drop_timer: float = 0.0


## Builds the belt from a level's conveyor seedbank block.
func setup_conveyor(seedbank: Dictionary) -> void:
	packets.clear()
	pool.clear()
	drop_delays.clear()
	speeds.clear()

	for entry in (seedbank.get("plants", []) as Array):
		if entry is Dictionary and entry.get("type") != null:
			pool.append({
				"type": StringName(entry["type"]),
				"weight": maxf(float(entry.get("weight", 100)), 0.0),
				# A null max means unlimited on the belt at once.
				"max": int(entry["max"]) if entry.get("max") != null else -1,
			})
	drop_delays = _sorted_conditions(seedbank.get("drop_delay", []), "delay", 5.0)
	speeds = _sorted_conditions(seedbank.get("speed", []), "speed", 100.0)

	_drop_timer = 0.0     # the belt starts delivering immediately
	changed.emit()


## Conditions keyed by packet count, largest threshold last.
func _sorted_conditions(source: Array, value_key: String,
		fallback: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in source:
		if c is Dictionary:
			out.append({
				"value": float(c.get(value_key, fallback)),
				"threshold": int(c.get("max_packets", 0)),
			})
	out.sort_custom(func(a, b): return a["threshold"] < b["threshold"])
	if out.is_empty():
		out.append({"value": fallback, "threshold": 0})
	return out


## The condition that applies at the current packet count: the last one whose
## threshold the belt has reached.
func _condition_value(conditions: Array[Dictionary]) -> float:
	var value: float = conditions[0]["value"]
	for c in conditions:
		if packets.size() >= int(c["threshold"]):
			value = c["value"]
	return value


func current_drop_delay() -> float:
	return _condition_value(drop_delays)


func current_speed() -> float:
	return _condition_value(speeds)


func _process(delta: float) -> void:
	# Deliberately does not call super(): conveyor packets never recharge.
	if pool.is_empty() or packets.size() >= capacity:
		return
	_drop_timer -= delta
	if _drop_timer > 0.0:
		return
	_deliver()
	_drop_timer = current_drop_delay()


func _deliver() -> void:
	var choice := _pick()
	if choice == &"":
		return
	var def := Data.plant(choice)
	if def == null:
		push_warning("ConveyorSeedBank: unknown plant '%s'" % choice)
		return
	# Free and immediately usable: recharge 0 means it arrives ready.
	packets.append(SeedPacket.create(&"plant", choice, 0, 0.0, 1.0))
	packet_arrived.emit(choice)
	changed.emit()


## Weighted pick, skipping anything already at its limit on the belt.
func _pick() -> StringName:
	var counts := {}
	for p in packets:
		counts[p.id] = int(counts.get(p.id, 0)) + 1

	var eligible: Array[Dictionary] = []
	var total := 0.0
	for entry in pool:
		var limit: int = entry["max"]
		if limit >= 0 and int(counts.get(entry["type"], 0)) >= limit:
			continue
		eligible.append(entry)
		total += entry["weight"]
	if eligible.is_empty():
		return &""
	if total <= 0.0:
		return eligible[randi() % eligible.size()]["type"]

	var roll := randf() * total
	for entry in eligible:
		roll -= entry["weight"]
		if roll <= 0.0:
			return entry["type"]
	return eligible[-1]["type"]


## Puts one packet straight onto the belt, as a broken vase does with the
## plant inside it. Refused once the belt is full.
func add_packet(id: StringName) -> bool:
	if packets.size() >= capacity or Data.plant(id) == null:
		return false
	packets.append(SeedPacket.create(&"plant", id, 0, 0.0, 1.0))
	packet_arrived.emit(id)
	changed.emit()
	return true


## Mid-level changes from a ModifyConveyorWaveActionProps wave action.
func add_to_pool(entries: Array) -> void:
	for entry in entries:
		if not (entry is Dictionary) or entry.get("type") == null:
			continue
		var id := StringName(entry["type"])
		var existing := _pool_index(id)
		var record := {
			"type": id,
			"weight": maxf(float(entry.get("weight", 100)), 0.0),
			"max": int(entry["max"]) if entry.get("max") != null else -1,
		}
		if existing >= 0:
			pool[existing] = record
		else:
			pool.append(record)


func remove_from_pool(ids: Array) -> void:
	for id in ids:
		var i := _pool_index(StringName(id))
		if i >= 0:
			pool.remove_at(i)


func _pool_index(id: StringName) -> int:
	for i in pool.size():
		if pool[i]["type"] == id:
			return i
	return -1


# --- SeedBank overrides ---------------------------------------------------

## A packet on the belt is always usable; there is nothing to pay or wait for.
func is_recharged(slot: int) -> bool:
	return packet(slot) != null


func can_afford(_slot: int, _sun: int) -> bool:
	return true


func cost_of(_slot: int) -> int:
	return 0


## Placing takes the packet off the belt rather than recharging it.
func consume(slot: int) -> void:
	if slot >= 0 and slot < packets.size():
		packets.remove_at(slot)
		changed.emit()


func slots_are_stable() -> bool:
	return false
