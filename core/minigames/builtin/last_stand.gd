extends Minigame
## Last Stand: a big pile of sun and no more coming. The player builds a
## defence first and starts the zombies when ready, with the button PVZGE
## shows over the lawn; after that the level plays as normal.
##
## Config: starting_sun, starting_plantfood.

var onslaught: bool = false
var _layer: CanvasLayer
var _button: Button


func setup() -> void:
	board.sun = int(cfg(&"starting_sun", board.sun))
	board.sun_changed.emit(board.sun)
	board.plant_food = int(cfg(&"starting_plantfood", 0))
	board.plant_food_changed.emit(board.plant_food)


func begin() -> void:
	if onslaught:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_button = MenuUI.button(tr("Start Onslaught!"), start_onslaught,
			Vector2(300, 64), &"green")
	_button.name = "StartOnslaught"
	_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_button.offset_left = -150
	_button.offset_right = 150
	_button.offset_top = -190
	_button.offset_bottom = -126
	_layer.add_child(_button)


## The player is happy with their defence: let the zombies come.
func start_onslaught() -> void:
	if onslaught:
		return
	onslaught = true
	if is_instance_valid(_layer):
		_layer.queue_free()
	notify_progress()


func holds_waves() -> bool:
	return not onslaught


func drops_sky_sun() -> bool:
	return false


func intro_text() -> String:
	return tr("Plan your defence and defeat the zombies")


func describe() -> String:
	return "" if onslaught else tr("Plan your defenses!")


func save_state() -> Dictionary:
	return {"onslaught": onslaught}


func load_state(state: Dictionary) -> void:
	if bool(state.get("onslaught", false)):
		start_onslaught()
