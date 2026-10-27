class_name Board
extends Node2D
## The lawn: grid geometry, entity ownership, and player input.
##
## Everything positional goes through here so components never do their own
## coordinate maths. Rows run top to bottom, columns left to right; zombies
## enter from the right and walk toward the house at the left.

signal sun_changed(total: int)
signal level_lost
signal level_won
signal mower_triggered(row: int)
signal plant_food_changed(total: int)
## Raised so level objectives can observe what happens without polling.
signal zombie_died(zombie: Zombie)
signal plant_died(plant: Plant)
signal sun_collected(amount: int)
## Coins reached the coin counter and were banked in Saves.
signal coins_collected(amount: int)
signal zombie_reached_house(zombie: Zombie)
## A lawn ability became available or was spent.
signal lawn_ability_changed(component: LawnComponent)
## A gravestone (or ice block, or weapon rack) was broken by a plant.
signal grave_destroyed(grave: Grave)
## Sun paid out for something, so a spending limit can be tracked.
signal sun_spent(amount: int)
## A plant went into the ground, by the player or by the level.
signal plant_placed(plant: Plant)
## The player dug up a plant with the shovel, which puts the shovel down.
signal shovel_used

## Drawing order. The lawn reads front-to-back: a plant in row 4 covers a
## zombie in row 0, and within one row the zombie covers the plant it is
## eating. So the row decides the band and the kind decides the place in it.
## Collectables sit above the lot, because a sun behind a gargantuar is a sun
## nobody clicks.
const ROW_BAND := 10
const LAYER_PLANT := 0
const LAYER_OBJECT := 1
const LAYER_MOWER := 2
const LAYER_ZOMBIE := 3
const LAYER_PROJECTILE := 4
const LAYER_COLLECTABLE := 1000

## How PVZGE moves a dropping, turned into per-second terms. It steps 60 times
## a second, moving half its velocity each step and losing 0.55 of its upward
## speed to gravity, so speeds scale by 30 and the pull by 30 * 33.
const DROP_SPEED := 30.0
const DROP_GRAVITY := 990.0

## How far a zombie may stand off its lane's centre line, as a share of the
## row height.
const LANE_SCATTER := 0.09

const DEFAULT_ROWS := 5
const DEFAULT_COLS := 9

@export_group("Grid")
## Lanes on the lawn. Exported so a level or stage can use a different shape.
@export_range(1, 12) var rows: int = DEFAULT_ROWS
@export_range(1, 16) var cols: int = DEFAULT_COLS
@export var cell_size := Vector2(84.0, 98.0)
@export var origin := Vector2(180.0, 120.0)

@export_group("Mowers")
## One mower per lane, parked at the house. Levels turn these on through their
## feature list; without them a single zombie reaching the house ends the level.
@export var mowers_enabled: bool = false
## How far left of the house line the mowers park.
@export var mower_offset: float = 26.0

@export_group("Economy")
@export var starting_sun: int = 50
## Where collected sun flies to, in board-local coordinates. Should sit under
## the sun counter in the HUD.
@export var sun_collect_target := Vector2(60.0, 30.0)
## Where collected plant food flies to, in board-local coordinates.
@export var plant_food_collect_target := Vector2(200.0, 30.0)
## Where collected coins fly to, in board-local coordinates.
@export var coin_collect_target := Vector2(340.0, 30.0)
## Plant food the player can hold at once.
@export var max_plant_food: int = 3

@export_group("Appearance")
@export var lawn_light := Color("5a8f3c")
@export var lawn_dark := Color("528436")
@export var house_line := Color("3d2b1f")
## Tint drawn over lanes the player cannot plant in.
@export var locked_lane_tint := Color(0, 0, 0, 0.35)

var sun: int = 50
var plant_food: int = 0
## What the player has picked from the seed bank, as {kind, id, slot}.
## Zombies are placeable too, for level types where the player plays the
## zombie side.
var selected_seed: Dictionary = {}
## A tap-to-fire plant the player has armed - a banana launcher waiting to be
## told where to throw. The next click on the lawn picks the spot.
var aiming: EntityComponent = null
## Optional. When set, a packet must have recharged before it can be placed,
## and placing starts its recharge.
var seed_bank: SeedBank = null
## When true a click digs up a plant instead of placing a seed.
var shovel_active: bool = false
## When true a click feeds a plant instead of placing a seed.
var plant_food_active: bool = false

## Terrain per cell, Vector2i(col, row) -> object id. A cell with no entry is
## ordinary ground. This is the shared mechanism behind Big Wave Beach water
## and Sky's open air: both are cells that need something before a plant can
## go there, so both are terrain rather than two bespoke systems.
var terrain: Dictionary = {}
## Tags currently satisfied per cell, from whatever has been placed there -
## a lily pad on water, a platform over a gap.
var _cell_provides: Dictionary = {}

## Rail per cell, Vector2i(col, row) -> rail object id. Kept apart from
## terrain because a rail can run through water: Big Wave Beach has both.
var _rails: Dictionary = {}
## The first flooded column while a tide is in, or -1 with no tide. Cells the
## tide painted are remembered so a receding tide only dries what it wet.
var tide_from: int = -1
var _tide_cells: Dictionary = {}
## Frost per cell. Two frost-wind blasts on the same plant freeze it solid.
var _chill: Dictionary = {}
## A rail cart the player has picked up and is about to move.
var _held_cart: GridObject = null
## Extra placement rules, each `func(kind, id, row, col) -> String` returning
## a refusal or "". Level objectives such as a plant cap or a mold colony add
## themselves here, so the board does not need to know about them.
var placement_checks: Array[Callable] = []

## Lanes the player may plant in, 0-based. Empty means every lane is open.
## Tutorial 1 uses this to confine the player to a single lane.
var plantable_rows: Array[int] = []

var _plants: Dictionary = {}          ## Vector2i -> Plant
## Plants that carry another plant on top of them - a lily pad on water, a
## flower pot in the sky - sit in their own layer under the cell's plant.
## Zombies eat the plant on top first, then the carrier.
var _carriers: Dictionary = {}        ## Vector2i -> Plant
## What last died in each cell, so an intensive carrot knows what to bring
## back. Digging a plant up is not a death and leaves no record.
var _dead_plants: Dictionary = {}     ## Vector2i -> StringName
## Grid items standing in a cell: gravestones, slider and trap tiles, puddles,
## ice blocks. One per cell. Vector2i -> GridObject (Grave is one too).
var _objects: Dictionary = {}
var _zombies_by_row: Dictionary = {}  ## int -> Array[Zombie]
var _projectiles: Node2D
var _suns: Node2D
var _entities: Node2D
var _mowers_node: Node2D
var _mowers: Dictionary = {}   ## int row -> Mower
var _lawn_node: Node
## The lawn's art, when the stage has any; otherwise the placeholder draws.
var scenery: LawnScenery
## The current world's own behaviours, from its lawn data.
var lawn_components: Array[LawnComponent] = []


func _ready() -> void:
	_entities = Node2D.new()
	_entities.name = "Entities"
	add_child(_entities)
	_projectiles = Node2D.new()
	_projectiles.name = "Projectiles"
	add_child(_projectiles)
	_suns = Node2D.new()
	_suns.name = "Suns"
	add_child(_suns)
	_mowers_node = Node2D.new()
	_mowers_node.name = "Mowers"
	add_child(_mowers_node)
	_lawn_node = Node.new()
	_lawn_node.name = "LawnComponents"
	add_child(_lawn_node)
	scenery = LawnScenery.new()
	scenery.name = "Scenery"
	add_child(scenery)
	sun = starting_sun
	for r in rows:
		_zombies_by_row[r] = []
	sun_changed.emit(sun)


