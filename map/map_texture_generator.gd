
class_name MapTextureGenerator

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
]
# Bounded SDF refresh assumes max distance any shader cares about. Must be >= the largest
# value the consuming uniforms (country_fade_inwards/outwards, selection_thickness) can hit.
# Used to derive the JFA crop region from the per-batch dirty rect.
const SDF_AFFECT_RANGE: int = 128

var lookup_texture: ImageTexture
var border_texture: ImageTexture
var territory_border_texture: ImageTexture
var country_border_texture: ImageTexture
var province_sdf_texture: ImageTexture
var territory_sdf_texture: ImageTexture
var country_sdf_texture: ImageTexture

# CPU-side mirrors so we can mutate masks and SDF tiles without going through the GPU
# per province. The territory/country SDF images are also kept here so partial JFA results
# can be blitted into a known-good full image before re-uploading.
var territory_border_image: Image
var country_border_image: Image
var territory_sdf_image: Image
var country_sdf_image: Image

# Accumulated bounding box of regions whose mask has been mutated since the last refresh.
# Empty (has_area()==false) means no pending change.
var _territory_dirty_box: Rect2i
var _country_dirty_box: Rect2i

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
	territory_border_image = cache.load_territory_border()
	territory_border_texture = ImageTexture.create_from_image(territory_border_image)
	country_border_image = cache.load_country_border()
	country_border_texture = ImageTexture.create_from_image(country_border_image)
	province_sdf_texture = ImageTexture.create_from_image(cache.load_province_sdf())
	territory_sdf_image = cache.load_territory_sdf()
	territory_sdf_texture = ImageTexture.create_from_image(territory_sdf_image)
	country_sdf_image = cache.load_country_sdf()
	country_sdf_texture = ImageTexture.create_from_image(country_sdf_image)
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
	var country_border_data: PackedByteArray = PackedByteArray()
	country_border_data.resize(border_size)

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

			var is_country_border: bool = _is_country_border_pixel(x, y, src_idx, r, g, b, db)
			country_border_data[border_idx] = 0 if is_country_border else 255

	var lut_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RG8, lut_data)
	lookup_texture = ImageTexture.create_from_image(lut_image)
	var border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, border_data)
	border_texture = ImageTexture.create_from_image(border_image)
	territory_border_image = Image.create_from_data(width, height, false, Image.FORMAT_L8, territory_border_data)
	territory_border_texture = ImageTexture.create_from_image(territory_border_image)
	country_border_image = Image.create_from_data(width, height, false, Image.FORMAT_L8, country_border_data)
	country_border_texture = ImageTexture.create_from_image(country_border_image)
	print("  Province SDF (GPU JFA) - Start")
	var province_sdf_image: Image = MapTextureSDF.build_sdf(border_data, width, height)
	print("  Province SDF (GPU JFA) - End")
	province_sdf_texture = ImageTexture.create_from_image(province_sdf_image)
	print("  Territory SDF (GPU JFA) - Start")
	territory_sdf_image = MapTextureSDF.build_sdf(territory_border_data, width, height)
	print("  Territory SDF (GPU JFA) - End")
	territory_sdf_texture = ImageTexture.create_from_image(territory_sdf_image)
	print("  Country SDF (GPU JFA) - Start")
	country_sdf_image = MapTextureSDF.build_sdf(country_border_data, width, height)
	print("  Country SDF (GPU JFA) - End")
	country_sdf_texture = ImageTexture.create_from_image(country_sdf_image)
	cache.save(lut_image, border_image, territory_border_image, country_border_image, province_sdf_image, territory_sdf_image, country_sdf_image, db)


func update_map_texture(db: Database, center: Vector2i, radius: int, refresh: bool = true) -> void:
	var x_min: int = max(0, center.x - radius)
	var x_max: int = min(width - 1, center.x + radius)
	var y_min: int = max(0, center.y - radius)
	var y_max: int = min(height - 1, center.y + radius)

	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			var src_idx: int = y * src_stride + x * bpp
			var r: int = src_data[src_idx]
			var g: int = src_data[src_idx + 1]
			var b: int = src_data[src_idx + 2]
			var is_territory_border: bool = _is_territory_border_pixel(x, y, src_idx, r, g, b, db)
			territory_border_image.set_pixel(x, y, Color(0, 0, 0) if is_territory_border else Color(1, 1, 1))
	_territory_dirty_box = _expand_dirty_box(_territory_dirty_box, x_min, y_min, x_max, y_max)
	if refresh:
		refresh_territory_sdf()


