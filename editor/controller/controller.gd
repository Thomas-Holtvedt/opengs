extends CameraController

signal province_selected(world_pos: Vector2, additive: bool)


func _on_province_click(world_pos: Vector2, event: InputEvent) -> void:
	province_selected.emit(world_pos, event.shift_pressed)
	