## Clears the lawn back to its starting state, ready for another level.
func reset() -> void:
	for group in [_entities, _projectiles, _suns, _mowers_node]:
		for child in group.get_children():
			child.queue_free()
	for c in lawn_components:
		c.queue_free()
	lawn_components.clear()
	_mowers.clear()
	_plants.clear()
	_carriers.clear()
	_dead_plants.clear()
	_objects.clear()
	for r in _zombies_by_row:
		_zombies_by_row[r].clear()
	plantable_rows.clear()
	terrain.clear()
	_cell_provides.clear()
	_rails.clear()
	_tide_cells.clear()
	_chill.clear()
	tide_from = -1
	_held_cart = null
	placement_checks.clear()
	selected_seed = {}
	sun = starting_sun
	plant_food = 0
	sun_changed.emit(sun)
	plant_food_changed.emit(plant_food)
	queue_redraw()


## Builds the world's own behaviours from its lawn data. Replaces whatever the
## previous level installed, so switching worlds switches mechanics.
func setup_lawn(lawn: Dictionary, runner: Node) -> void:
	_show_scenery(lawn, runner)
	for c in lawn_components:
		c.queue_free()
	lawn_components.clear()
	for spec in (lawn.get("components", []) as Array):
		if not (spec is Dictionary):
			continue
		var comp := Components.create_lawn_component(spec, self, runner)
		if comp == null:
			continue
		_lawn_node.add_child(comp)
		lawn_components.append(comp)
		comp.state_changed.connect(func(c): lawn_ability_changed.emit(c))
		comp.setup()


## Puts the stage's art down, and gives the mowers their world's look. The
## level names its stage; the lawn data is the fallback for one that does not.
func _show_scenery(lawn: Dictionary, runner: Node) -> void:
	var level: Dictionary = runner.get("level") if runner != null and runner.get("level") is Dictionary else {}
	var stage := StringName(level.get("stage", lawn.get("id", "")))
	var open := plantable_rows.size() if not plantable_rows.is_empty() else rows
	if not scenery.show_stage(stage, self, open):
		scenery.show_stage(StringName(lawn.get("id", "")), self, open)
	# The level's lawn data names its mower; the art entry knows it for stages
	# the data does not cover, such as the tutorial's.
	var mower_id := StringName(lawn.get("mower", Art.mapping(&"lawn", scenery.stage).get("mower", "")))
	for m in _mowers.values():
		if is_instance_valid(m):
			m.attach_art(mower_id)
	queue_redraw()


## The world abilities the player can trigger, in declaration order.
func lawn_abilities() -> Array[LawnComponent]:
	var out: Array[LawnComponent] = []
	for c in lawn_components:
		if c.is_ability:
			out.append(c)
	return out


## Fires the nth available world ability. Returns false if it could not fire.
func activate_lawn_ability(index: int = 0) -> bool:
	var abilities := lawn_abilities()
	if index < 0 or index >= abilities.size():
		return false
	return abilities[index].activate()


## Parks a fresh mower in every lane. Called when a level with mowers starts.
func setup_mowers() -> void:
	for child in _mowers_node.get_children():
		child.queue_free()
	_mowers.clear()
	if not mowers_enabled:
		return
	for r in rows:
		var m := Mower.new()
		m.row = r
		m.board = self
		m.name = "Mower_%d" % r
		m.position = Vector2(house_x() - mower_offset, grid_to_world(r, 0).y)
		m.z_index = lane_z(r, LAYER_MOWER)
		m.finished.connect(_on_mower_finished)
		_mowers_node.add_child(m)
		_mowers[r] = m


func mower_in_row(row: int) -> Mower:
	var m = _mowers.get(row)
	return m if is_instance_valid(m) else null


## True when a lane still has an unused mower protecting it.
func has_mower(row: int) -> bool:
	var m := mower_in_row(row)
	return m != null and m.is_available()


func _on_mower_finished(row: int) -> void:
	_mowers.erase(row)


## Everything on the lawn, as plain data. The board knows how to describe
## itself so a saver does not have to reach into its internals.
##
## Projectiles and uncollected sun are deliberately left out - they are in
## flight, and resuming a level with them restored would be stranger than
## resuming without them.
func snapshot() -> Dictionary:
	var plants: Array = []
	# Carriers first, so a lily pad is back on the water before what stood on
	# it is restored.
	var standing: Array = _carriers.values() + _plants.values()
	for p in standing:
		# Untyped: a typed assignment of a freed plant is a script error.
		if not is_instance_valid(p) or p.is_dead:
			continue
		plants.append({"id": String(p.entity_id()), "row": p.row, "col": p.col,
				"health": p.health, "encased": p.is_encased()})

	var zombies: Array = []
	for row in _zombies_by_row:
		for z in _zombies_by_row[row]:
			if not is_instance_valid(z) or z.is_dead:
				continue
			zombies.append({"id": String(z.entity_id()), "row": z.row,
					"x": z.position.x, "health": z.health,
					"charmed": z.is_charmed(),
					"encased": z.is_encased(),
					"carrying_plantfood": z.has_tag(&"carrying_plantfood")})

	var objects: Array = []
	for cell in _objects:
		var o = _objects[cell]
		if not is_instance_valid(o) or o.is_dead:
			continue
		objects.append({"id": String(o.entity_id()), "row": o.row, "col": o.col,
				"health": o.health})

	var ground: Array = []
	for cell in terrain:
		ground.append({"col": cell.x, "row": cell.y,
				"terrain": String(terrain[cell])})
	var rails: Array = []
	for cell in _rails:
		rails.append({"col": cell.x, "row": cell.y, "rail": String(_rails[cell])})
	var provided: Array = []
	for cell in _cell_provides:
		provided.append({"col": cell.x, "row": cell.y,
				"tag": String(_cell_provides[cell])})

	var lawn: Dictionary = {}
	for c in lawn_components:
		var state := c.save_state()
		if not state.is_empty():
			lawn[c.name] = state

	return {
		"sun": sun, "plant_food": plant_food,
		"plantable_rows": plantable_rows.duplicate(),
		"mower_rows": _remaining_mower_rows(),
		"plants": plants, "zombies": zombies, "objects": objects,
		"terrain": ground, "cell_provides": provided,
		"rails": rails, "tide_from": tide_from,
		"lawn_components": lawn,
	}


func _remaining_mower_rows() -> Array:
	var out: Array = []
	for row in _mowers:
		if has_mower(row):
			out.append(row)
	return out


## Rebuilds the lawn from a snapshot. The caller is expected to have started
## the level already, so lawn components and mowers exist; this corrects them.
func apply_snapshot(state: Dictionary) -> void:
	for group in [_entities, _projectiles, _suns]:
		for child in group.get_children():
			child.queue_free()
	_plants.clear()
	_carriers.clear()
	_objects.clear()
	for row in _zombies_by_row:
		_zombies_by_row[row].clear()
	terrain.clear()
	_cell_provides.clear()
	_rails.clear()
	_chill.clear()
	_held_cart = null

	var rows: Array[int] = []
	for r in (state.get("plantable_rows", []) as Array):
		rows.append(int(r))
	plantable_rows = rows

	for cell in (state.get("terrain", []) as Array):
		terrain[Vector2i(int(cell.get("col", 0)), int(cell.get("row", 0)))] = \
				StringName(cell.get("terrain", &""))

	for cell in (state.get("rails", []) as Array):
		_rails[Vector2i(int(cell.get("col", 0)), int(cell.get("row", 0)))] = \
				StringName(cell.get("rail", &"rail"))
	# The tide's painted cells are already in the terrain just restored; only
	# which of them it owns needs rebuilding.
	_tide_cells.clear()
	tide_from = int(state.get("tide_from", -1))
	if tide_from >= 0:
		for c in range(tide_from, cols):
			for r in rows:
				if terrain_at(r, c) == &"water":
					_tide_cells[Vector2i(c, r)] = true

	for entry in (state.get("objects", []) as Array):
		var o := place_object(StringName(entry.get("id", &"")),
				int(entry.get("row", 0)), int(entry.get("col", 0)))
		if o != null:
			o.health = minf(float(entry.get("health", o.health)), o.max_health)
			o.queue_redraw()

	# Plants are placed directly rather than through place_entity, so terrain
	# rules and costs do not re-apply to something already standing.
	for entry in (state.get("plants", []) as Array):
		var p := _place_plant_at(StringName(entry.get("id", &"")),
				int(entry.get("row", 0)), int(entry.get("col", 0)))
		if p == null:
			continue
		p.died.connect(func(who): _on_placed_plant_died(who, p.row, p.col))
		p.health = minf(float(entry.get("health", p.health)), p.max_health)
		if bool(entry.get("encased", false)):
			_rejoin_block(p, p.row, p.col)
		p.queue_redraw()

	for cell in (state.get("cell_provides", []) as Array):
		_cell_provides[Vector2i(int(cell.get("col", 0)), int(cell.get("row", 0)))] = \
				StringName(cell.get("tag", &""))

	for entry in (state.get("zombies", []) as Array):
		var z := spawn_zombie(StringName(entry.get("id", &"")),
				int(entry.get("row", 0)))
		if z == null:
			continue
		z.position.x = float(entry.get("x", z.position.x))
		z.health = minf(float(entry.get("health", z.health)), z.max_health)
		if bool(entry.get("charmed", false)):
			z.charm()
		if bool(entry.get("carrying_plantfood", false)):
			z.set_runtime_tag(&"carrying_plantfood", true)
		if bool(entry.get("encased", false)):
			z.col = world_to_col(z.position.x)
			_rejoin_block(z, z.row, z.col)
		z.queue_redraw()

	# Mowers that were already spent stay spent.
	# JSON numbers come back as floats, and Array.has(2) misses 2.0.
	var kept: Array[int] = []
	for r in (state.get("mower_rows", []) as Array):
		kept.append(int(r))
	for row in _mowers.keys():
		if not kept.has(row):
			var m := mower_in_row(row)
			if m != null:
				m.queue_free()
			_mowers.erase(row)

	var lawn: Dictionary = state.get("lawn_components", {})
	for c in lawn_components:
		if lawn.has(c.name):
			c.load_state(lawn[c.name])

	sun = int(state.get("sun", starting_sun))
	plant_food = int(state.get("plant_food", 0))
	sun_changed.emit(sun)
	plant_food_changed.emit(plant_food)
	queue_redraw()


