class_name Character
extends Node2D
## Shared base for plants and zombies: grid position, health, damage, and the
## component list built from an EntityDef.
##
## This is the inheritance half of the model and deliberately stays thin. It
## owns only what every board entity has - where it is, how much health it has,
## and how it dies. Anything an entity *does* belongs in a component.

signal died(who: Character)
signal damaged(who: Character, amount: float, remaining: float)
signal tag_changed(who: Character, tag: StringName, present: bool)

@export var row: int = 0
@export var col: int = 0

var def: EntityDef
var board: Node = null
var health: float = 0.0
var max_health: float = 0.0
var is_dead: bool = false
## Whatever dealt the most recent blow. A plant that answers being eaten - a
## hypno-shroom turning its eater - reads this when it dies, so the zombie
## never has to know which plants bite back.
var last_damage_source: Node = null

## The visual, when extracted art covers this entity. Null leaves the
## placeholder drawing in place, so the game runs the same without any art.
var art: Armature = null
## How fast this entity's art runs relative to its rig. Each entity draws its
## own, a little either side of 1, as PVZGE does, so a row of sunflowers or a
## crowd of zombies does not bob in lockstep.
var art_rate: float = 1.0
## The state this entity idles in. A component swaps it while the entity is
## in a phase with its own resting look - a potato mine still underground -
## so every return to idle lands on the right animation.
var idle_state: StringName = &"idle"

var _components: Array[EntityComponent] = []
var _runtime_tags: Dictionary = {}   ## tags added or removed after spawn
var _timed_tags: Dictionary = {}     ## tag -> seconds left

## Buff multipliers something else has applied. Components read
## `attack_rate` when timing themselves, so a buff speeds up whatever the
## entity does without each component knowing who buffed it.
var attack_rate: float = 1.0
var resistance: float = 1.0
var _buff_left: float = 0.0
## The opposite of a buff: everything this entity does is divided by it, so a
## small value is a near-standstill. A plant has nothing to stop walking, so
## this is what a stun means for one.
var suppression: float = 1.0
var _suppress_left: float = 0.0


## Build this entity from a definition. Called once, right after instancing.
func initialize(entity_def: EntityDef, owning_board: Node) -> void:
	def = entity_def
	board = owning_board
	max_health = float(def.stat(&"toughness", 100.0))
	health = max_health
	_spawn_components()
	_attach_art()
	_on_initialized()


func _spawn_components() -> void:
	for spec in def.components:
		var comp := Components.create(spec, self)
		if comp == null:
			continue
		add_child(comp)
		_components.append(comp)
		comp.setup()


## Gives this entity its artwork if any was extracted for it. Subclasses say
## which kind they are; anything without a mapping keeps its placeholder.
func _attach_art() -> void:
	if def == null or not Art.is_available():
		return
	var built := Art.make(art_kind(), def.id)
	if built == null:
		return
	art = built
	art_rate = randf_range(0.9, 1.1)
	add_child(art)
	queue_redraw()


## Where this entity's shots appear, on the board. A rig whose mapping gives a
## `projectile_origin` - PVZGE's per-prefab spawn node (`PeaSpawnPoint`), in
## rig units with y up - fires from exactly there, at any scale or facing.
## Anything else fires from just ahead of its centre, as it always has: to the
## right for a plant, to the left for a zombie unless `direction` says.
func launch_point(direction: int = 0) -> Vector2:
	if art != null and def != null:
		var point: Array = Art.mapping(art_kind(), def.id).get("projectile_origin", [])
		if point.size() >= 2:
			# A mirrored rig has a negative x scale, which flips the point with it.
			return position + art.position + Vector2(float(point[0]) * art.scale.x,
					-float(point[1]) * art.scale.y)
	if direction == 0:
		direction = -1 if self is Zombie else 1
	return position + Vector2(24.0 * direction, -12.0)


## The namespace this entity's art is keyed under: "plant", "zombie", ...
func art_kind() -> StringName:
	return &""


## How long PVZGE fades into a state, in seconds. An attack (a shot, a bite)
## and a death ease in over a tenth of a second; everything else - walking,
## idling, going back to idle after an action - cuts straight to its pose,
## which is seamless because PopCap's rigs start and end those at rest.
const FADE_IN := {&"attack": 0.1, &"die": 0.1}


