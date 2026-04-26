
class_name MapTextureGenerator

const CACHE_DIR: String = "user://map_cache"
const LOOKUP_FILE: String = "lookup_texture.png"
const BORDER_FILE: String = "border_texture.png"
const TERRITORY_BORDER_FILE: String = "territory_border_texture.png"
const COLOR_MAP_FILE: String = "province_color_to_lookup.data"

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
]

var lookup_texture: ImageTexture
var border_texture: ImageTexture
var territory_border_texture: ImageTexture
var cache_id: String
var cache_available: bool


func _init(province_image: Image) -> void:
	cache_id = Marshalls.raw_to_base64(province_image.get_data()).md5_text()
	cache_available = FileAccess.file_exists(_cache_path(LOOKUP_FILE)) \
			and FileAccess.file_exists(_cache_path(BORDER_FILE)) \
			and FileAccess.file_exists(_cache_path(TERRITORY_BORDER_FILE)) \
			and FileAccess.file_exists(_cache_path(COLOR_MAP_FILE))


func create_map_textures(province_image: Image, db: Database) -> void:
	if cache_available:
		print("Loading Map from cache - Start")
		_load_from_cache(db)
		print("Loading Map from cache - End")
	else:
		print("Generating Map - Start")
		_generate(province_image, db)
		print("Generating Map - End")


func _load_from_cache(db: Database) -> void:
	var lookup_image := Image.load_from_file(_cache_path(LOOKUP_FILE))
	lookup_image.convert(Image.FORMAT_RG8)
	lookup_texture = ImageTexture.create_from_image(lookup_image)

	var border_image := Image.load_from_file(_cache_path(BORDER_FILE))
	border_image.convert(Image.FORMAT_L8)
	border_texture = ImageTexture.create_from_image(border_image)

	var territory_border_image := Image.load_from_file(_cache_path(TERRITORY_BORDER_FILE))
	territory_border_image.convert(Image.FORMAT_L8)
	territory_border_texture = ImageTexture.create_from_image(territory_border_image)

	var f := FileAccess.open(_cache_path(COLOR_MAP_FILE), FileAccess.READ)
	db.province_color_to_lookup = str_to_var(f.get_as_text())
	f.close()


func _generate(province_image: Image, db: Database) -> void:
	var width: int = province_image.get_width()
	var height: int = province_image.get_height()
	var src_data: PackedByteArray = province_image.get_data()
	@warning_ignore("integer_division")
	var bpp: int = src_data.size() / (width * height)
	var src_stride: int = width * bpp

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

			# --- Lookup texture ---
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

			# --- Border texture ---
			var is_border: bool = _is_border_pixel(
				x, y, width, height, src_data, src_idx, src_stride, bpp, r, g, b
			)
			border_data[border_idx] = 0 if is_border else 255

			# --- Territory Border texture ---
			var is_territory_border: bool = _is_territory_border_pixel(
				x, y, width, height, src_data, src_idx, src_stride, bpp, r, g, b, db
			)
			territory_border_data[border_idx] = 0 if is_territory_border else 255
	
	var lut_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RG8, lut_data)
	lookup_texture = ImageTexture.create_from_image(lut_image)
	var border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, border_data)
	border_texture = ImageTexture.create_from_image(border_image)
	var territory_border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, territory_border_data)
	territory_border_texture = ImageTexture.create_from_image(territory_border_image)
	_save_to_cache(lut_image, border_image, territory_border_image, db)


func _save_to_cache(lut_image: Image, border_image: Image, territory_border_image: Image, db: Database) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR + "/" + cache_id)
	lut_image.save_png(_cache_path(LOOKUP_FILE))
	border_image.save_png(_cache_path(BORDER_FILE))
	territory_border_image.save_png(_cache_path(TERRITORY_BORDER_FILE))
	var f := FileAccess.open(_cache_path(COLOR_MAP_FILE), FileAccess.WRITE)
	f.store_string(var_to_str(db.province_color_to_lookup))
	f.close()


func _is_border_pixel(
		x: int, y: int, width: int, height: int,
		src_data: PackedByteArray, src_idx: int, src_stride: int, bpp: int,
		r: int, g: int, b: int
) -> bool:
	for offset in NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			continue
		var ni: int = src_idx + offset.x * bpp + offset.y * src_stride
		if src_data[ni] != r or src_data[ni + 1] != g or src_data[ni + 2] != b:
			return true
	return false


func _is_territory_border_pixel(
		x: int, y: int, width: int, height: int,
		src_data: PackedByteArray, src_idx: int, src_stride: int, bpp: int,
		r: int, g: int, b: int, db: Database
) -> bool:
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


func _cache_path(filename: String) -> String:
	return "{dir}/{id}/{file}".format({"dir": CACHE_DIR, "id": cache_id, "file": filename})