# --- geometry ------------------------------------------------------------

## Where something in `row` belongs in the draw order.
func lane_z(row: int, layer: int) -> int:
	return row * ROW_BAND + layer


func grid_to_world(row: int, col: int) -> Vector2:
	return origin + Vector2((col + 0.5) * cell_size.x, (row + 0.5) * cell_size.y)


func world_to_col(x: float) -> int:
	return clampi(int(floorf((x - origin.x) / cell_size.x)), -1, cols - 1)


func world_to_row(y: float) -> int:
	return clampi(int(floorf((y - origin.y) / cell_size.y)), 0, rows - 1)


func in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < rows and col >= 0 and col < cols


func house_x() -> float:
	return origin.x - cell_size.x * 0.5


## Where zombies come on: PVZGE's `zombieSpawnX`, the centre of column 11.5
## on its nine-column lawn - two and a half squares past the last one. On a
## screen wider than PVZGE's that would still be in view, so the line also
## sits past the visible right edge, and zombies walk on rather than appear.
func spawn_x() -> float:
	var pvzge := origin.x + (cols + 3.0) * cell_size.x
	return maxf(pvzge, _screen_right() + cell_size.x * 0.6)


## The right edge of the last column. Zombies hurry until they reach it.
func lawn_right_x() -> float:
	return origin.x + cols * cell_size.x


## The visible right edge in board coordinates, or -INF off-screen.
func _screen_right() -> float:
	if not is_inside_tree():
		return -INF
	var view := get_viewport_rect()
	return (get_global_transform_with_canvas().affine_inverse()
			* Vector2(view.position.x + view.size.x, 0.0)).x


func despawn_x() -> float:
	return spawn_x() + cell_size.x


## PVZGE measures in its own pixels, 68 to a square. Distances lifted from its
## code go through here so they keep their size on a lawn of any scale.
func pvzge_px(px: float) -> float:
	return px * cell_size.x / 68.0


# --- plants --------------------------------------------------------------

## The plant a zombie meets in a cell: the one on top, or the carrier when
## nothing stands on it.
func plant_at(row: int, col: int) -> Plant:
	var p := occupant_at(row, col)
	return p if p != null else carrier_at(row, col)


## The cell's own plant, ignoring any carrier under it. This is what decides
## whether another plant can go in.
func occupant_at(row: int, col: int) -> Plant:
	var p = _plants.get(Vector2i(col, row))
	return p if is_instance_valid(p) and not p.is_dead else null


func carrier_at(row: int, col: int) -> Plant:
	var p = _carriers.get(Vector2i(col, row))
	return p if is_instance_valid(p) and not p.is_dead else null


## Whether a plant definition is a carrier: it provides something to its cell.
static func is_carrier_def(def: EntityDef) -> bool:
	if def == null:
		return false
	for tag in def.tag_list():
		if String(tag).begins_with("provides:"):
			return true
	return false


## Every living plant in one row, left to right.
func plants_in_row(row: int) -> Array:
	var out: Array = []
	for c in cols:
		for p in [occupant_at(row, c), carrier_at(row, c)]:
			if p != null and not p.is_dead:
				out.append(p)
	return out


func plant_count() -> int:
	var n := 0
	for cell in _plants:
		var p = _plants[cell]
		if is_instance_valid(p) and not p.is_dead:
			n += 1
	return n


func is_row_plantable(row: int) -> bool:
	return plantable_rows.is_empty() or plantable_rows.has(row)


## Paints a cell's terrain. Worlds do this through a lawn component.
func set_terrain(row: int, col: int, object_id: StringName) -> void:
	var cell := Vector2i(col, row)
	if object_id == &"":
		terrain.erase(cell)
	else:
		terrain[cell] = object_id
	queue_redraw()


func terrain_at(row: int, col: int) -> StringName:
	return terrain.get(Vector2i(col, row), &"")


## Whether a cell is water of any kind, which is all its sounds care about.
func is_water(row: int, col: int) -> bool:
	return String(terrain_at(row, col)).contains("water")


## The terrain definition for a cell, or null for ordinary ground.
func terrain_def(row: int, col: int) -> ObjectDef:
	var id := terrain_at(row, col)
	return Data.board_object(id) if id != &"" else null


## What a cell currently satisfies, from whatever has been placed on it.
func cell_provides(row: int, col: int) -> StringName:
	return _cell_provides.get(Vector2i(col, row), &"")


## Why a plant cannot go in a cell, or "" when it can. Returning a reason
## rather than a bool lets the HUD explain the refusal.
func placement_refusal(kind: StringName, id: StringName, row: int, col: int) -> String:
	if not in_bounds(row, col):
		return "out of bounds"
	if not is_row_plantable(row):
		return "lane is closed"
	if kind == &"zombie":
		return ""
	for check in placement_checks:
		var why: String = check.call(kind, id, row, col)
		if why != "":
			return why

	var plant_def := Data.plant(id)
	var item := object_at(row, col)
	var need := grave_need(plant_def)
	if need != &"":
		# Planted on a gravestone or block, not beside one: it needs the item
		# under it, and only minds a plant already there if that plant is
		# free to be eaten - a frozen one is what a hot potato is for.
		if not (item is Grave) or not bool(item.def.stat(need, false)):
			return "%s must go on something it can %s" % [id, need]
		var there := occupant_at(row, col)
		if there != null and not there.is_encased():
			return "cell is occupied"
		return ""
	if occupant_at(row, col) != null:
		return "cell is occupied"
	if is_carrier_def(plant_def) and carrier_at(row, col) != null:
		return "cell is occupied"
	# A rail is only plantable where a cart stands on it.
	if is_rail(row, col) and not is_railcart(item):
		return "plants go on the cart, not the rail"
	if item is Grave and not bool(item.def.extra.get("AllowPlantsInSquare", false)):
		return "%s is in the way" % item.def.id
	# A puddle or tile placed as an object carries the same rules as painted
	# terrain; painted terrain wins where both exist.
	var ground := terrain_def(row, col)
	if ground == null and item != null and not (item is Grave) and item.def is ObjectDef:
		ground = item.def
	if ground == null:
		return ""
	if ground.blocks_planting:
		return "nothing can be planted on %s" % ground.id
	if ground.requires_tag != &"":
		# Either the plant itself copes with this ground, or something already
		# placed in the cell makes it viable.
		var def := Data.plant(id)
		var plant_ok: bool = def != null and def.has_tag(ground.requires_tag)
		var cell_ok: bool = cell_provides(row, col) == ground.requires_tag
		if not (plant_ok or cell_ok):
			return "%s needs %s" % [ground.id, ground.requires_tag]
	return ""


