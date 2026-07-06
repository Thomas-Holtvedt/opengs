extends Resource
class_name MapTextureCache

const CACHE_DIR: String = "user://map_cache"
# Bump whenever the generated content changes for the same source image (mask semantics,
# SDF encoding, downsampling, ...) so stale caches regenerate instead of being loaded.
const CACHE_VERSION: int = 2
const LOOKUP_FILE: String = "lookup_texture.png"
const BORDER_FILE: String = "border_texture.png"
const TERRITORY_BORDER_FILE: String = "territory_border_texture.png"
const COUNTRY_BORDER_FILE: String = "country_border_texture.png"
const PROVINCE_SDF_FILE: String = "province_sdf_texture.png"
const TERRITORY_SDF_FILE: String = "territory_sdf_texture.png"
const COUNTRY_SDF_FILE: String = "country_sdf_texture_dist.png"
const COLOR_MAP_FILE: String = "province_color_to_lookup.data"

var cache_id: String
var available: bool


func _init(src_data: PackedByteArray) -> void:
	cache_id = Marshalls.raw_to_base64(src_data).md5_text() + "_v%d" % CACHE_VERSION
	available = FileAccess.file_exists(_cache_path(LOOKUP_FILE)) \
			and FileAccess.file_exists(_cache_path(BORDER_FILE)) \
			and FileAccess.file_exists(_cache_path(TERRITORY_BORDER_FILE)) \
			and FileAccess.file_exists(_cache_path(COUNTRY_BORDER_FILE)) \
			and FileAccess.file_exists(_cache_path(PROVINCE_SDF_FILE)) \
			and FileAccess.file_exists(_cache_path(TERRITORY_SDF_FILE)) \
			and FileAccess.file_exists(_cache_path(COUNTRY_SDF_FILE)) \
			and FileAccess.file_exists(_cache_path(COLOR_MAP_FILE))


func load_lookup() -> Image:
	return _load_image(LOOKUP_FILE, Image.FORMAT_RG8)


func load_border() -> Image:
	return _load_image(BORDER_FILE, Image.FORMAT_L8)


func load_territory_border() -> Image:
	return _load_image(TERRITORY_BORDER_FILE, Image.FORMAT_L8)


func load_country_border() -> Image:
	return _load_image(COUNTRY_BORDER_FILE, Image.FORMAT_L8)


func load_province_sdf() -> Image:
	return _load_image(PROVINCE_SDF_FILE, Image.FORMAT_RGBA8)


func load_territory_sdf() -> Image:
	return _load_image(TERRITORY_SDF_FILE, Image.FORMAT_RGBA8)


func load_country_sdf() -> Image:
	return _load_image(COUNTRY_SDF_FILE, Image.FORMAT_RGBA8)


func load_color_map(db: Database) -> void:
	var file: FileAccess = FileAccess.open(_cache_path(COLOR_MAP_FILE), FileAccess.READ)
	if file == null:
		push_error("Failed to open: " + _cache_path(COLOR_MAP_FILE))
		return
	db.province_color_to_lookup = str_to_var(file.get_as_text())
	file.close()


func save(lookup_image: Image, border_image: Image, territory_border_image: Image, country_border_image: Image, province_sdf_image: Image, territory_sdf_image: Image, country_sdf_image: Image, db: Database) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR + "/" + cache_id)
	lookup_image.save_png(_cache_path(LOOKUP_FILE))
	border_image.save_png(_cache_path(BORDER_FILE))
	territory_border_image.save_png(_cache_path(TERRITORY_BORDER_FILE))
	country_border_image.save_png(_cache_path(COUNTRY_BORDER_FILE))
	province_sdf_image.save_png(_cache_path(PROVINCE_SDF_FILE))
	territory_sdf_image.save_png(_cache_path(TERRITORY_SDF_FILE))
	country_sdf_image.save_png(_cache_path(COUNTRY_SDF_FILE))
	var file: FileAccess = FileAccess.open(_cache_path(COLOR_MAP_FILE), FileAccess.WRITE)
	if file == null:
		push_error("Failed to open: " + _cache_path(COLOR_MAP_FILE))
		return
	file.store_string(var_to_str(db.province_color_to_lookup))
	file.close()


func _load_image(file: String, format: Image.Format) -> Image:
	var img: Image = Image.load_from_file(_cache_path(file))
	img.convert(format)
	return img


func _cache_path(filename: String) -> String:
	return "{dir}/{id}/{file}".format({"dir": CACHE_DIR, "id": cache_id, "file": filename})
