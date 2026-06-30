extends Node
# Thin coordinator. Keep this node small.
# Belongs here: cross-controller methods that span two or more controllers (e.g. focus_on() = camera + map).
# Rule of thumb: if a method only touches one controller, it belongs on that controller, not here.

@onready var map: Map = $"../Map"
@onready var camera: CameraController = $"../CameraControllerEditor"
@onready var selection: SelectionController = $"../SelectionController"


func select_and_show(target: Province) -> void:
	selection.select(target, false)
	camera.move_to((target.center - Vector2i(map.map_mesh.size)) * 0.5)
	map.pulse_selection(10)