## Plays the animation this entity's mapping gives for a state, if it has one.
func play_art(state: StringName, loop: bool = true) -> bool:
	if art == null or def == null:
		return false
	if state == &"idle":
		state = idle_state
		if state == &"idle":
			return _play_idle()
	var name := Art.animation_for(art_kind(), def.id, state)
	return art.play(name, loop, false, float(FADE_IN.get(state, 0.0))) if name != &"" else false


## Idles the way PVZGE's AnimationController does. A rig whose mapping lists
## `idle_random` animations plays its idle once at a time, and each time it
## comes round there is a `random_rate`/200 chance (the prefab's RandRate, 100
## unless it says otherwise) of a fidget instead - the peashooter glancing
## about, the sunflower's sway. Anything else just loops its idle.
func _play_idle() -> bool:
	var entry := Art.mapping(art_kind(), def.id)
	var name := Art.animation_for(art_kind(), def.id, &"idle")
	var fidgets: Array = entry.get("idle_random", [])
	if fidgets.is_empty():
		return art.play(name, true, false, 0.0) if name != &"" else false
	if randf() < float(entry.get("random_rate", 100.0)) / 200.0:
		name = StringName(fidgets.pick_random())
	if name == &"" or not art.play(name, false, true, 0.0):
		return false
	if not art.animation_finished.is_connected(_on_art_finished):
		art.animation_finished.connect(_on_art_finished)
	return true


## Plays a one-shot and goes back to idling when it ends.
##
## This is what a component calls when it acts - a peashooter firing, a
## sunflower producing - so the component says what happened and never has to
## know what the entity should look like afterwards, or whether it has art.
func play_art_once(state: StringName) -> bool:
	if not play_art(state, false):
		return false
	if not art.animation_finished.is_connected(_on_art_finished):
		art.animation_finished.connect(_on_art_finished)
	return true


func _on_art_finished(_name: StringName) -> void:
	play_art(&"idle")


## How fast the art should play right now. Whatever slows or speeds the
## entity's behaviour slows or speeds its animation with it, so a stunned
## plant visibly crawls and a buffed one visibly hurries.
func art_speed() -> float:
	return art_rate * attack_rate * suppression


## Hook for subclasses; runs after components exist.
func _on_initialized() -> void:
	pass


## Speeds this entity up and toughens it for a while. Re-applying keeps the
## stronger multiplier and the longer remaining time.
func apply_buff(rate: float, resist: float, seconds: float) -> void:
	attack_rate = maxf(attack_rate, maxf(rate, 0.01))
	if resist > resistance:
		# Extra resistance raises current health along with the ceiling, so a
		# buff is felt immediately rather than only on the next hit.
		var ratio := resist / resistance
		resistance = resist
		max_health *= ratio
		health *= ratio
	_buff_left = maxf(_buff_left, seconds)
	set_runtime_tag(&"buffed", true)
	queue_redraw()


func is_buffed() -> bool:
	return _buff_left > 0.0


## Slows everything this entity does for `seconds`. Components divide their
## timers by `attack_rate * suppression` through `scaled()`, so this reaches
## every one of them without any component knowing it can be suppressed.
## Re-applying keeps the stronger factor and the longer time.
func apply_suppression(factor: float, seconds: float) -> void:
	suppression = minf(suppression if _suppress_left > 0.0 else 1.0,
			clampf(factor, 0.01, 1.0))
	_suppress_left = maxf(_suppress_left, seconds)
	set_runtime_tag(&"suppressed", true)
	queue_redraw()


func is_suppressed() -> bool:
	return _suppress_left > 0.0


func _tick_suppression(delta: float) -> void:
	if _suppress_left <= 0.0:
		return
	_suppress_left -= delta
	if _suppress_left > 0.0:
		return
	suppression = 1.0
	set_runtime_tag(&"suppressed", false)
	queue_redraw()


## Frozen in a block: none of this entity's behaviour runs until `release`.
## Kept separate from suppression, which only slows things down - an encased
## peashooter must not fire at all, and an encased imp must not walk.
func encase() -> void:
	set_runtime_tag(&"encased", true)
	for comp in _components:
		comp.process_mode = Node.PROCESS_MODE_DISABLED
	queue_redraw()


func release() -> void:
	if not is_encased():
		return
	set_runtime_tag(&"encased", false)
	for comp in _components:
		comp.process_mode = Node.PROCESS_MODE_INHERIT
	queue_redraw()


