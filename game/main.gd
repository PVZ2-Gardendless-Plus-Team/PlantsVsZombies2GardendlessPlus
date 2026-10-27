extends Node2D
## The level screen: builds the board, wires the HUD, and runs a level.
##
## Normally opened by the App from the world map. Run on its own (F6 in the
## editor) it plays its campaign straight through, as before.

## The player asked to leave: `destination` is &"map" or &"menu".
signal exit_requested(destination: StringName)

const APP_SCENE := "res://game/app.tscn"

## Campaign to play. Clearing a level advances to the next one in its list.
@export var campaign_id: StringName = &"tutorial"
## Level to begin at. Empty starts at the campaign's first level; setting it
## to any level id jumps straight there, which is handy while testing.
@export var start_level: StringName = &""

@export_group("Saving")
## Seconds between autosaves while a level is running. Every level keeps its
## own slot, so several can be part-played at once.
@export var autosave_interval: float = 10.0
## Resume a part-played level instead of restarting it.
@export var resume_saves: bool = true

@export_group("Pacing")
## Seconds the result is shown before the next level begins.
@export var level_transition_delay: float = 2.5
## Seconds before a failed level restarts.
@export var retry_delay: float = 3.0
## Go back to the world map after a win instead of straight on to the next
## level. The App turns this on; a level run on its own plays straight through.
@export var return_to_map: bool = false

@export_group("HUD")
@export var hud_font_size: int = 18
@export var seed_button_size := Vector2(96, 56)
## Speed applied while Fast Forward is toggled on.
@export_range(1.0, 8.0) var fast_forward_scale: float = 2.5

@onready var board: Board = $Board
@onready var runner: LevelRunner = $LevelRunner

var seed_bank: SeedBank
var pause_menu: PauseMenu

var _seed_buttons: Array[SeedPacketView] = []
## {kind, id} per slot, parallel to _seed_buttons.
var _seeds: Array[Dictionary] = []
var _status: Label
var _sun_counter: SunCounter
var _coin_counter: CoinCounter
## Shown after a prize other than coins is picked up.
var _award: AwardScreen
## The won level's prize, waiting on the lawn to be collected.
var _reward_drop: RewardDrop
## Where the last zombie fell: the prize drops there, as in PVZGE.
var _last_zombie_at: Variant = null
var _shovel_button: ShovelButton
var _plant_food_bar: PlantFoodBar
var _banner: LevelBanner
var _wave_label: Label
var _level_label: Label
var _seed_bar: HBoxContainer

var _mode_label: Label
var _objective_label: Label
var _ability_label: Label
var _conveyor_level: bool = false
var _fast_forward: bool = false

## The pre-level seed picker, built the first time a level needs it.
var _chooser: SeedChooser

var _campaign: CampaignDef
var _current_level: StringName = &""
## Guards against a result firing twice while a transition is already queued.
var _transitioning: bool = false
var _autosave_timer: float = 0.0


func _ready() -> void:
	_build_hud()
	_build_pause_menu()
	board.sun_changed.connect(_on_sun_changed)
	board.plant_food_changed.connect(_on_plant_food_changed)
	board.lawn_ability_changed.connect(_on_lawn_ability_changed)
	board.shovel_used.connect(_refresh_mode_label)
	board.level_lost.connect(_on_lost)
	board.zombie_died.connect(_on_zombie_died)
	runner.seedbank_ready.connect(_on_seedbank_ready)
	runner.wave_started.connect(_on_wave_started)
	runner.level_complete.connect(_on_won)
	runner.level_failed.connect(_on_objective_failed)
	runner.objectives_changed.connect(_on_objectives_changed)

	print("[boot] ", Data.summary())
	print("[boot] ", Components.summary())
	print("[boot] ", Mods.summary())
	print("[boot] ", Audio.summary())
	print("[boot] ", Art.summary())
	print("[boot] ", Saves.summary())

	_campaign = Data.campaign(campaign_id)
	var first := start_level
	if first == &"":
		if _campaign == null:
			_status.text = "Campaign '%s' not found" % campaign_id
			return
		first = _campaign.first_level()
	# Jumping straight to a level should still follow its campaign afterwards.
	if _campaign == null:
		_campaign = Data.campaign_for_level(first)
	load_level(first)


