class_name Grave
extends GridObject
## A gravestone: destroyable by plants, and able to fire grid-item events such
## as summoning zombies on a timer.

signal destroyed_by(who: Node)

@export var grave_size := Vector2(58, 62)
@export var grave_color: Color = Color("8d8d96")
@export var health_bar_color: Color = Color("cfcfd8")

## Sunk out of sight - PVZGE's Tombstone.hidden, renamed because Godot's
## CanvasItem already has a `hidden` signal. A grave buster chewing on a stone
## sinks it: it is still in its cell, but nothing can aim at or hit it until
## it comes back up.
var sunk: bool = false:
	set(value):
		sunk = value
		visible = not value


func _on_initialized() -> void:
	queue_redraw()


func is_gravebuster_plantable() -> bool:
	return def is GraveDef and def.gravebuster_plantable


func is_flying() -> bool:
	return def is GraveDef and def.flying


func _on_death() -> void:
	destroyed_by.emit(self)
	if board and board.has_method("remove_object"):
		board.remove_object(row, col)
	queue_free()


func _draw() -> void:
	var rect := Rect2(Vector2(-grave_size.x * 0.5, -grave_size.y * 0.6), grave_size)
	draw_rect(rect, grave_color, true)
	draw_rect(rect, grave_color.darkened(0.45), false, 2.0)

	if health < max_health:
		var bar := Rect2(Vector2(-grave_size.x * 0.5, -grave_size.y * 0.6 - 8),
				Vector2(grave_size.x, 4))
		draw_rect(bar, Color(0, 0, 0, 0.5), true)
		bar.size.x *= health_fraction()
		draw_rect(bar, health_bar_color, true)
