@tool
class_name RigSlot
extends Node2D
## One slot of a rig: a node at its bone, holding one child per picture it
## can show, named by that picture's index.
##
## Animations key `display` to switch pictures - an eye blinking, a mouth
## opening, a plant food helmet appearing - and it stays a switch, never a
## texture swap mid-blend. One integer per slot keeps a rig like the seed
## packet's, with a picture for every plant, to one track per animation
## instead of one per picture. -1 shows nothing, as in DragonBones.

@export var display: int = 0:
	set(value):
		display = value
		_show()


func _ready() -> void:
	_show()


func _show() -> void:
	var shown := str(display)
	for child in get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = child.name == shown