## The GraveDef flag a plant must be planted onto, from its
## `on_grave:<flag>` tag - grave buster on `gravebuster_plantable` stones, hot
## potato on `hot_potato_meltable` ice. &"" for an ordinary plant.
static func grave_need(def: EntityDef) -> StringName:
	if def == null:
		return &""
	for tag in def.tag_list():
		if String(tag).begins_with("on_grave:"):
			return StringName(String(tag).substr(9))
	return &""


## A lily pad or platform makes its cell viable for the next plant.
func _claim_provides(id: StringName, row: int, col: int) -> void:
	var def := Data.plant(id)
	if def == null:
		return
	for tag in def.tag_list():
		if String(tag).begins_with("provides:"):
			_cell_provides[Vector2i(col, row)] = StringName(String(tag).substr(9))


func can_place(row: int, col: int) -> bool:
	return in_bounds(row, col) and is_row_plantable(row) and occupant_at(row, col) == null


## Places a plant. Convenience wrapper over `place_entity`.
func place_plant(id: StringName, row: int, col: int) -> Plant:
	return place_entity(&"plant", id, row, col)


## Places whatever a seed packet holds. Plants occupy their cell; zombies are
## dropped into the lane and walk from there, so they do not block it.
## `imitates` is for an imitater packet: the plant it will turn into.
func place_entity(kind: StringName, id: StringName, row: int, col: int,
		imitates: StringName = &"") -> Character:
	if not can_place_entity(kind, id, row, col):
		return null
	if kind == &"zombie":
		var z := spawn_zombie(id, row)
		if z != null:
			z.position.x = grid_to_world(row, col).x
		return z
	var p := _place_plant_at(id, row, col, imitates)
	if p != null:
		_claim_provides(id, row, col)
		# Read the cell at death time: move_plant may have carried it elsewhere.
		p.died.connect(func(who): _on_placed_plant_died(who, who.row, who.col))
		Audio.play(&"plant.place.water" if is_water(row, col) else &"plant.place", p.position)
		if not is_water(row, col):
			Effect.spawn(_projectiles, &"plant_dirt", &"place", p.position,
					lane_z(row, LAYER_PROJECTILE))
		plant_placed.emit(p)
	return p


## True when `kind` may be placed in this cell. Zombies ignore terrain and
## share a lane; plants need the ground to suit them.
func can_place_entity(kind: StringName, id: StringName,
		row: int, col: int) -> bool:
	return placement_refusal(kind, id, row, col) == ""


## Placement cost for a seed, read from whichever definition owns it.
func seed_cost(kind: StringName, id: StringName) -> int:
	var def: EntityDef = Data.zombie(id) if kind == &"zombie" else Data.plant(id)
	return int(def.stat(&"sun_cost", 100)) if def else 0


func _place_plant_at(id: StringName, row: int, col: int,
		imitates: StringName = &"") -> Plant:
	var def := Data.plant(id)
	if def == null:
		push_warning("Board: unknown plant '%s'" % id)
		return null

	var p := Plant.new()
	p.row = row
	p.col = col
	p.position = grid_to_world(row, col)
	p.name = "Plant_%s_%d_%d" % [id, row, col]
	var cell := Vector2i(col, row)
	var carrier := is_carrier_def(def)
	# A carrier sits just under the band its passenger draws in.
	p.z_index = lane_z(row, LAYER_PLANT) - (1 if carrier else 0)
	p.imitates = imitates
	_entities.add_child(p)
	p.initialize(def, self)
	if carrier:
		_carriers[cell] = p
	elif occupant_at(row, col) == null:
		_plants[cell] = p
	# Otherwise it is working on whatever is already here - a hot potato on a
	# frozen plant - and is not the cell's plant.
	return p


## Forgets a plant. `who` says which one when a carrier and its passenger
## share the cell; without it the plant on top goes.
func remove_plant(row: int, col: int, who: Node = null) -> void:
	var cell := Vector2i(col, row)
	if who != null and _carriers.get(cell) == who:
		_carriers.erase(cell)
	elif who == null or _plants.get(cell) == who:
		_plants.erase(cell)


## Losing a carrier takes its cell's provision with it, so the water is
## dangerous again once the lily pad is eaten.
func _on_placed_plant_died(who: Character, row: int, col: int) -> void:
	if is_carrier_def(who.def):
		_cell_provides.erase(Vector2i(col, row))
	_dead_plants[Vector2i(col, row)] = who.entity_id()
	plant_died.emit(who)


## The plant that most recently died in a cell, or &"" if none has.
func last_dead_plant(row: int, col: int) -> StringName:
	return _dead_plants.get(Vector2i(col, row), &"")


func forget_dead_plant(row: int, col: int) -> void:
	_dead_plants.erase(Vector2i(col, row))


## Sets what a cell remembers as its last death. &"" forgets.
func remember_dead_plant(row: int, col: int, id: StringName) -> void:
	if id == &"":
		forget_dead_plant(row, col)
	else:
		_dead_plants[Vector2i(col, row)] = id


## Brings `id` back in a cell at a share of its health, as an intensive carrot
## does. Clears the cell's memory either way, so the carrot's own death is not
## what the next carrot finds.
func revive_plant(id: StringName, row: int, col: int, health_fraction: float) -> Plant:
	forget_dead_plant(row, col)
	if id == &"":
		return null
	var back := place_preset_plant(id, row, col)
	if back == null:
		return null
	Audio.play(&"plant.revive", back.position)
	back.health = back.max_health * clampf(health_fraction, 0.01, 1.0)
	back.queue_redraw()
	return back


## Whether an umbrella covers a cell, for anything that drops out of the sky.
func is_sheltered(row: int, col: int) -> bool:
	for p in _all_plants():
		var u = p.component(&"umbrella")
		if u != null and u.covers(row, col):
			return true
	return false


## Whether any light on the lawn reaches a cell.
func is_lit(row: int, col: int) -> bool:
	for p in _all_plants():
		var light = p.component(&"light_source")
		if light != null and light.lights(row, col):
			return true
	return false


func _all_plants() -> Array:
	var out: Array = []
	for r in rows:
		out.append_array(plants_in_row(r))
	return out


## Relocates a plant between cells, keeping the board's index in step. Used by
## slide tiles and anything else that carries a plant around.
func move_plant(from_row: int, from_col: int, to_row: int, to_col: int) -> bool:
	# The plant on top moves, leaving its carrier; a bare carrier moves itself.
	var layer := _plants
	var p := occupant_at(from_row, from_col)
	if p == null:
		layer = _carriers
		p = carrier_at(from_row, from_col)
	if p == null or not in_bounds(to_row, to_col):
		return false
	var there = layer.get(Vector2i(to_col, to_row))
	if is_instance_valid(there) and not there.is_dead:
		return false
	layer.erase(Vector2i(from_col, from_row))
	layer[Vector2i(to_col, to_row)] = p
	p.row = to_row
	p.col = to_col
	p.position = grid_to_world(to_row, to_col)
	# A carrier's provision travels with it.
	var provided: StringName = _cell_provides.get(Vector2i(from_col, from_row), &"")
	if provided != &"" and layer == _carriers:
		_cell_provides.erase(Vector2i(from_col, from_row))
		_cell_provides[Vector2i(to_col, to_row)] = provided
	return true


## Digs up the plant in a cell, freeing the square. Returns false if empty.
func dig_up(row: int, col: int) -> bool:
	# The plant on top comes up first; the carrier under it on a second dig.
	var p := plant_at(row, col)
	if p == null:
		return false
	remove_plant(row, col, p)
	# A dug-up carrier takes its provision with it, as when it is eaten.
	if is_carrier_def(p.def):
		_cell_provides.erase(Vector2i(col, row))
	Audio.play(&"plant.dig.water" if is_water(row, col) else &"plant.dig", p.position)
	if not is_water(row, col):
		Effect.spawn(_projectiles, &"plant_dirt", &"dig", p.position,
				lane_z(row, LAYER_PROJECTILE))
	p.queue_free()
	return true


