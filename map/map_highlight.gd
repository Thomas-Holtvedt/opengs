extends Resource
class_name MapHighlight

var highlighted_province: Color
var highlighted_territory: PackedColorArray
var province_hl: Color = Color(0.361, 1.0, 0.192, 1.0)
var territory_hl: Color = Color(1.0, 1.0, 1.0, 1.0)
var null_hl: Color = Color(0.0, 0.0, 0.0, 1.0)


func _init(province: Province) -> void:
	highlighted_province = province.color
	if province.territory != null:
		var territory: Territory = province.territory
		for t_province in territory.provinces:
			highlighted_territory.append(t_province.color)
			
	
func apply_highlights(mm: MapMode) -> MapMode:
	for color: Color in highlighted_territory:
		mm.update_color_map(color, territory_hl, mm.highlight_offset)
		mm.update_color_map(highlighted_province, province_hl, mm.highlight_offset)
	return mm

func remove_highlights(mm: MapMode) -> MapMode:
	for color: Color in highlighted_territory:
		mm.update_color_map(color, null_hl, mm.highlight_offset)
		mm.update_color_map(highlighted_province, null_hl, mm.highlight_offset)
	return mm
