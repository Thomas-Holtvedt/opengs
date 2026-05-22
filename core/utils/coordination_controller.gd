extends Node
# Thin coordinator. Keep this node small.
# Belongs here: cross-controller methods that span two or more controllers (e.g. focus_on() = camera + map).
# Rule of thumb: if a method only touches one controller, it belongs on that controller, not here.

@onready var map = $"../Map"
@onready var camera: CameraController = $"../CameraControllerEditor"
@onready var selection: SelectionController = $"../SelectionController"

func select_and_show(target: Province):
	selection.select(target, false, map)
	#camera.move_to((target.center - Vector2i(2500, 1250)) * 0.1)
	camera.move_to((target.center - Vector2i(map.map_mesh.size)) * 0.5)
	map.pulse_selection(10)
