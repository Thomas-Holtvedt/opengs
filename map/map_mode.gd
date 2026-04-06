extends ImageTexture
class_name MapMode

enum Type {POLITICAL, IDEOLOGY, TERRITORY, PROVINCE}

const PRIMARY_OFFSET = 0
var secondary_offset: int
var highlight_offset: int
var _province_color_to_lookup: Dictionary[Color, Color]
var color_map: Image


func _init(province_color_to_lookup: Dictionary[Color, Color], color_to_province: Dictionary[Color, Province], type: Type, num_lookup_rows: int = 256) -> void:
	secondary_offset = num_lookup_rows
	highlight_offset = 2 * num_lookup_rows
	color_map = _create_color_map(province_color_to_lookup, color_to_province, type, num_lookup_rows)
	self._province_color_to_lookup = province_color_to_lookup
	self.set_image(color_map)



func _create_color_map(province_color_to_lookup, color_to_province, type, num_lookup_rows: int) -> Image:
	var _color_map = Image.create(256, 3 * num_lookup_rows, false, Image.FORMAT_RGB8)
	for province_color: Color in province_color_to_lookup:
		if not color_to_province.has(province_color):
			continue
		var lookup: Color = province_color_to_lookup[province_color]
		var x = roundi(lookup.r * 255)
		var y = roundi(lookup.g * 255)
		var province: Province = color_to_province[province_color]
		if province.type != Province.Type.LAND:
			continue
		match type:
			Type.POLITICAL:
				_color_map.set_pixel(x, y, province.province_owner.map_color)
				_color_map.set_pixel(x, y + secondary_offset, province.province_controller.map_color)

			Type.IDEOLOGY:
				match province.province_owner.ideology:
					Country.Ideology.DEMOCRACY:
						_color_map.set_pixel(x, y, Color(0.0, 0.0, 1.0, 1.0))
					Country.Ideology.COMMUNISM:
						_color_map.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))

				match province.province_controller.ideology:
					Country.Ideology.DEMOCRACY:
						_color_map.set_pixel(x, y + secondary_offset, Color(0.0, 0.0, 1.0, 1.0))
					Country.Ideology.COMMUNISM:
						_color_map.set_pixel(x, y + secondary_offset, Color(1.0, 0.0, 0.0, 1.0))

			Type.PROVINCE:
				_color_map.set_pixel(x, y, province_color)
				_color_map.set_pixel(x, y + secondary_offset, province_color)

			Type.TERRITORY:
				var sibling_province = province.territory.provinces[0]
				_color_map.set_pixel(x, y, sibling_province.color)
				_color_map.set_pixel(x, y + secondary_offset, sibling_province.color)


	return _color_map

func update_color_map(input_color: Color, output_color: Color, offset: int) -> void:
	var lookup = _province_color_to_lookup.get(input_color, null)
	if lookup:
		var x = roundi(lookup.r * 255)
		var y = roundi(lookup.g * 255)
		color_map.set_pixel(x, y + offset, output_color)
		self.set_image(color_map)