## Clears the board and starts `level_id`.
func load_level(level_id: StringName) -> void:
	var level := Data.level(level_id)
	if level.is_empty():
		_status.text = "Level '%s' not found" % level_id
		push_warning("Main: unknown level '%s'" % level_id)
		return

	_current_level = level_id
	_transitioning = false
	_autosave_timer = autosave_interval
	_last_zombie_at = null
	_reward_drop = null
	if _award != null:
		_award.hide()
	board.shovel_active = false
	board.plant_food_active = false
	board.reset()
	_close_chooser()
	runner.start(level, board)

	# A part-played level resumes where it was left rather than restarting.
	var save := Saves.load_save(level_id) if resume_saves else {}
	if not save.is_empty() and runner.needs_seed_choice():
		# The hand was picked when the level was first played; keep it.
		_use_chosen_seeds(_saved_seed_ids(save))
	if Saves.restore(save, runner, board, seed_bank):
		print("[save] resumed '%s' from %s"
				% [level_id, save.get("saved_at", "an earlier session")])
	elif runner.needs_seed_choice():
		_open_chooser()

	_status.text = ""
	_wave_label.text = ""
	_sun_counter.set_total(board.sun, true)
	# A chooser level says "Ready, Set, Plant!" once the player has picked.
	if runner.running:
		_banner.ready_set_plant()
	_refresh_mode_label()
	_level_label.text = _level_title(level)
	_refresh_ability_label()


func _level_title(level: Dictionary) -> String:
	# The world's own name, which a pack can rename without touching levels.
	var world := runner.world_name()
	var title := str(level.get("comment", level.get("name", _current_level)))
	if world != "":
		title = "%s - %s" % [world, title]
	if _campaign != null:
		var i := _campaign.index_of(_current_level)
		if i >= 0:
			return "%s  -  %d / %d" % [title, i + 1, _campaign.levels.size()]
	return title


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := VBoxContainer.new()
	root.position = Vector2(20, 16)
	layer.add_child(root)

	# The tools along the top, PVZGE-style: sun, packets, plant food, shovel.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)

	_sun_counter = SunCounter.new(hud_font_size + 6)
	top.add_child(_sun_counter)
	_seed_bar = HBoxContainer.new()
	_seed_bar.add_theme_constant_override("separation", 8)
	top.add_child(_seed_bar)
	_plant_food_bar = PlantFoodBar.new(board.max_plant_food, hud_font_size)
	_plant_food_bar.pressed.connect(_toggle_plant_food)
	top.add_child(_plant_food_bar)
	_shovel_button = ShovelButton.new()
	_shovel_button.board = board
	_shovel_button.pressed.connect(_toggle_shovel)
	top.add_child(_shovel_button)
	_coin_counter = CoinCounter.new(hud_font_size + 2)
	top.add_child(_coin_counter)

	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 24)
	root.add_child(info)
	_wave_label = _make_label("")
	info.add_child(_wave_label)
	_level_label = _make_label("")
	info.add_child(_level_label)
	_mode_label = _make_label("")
	info.add_child(_mode_label)
	_status = _make_label("")
	info.add_child(_status)
	_objective_label = _make_label("")
	root.add_child(_objective_label)
	_ability_label = _make_label("")
	root.add_child(_ability_label)

	# Its own layer above the HUD, so the words cross the whole screen.
	var banners := CanvasLayer.new()
	banners.layer = layer.layer + 1
	add_child(banners)
	_banner = LevelBanner.new()
	banners.add_child(_banner)

	# Over the chooser's layer, under the pause menu.
	var awards := CanvasLayer.new()
	awards.layer = 6
	add_child(awards)
	_award = AwardScreen.new()
	awards.add_child(_award)
	_award.continued.connect(_finish_level.bind(0.0))


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", hud_font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _on_seedbank_ready(seeds: Array) -> void:
	# The bank owns cost and recharge; the buttons are just a view of it.
	_conveyor_level = runner.is_conveyor()
	_make_seed_bank(_conveyor_level)
	if _conveyor_level:
		seed_bank.setup_conveyor(runner.level.get("seedbank", {}))
	else:
		seed_bank.setup(seeds, runner.seed_recharge_scale() < 1.0)

	_rebuild_seed_buttons()


