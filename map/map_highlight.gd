extends Resource
class_name MapHighlight

var highlighted_provinces: PackedColorArray
var highlighted_territory: PackedColorArray
var province_hl: Color = Color(0.361, 1.0, 0.192, 1.0)
var territory_hl: Color = Color(1.0, 1.0, 1.0, 1.0)
var null_hl: Color = Color(0.0, 0.0, 0.0, 1.0)


func _init(provinces: Array[Province]) -> void:
	var province_set: Dictionary = {}
	for province in provinces:
		if province.color in province_set:
			continue
		province_set[province.color] = true
		highlighted_provinces.append(province.color)

	var territory_set: Dictionary = {}
	for province in provinces:
		if province.territory == null:
			continue
		for t_province in province.territory.provinces:
			if t_province.color in province_set:
				continue # selected province takes precedence over territory color
			if t_province.color in territory_set:
				continue
			territory_set[t_province.color] = true
			highlighted_territory.append(t_province.color)


# Mutates the given map mode in place.
func apply_highlights(map_mode: MapMode) -> void:
	for color: Color in highlighted_territory:
		map_mode.update_color_map(color, territory_hl, map_mode.highlight_offset)
	for color: Color in highlighted_provinces:
		map_mode.update_color_map(color, province_hl, map_mode.highlight_offset)
	map_mode.commit()


# Mutates the given map mode in place.
func remove_highlights(map_mode: MapMode) -> void:
	for color: Color in highlighted_territory:
		map_mode.update_color_map(color, null_hl, map_mode.highlight_offset)
	for color: Color in highlighted_provinces:
		map_mode.update_color_map(color, null_hl, map_mode.highlight_offset)
	map_mode.commit()