# --- grid objects --------------------------------------------------------

## Puts a grid item in a cell: a gravestone, a weapon rack, a slider or trap
## tile, a puddle. PVZGE also lists a few plants as grid items (lily pads on a
## Beach lawn), and those are planted instead. Returns what was placed, or
## null when the id is unknown or the cell already holds an item.
func place_object(id: StringName, row: int, col: int) -> Node2D:
	if not in_bounds(row, col):
		return null
	var def: EntityDef = Data.grave(id)
	if def == null:
		def = Data.board_object(id)
	if def == null:
		if Data.plant(id) != null:
			return place_preset_plant(id, row, col)
		push_warning("Board: unknown grid item '%s'" % id)
		return null
	if object_at(row, col) != null:
		return null

	var o: GridObject = Grave.new() if def is GraveDef else GridObject.new()
	o.row = row
	o.col = col
	o.position = grid_to_world(row, col)
	o.name = "Object_%s_%d_%d" % [id, row, col]
	o.z_index = lane_z(row, LAYER_OBJECT)
	_entities.add_child(o)
	o.initialize(def, self)
	_objects[Vector2i(col, row)] = o
	if o is Grave:
		o.destroyed_by.connect(_on_grave_destroyed)
	return o


func object_at(row: int, col: int) -> GridObject:
	var o = _objects.get(Vector2i(col, row))
	return o if is_instance_valid(o) and not o.is_dead else null


## Forgets the item in a cell. Called by the item itself as it dies.
func remove_object(row: int, col: int) -> void:
	_objects.erase(Vector2i(col, row))


## Living gravestones in one row, nearest the house first.
func graves_in_row(row: int) -> Array:
	var out: Array = []
	for c in cols:
		var o := object_at(row, c)
		if o is Grave:
			out.append(o)
	return out


## Everything a plant's attack can hit in a row. Graves come first so a block
## of ice is struck before the zombie standing inside it. A block holding one
## of the player's own plants is not a target.
func plant_targets_in_row(row: int) -> Array:
	var out: Array = []
	for g in graves_in_row(row):
		if not g.has_tag(&"holds_plant"):
			out.append(g)
	out.append_array(hostile_zombies_in_row(row))
	return out


## Plants something the level put there, not the player: no cost, no lane
## lock and no terrain check, though the cell must be free. A lily pad still
## makes its water plantable.
func place_preset_plant(id: StringName, row: int, col: int) -> Plant:
	if not in_bounds(row, col):
		return null
	if (carrier_at(row, col) if is_carrier_def(Data.plant(id)) else occupant_at(row, col)) != null:
		return null
	var p := _place_plant_at(id, row, col)
	if p == null:
		return null
	_claim_provides(id, row, col)
	p.died.connect(func(who): _on_placed_plant_died(who, who.row, who.col))
	plant_placed.emit(p)
	return p


## Shuts `who` inside a block of ice standing in its cell. Breaking the block
## frees it; until then it does nothing.
func encase_in_block(who: Character, block_id: StringName) -> bool:
	var block := place_object(block_id, who.row, who.col)
	if not (block is Grave):
		return false
	_bind_block(who, block)
	return true


func _rejoin_block(who: Character, row: int, col: int) -> void:
	var block := object_at(row, col)
	if block is Grave:
		_bind_block(who, block)


func _bind_block(who: Character, block: Grave) -> void:
	who.encase()
	if who is Plant:
		block.set_runtime_tag(&"holds_plant", true)
	block.died.connect(func(_b):
		if is_instance_valid(who) and not who.is_dead:
			who.release())


## A broken grave pays out what its data says: sun, plant food, or both.
func _on_grave_destroyed(grave: Node) -> void:
	var g := grave as Grave
	if g == null:
		return
	var sun_value := int(g.def.extra.get("SunValue", 0))
	for i in ceili(sun_value / float(SunToken.VALUE)):
		drop_sun(g.position + Vector2(randf_range(-12, 12), 0))
	for i in int(g.def.stat(&"plantfood_count", 0)):
		drop_plant_food(g.position)
	grave_destroyed.emit(g)


# --- rails ---------------------------------------------------------------

## Lays rail through a cell. Plants can then only go there on a cart.
func add_rail(row: int, col: int, rail_id: StringName = &"rail") -> void:
	if in_bounds(row, col):
		_rails[Vector2i(col, row)] = rail_id
		queue_redraw()


func is_rail(row: int, col: int) -> bool:
	return _rails.has(Vector2i(col, row))


func is_railcart(o: Variant) -> bool:
	return o is GridObject and is_instance_valid(o) and not o.is_dead \
			and o.def != null and o.def.extra.has("RailType")


func railcart_at(row: int, col: int) -> GridObject:
	var o := object_at(row, col)
	return o if is_railcart(o) else null


## Rolls the cart at (row, col) along its rail to `to_row`, carrying whatever
## is planted on it. Carts cannot pass each other or leave their rail, so
## every cell on the way must be rail with no other cart.
func move_railcart(row: int, col: int, to_row: int) -> bool:
	var cart := railcart_at(row, col)
	if cart == null or to_row == row or not is_rail(to_row, col):
		return false
	var step := 1 if to_row > row else -1
	var r := row + step
	while true:
		if not is_rail(r, col) or object_at(r, col) != null or plant_at(r, col) != null:
			return false
		if r == to_row:
			break
		r += step
	_objects.erase(Vector2i(col, row))
	_objects[Vector2i(col, to_row)] = cart
	cart.row = to_row
	cart.position = grid_to_world(to_row, col)
	cart.z_index = lane_z(to_row, LAYER_OBJECT)
	cart.name = "Object_%s_%d_%d" % [cart.entity_id(), to_row, col]
	if plant_at(row, col) != null:
		move_plant(row, col, to_row, col)
		var rider := plant_at(to_row, col)
		rider.z_index = lane_z(to_row, LAYER_PLANT)
	queue_redraw()
	return true


## The first click on a cart picks it up; the next click on its rail sets it
## down there. Clicking anything else lets go.
func _handle_cart_click(row: int, col: int) -> bool:
	if _held_cart != null and is_instance_valid(_held_cart):
		var held := _held_cart
		_held_cart = null
		queue_redraw()
		if col == held.col and move_railcart(held.row, held.col, row):
			return true
		if held == railcart_at(row, col):
			return true
	var cart := railcart_at(row, col)
	if cart == null:
		return false
	_held_cart = cart
	queue_redraw()
	return true


# --- tide ----------------------------------------------------------------

## Moves the shoreline so that columns `from_col` and right are water. A
## column past the lawn's edge is a dry lawn. Plants that cannot stand in
## water drown as it reaches them, unless something carries them.
func set_tide(from_col: int) -> void:
	tide_from = clampi(from_col, 0, cols)
	for cell in _tide_cells.keys():
		if cell.x < tide_from:
			if terrain_at(cell.y, cell.x) == &"water":
				set_terrain(cell.y, cell.x, &"")
			_tide_cells.erase(cell)
	for c in range(tide_from, cols):
		for r in rows:
			var cell := Vector2i(c, r)
			if _tide_cells.has(cell) or terrain_at(r, c) != &"":
				continue
			set_terrain(r, c, &"water")
			_tide_cells[cell] = true
			_drown_if_stranded(r, c)
	queue_redraw()


## A plant now standing on ground it could not have been planted on is lost,
## the way PVZGE drowns a plant the tide reaches.
func _drown_if_stranded(row: int, col: int) -> void:
	var p := plant_at(row, col)
	if p == null:
		return
	var ground := terrain_def(row, col)
	if ground == null or ground.requires_tag == &"":
		return
	if p.has_tag(ground.requires_tag) or cell_provides(row, col) == ground.requires_tag:
		return
	if is_railcart(object_at(row, col)) and bool(object_at(row, col).def.extra.get("AboveTide", false)):
		return
	p.die()