## Shows the seed chooser and holds the lawn still until the player is done,
## so nothing on it moves while they pick.
func _open_chooser() -> void:
	if _chooser == null:
		var layer := CanvasLayer.new()
		# Over the HUD and its banners, under the pause menu.
		layer.layer = 5
		add_child(layer)
		_chooser = SeedChooser.new()
		layer.add_child(_chooser)
		_chooser.confirmed.connect(_on_seeds_chosen)
	board.process_mode = Node.PROCESS_MODE_DISABLED
	_chooser.open(SeedChooserRules.from_level(runner.level, board),
			Saves.last_seed_choice())


func _close_chooser() -> void:
	if _chooser != null:
		_chooser.hide()
	board.process_mode = Node.PROCESS_MODE_INHERIT


func _on_seeds_chosen(hand: Array[StringName]) -> void:
	Saves.remember_seed_choice(hand)
	_close_chooser()
	_use_chosen_seeds(_chooser.rules.seeds_for(hand))
	Audio.play(&"ui.chooseseeds.close")
	_banner.ready_set_plant()


## Fills the bank with the player's picks and starts the level.
func _use_chosen_seeds(ids: Array) -> void:
	var seeds: Array = []
	for id in ids:
		seeds.append({"kind": &"plant", "id": StringName(id)})
	seed_bank.setup(seeds, runner.seed_recharge_scale() < 1.0)
	_rebuild_seed_buttons()
	runner.begin()


## The plants a save's seed bank held, in slot order.
func _saved_seed_ids(save: Dictionary) -> Array:
	var out: Array = []
	for entry in (save.get("seed_bank", []) as Array):
		if entry is Dictionary:
			out.append(StringName(entry.get("id", "")))
	return out


## Swaps in the bank this level needs. A conveyor belt and a chooser behave
## differently enough to be separate types rather than one with a mode flag.
func _make_seed_bank(conveyor: bool) -> void:
	if seed_bank != null:
		seed_bank.queue_free()
	seed_bank = ConveyorSeedBank.new() if conveyor else SeedBank.new()
	seed_bank.name = "SeedBank"
	add_child(seed_bank)
	seed_bank.changed.connect(_on_seed_bank_changed)
	board.seed_bank = seed_bank
	runner.seed_bank = seed_bank


## A chooser's slots are fixed, so its buttons only need restyling. A belt's
## packets come and go, so its buttons are rebuilt when the count changes.
func _on_seed_bank_changed() -> void:
	if seed_bank.slots_are_stable() and _seed_buttons.size() == seed_bank.size():
		_refresh_seed_buttons()
	else:
		_rebuild_seed_buttons()


func _rebuild_seed_buttons() -> void:
	for b in _seed_buttons:
		b.queue_free()
	_seed_buttons.clear()
	_seeds.clear()

	for slot in seed_bank.size():
		var packet := seed_bank.packet(slot)
		var b := SeedPacketView.new()
		# Show the hotkey on the packet so the binding is discoverable.
		b.setup(packet.kind, packet.id, packet.cost, "%d  " % (slot + 1))
		b.custom_minimum_size = seed_button_size
		b.pressed.connect(_select_seed.bind(slot))
		_seed_bar.add_child(b)
		_seed_buttons.append(b)
		_seeds.append({"kind": packet.kind, "id": packet.id, "slot": slot})
	_refresh_seed_buttons()


## The action for a seed slot. Conveyor levels have more slots and their own
## bindings from slot 5 onward, so the layout depends on the seed bank mode.
func _slot_action(slot: int) -> StringName:
	var n := slot + 1
	if _conveyor_level and n >= 5:
		return StringName("Slot %d (Convayor)" % n)
	return StringName("Slot %d" % n)


