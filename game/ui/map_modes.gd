extends CanvasLayer
signal map_mode_selected(mode: MapMode.Type)

func _on_button_political_button_up() -> void:
	map_mode_selected.emit(MapMode.Type.POLITICAL)

func _on_button_ideology_button_up() -> void:
	map_mode_selected.emit(MapMode.Type.IDEOLOGY)

func _on_button_province_button_up() -> void:
	map_mode_selected.emit(MapMode.Type.PROVINCE)

func _on_button_territory_button_up() -> void:
	map_mode_selected.emit(MapMode.Type.TERRITORY)