# --- frost ---------------------------------------------------------------

## Adds frost to a cell. A plant that builds up more than `freeze_at` is
## frozen in a block of ice, as two frost-wind blasts do in Frostbite Caves.
func chill_cell(row: int, col: int, amount: float, freeze_at: float = 2.0,
		block_id: StringName = &"planttarget_iceblock") -> void:
	var p := plant_at(row, col)
	var cell := Vector2i(col, row)
	if p == null or p.is_encased():
		_chill.erase(cell)
		return
	var level: float = _chill.get(cell, 0.0) + amount
	if level > freeze_at:
		_chill.erase(cell)
		encase_in_block(p, block_id)
		return
	_chill[cell] = level
	p.set_runtime_tag(&"chilled", true)


func chill_at(row: int, col: int) -> float:
	return _chill.get(Vector2i(col, row), 0.0)


# --- power tiles ---------------------------------------------------------

## The power-tile group a cell belongs to ("alpha", "beta"...), or "".
func power_tile_group(row: int, col: int) -> String:
	var item := object_at(row, col)
	for id in [String(item.entity_id()) if item != null else "",
			String(terrain_at(row, col))]:
		if id.begins_with("powertile_"):
			return id.trim_prefix("powertile_")
	return ""


## Plant food given to a plant on a power tile reaches every plant on the
## other tiles of its group, each after its tile's propagation delay.
func _propagate_power(row: int, col: int) -> void:
	var group := power_tile_group(row, col)
	if group == "":
		return
	for cell in _objects.keys():
		if cell == Vector2i(col, row):
			continue
		var tile := object_at(cell.y, cell.x)
		if tile == null or power_tile_group(cell.y, cell.x) != group:
			continue
		var delay := float(tile.get_meta(&"propagation_delay",
				tile.def.extra.get("DefaultPropagationDelay", 2.0)))
		get_tree().create_timer(delay, false).timeout.connect(
				_power_tile_fire.bind(cell.y, cell.x))


func _power_tile_fire(row: int, col: int) -> void:
	var p := plant_at(row, col)
	if p != null and not p.is_encased():
		p.apply_plant_food()


# --- dinosaurs -----------------------------------------------------------

## Calls a dinosaur into a lane. Its behaviour comes from data/native/dinos.
func spawn_dino(id: StringName, row: int) -> Dino:
	var spec := Data.dino(id)
	if spec.is_empty() or row < 0 or row >= rows:
		push_warning("Board: unknown dinosaur '%s'" % id)
		return null
	var d := Dino.new()
	d.name = "Dino_%s_%d" % [id, row]
	_entities.add_child(d)
	d.setup(spec, self, row)
	return d


# --- zombies -------------------------------------------------------------

## `x_offset` is in cells, pushing the zombie further right of the spawn line
## so that several zombies entering the same lane do not overlap.
## `marks` are runtime tags set BEFORE the zombie initializes, so its own
## components see them during setup. That is what stops an escort from
## bringing an escort, or a summoner from summoning summoners.
func spawn_zombie(id: StringName, row: int, x_offset: float = 0.0,
		marks: Array = []) -> Zombie:
	var def := Data.zombie(id)
	if def == null:
		push_warning("Board: unknown zombie '%s'" % id)
		return null

	var z := Zombie.new()
	z.row = clampi(row, 0, rows - 1)
	z.col = cols - 1
	# A little scatter within the lane, so a wave is a crowd rather than a
	# line of identical figures standing on one rail.
	z.lane_offset = randf_range(-1.0, 1.0) * cell_size.y * LANE_SCATTER
	z.position = Vector2(spawn_x() + x_offset * cell_size.x,
			grid_to_world(z.row, 0).y + z.lane_offset)
	z.name = "Zombie_%s" % id
	_entities.add_child(z)
	for mark in marks:
		z.set_runtime_tag(StringName(mark), true)
	z.initialize(def, self)

	z.z_index = lane_z(z.row, LAYER_ZOMBIE)
	_zombies_by_row[z.row].append(z)
	z.died.connect(_on_carrier_died)
	z.died.connect(_on_zombie_gone)
	z.tree_exiting.connect(_on_zombie_gone.bind(z))
	z.reached_house.connect(_on_zombie_reached_house)
	Audio.play(&"zombie.spawn", z.position)
	return z


## Spawns a zombie at a point on the lawn rather than off the right edge.
## Used by zombies that bring or release others - a thrown imp, a camel's
## mummy - where the spawn point is where the parent is, not the spawn line.
func spawn_zombie_at(id: StringName, row: int, x: float,
		marks: Array = []) -> Zombie:
	var z := spawn_zombie(id, row, 0.0, marks)
	if z == null:
		return null
	z.position.x = clampf(x, house_x(), spawn_x())
	z.col = world_to_col(z.position.x)
	return z


## Picks a zombie up and puts it down elsewhere: a dinosaur's kick, a storm.
## Whatever it was eating is let go. Zombies that steer themselves - a boss -
## and ones frozen in a block are left where they are; returns false then.
func move_zombie(z: Zombie, row: int, x: float) -> bool:
	if z == null or z.is_dead or z.movement_claimed or z.is_encased():
		return false
	row = clampi(row, 0, rows - 1)
	if row != z.row:
		_zombies_by_row[z.row].erase(z)
		_zombies_by_row[row].append(z)
		z.row = row
		z.position.y = grid_to_world(row, 0).y + z.lane_offset
	z.position.x = clampf(x, house_x(), spawn_x())
	z.col = world_to_col(z.position.x)
	z.target = null
	z.z_index = lane_z(row, LAYER_ZOMBIE)
	z.queue_redraw()
	return true


## The lane among `candidates` with the fewest hostile zombies, ties broken
## at random. Storms and the low tide spread their arrivals this way.
func quietest_row(candidates: Array) -> int:
	var best: Array[int] = []
	var fewest := INF
	for r in candidates:
		var row := int(r)
		if row < 0 or row >= rows:
			continue
		var n := hostile_zombies_in_row(row).size()
		if n < fewest:
			fewest = n
			best = [row]
		elif n == fewest:
			best.append(row)
	return best.pick_random() if not best.is_empty() else randi() % rows


## A zombie on the threshold is caught by the lane's mower if one is left;
## otherwise the level is lost.
func _on_zombie_reached_house(who: Zombie) -> void:
	zombie_reached_house.emit(who)

	# The world gets first refusal: a lawn with its own threshold rule - house
	# health instead of mowers, say - consumes the zombie here.
	for c in lawn_components:
		if c.handle_zombie_at_house(who):
			return

	var m := mower_in_row(who.row)
	if m != null and m.trigger():
		mower_triggered.emit(who.row)
		Audio.play(&"mower.trigger", m.position)
		return
	level_lost.emit()


## A zombie marked as carrying plant food drops it where it fell.
func _on_carrier_died(who: Character) -> void:
	if who is Zombie:
		zombie_died.emit(who)
		if who.has_tag(&"carrying_plantfood"):
			drop_plant_food(who.position)
		# A plantern's gift: every zombie it lit carries sun to drop.
		if who.has_tag(&"carrying_sun"):
			for i in ceili(int(who.get_meta(&"carried_sun", 0)) / float(SunToken.VALUE)):
				drop_sun(who.position + Vector2(i * 16.0, 0))


func _on_zombie_gone(who: Node) -> void:
	for r in _zombies_by_row:
		_zombies_by_row[r].erase(who)


## Living zombies in one row, nearest the house first.
func zombies_in_row(row: int) -> Array:
	var out: Array = []
	for z in _zombies_by_row.get(row, []):
		if is_instance_valid(z) and not z.is_dead:
			out.append(z)
	out.sort_custom(func(a, b): return a.position.x < b.position.x)
	return out


## Zombies in a lane that still fight for the zombie side. Plant weapons use
## this so they never target a charmed zombie fighting for the player.
func hostile_zombies_in_row(row: int) -> Array:
	var out: Array = []
	for z in zombies_in_row(row):
		if not z.is_charmed():
			out.append(z)
	return out


