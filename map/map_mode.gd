extends ImageTexture
class_name MapMode

enum Type {POLITICAL, IDEOLOGY, TERRITORY, PROVINCE, TERRAIN}

const PRIMARY_OFFSET: int = 0
var secondary_offset: int
var highlight_offset: int
var _province_color_to_lookup: Dictionary[Color, Color]
var color_map: Image


func _init(province_color_to_lookup: Dictionary[Color, Color], color_to_province: Dictionary[Color, Province], type: Type) -> void:
	var num_lookup_rows: int = maxi(1, ceili(float(province_color_to_lookup.size()) / 256.0))
	secondary_offset = num_lookup_rows
	highlight_offset = 2 * num_lookup_rows
	color_map = _create_color_map(province_color_to_lookup, color_to_province, type, num_lookup_rows)
	self._province_color_to_lookup = province_color_to_lookup
	self.set_image(color_map)



func _create_color_map(province_color_to_lookup: Dictionary[Color, Color], color_to_province, type, num_lookup_rows: int) -> Image:
	var _color_map: Image = Image.create(256, 3 * num_lookup_rows, false, Image.FORMAT_RGB8)
	for province_color: Color in province_color_to_lookup:
		if color_to_province.has(province_color):
			var lookup: Color = province_color_to_lookup[province_color]
			var x: int = roundi(lookup.r * 255)
			var y: int = roundi(lookup.g * 255)
			var province: Province = color_to_province[province_color]
			if province.type == Province.Type.LAND:
				match type:
					Type.POLITICAL:
						_color_map.set_pixel(x, y, province.province_owner.map_color)
						_color_map.set_pixel(x, y + secondary_offset, province.province_controller.map_color)

					Type.IDEOLOGY:
						_color_map.set_pixel(x, y, _ideology_color(province.province_owner.ideology))
						_color_map.set_pixel(x, y + secondary_offset, _ideology_color(province.province_controller.ideology))

					Type.PROVINCE:
						_color_map.set_pixel(x, y, province_color)
						_color_map.set_pixel(x, y + secondary_offset, province_color)

					Type.TERRITORY:
						var sibling_province: Province = province.territory.provinces[0]
						_color_map.set_pixel(x, y, sibling_province.color)
						_color_map.set_pixel(x, y + secondary_offset, sibling_province.color)

					Type.TERRAIN:
						_color_map.set_pixel(x, y, _terrain_color(province.terrain))
						_color_map.set_pixel(x, y + secondary_offset, _terrain_color(province.terrain))
	return _color_map

func _ideology_color(ideology: Country.Ideology) -> Color:
	match ideology:
		Country.Ideology.DEMOCRACY:
			return Color.BLUE
		Country.Ideology.COMMUNISM:
			return Color.RED
	return Color.BLACK
	
func _terrain_color(terrain: Province.Terrain) -> Color:
	match terrain:
		Province.Terrain.FOREST:
			return Color.WEB_GREEN
		Province.Terrain.HILLS:
			return Color.GRAY
		Province.Terrain.MOUNTAIN:
			return Color.DARK_GRAY
		Province.Terrain.PLAINS:
			return Color.LIGHT_YELLOW
		Province.Terrain.URBAN:
			return Color.RED
		Province.Terrain.JUNGLE:
			return Color.DARK_GREEN
		Province.Terrain.MARSH:
			return Color.DARK_OLIVE_GREEN
		Province.Terrain.DESERT:
			return Color.SANDY_BROWN
		Province.Terrain.DEEP_OCEAN:
			return Color.DARK_BLUE
		Province.Terrain.SHALLOW_SEA:
			return Color.LIGHT_BLUE
		Province.Terrain.FJORDS:
			return Color.BLUE
		Province.Terrain.LAKES:
			return Color.BLUE
	return Color.BLACK


func update_color_map(input_color: Color, output_color: Color, offset: int) -> void:
	var lookup: Color = _province_color_to_lookup.get(input_color, null)
	if lookup:
		var x: int = roundi(lookup.r * 255)
		var y: int = roundi(lookup.g * 255)
		color_map.set_pixel(x, y + offset, output_color)
		self.set_image(color_map)
