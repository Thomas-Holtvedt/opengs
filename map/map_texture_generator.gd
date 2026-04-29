
class_name MapTextureGenerator

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
]

var lookup_texture: ImageTexture
var border_texture: ImageTexture
var territory_border_texture: ImageTexture

var province_image: Image
var width: int
var height: int
var src_data: PackedByteArray
var bpp: int
var src_stride: int

var cache: MapTextureCache


func _init(p_province_image: Image) -> void:
	province_image = p_province_image
	width = province_image.get_width()
	height = province_image.get_height()
	src_data = province_image.get_data()
	@warning_ignore("integer_division")
	bpp = src_data.size() / (width * height)
	src_stride = width * bpp
	cache = MapTextureCache.new(src_data)


func create_map_textures(db: Database) -> void:
	if cache.available:
		print("Loading Map from cache - Start")
		_load_from_cache(db)
		print("Loading Map from cache - End")
	else:
		print("Generating Map - Start")
		_generate(db)
		print("Generating Map - End")


func _load_from_cache(db: Database) -> void:
	lookup_texture = ImageTexture.create_from_image(cache.load_lookup())
	border_texture = ImageTexture.create_from_image(cache.load_border())
	territory_border_texture = ImageTexture.create_from_image(cache.load_territory_border())
	cache.load_color_map(db)


func _generate(db: Database) -> void:
	var lut_size: int = width * height * 2
	var lut_stride: int = width * 2
	var border_size: int = width * height

	var lut_data: PackedByteArray = PackedByteArray()
	lut_data.resize(lut_size)
	var border_data: PackedByteArray = PackedByteArray()
	border_data.resize(border_size)
	var territory_border_data: PackedByteArray = PackedByteArray()
	territory_border_data.resize(border_size)

	var color_key_to_lookup: Dictionary[int, Vector2i] = {}
	var color_map_r: int = 0
	var color_map_g: int = 0

	for y in range(height):
		for x in range(width):
			var src_idx: int = y * src_stride + x * bpp
			var lut_idx: int = y * lut_stride + x * 2
			var border_idx: int = y * width + x
			var r: int = src_data[src_idx]
			var g: int = src_data[src_idx + 1]
			var b: int = src_data[src_idx + 2]
			var key: int = (r << 16) | (g << 8) | b

			if not color_key_to_lookup.has(key):
				color_key_to_lookup[key] = Vector2i(color_map_r, color_map_g)
				db.province_color_to_lookup[Color(r / 255.0, g / 255.0, b / 255.0)] = Color(color_map_r / 255.0, color_map_g / 255.0, 0.0)
				color_map_r += 1
				if color_map_r == 256:
					color_map_r = 0
					color_map_g += 1

			var lookup: Vector2i = color_key_to_lookup[key]
			lut_data[lut_idx] = lookup.x
			lut_data[lut_idx + 1] = lookup.y

			var is_border: bool = _is_border_pixel(x, y, src_idx, r, g, b)
			border_data[border_idx] = 0 if is_border else 255

			var is_territory_border: bool = _is_territory_border_pixel(x, y, src_idx, r, g, b, db)
			territory_border_data[border_idx] = 0 if is_territory_border else 255

	var lut_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RG8, lut_data)
	lookup_texture = ImageTexture.create_from_image(lut_image)
	var border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, border_data)
	border_texture = ImageTexture.create_from_image(border_image)
	var territory_border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, territory_border_data)
	territory_border_texture = ImageTexture.create_from_image(territory_border_image)
	cache.save(lut_image, border_image, territory_border_image, db)


func update_map_texture(db: Database, center: Vector2i, radius: int) -> void:
	var x_min: int = max(0, center.x - radius)
	var x_max: int = min(width - 1, center.x + radius)
	var y_min: int = max(0, center.y - radius)
	var y_max: int = min(height - 1, center.y + radius)

	var img: Image = territory_border_texture.get_image()
	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			var src_idx: int = y * src_stride + x * bpp
			var r: int = src_data[src_idx]
			var g: int = src_data[src_idx + 1]
			var b: int = src_data[src_idx + 2]
			var is_territory_border: bool = _is_territory_border_pixel(x, y, src_idx, r, g, b, db)
			img.set_pixel(x, y, Color(0, 0, 0) if is_territory_border else Color(1, 1, 1))
	territory_border_texture.update(img)


func _is_border_pixel(x: int, y: int, src_idx: int, r: int, g: int, b: int) -> bool:
	for offset in NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			continue
		var ni: int = src_idx + offset.x * bpp + offset.y * src_stride
		if src_data[ni] != r or src_data[ni + 1] != g or src_data[ni + 2] != b:
			return true
	return false


func _is_territory_border_pixel(x: int, y: int, src_idx: int, r: int, g: int, b: int, db: Database) -> bool:
	var territory: Territory = _territory_at(r, g, b, db)
	for offset in NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			continue
		var ni: int = src_idx + offset.x * bpp + offset.y * src_stride
		if _territory_at(src_data[ni], src_data[ni + 1], src_data[ni + 2], db) != territory:
			return true
	return false


func _territory_at(r: int, g: int, b: int, db: Database) -> Territory:
	var province: Province = db.color_to_province.get(Color(r / 255.0, g / 255.0, b / 255.0))
	return province.territory if province != null else null


func set_map_textures(shader_material: ShaderMaterial) -> void:
	shader_material.set_shader_parameter("lookup_image", lookup_texture)
	shader_material.set_shader_parameter("province_border_image", border_texture)
	shader_material.set_shader_parameter("territory_border_image", territory_border_texture)
