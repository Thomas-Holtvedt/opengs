extends Node
class_name SelectionController

# Owns selected_provinces state. Translates clicks into selection changes,
# drives map highlight, and emits selection_changed for UI to react.

signal selection_changed(provinces: Array[Province])

var selected_provinces: Array[Province] = []


func select_at(world_pos: Vector2, additive: bool, map: Map, db: Database) -> void:
	var color: Color = map.get_pixel_lookup_color(world_pos)
	var clicked: Province = db.color_to_province[color]
	select(clicked, additive, map)


func select(province: Province, additive: bool, map: Map) -> void:
	if additive:
		if province in selected_provinces:
			if selected_provinces.size() > 1:
				selected_provinces.erase(province)
		else:
			selected_provinces.append(province)
	else:
		selected_provinces = [province]
	map.highlight_provinces(selected_provinces)
	selection_changed.emit(selected_provinces)
	