## Hostile zombies within `rows_reach` lanes of `row` and `cells_reach`
## squares either side of `x` - the "3x3 around me" most area plants mean.
func hostile_zombies_near(row: int, x: float, rows_reach: int,
		cells_reach: float) -> Array:
	var out: Array = []
	var reach := cells_reach * cell_size.x
	for r in range(maxi(0, row - rows_reach), mini(rows, row + rows_reach + 1)):
		for z in hostile_zombies_in_row(r):
			if absf(z.position.x - x) <= reach:
				out.append(z)
	return out


## Every hostile zombie on the lawn, nearest the house first.
func all_hostile_zombies() -> Array:
	var out: Array = []
	for r in rows:
		out.append_array(hostile_zombies_in_row(r))
	out.sort_custom(func(a, b): return a.position.x < b.position.x)
	return out


## Walks a zombie into another lane, keeping the lane index in step. Used by
## anything that pulls zombies sideways - a sweet potato's lure.
func move_zombie_to_row(z: Zombie, row: int) -> void:
	if not is_instance_valid(z) or row < 0 or row >= rows or z.row == row:
		return
	_zombies_by_row[z.row].erase(z)
	z.row = row
	_zombies_by_row[row].append(z)
	z.position.y = grid_to_world(row, 0).y + z.lane_offset
	z.z_index = lane_z(row, LAYER_ZOMBIE)
	z.target = null


func charmed_zombies_in_row(row: int) -> Array:
	var out: Array = []
	for z in zombies_in_row(row):
		if z.is_charmed():
			out.append(z)
	return out


func zombie_count() -> int:
	var n := 0
	for r in _zombies_by_row:
		for z in _zombies_by_row[r]:
			if is_instance_valid(z) and not z.is_dead and not z.is_charmed():
				n += 1
	return n


# --- projectiles and sun -------------------------------------------------

## `direction` 0 picks the side's own way (a plant's shot goes right); a
## split pea's rear head passes -1 to fire back toward the house.
func spawn_projectile(id: StringName, row: int, from: Vector2, source: Node,
		direction: int = 0) -> Projectile:
	var pr := Projectile.new()
	pr.row = row
	pr.board = self
	pr.source = source
	pr.damage = float(Data.projectile_damage(id))
	pr.from_zombie = source is Zombie
	pr.direction = direction if direction != 0 else (-1 if pr.from_zombie else 1)
	pr.position = from
	pr.z_index = lane_z(row, LAYER_PROJECTILE)
	_projectiles.add_child(pr)
	pr.attach_art(id)
	return pr


## A projectile landing on a square: its SplashDamage entries say how far it
## spreads ({Damage, Range: {w, h}, FreezeDuration, ChillDuration}). One with
## no splash just hits that square. Gravestones in the blast break too.
func splash_at(row: int, x: float, projectile_id: StringName, source: Node,
		damage_scale: float = 1.0) -> int:
	var def := Data.projectile(projectile_id)
	var entries: Array = def.extra.get("SplashDamage", []) if def != null else []
	if entries.is_empty():
		entries = [{"Damage": Data.projectile_damage(projectile_id), "Range": {"w": 1, "h": 1}}]
	var hit := 0
	for entry in entries:
		var area: Dictionary = entry.get("Range", {"w": 1, "h": 1})
		var half_rows := int((int(area.get("h", 1)) - 1) / 2)
		var half_w: float = float(area.get("w", 1)) * 0.5 * cell_size.x
		var damage := float(entry.get("Damage", 0.0)) * damage_scale
		for r in range(maxi(0, row - half_rows), mini(rows, row + half_rows + 1)):
			for t in plant_targets_in_row(r):
				if absf(t.position.x - x) > half_w:
					continue
				if damage > 0.0:
					t.take_damage(damage, source if is_instance_valid(source) else null)
					hit += 1
				if t is Zombie:
					if float(entry.get("FreezeDuration", 0.0)) > 0.0:
						t.apply_freeze(float(entry["FreezeDuration"]))
					elif float(entry.get("ChillDuration", 0.0)) > 0.0:
						t.apply_slow(0.5, float(entry["ChillDuration"]))
	return hit


## Sends a sweeper down a lane from the house end. See LaneSweeper.
func spawn_sweeper(row: int, speed: float, dps: float, source: Node) -> LaneSweeper:
	var s := LaneSweeper.new()
	s.board = self
	s.source = source
	s.row = row
	s.speed = speed
	s.dps = dps
	s.half_width = cell_size.x * 0.5
	s.position = Vector2(house_x(), grid_to_world(row, 0).y)
	s.z_index = lane_z(row, LAYER_PROJECTILE)
	_projectiles.add_child(s)
	return s


## Drops a sun from `at`: it hops up, drifts a little either way and settles
## slightly below where it started. Every sun is worth SunToken.VALUE, so
## there is no amount to pass.
func drop_sun(at: Vector2) -> void:
	var ground := at.y + 20.0
	var s := _add_sun_token(at, ground)
	# PVZGE's produceSun: a random sideways drift of up to 3 and an upward
	# speed of 10, from a little above the ground.
	var unit := original_unit()
	s.toss(ground, 50.0, Vector2(randf_range(-3.0, 3.0) * DROP_SPEED * unit.x,
			10.0 * DROP_SPEED * unit.y), DROP_GRAVITY * unit.y)


## Pops a sun out of a plant, as a sunflower does: it leaves `from` heading
## along `direction` and lands on the ground at `ground_y`, the plant's feet.
func pop_sun(from: Vector2, ground_y: float, direction: Vector2) -> void:
	var s := _add_sun_token(from, ground_y)
	var unit := original_unit()
	var v := direction.normalized() * randf_range(7.0, 13.0) * DROP_SPEED
	s.toss(ground_y, ground_y - from.y, Vector2(v.x * unit.x, v.y * unit.y),
			DROP_GRAVITY * unit.y)


## One of PVZGE's world units, in board pixels, on each axis.
func original_unit() -> Vector2:
	return cell_size / LawnScenery.SQUARE_SIZE


func drop_sun_from_sky() -> void:
	var at := grid_to_world(randi() % rows, randi() % cols)
	_add_sun_token(Vector2(at.x, origin.y - 40.0), at.y)


func _add_sun_token(at: Vector2, rest_y: float) -> SunToken:
	var s := SunToken.new()
	s.z_index = LAYER_COLLECTABLE
	s.position = at
	s.fall_to_y = rest_y
	s.collect_target = to_global(sun_collect_target)
	s.x_limits = Vector2(origin.x + cell_size.x * 0.25, origin.x + cell_size.x * (cols - 0.25))
	s.position.x = clampf(s.position.x, s.x_limits.x, s.x_limits.y)
	s.collected.connect(func(c): _on_sun_collected(c))
	_suns.add_child(s)
	Audio.play(&"sun.drop", at)
	return s


func _on_sun_collected(token: Collectable) -> void:
	add_sun(SunToken.VALUE)
	sun_collected.emit(SunToken.VALUE)
	Audio.play(&"sun.collect", token.position)


## Leaves a sun bomb where a moon bean was eaten. `props` carries its
## zombie_damage, zombie_radius, plant_damage and plant_radius (pixels).
func drop_sun_bomb(at: Vector2, props: Dictionary = {}) -> SunBomb:
	var b := SunBomb.new()
	b.board = self
	b.z_index = LAYER_COLLECTABLE
	b.position = at + Vector2(0, -30)
	b.fall_to_y = at.y
	for key in props:
		b.set(key, props[key])
	_suns.add_child(b)
	return b


## Drops plant food where a carrier zombie died.
func drop_plant_food(at: Vector2) -> PlantFoodToken:
	var t := PlantFoodToken.new()
	t.z_index = LAYER_COLLECTABLE
	t.position = at + Vector2(0, -30)
	t.fall_to_y = at.y + 10.0
	t.collect_target = to_global(plant_food_collect_target)
	t.collected.connect(func(c): _on_plant_food_collected(c))
	_suns.add_child(t)
	Audio.play(&"plantfood.drop", at)
	return t


