# Extends ImageTexture deliberately: the mode IS the color-map texture, so it can be
# bound directly as the color_map_image shader uniform (see Map.update_map).
extends ImageTexture
class_name MapMode

enum Type {POLITICAL, IDEOLOGY, TERRITORY, PROVINCE, TERRAIN}

const PRIMARY_OFFSET: int = 0
var type: Type
var secondary_offset: int
var highlight_offset: int
var _province_color_to_lookup: Dictionary[Color, Color]
var color_map: Image


func _init(province_color_to_lookup: Dictionary[Color, Color], color_to_province: Dictionary[Color, Province], mode_type: Type) -> void:
	var num_lookup_rows: int = maxi(1, ceili(float(province_color_to_lookup.size()) / 256.0))
	self.type = mode_type
	secondary_offset = num_lookup_rows
	highlight_offset = 2 * num_lookup_rows
	self._province_color_to_lookup = province_color_to_lookup
	color_map = Image.create(256, 3 * num_lookup_rows, false, Image.FORMAT_RGB8)
	for province_color: Color in province_color_to_lookup:
		if color_to_province.has(province_color):
			update_province(color_to_province[province_color])
	self.set_image(color_map)


func update_province(province: Province) -> void:
	if province.type != Province.Type.LAND:
		return
	var colors: Array[Color] = _compute_colors(province)
	update_color_map(province.color, colors[0], PRIMARY_OFFSET)
	update_color_map(province.color, colors[1], secondary_offset)


func _compute_colors(province: Province) -> Array[Color]:
	match type:
		Type.POLITICAL:
			return [province.province_owner.map_color, province.province_controller.map_color]
		Type.IDEOLOGY:
			return [_ideology_color(province.province_owner.ideology), _ideology_color(province.province_controller.ideology)]
		Type.PROVINCE:
			return [province.color, province.color]
		Type.TERRITORY:
			var sibling: Province = province.territory.provinces[0]
			return [sibling.color, sibling.color]
		Type.TERRAIN:
			var terrain_color: Color = _terrain_color(province.terrain)
			return [terrain_color, terrain_color]
	return [Color.BLACK, Color.BLACK]


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
	if not _province_color_to_lookup.has(input_color):
		return
	var lookup: Color = _province_color_to_lookup[input_color]
	var x: int = roundi(lookup.r * 255)
	var y: int = roundi(lookup.g * 255)
	color_map.set_pixel(x, y + offset, output_color)


func commit() -> void:
	self.set_image(color_map)
