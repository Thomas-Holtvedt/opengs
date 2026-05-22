extends CameraController

signal province_selected(world_pos: Vector2)


func _on_province_click(world_pos: Vector2, _event: InputEvent) -> void:
	province_selected.emit(world_pos)