func _on_plant_food_collected(token: Collectable) -> void:
	add_plant_food(PlantFoodToken.VALUE)
	Audio.play(&"plantfood.collect", token.position)


## Drops a coin worth `value` just above `at`.
func drop_coin(at: Vector2, value: int = CoinToken.SILVER) -> CoinToken:
	var c := CoinToken.new()
	c.value = value
	c.z_index = LAYER_COLLECTABLE
	c.position = at + Vector2(0, -30)
	c.fall_to_y = at.y + 10.0
	c.collect_target = to_global(coin_collect_target)
	c.collected.connect(func(t): _on_coin_collected(t))
	_suns.add_child(c)
	return c


func _on_coin_collected(token: Collectable) -> void:
	var value: int = (token as CoinToken).value
	Saves.add_currency(&"coins", value)
	coins_collected.emit(value)
	Audio.play(&"coin.collect", token.position)


## Drops a won level's prize at `at` - where its last zombie fell - and sends
## it leaping to the middle of the lawn to wait for the player.
func drop_reward(reward: LevelReward, at: Vector2) -> RewardDrop:
	var d := RewardDrop.new()
	d.reward = reward
	d.z_index = LAYER_COLLECTABLE
	d.position = at
	# A prize is shown off in the middle of the screen once it is picked up.
	d.collect_target = get_viewport().get_canvas_transform().affine_inverse() \
			* get_viewport().get_visible_rect().get_center()
	d.picked_up.connect(_on_reward_picked_up)
	_suns.add_child(d)
	d.leap_to(grid_to_world(floori(rows / 2.0), floori(cols / 2.0)))
	Audio.play(&"reward.drop", at)
	return d


## A coin bag bursts into coins that fly to the counter on their own, as
## PVZGE's coinbag does.
func _on_reward_picked_up(drop: RewardDrop) -> void:
	if drop.reward == null or drop.reward.type != LevelReward.COIN_BAG:
		return
	var total := drop.reward.amount
	var count := clampi(floori(total / float(LevelReward.SILVER_COIN)), 1, 20)
	var each := floori(total / float(count))
	for i in count:
		var value := each + (total - each * count if i == count - 1 else 0)
		var spread := (i - (count - 1) * 0.5) * 22.0
		var coin := drop_coin(drop.position + Vector2(spread, 0), value)
		get_tree().create_timer(0.6 + i * 0.08).timeout.connect(func() -> void:
			if is_instance_valid(coin):
				coin.collect())


func add_plant_food(amount: int) -> void:
	plant_food = clampi(plant_food + amount, 0, max_plant_food)
	plant_food_changed.emit(plant_food)


func spend_plant_food() -> bool:
	if plant_food <= 0:
		return false
	plant_food -= 1
	plant_food_changed.emit(plant_food)
	return true


## Feeds the plant in a cell, if the player has food and the plant uses it.
func feed_plant(row: int, col: int) -> bool:
	var p := plant_at(row, col)
	if p == null or plant_food <= 0:
		return false
	if not p.apply_plant_food():
		return false
	spend_plant_food()
	Audio.play(&"plant.food", p.position)
	_propagate_power(row, col)
	return true


func add_sun(amount: int) -> void:
	sun += amount
	sun_changed.emit(sun)


func spend_sun(amount: int) -> bool:
	if sun < amount:
		return false
	sun -= amount
	sun_changed.emit(sun)
	if amount > 0:
		sun_spent.emit(amount)
	return true


# --- input ---------------------------------------------------------------

## Taps a plant that does something when tapped: a strawburst fires, a banana
## launcher arms and waits for `aim_at`. Returns true if anything responded.
func tap_plant(row: int, col: int) -> bool:
	var p := plant_at(row, col)
	if p == null or p.is_dead:
		return false
	for comp in p.components():
		if comp.has_method("on_tapped") and comp.on_tapped():
			if comp.has_method("fire_at"):
				aiming = comp
			return true
	return false


## Fires the armed plant at a square. A click off the lawn, or on the plant
## itself, puts it down again.
func aim_at(row: int, col: int) -> bool:
	var armed := aiming
	aiming = null
	if not is_instance_valid(armed) or armed.host.is_dead:
		return false
	if not in_bounds(row, col) or (row == armed.host.row and col == armed.host.col):
		return false
	return armed.fire_at(row, col)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	click(get_local_mouse_position())


## What a left click at `at`, in board coordinates, does with whatever is in
## hand: place it, dig, feed, aim, or tap a plant.
func click(at: Vector2) -> void:
	# Sun is picked up by hovering, so a click only ever places, digs or feeds.
	if plant_food_active:
		if feed_plant(world_to_row(at.y), world_to_col(at.x)):
			plant_food_active = false
			get_viewport().set_input_as_handled()
		return
	if aiming != null:
		aim_at(world_to_row(at.y), world_to_col(at.x))
		get_viewport().set_input_as_handled()
		return
	if selected_seed.is_empty() and not shovel_active \
			and tap_plant(world_to_row(at.y), world_to_col(at.x)):
		get_viewport().set_input_as_handled()
		return
	if shovel_active:
		# One dig per pick-up, as in PVZGE: the shovel goes back after use.
		if dig_up(world_to_row(at.y), world_to_col(at.x)):
			shovel_active = false
			shovel_used.emit()
			get_viewport().set_input_as_handled()
		return
	if selected_seed.is_empty():
		if _handle_cart_click(world_to_row(at.y), world_to_col(at.x)):
			get_viewport().set_input_as_handled()
		return
	var kind := StringName(selected_seed.get("kind", &"plant"))
	var id := StringName(selected_seed.get("id", &""))
	var slot := int(selected_seed.get("slot", -1))
	var row := world_to_row(at.y)
	var col := world_to_col(at.x)
	if not can_place_entity(kind, id, row, col):
		return
	# A packet still recharging cannot be used, however much sun is banked.
	if seed_bank != null and not seed_bank.is_recharged(slot):
		return
	# The bank owns the price: a conveyor packet is free, a chooser packet is
	# whatever its plant costs.
	var cost := seed_bank.cost_of(slot) if seed_bank != null else seed_cost(kind, id)
	if not spend_sun(cost):
		return
	if place_entity(kind, id, row, col,
			StringName(selected_seed.get("imitates", &""))) != null:
		if seed_bank != null:
			seed_bank.consume(slot)
		selected_seed = {}
	get_viewport().set_input_as_handled()


# --- placeholder lawn ----------------------------------------------------

func _draw() -> void:
	# With the stage's own art down, the grass, the locked lanes and the house
	# are all in the picture; only terrain still needs marking.
	var art := scenery != null and scenery.has_art()
	for r in rows:
		var locked := not is_row_plantable(r)
		for c in cols:
			var rect := Rect2(origin + Vector2(c * cell_size.x, r * cell_size.y), cell_size)
			var light := (r + c) % 2 == 0
			if not art:
				draw_rect(rect, lawn_light if light else lawn_dark, true)
			# Terrain reads differently from plain ground at a glance.
			var ground := terrain_def(r, c)
			if ground != null:
				var tint := Color("2d6f9e", 0.55)
				if ground.blocks_planting:
					tint = Color(0, 0, 0, 0.55)
				draw_rect(rect, tint, true)
				if cell_provides(r, c) != &"":
					draw_rect(rect, Color("6ad46a", 0.3), true)
			if is_rail(r, c):
				var mid := rect.position.x + rect.size.x * 0.5
				for dx in [-12.0, 12.0]:
					draw_line(Vector2(mid + dx, rect.position.y),
							Vector2(mid + dx, rect.end.y), Color("5b4636"), 3.0)
			if locked and not (art and scenery.shows_open_rows()):
				draw_rect(rect, locked_lane_tint, true)
	if _held_cart != null and is_instance_valid(_held_cart):
		draw_rect(Rect2(_held_cart.position - cell_size * 0.5, cell_size),
				Color("f2c744"), false, 3.0)
	if art:
		return
	# House edge and the line zombies must not cross.
	draw_line(Vector2(house_x(), origin.y),
			Vector2(house_x(), origin.y + rows * cell_size.y), house_line, 4.0)