func _action_pressed(event: InputEvent, action: StringName) -> bool:
	# Guarded: an unbound or missing action must not spam errors.
	return InputMap.has_action(action) and event.is_action_pressed(action)


func _build_pause_menu() -> void:
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.can_open = can_pause
	pause_menu.restart_requested.connect(restart_level)
	pause_menu.exit_requested.connect(leave_level)
	fast_forward_scale = Settings.get_value(&"fast_forward_scale")
	Settings.changed.connect(_on_setting_changed)


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"fast_forward_scale":
		fast_forward_scale = value
		if _fast_forward:
			Engine.time_scale = fast_forward_scale
		_refresh_mode_label()


## Pausing is only offered while the level is actually being played, not
## during the result banner before the next level loads.
func can_pause() -> bool:
	return runner.running and not _transitioning


func pause() -> void:
	pause_menu.open()


## Starts the current level over, dropping its part-played save.
func restart_level() -> void:
	get_tree().paused = false
	Saves.clear_save(_current_level)
	load_level(_current_level)


## Leaves the level for the map or the title. A run in progress is saved
## first, so the map offers to resume it.
func leave_level(destination: StringName) -> void:
	get_tree().paused = false
	if runner.running and not _transitioning:
		Saves.save_level(runner, board, seed_bank)
	runner.stop()
	_transitioning = true
	Audio.stop_music()
	if exit_requested.get_connections().is_empty():
		# Launched without the App: bring it up on the requested screen.
		App.start_screen = destination
		var campaign := Data.campaign_for_level(_current_level)
		App.start_campaign = campaign.id if campaign != null else &""
		get_tree().change_scene_to_file(APP_SCENE)
	else:
		exit_requested.emit(destination)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			and Settings.get_value(&"pause_on_focus_loss"):
		pause()


func _exit_tree() -> void:
	# Fast forward and pause are global; neither may outlive the level.
	if _fast_forward:
		Engine.time_scale = 1.0
	if pause_menu != null and pause_menu.is_open():
		get_tree().paused = false


## Seed slots, shovel and fast forward all come from the project's InputMap,
## so they can be rebound - including to a controller - without code changes.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return

	if _action_pressed(event, &"Lawn Ability"):
		if not board.activate_lawn_ability(0):
			Audio.play(&"lawn.ability.refuse")
		_refresh_ability_label()
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Plant Food"):
		_toggle_plant_food()
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Shovel"):
		_toggle_shovel()
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Fast Forward"):
		_toggle_fast_forward()
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Previous Slot"):
		_step_slot(-1)
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Next Slot"):
		_step_slot(1)
		get_viewport().set_input_as_handled()
		return

	for slot in _seeds.size():
		if _action_pressed(event, _slot_action(slot)):
			_select_seed(slot)
			get_viewport().set_input_as_handled()
			return

	# Escape first drops whatever is in hand; with nothing in hand it pauses.
	if _action_pressed(event, &"Pause"):
		if board.selected_seed.is_empty() and not board.shovel_active \
				and not board.plant_food_active:
			pause()
		else:
			_select_seed(-1)
			board.shovel_active = false
			board.plant_food_active = false
			_refresh_mode_label()
		get_viewport().set_input_as_handled()


## Cycles the selection, skipping packets that cannot be picked. Bound to
## Previous/Next Slot, which are reserved for controller shoulder buttons.
func _step_slot(step: int) -> void:
	if _seeds.is_empty():
		return
	var start: int = board.selected_seed.get("slot", -1)
	for i in _seeds.size():
		var next := posmod(start + step * (i + 1), _seeds.size())
		if seed_bank.can_use(next, board.sun):
			_select_seed(next)
			return


func _toggle_shovel() -> void:
	board.shovel_active = not board.shovel_active
	if board.shovel_active:
		Audio.play(&"ui.shovel")
		board.plant_food_active = false
		board.selected_seed = {}
	_refresh_seed_buttons()
	_refresh_mode_label()


