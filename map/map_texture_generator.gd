
class_name MapTextureGenerator

var lookup_texture: ImageTexture
var border_texture: ImageTexture
var province_color_to_lookup: Dictionary[Color, Color]
var cache_id: String





func _init(province_image: Image) -> void:
	cache_id = Marshalls.raw_to_base64(province_image.get_data()).md5_text()

	if FileAccess.file_exists(_cache_path("lookup_texture.png")) \
			and FileAccess.file_exists(_cache_path("border_texture.png")) \
			and FileAccess.file_exists(_cache_path("province_color_to_lookup.data")):
		print("Loading Map from cache - Start")
		var lookup_image := Image.load_from_file(_cache_path("lookup_texture.png"))
		lookup_image.convert(Image.FORMAT_RG8) # Memory optimization
		lookup_texture = ImageTexture.create_from_image(lookup_image)

		var border_image := Image.load_from_file(_cache_path("border_texture.png"))
		border_image.convert(Image.FORMAT_L8) # Memory optimization
		border_texture = ImageTexture.create_from_image(border_image)
		var f = FileAccess.open(_cache_path("province_color_to_lookup.data"), FileAccess.READ)
		province_color_to_lookup = str_to_var(f.get_as_text())
		f.close()
		print("Loading Map from cache - End")
	else:
		print("Generating Map - Start")
		_generate(province_image)
		print("Generating Map - End")

func _generate(province_image: Image) -> void:
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
				province_color_to_lookup[Color(r / 255.0, g / 255.0, b / 255.0)] = Color(color_map_r / 255.0, color_map_g / 255.0, 0.0)
				color_map_r += 1
				if color_map_r == 256:
					color_map_r = 0
					color_map_g += 1

			var lookup: Vector2i = color_key_to_lookup[key]
			lut_data[lut_idx] = lookup.x
			lut_data[lut_idx + 1] = lookup.y

			# --- Border texture ---
			var is_border: bool = false
			if x > 0:
				var ni: int = src_idx - bpp
				if src_data[ni] != r or src_data[ni + 1] != g or src_data[ni + 2] != b:
					is_border = true
			if not is_border and x < width - 1:
				var ni: int = src_idx + bpp
				if src_data[ni] != r or src_data[ni + 1] != g or src_data[ni + 2] != b:
					is_border = true
			if not is_border and y > 0:
				var ni: int = src_idx - src_stride
				if src_data[ni] != r or src_data[ni + 1] != g or src_data[ni + 2] != b:
					is_border = true
			if not is_border and y < height - 1:
				var ni: int = src_idx + src_stride
				if src_data[ni] != r or src_data[ni + 1] != g or src_data[ni + 2] != b:
					is_border = true

			if is_border:
				border_data[border_idx] = 0
			else:
				border_data[border_idx] = 255
	DirAccess.make_dir_recursive_absolute("user://map_cache/" + cache_id)
	var lut_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RG8, lut_data)
	lookup_texture = ImageTexture.create_from_image(lut_image)
	lut_image.save_png(_cache_path("lookup_texture.png"))
	var border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, border_data)
	border_texture = ImageTexture.create_from_image(border_image)
	border_image.save_png(_cache_path("border_texture.png"))
	var f := FileAccess.open(_cache_path("province_color_to_lookup.data"), FileAccess.WRITE)
	if f:
		f.store_string(var_to_str(province_color_to_lookup))
		f.close()

func _cache_path(filename: String) -> String:
	return "user://map_cache/{id}/{file}".format({"id": cache_id, "file": filename})