func refresh_territory_sdf() -> void:
	if not _territory_dirty_box.has_area():
		return
	territory_border_texture.update(territory_border_image)
	_refresh_sdf_bounded(territory_sdf_image, territory_sdf_texture, territory_border_image, _territory_dirty_box)
	_territory_dirty_box = Rect2i()


func update_country_borders(db: Database, center: Vector2i, radius: int, refresh: bool = true) -> void:
	var x_min: int = max(0, center.x - radius)
	var x_max: int = min(width - 1, center.x + radius)
	var y_min: int = max(0, center.y - radius)
	var y_max: int = min(height - 1, center.y + radius)

	for y in range(y_min, y_max + 1):
		for x in range(x_min, x_max + 1):
			var src_idx: int = y * src_stride + x * bpp
			var r: int = src_data[src_idx]
			var g: int = src_data[src_idx + 1]
			var b: int = src_data[src_idx + 2]
			var is_country_border: bool = _is_country_border_pixel(x, y, src_idx, r, g, b, db)
			country_border_image.set_pixel(x, y, Color(0, 0, 0) if is_country_border else Color(1, 1, 1))
	_country_dirty_box = _expand_dirty_box(_country_dirty_box, x_min, y_min, x_max, y_max)
	if refresh:
		refresh_country_sdf()


func refresh_country_sdf() -> void:
	if not _country_dirty_box.has_area():
		return
	country_border_texture.update(country_border_image)
	_refresh_sdf_bounded(country_sdf_image, country_sdf_texture, country_border_image, _country_dirty_box)
	_country_dirty_box = Rect2i()


# Runs JFA on the smallest crop containing every pixel whose SDF could have changed
# (dirty_box padded by SDF_AFFECT_RANGE) plus another SDF_AFFECT_RANGE so the JFA can
# see all borders that any affected pixel could reach. The crop result is blitted back
# into sdf_image at the affected sub-region, then the whole image is re-uploaded.
func _refresh_sdf_bounded(sdf_image: Image, sdf_texture: ImageTexture, border_image: Image, dirty_box: Rect2i) -> void:
	var image_bounds: Rect2i = Rect2i(0, 0, width, height)
	var affected: Rect2i = dirty_box.grow(SDF_AFFECT_RANGE).intersection(image_bounds)
	var crop: Rect2i = affected.grow(SDF_AFFECT_RANGE).intersection(image_bounds)
	var crop_data: PackedByteArray = MapTextureSDF.build_sdf_region(border_image.get_data(), width, height, crop)
	var crop_image: Image = Image.create_from_data(crop.size.x, crop.size.y, false, Image.FORMAT_RGBA8, crop_data)
	var local_affected: Rect2i = Rect2i(affected.position - crop.position, affected.size)
	sdf_image.blit_rect(crop_image, local_affected, affected.position)
	sdf_texture.update(sdf_image)


func _expand_dirty_box(current: Rect2i, x_min: int, y_min: int, x_max: int, y_max: int) -> Rect2i:
	var added: Rect2i = Rect2i(x_min, y_min, x_max - x_min + 1, y_max - y_min + 1)
	return added if not current.has_area() else current.merge(added)


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


func _is_country_border_pixel(x: int, y: int, src_idx: int, r: int, g: int, b: int, db: Database) -> bool:
	var owner: Country = _owner_at(r, g, b, db)
	for offset in NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			continue
		var ni: int = src_idx + offset.x * bpp + offset.y * src_stride
		if _owner_at(src_data[ni], src_data[ni + 1], src_data[ni + 2], db) != owner:
			return true
	return false


func _owner_at(r: int, g: int, b: int, db: Database) -> Country:
	var province: Province = db.color_to_province.get(Color(r / 255.0, g / 255.0, b / 255.0))
	return province.province_owner if province != null else null


func set_map_textures(shader_material: ShaderMaterial) -> void:
	shader_material.set_shader_parameter("lookup_image", lookup_texture)
	shader_material.set_shader_parameter("province_border_image", border_texture)
	shader_material.set_shader_parameter("territory_border_image", territory_border_texture)
	shader_material.set_shader_parameter("province_sdf_image", province_sdf_texture)
	shader_material.set_shader_parameter("territory_sdf_image", territory_sdf_texture)
	shader_material.set_shader_parameter("country_sdf_image", country_sdf_texture)