## Arms plant food. The next click on a plant feeds it, if there is any left.
func _toggle_plant_food() -> void:
	if board.plant_food <= 0:
		board.plant_food_active = false
		_refresh_mode_label()
		return
	board.plant_food_active = not board.plant_food_active
	if board.plant_food_active:
		board.shovel_active = false
		board.selected_seed = {}
	_refresh_seed_buttons()
	_refresh_mode_label()


func _on_plant_food_changed(total: int) -> void:
	_plant_food_bar.set_count(total)
	if total <= 0:
		board.plant_food_active = false
	_refresh_mode_label()


func _toggle_fast_forward() -> void:
	_fast_forward = not _fast_forward
	Engine.time_scale = fast_forward_scale if _fast_forward else 1.0
	Audio.play(&"ui.fastforward.on" if _fast_forward else &"ui.fastforward.off")
	_refresh_mode_label()


func _refresh_mode_label() -> void:
	var bits := []
	if board.plant_food_active:
		bits.append("Plant Food")
	if board.shovel_active:
		bits.append("Shovel")
	if _fast_forward:
		bits.append("x%.1f" % fast_forward_scale)
	_mode_label.text = "  ".join(bits)
	_refresh_tools()


## Selects a seed slot, or clears the selection when `slot` is out of range.
## Selecting the slot that is already active clears it, so a hotkey toggles.
func _select_seed(slot: int) -> void:
	# As in PVZGE's tryChangingIndex, a packet that is recharging or that the
	# bank cannot pay for is not picked up at all. Short of sun, the counter
	# flashes too.
	if slot >= 0 and slot < _seeds.size() and not seed_bank.can_use(slot, board.sun):
		Audio.play(&"ui.seed.refuse")
		if seed_bank.is_recharged(slot):
			_sun_counter.warn()
		return
	if slot < 0 or slot >= _seeds.size():
		board.selected_seed = {}
	elif board.selected_seed == _seeds[slot]:
		Audio.play(&"ui.seed.cancel")
		board.selected_seed = {}     # re-pressing the same slot deselects
	else:
		Audio.play(&"ui.seed.select")
		board.selected_seed = _seeds[slot].duplicate()
	_refresh_seed_buttons()


func _on_sun_changed(total: int) -> void:
	_sun_counter.set_total(total)
	_refresh_seed_buttons()


## Shows each packet's state: recharging, unaffordable, ready, or selected.
func _refresh_seed_buttons() -> void:
	for i in _seed_buttons.size():
		var packet := seed_bank.packet(i)
		var b := _seed_buttons[i]
		if packet == null:
			continue
		# The packet shades itself in proportion to the recharge left, so it
		# visibly fills up.
		b.show_state(1.0 if packet.is_recharged() else packet.fraction(),
				seed_bank.can_afford(i, board.sun), board.selected_seed.get("slot", -1) == i)
	_refresh_tools()


## The shovel and plant food buttons show whether they are in hand.
func _refresh_tools() -> void:
	_shovel_button.set_active(board.shovel_active)
	_plant_food_bar.set_active(board.plant_food_active)


func _on_objectives_changed(_objectives: Array) -> void:
	_objective_label.text = "   ".join(runner.objective_lines())


func _on_lawn_ability_changed(_component: LawnComponent) -> void:
	_refresh_ability_label()


## Shows the world's own behaviours, abilities first with their charge.
func _refresh_ability_label() -> void:
	var bits: Array[String] = []
	for c in board.lawn_components:
		var text := c.describe()
		if text == "":
			continue
		if c.is_ability:
			bits.append("[G] %s" % text if c.can_activate() else text)
		else:
			bits.append(text)
	_ability_label.text = "   ".join(bits)


## A broken objective loses the level, and names which rule broke.
func _on_objective_failed(objective: Objective) -> void:
	if _transitioning:
		return
	var text := objective.describe()
	_on_lost()
	_status.text = "Objective failed: %s" % (text if text != "" else objective.name)


func _on_wave_started(index: int, total: int) -> void:
	_wave_label.text = "Wave %d / %d" % [index, total]
	# PVZGE warns on every flag wave and once more on the last one.
	if index == total and total > 1:
		_banner.final_wave()
	elif _is_flag_wave(index):
		_banner.huge_wave()


