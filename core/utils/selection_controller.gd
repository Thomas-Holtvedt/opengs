extends Node
class_name SelectionController

# Owns selected_provinces state. Translates clicks into selection changes,
# drives map highlight, and emits selection_changed for UI to react.
# Dependencies are injected once via setup().

signal selection_changed(provinces: Array[Province])

var map: Map
var db: Database
var selected_provinces: Array[Province] = []


func setup(target_map: Map, database: Database) -> void:
	map = target_map
	db = database


func select_at(world_pos: Vector2, additive: bool) -> void:
	var color: Color = map.get_pixel_lookup_color(world_pos)
	var clicked: Province = db.color_to_province[color]
	select(clicked, additive)


func select(province: Province, additive: bool) -> void:
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
	
