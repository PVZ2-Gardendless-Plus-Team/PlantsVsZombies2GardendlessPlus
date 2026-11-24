class_name EntityComponent
extends Node
## Base class for every behaviour attached to a plant or zombie.
##
## Components are the composition half of the entity model: a Character owns
## its position, health and lane, while everything it *does* - shooting,
## producing sun, eating, exploding - is a component added as a child node.
##
## A mod replaces a behaviour by registering its own script under an existing
## component type name; nothing else in the game needs to know.

var host: Node = null          ## the Character this is attached to
var config: Dictionary = {}    ## the component's entry from the entity JSON


## Called once after the component is attached and `host`/`config` are set.
## Override instead of `_ready` so setup order is guaranteed.
func setup() -> void:
	pass


## Called when the player feeds this entity plant food. Return true if the
## component did something, so the food is only spent when it has an effect.
## Components that have no boosted behaviour simply do not override this.
func on_plantfood() -> bool:
	return false


func cfg(key: StringName, fallback: Variant = null) -> Variant:
	return config.get(key, fallback)


## Config value with a random jitter applied, for the common
## `interval` / `interval_jitter` pairing. Divided by the host's attack rate,
## so anything that buffs the entity speeds this up without the component
## needing to know a buff exists.
func cfg_jittered(key: StringName, jitter_key: StringName, fallback: float = 0.0) -> float:
	var base := float(config.get(key, fallback))
	var jitter := float(config.get(jitter_key, 0.0))
	var seconds: float = base + (randf() * 2.0 - 1.0) * jitter if jitter > 0.0 else base
	return scaled(seconds)


## Config value drawn uniformly from a `key` / `key_max` pair, which is how
## PopCap's {Min, Max} ranges arrive. A key with no `_max` is a fixed value.
func cfg_range(key: StringName, fallback: float = 0.0) -> float:
	var low := float(config.get(key, fallback))
	var high := float(config.get(StringName(String(key) + "_max"), low))
	return low if is_equal_approx(low, high) else randf_range(low, high)


## Scales a duration by the host's attack rate, and by its suppression - a
## buff speeds this up, a stun slows it to a crawl, and the component itself
## needs to know about neither.
func scaled(seconds: float) -> float:
	if host == null:
		return seconds
	return seconds / maxf(host.attack_rate * host.suppression * host.fire_rate_scale, 0.01)


## Whether this component takes over the host's attack. A zombie whose attack
## is claimed still stops at whatever blocks it, but deals no bite damage -
## the component does the damage instead, on its own schedule. This is how a
## gargantuar smashes rather than eats without the zombie knowing what a
## gargantuar is.
func claims_attack() -> bool:
	return false


## Whether this component moves the host itself. A boss hovers at its own
## column and charges on its own schedule, so it must not also be walking
## toward the house a lane at a time.
func claims_movement() -> bool:
	return false


## Return true to refuse the host's death. Called from `Character.die` before
## anything is torn down, so a component can convert a death into something
## else - a boss advancing a stage, a plant with a second wind.
func prevent_death() -> bool:
	return false