## Whether wave `index` (1-based) carries a flag, by the level's own pacing.
func _is_flag_wave(index: int) -> bool:
	var every := int((runner.level.get("wave_pacing", {}) as Dictionary)
			.get("flag_interval", 0))
	return every > 0 and index % every == 0


func _process(delta: float) -> void:
	if not runner.running or _transitioning or autosave_interval <= 0.0:
		return
	_autosave_timer -= delta
	if _autosave_timer > 0.0:
		return
	_autosave_timer = autosave_interval
	Saves.save_level(runner, board, seed_bank)


func _on_won() -> void:
	if _transitioning:
		return
	_transitioning = true
	runner.stop()
	# The first win earns the level's own prize; every later one a coin bag.
	var first_win := not Saves.is_cleared(_current_level)
	# Clearing a level ends its run, which retires its save slot.
	Saves.mark_cleared(_current_level)
	if first_win:
		for feature in (runner.level.get("unlocks_features", []) as Array):
			Saves.unlock_feature(StringName(feature))
	var reward := LevelReward.for_level(runner.level, first_win)
	# Granted as it drops, so leaving before picking it up cannot lose it.
	reward.grant()
	_play_ending(&"victory", &"level.win")
	_status.text = "Level complete!"
	_drop_reward(reward)


## Drops the prize where the last zombie fell; the level ends once the player
## has picked it up.
func _drop_reward(reward: LevelReward) -> void:
	var canvas := board.get_viewport().get_canvas_transform().affine_inverse()
	if reward.type == LevelReward.COIN_BAG:
		_coin_counter.show()
	board.coin_collect_target = board.to_local(canvas * _coin_counter.collect_point())
	var at: Vector2 = _last_zombie_at if _last_zombie_at != null \
			else board.grid_to_world(floori(board.rows / 2.0), board.cols - 2)
	_reward_drop = board.drop_reward(reward, at)
	_reward_drop.collected.connect(_on_reward_collected)


func _on_reward_collected(drop: Collectable) -> void:
	var reward: LevelReward = (drop as RewardDrop).reward
	if reward != null and reward.is_award():
		_award.open(reward)
	else:
		# Give the coins time to reach the counter before moving on.
		_finish_level(level_transition_delay)


## Moves on once the prize is in hand: the next level, or the map.
func _finish_level(delay: float) -> void:
	if _campaign == null or _campaign.is_last(_current_level) \
			or _campaign.index_of(_current_level) < 0:
		_status.text = (_campaign.completion_message if _campaign != null
				else "Level complete!")
		if return_to_map:
			_leave_after(delay)
		return
	if return_to_map:
		_leave_after(delay)
		return
	_advance_after(delay, _campaign.next_after(_current_level))


func _on_zombie_died(zombie: Zombie) -> void:
	_last_zombie_at = zombie.position


func _on_lost() -> void:
	if _transitioning:
		return
	_transitioning = true
	runner.stop()
	# A failed run is not worth resuming; the retry starts the level over.
	Saves.clear_save(_current_level)
	Audio.stop_music()
	_play_ending(&"lose", &"level.lose")
	_status.text = "The zombies ate your brains!"
	_advance_after(retry_delay, _current_level)


## Loads `level_id` after a pause, so the result is readable first.
## The tree is never paused here - that would stop the timer too.
func _advance_after(delay: float, level_id: StringName) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree():
		load_level(level_id)


func _leave_after(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree():
		leave_level(&"map")


## Ends the level with its world's music, falling back to the plain cue.
##
## Winning and losing are scored, not sound-effected: PVZGE keeps VIC_, LOSE_
## and LEAVE_ in its music enum beside the stage loops, so they are routed as
## music here and a world can end its own way.
func _play_ending(kind: StringName, fallback: StringName) -> void:
	var cue: StringName = runner.music_cue(kind) if runner != null else &""
	if cue != &"":
		Audio.play_music(cue)
	else:
		Audio.play(fallback)