func is_encased() -> bool:
	return has_tag(&"encased")


func _tick_buff(delta: float) -> void:
	if _buff_left <= 0.0:
		return
	_buff_left -= delta
	if _buff_left > 0.0:
		return
	if resistance != 1.0:
		max_health /= resistance
		health = minf(health / resistance, max_health)
	attack_rate = 1.0
	resistance = 1.0
	set_runtime_tag(&"buffed", false)
	queue_redraw()


func _process(delta: float) -> void:
	_tick_buff(delta)
	_tick_suppression(delta)
	_tick_timed_tags(delta)
	if art != null:
		art.set_speed_scale(art_speed())


## Grants a tag for a while - shadow power from a gloom-shroom, say. Topping it
## up keeps the longer time.
func add_timed_tag(tag: StringName, seconds: float) -> void:
	_timed_tags[tag] = maxf(_timed_tags.get(tag, 0.0), seconds)
	set_runtime_tag(tag, true)


func _tick_timed_tags(delta: float) -> void:
	if _timed_tags.is_empty():
		return
	for tag in _timed_tags.keys():
		_timed_tags[tag] -= delta
		if _timed_tags[tag] <= 0.0:
			_timed_tags.erase(tag)
			set_runtime_tag(tag, false)


# --- tags ----------------------------------------------------------------

## Tags come from the definition, with runtime overrides layered on top, so a
## status effect can grant or strip a capability without mutating shared data.
func has_tag(tag: StringName) -> bool:
	if _runtime_tags.has(tag):
		return _runtime_tags[tag]
	return def != null and def.has_tag(tag)


func set_runtime_tag(tag: StringName, present: bool) -> void:
	if has_tag(tag) == present:
		return
	_runtime_tags[tag] = present
	tag_changed.emit(self, tag, present)


func clear_runtime_tag(tag: StringName) -> void:
	if _runtime_tags.erase(tag):
		tag_changed.emit(self, tag, has_tag(tag))


func matches(required: Array, excluded: Array = []) -> bool:
	for t in required:
		if not has_tag(StringName(t)):
			return false
	for t in excluded:
		if has_tag(StringName(t)):
			return false
	return true


# --- health --------------------------------------------------------------

func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	if source != null:
		last_damage_source = source
	# Armor components absorb first and may reduce what reaches the body.
	for comp in _components:
		if comp.has_method("absorb_damage"):
			amount = float(comp.absorb_damage(amount))
			if amount <= 0.0:
				return
	health = maxf(0.0, health - amount)
	damaged.emit(self, amount, health)
	queue_redraw()
	if health <= 0.0:
		die()


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(max_health, health + amount)
	queue_redraw()


func die() -> void:
	if is_dead:
		return
	# Last chance for a component to refuse: a staged boss moves to its next
	# stage here rather than dying, and nothing else has to know it has
	# stages.
	for comp in _components:
		if comp.prevent_death():
			health = maxf(health, 1.0)
			queue_redraw()
			return
	is_dead = true
	died.emit(self)
	_on_death()
	queue_redraw()


func _on_death() -> void:
	queue_free()


func health_fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


# --- components ----------------------------------------------------------

## Feeds this entity. Returns true if any component responded, so the board
## only spends the food when it actually did something.
func apply_plant_food() -> bool:
	if is_dead:
		return false
	var used := false
	for c in _components:
		if c.on_plantfood():
			used = true
	if used:
		queue_redraw()
	return used


## Adds a behaviour after spawn. This is how one entity marks another - a sun
## bean leaving its eater sun-infected, a shrinking violet shrinking a zombie -
## without the target's definition having to list every way it can be marked.
func attach_component(type: StringName, config: Dictionary = {}) -> EntityComponent:
	var spec := ComponentSpec.new()
	spec.type = type
	spec.config = config.duplicate(true)
	var comp := Components.create(spec, self)
	if comp == null:
		return null
	add_child(comp)
	_components.append(comp)
	comp.setup()
	return comp


func detach_component(comp: EntityComponent) -> void:
	_components.erase(comp)
	comp.queue_free()


func component(type: StringName) -> EntityComponent:
	for c in _components:
		if StringName(c.name) == type:
			return c
	return null


func components() -> Array[EntityComponent]:
	return _components


func entity_id() -> StringName:
	return def.id if def else &""
