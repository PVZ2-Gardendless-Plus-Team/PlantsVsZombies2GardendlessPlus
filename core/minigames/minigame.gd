class_name Minigame
extends Node
## A level played by different rules: nuts bowled from behind a line, vases
## broken open, plants matched in threes, zombies that never stop coming.
##
## Minigames are the third kind of level rule after objectives and lawn
## components, and are named, data-configured and replaceable the same way. A
## level lists them under `minigames`; each entry's `type` picks the script and
## the rest is the PVZGE module's own settings, in snake_case.
##
## A mode changes the level through the hooks below rather than the runner
## knowing about it: it can hold the waves back, stop sun falling, refuse
## placements, catch clicks on the lawn, and decide on its own when the level
## is won or lost.
##
## A pack ships one as `minigames/<type>.gd`; the file name is the type.

## Emitted when what the HUD shows for this mode changes.
signal progress_changed(minigame: Minigame)

var runner: Node = null        ## the LevelRunner
var board: Node = null         ## the Board
var config: Dictionary = {}    ## this mode's entry from the level

## Set by the runner once the player has picked seeds and the level is live.
var started: bool = false


## Called once after `runner`, `board` and `config` are set, with the lawn
## already laid out and the level's own placements made.
func setup() -> void:
	pass


## Called when the level starts running: straight away, or after the seed
## chooser closes.
func begin() -> void:
	pass


## Called every frame the level is running.
func tick(_delta: float) -> void:
	pass


func cfg(key: StringName, fallback: Variant = null) -> Variant:
	return config.get(key, fallback)


# --- how the mode changes the level --------------------------------------

## While true the runner does not move on to the level's next wave: Last
## Stand waits for the player to start the onslaught, Beghouled and the
## endless zones send their own zombies.
func holds_waves() -> bool:
	return false


## Whether sun keeps falling from the sky.
func drops_sky_sun() -> bool:
	return true


## Whether the player gets a shovel and plant food in this mode.
func allows_shovel() -> bool:
	return true


func allows_plant_food() -> bool:
	return true


## Whether the seed chooser is skipped, for a mode that hands out its own
## seeds (vases, a matching board).
func skips_seed_chooser() -> bool:
	return false


## Whether the seeds come on a belt: free packets that arrive or are handed
## out by the mode (a vase's plant), rather than a fixed bank.
func uses_belt() -> bool:
	return false


## The word "Ready... Set..." ends on: PLANT!, ROLL!, MATCH!...
func start_word() -> String:
	return ""


## The mode's one-line goal, shown before the level starts, in PVZGE's words.
func intro_text() -> String:
	return ""


## A refusal for placing `id` here, or "" to allow it. Registered with the
## board's placement checks while the mode is live.
func placement_refusal(_kind: StringName, _id: StringName, _row: int, _col: int) -> String:
	return ""


## A click on the lawn with nothing in hand, or with a seed in hand on a cell
## the mode owns. Return true to consume it.
func handle_click(_row: int, _col: int) -> bool:
	return false


# --- outcome --------------------------------------------------------------

## The mode's own win condition, checked together with the level's
## objectives: the level is won once both are met.
func is_met() -> bool:
	return true


## True once the mode can no longer be won.
func is_failed() -> bool:
	return false


## Progress for the HUD, e.g. "Matches 34 / 100". Empty shows nothing.
func describe() -> String:
	return ""


func notify_progress() -> void:
	progress_changed.emit(self)


## What the mode needs remembered across a save.
func save_state() -> Dictionary:
	return {}


func load_state(_state: Dictionary) -> void:
	pass
