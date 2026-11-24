class_name SeedBank
extends Node
## The player's seed slots: what can be planted, and when each is ready again.
##
## Availability is two independent gates - the packet must have recharged, and
## the player must be able to afford it. Keeping them separate means the HUD
## can show *why* a packet is unusable.
##
## This is the chooser bank, where slots are fixed and recharge after use.
## ConveyorSeedBank replaces that with a belt of free packets.

signal changed

## Scales every recharge time. Levels listing SeedPacketHalfTimeModule set
## this to 0.5, which is what the early tutorial levels use.
@export var recharge_scale: float = 1.0

var packets: Array[SeedPacket] = []


## Rebuilds the slots from a level's seed list ({kind, id} entries).
func setup(seeds: Array, half_recharge: bool = false) -> void:
	recharge_scale = 0.5 if half_recharge else 1.0
	packets.clear()
	for seed in seeds:
		var kind := StringName(seed.get("kind", &"plant"))
		var id := StringName(seed.get("id", &""))
		var def: EntityDef = Data.zombie(id) if kind == &"zombie" else Data.plant(id)
		if def == null:
			push_warning("SeedBank: unknown %s '%s'" % [kind, id])
			continue
		packets.append(SeedPacket.create(
				kind, id,
				# A mode may price a packet itself (a Beghouled upgrade).
				int(seed.get("cost", def.stat(&"sun_cost", 100))),
				float(def.stat(&"cooldown", 5.0)) * recharge_scale,
				float(def.stat(&"cooldown_from", 1.0))))
	changed.emit()


func _process(delta: float) -> void:
	var any := false
	for p in packets:
		if p.tick(delta):
			any = true
	if any:
		changed.emit()


func packet(slot: int) -> SeedPacket:
	return packets[slot] if slot >= 0 and slot < packets.size() else null


func size() -> int:
	return packets.size()


## True when the packet has recharged. Affordability is checked separately so
## the HUD can distinguish "still charging" from "not enough sun".
func is_recharged(slot: int) -> bool:
	var p := packet(slot)
	return p != null and p.is_recharged()


func can_afford(slot: int, sun: int) -> bool:
	var p := packet(slot)
	return p != null and sun >= p.cost


func can_use(slot: int, sun: int) -> bool:
	return is_recharged(slot) and can_afford(slot, sun)


## Starts the packet recharging after a successful placement.
func spend(slot: int) -> void:
	var p := packet(slot)
	if p != null:
		p.spend()
		changed.emit()


## Makes a packet ready at once: plant food on it, with Instant Recharge.
func finish_recharge(slot: int) -> void:
	var p := packet(slot)
	if p != null and not p.is_recharged():
		p.charge = p.recharge
		changed.emit()


## What a successful placement does to the packet. The chooser recharges it;
## a conveyor belt takes it away instead.
func consume(slot: int) -> void:
	spend(slot)


## Sun charged for a placement. Conveyor packets are free.
func cost_of(slot: int) -> int:
	var p := packet(slot)
	return p.cost if p != null else 0


## True when the slot list itself changes shape, so the HUD knows to rebuild
## its buttons rather than just restyle them.
func slots_are_stable() -> bool:
	return true


## Charge per slot, so a resumed level does not hand back full packets.
func snapshot() -> Array:
	var out: Array = []
	for p in packets:
		out.append({"kind": String(p.kind), "id": String(p.id),
				"charge": p.charge})
	return out


func apply_snapshot(state: Array) -> void:
	# Matched by id rather than position, so a level whose seed list changed
	# between save and load restores what it still has. A plant held twice -
	# an Imitater's copy - matches its slots in order.
	var used: Dictionary = {}
	for entry in state:
		if not (entry is Dictionary):
			continue
		var slot := slot_of(StringName(entry.get("kind", &"plant")),
				StringName(entry.get("id", &"")), used)
		used[slot] = true
		var p := packet(slot)
		if p != null:
			p.charge = clampf(float(entry.get("charge", p.recharge)),
					0.0, p.recharge)
	changed.emit()


## The first slot holding `kind`/`id`, passing over any slot in `skip`.
func slot_of(kind: StringName, id: StringName, skip: Dictionary = {}) -> int:
	for i in packets.size():
		if packets[i].kind == kind and packets[i].id == id and not skip.has(i):
			return i
	return -1
