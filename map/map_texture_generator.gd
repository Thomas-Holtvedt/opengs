
class_name MapTextureGenerator

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
]
# Bounded SDF refresh assumes max distance any shader cares about. Must be >= the largest
# value the consuming uniforms (country_fade_inwards/outwards, selection_thickness) can hit.
# Used to derive the JFA crop region from the per-batch dirty rect.
const SDF_AFFECT_RANGE: int = 128
# Country SDF is rendered downsampled by this factor on each axis. Only the political-mode
# fade reads it (smooth gradient, linear-filtered), so coarse data is fine and the JFA cost
# drops ~SCALE^2. Encoded offsets are in downsampled-texel units; the shader multiplies them
# back up by country_sdf_scale so fade uniforms stay in full-res pixels.
const COUNTRY_SDF_SCALE: int = 4

var lookup_texture: ImageTexture
var border_texture: ImageTexture
var territory_border_texture: ImageTexture
var province_sdf_texture: ImageTexture
var territory_sdf_texture: ImageTexture
var country_sdf_texture: ImageTexture
# Note: there is no country_border_texture. country_border_image is kept around purely so
# we can write the L8 mask into the disk cache during cold gen, but the shader has no
# country_border_image uniform — only country_sdf_image is sampled. Re-uploading the L8
# mask on every refresh was a ~10 ms wasted GPU transfer per province change.

# CPU-side mirrors so we can mutate masks and SDF tiles without going through the GPU
# per province. The territory/country SDF images are also kept here so partial JFA results
# can be blitted into a known-good full image before re-uploading.
var territory_border_image: Image
var country_border_image: Image
var territory_sdf_image: Image
var country_sdf_image: Image

# Downsampled mirror of country_border_image; the actual JFA input. Re-derived by the
# country SDF worker for the affected ds-region on every refresh — never touched by the
# main thread after init.
var country_border_ds_data: PackedByteArray

# Raw byte mirrors of the L8 border masks. The territory variant is mutated synchronously
# by update_map_texture on the main thread; the country variant is mutated only by the
# country SDF worker thread (see _country_worker_run). PackedByteArray byte writes are
# ~50x faster than Image.set_pixel in GDScript, which is what made these worth keeping.
var territory_border_bytes: PackedByteArray
var country_border_bytes: PackedByteArray

# Accumulated bounding box of regions whose mask has been mutated since the last refresh.
# Empty (has_area()==false) means no pending change.
var _territory_dirty_box: Rect2i
var _country_dirty_box: Rect2i

# Async refresh state for the country SDF (main-thread-only).
# _country_worker_busy is true while a WorkerThreadPool task is mid-flight (from add_task
# until its deferred _country_sdf_apply has run on the main thread).
# _country_pending_box accumulates any new dirty regions that come in while the worker is
# busy; once the in-flight task finishes, the apply step kicks off a follow-up task with it.
var _country_worker_busy: bool = false
var _country_pending_box: Rect2i

# Stored Database reference so the worker can re-derive country border pixels without the
# main thread having to pass `db` through the deferred call. Set lazily by
# update_country_borders; the worker only reads provinces/ownership, never mutates them.
var _db: Database

var province_image: Image
var width: int
var height: int
var src_data: PackedByteArray
var bpp: int
var src_stride: int

# Downsampled country-SDF dimensions (width/height divided by COUNTRY_SDF_SCALE).
var country_sdf_width: int
var country_sdf_height: int

var cache: MapTextureCache


func _init(p_province_image: Image) -> void:
	province_image = p_province_image
	width = province_image.get_width()
	height = province_image.get_height()
	src_data = province_image.get_data()
	@warning_ignore("integer_division")
	bpp = src_data.size() / (width * height)
	src_stride = width * bpp
	@warning_ignore("integer_division")
	country_sdf_width = width / COUNTRY_SDF_SCALE
	@warning_ignore("integer_division")
	country_sdf_height = height / COUNTRY_SDF_SCALE
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
	territory_border_bytes = territory_border_image.get_data()
	territory_border_texture = ImageTexture.create_from_image(territory_border_image)
	country_border_image = cache.load_country_border()
	country_border_bytes = country_border_image.get_data()
	province_sdf_texture = ImageTexture.create_from_image(cache.load_province_sdf())
	territory_sdf_image = cache.load_territory_sdf()
	territory_sdf_texture = ImageTexture.create_from_image(territory_sdf_image)
	country_sdf_image = cache.load_country_sdf()
	country_sdf_texture = ImageTexture.create_from_image(country_sdf_image)
	country_border_ds_data = _downsample_country_border(country_border_bytes)
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
	var territory_cache: Dictionary[int, Territory] = {}
	var owner_cache: Dictionary[int, Country] = {}

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

			var is_territory_border: bool = _is_territory_border_pixel(x, y, src_idx, r, g, b, territory_cache, db)
			territory_border_data[border_idx] = 0 if is_territory_border else 255

			var is_country_border: bool = _is_country_border_pixel(x, y, src_idx, r, g, b, owner_cache, db)
			country_border_data[border_idx] = 0 if is_country_border else 255

	var lut_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RG8, lut_data)
	lookup_texture = ImageTexture.create_from_image(lut_image)
	var border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, border_data)
	border_texture = ImageTexture.create_from_image(border_image)
	territory_border_image = Image.create_from_data(width, height, false, Image.FORMAT_L8, territory_border_data)
	territory_border_bytes = territory_border_data
	territory_border_texture = ImageTexture.create_from_image(territory_border_image)
	country_border_image = Image.create_from_data(width, height, false, Image.FORMAT_L8, country_border_data)
	country_border_bytes = country_border_data
	print("  Province SDF (GPU JFA) - Start")
	var province_sdf_image: Image = MapTextureSDF.build_sdf(border_data, width, height)
	print("  Province SDF (GPU JFA) - End")
	province_sdf_texture = ImageTexture.create_from_image(province_sdf_image)
	print("  Territory SDF (GPU JFA) - Start")
	territory_sdf_image = MapTextureSDF.build_sdf(territory_border_data, width, height)
	print("  Territory SDF (GPU JFA) - End")
	territory_sdf_texture = ImageTexture.create_from_image(territory_sdf_image)
	print("  Country SDF (GPU JFA, %dx downsample) - Start" % COUNTRY_SDF_SCALE)
	country_border_ds_data = _downsample_country_border(country_border_data)
	country_sdf_image = MapTextureSDF.build_sdf(country_border_ds_data, country_sdf_width, country_sdf_height)
	print("  Country SDF (GPU JFA, %dx downsample) - End" % COUNTRY_SDF_SCALE)
	country_sdf_texture = ImageTexture.create_from_image(country_sdf_image)
	cache.save(lut_image, border_image, territory_border_image, country_border_image, province_sdf_image, territory_sdf_image, country_sdf_image, db)


func update_map_texture(db: Database, center: Vector2i, radius: int, refresh: bool = true) -> void:
	var x_min: int = max(0, center.x - radius)
	var x_max: int = min(width - 1, center.x + radius)
	var y_min: int = max(0, center.y - radius)
	var y_max: int = min(height - 1, center.y + radius)
	var territory_cache: Dictionary[int, Territory] = {}

	for y in range(y_min, y_max + 1):
		var row: int = y * width
		for x in range(x_min, x_max + 1):
			var src_idx: int = y * src_stride + x * bpp
			var r: int = src_data[src_idx]
			var g: int = src_data[src_idx + 1]
			var b: int = src_data[src_idx + 2]
			var is_territory_border: bool = _is_territory_border_pixel(x, y, src_idx, r, g, b, territory_cache, db)
			territory_border_bytes[row + x] = 0 if is_territory_border else 255
	_territory_dirty_box = _expand_dirty_box(_territory_dirty_box, x_min, y_min, x_max, y_max)
	if refresh:
		refresh_territory_sdf()


func refresh_territory_sdf() -> void:
	if not _territory_dirty_box.has_area():
		return
	# territory_border_texture is bound in set_map_textures but map2d.gdshader declares
	# `territory_border_image` without sampling it, so the per-refresh GPU upload would be
	# a wasted 12.5 MB transfer. Re-add a set_data + texture.update here if the shader ever
	# starts reading territory_border_image again.
	_refresh_sdf_bounded(territory_sdf_image, territory_sdf_texture, territory_border_bytes, _territory_dirty_box)
	_territory_dirty_box = Rect2i()


# Just tracks the dirty region on the main thread; the actual border-mask rewrite happens
# on a worker thread inside _country_worker_run, kicked off by refresh_country_sdf.
func update_country_borders(db: Database, center: Vector2i, radius: int, refresh: bool = true) -> void:
	_db = db
	var x_min: int = max(0, center.x - radius)
	var x_max: int = min(width - 1, center.x + radius)
	var y_min: int = max(0, center.y - radius)
	var y_max: int = min(height - 1, center.y + radius)
	_country_dirty_box = _expand_dirty_box(_country_dirty_box, x_min, y_min, x_max, y_max)
	if refresh:
		refresh_country_sdf()


# Hands the accumulated dirty region off to a WorkerThreadPool task. Returns immediately;
# the visible fade band updates once the worker finishes and its deferred apply runs on the
# next main-thread frame. If a worker is already in flight, the new region is folded into
# _country_pending_box and picked up after the current task completes.
func refresh_country_sdf() -> void:
	if not _country_dirty_box.has_area():
		return
	var dirty_box: Rect2i = _country_dirty_box
	_country_dirty_box = Rect2i()

	if _country_worker_busy:
		_country_pending_box = _country_pending_box.merge(dirty_box) if _country_pending_box.has_area() else dirty_box
		return

	_start_country_worker(dirty_box)


func _start_country_worker(dirty_box: Rect2i) -> void:
	_country_worker_busy = true
	WorkerThreadPool.add_task(_country_worker_run.bind(dirty_box))


# Worker-thread function: rewrites country_border_bytes for the dirty region, syncs the
# downsampled mask, runs JFA on the local RenderingDevice, then hands the resulting crop
# back to the main thread for the actual GPU-side blit + texture upload.
# Notes on concurrency:
#  - country_border_bytes / country_border_ds_data: only touched by this worker after init,
#    so no synchronization needed against the main thread.
#  - src_data, width/height/bpp/src_stride: written once at init, then read-only.
#  - _db.color_to_province: built during DataImporter and never mutated afterwards.
#  - province.province_owner: can be mutated by main while we read it. Treated as an
#    eventually-consistent snapshot — if main changes ownership mid-task, the next refresh
#    will reconcile.
func _country_worker_run(dirty_box: Rect2i) -> void:
	var x_min: int = dirty_box.position.x
	var x_max: int = dirty_box.position.x + dirty_box.size.x - 1
	var y_min: int = dirty_box.position.y
	var y_max: int = dirty_box.position.y + dirty_box.size.y - 1
	var owner_cache: Dictionary[int, Country] = {}

	for y in range(y_min, y_max + 1):
		var row: int = y * width
		for x in range(x_min, x_max + 1):
			var src_idx: int = y * src_stride + x * bpp
			var r: int = src_data[src_idx]
			var g: int = src_data[src_idx + 1]
			var b: int = src_data[src_idx + 2]
			var is_country_border: bool = _is_country_border_pixel(x, y, src_idx, r, g, b, owner_cache, _db)
			country_border_bytes[row + x] = 0 if is_country_border else 255

	var ds_dirty: Rect2i = _full_to_country_ds_rect(dirty_box)
	_downsample_country_border_region(country_border_bytes, ds_dirty)

	var ds_bounds: Rect2i = Rect2i(0, 0, country_sdf_width, country_sdf_height)
	@warning_ignore("integer_division")
	var ds_affect_range: int = SDF_AFFECT_RANGE / COUNTRY_SDF_SCALE
	var affected: Rect2i = ds_dirty.grow(ds_affect_range).intersection(ds_bounds)
	var crop: Rect2i = affected.grow(ds_affect_range).intersection(ds_bounds)
	var crop_data: PackedByteArray = MapTextureSDF.build_sdf_region(country_border_ds_data, country_sdf_width, country_sdf_height, crop)

	_country_sdf_apply.call_deferred(crop_data, affected, crop)


# Runs on the main thread (via call_deferred from the worker). Pure Godot rendering work
# that must stay off the worker thread: Image.blit_rect + ImageTexture.update.
func _country_sdf_apply(crop_data: PackedByteArray, affected: Rect2i, crop: Rect2i) -> void:
	var crop_image: Image = Image.create_from_data(crop.size.x, crop.size.y, false, Image.FORMAT_RGBA8, crop_data)
	var local_affected: Rect2i = Rect2i(affected.position - crop.position, affected.size)
	country_sdf_image.blit_rect(crop_image, local_affected, affected.position)
	country_sdf_texture.update(country_sdf_image)

	_country_worker_busy = false
	if _country_pending_box.has_area():
		var next_box: Rect2i = _country_pending_box
		_country_pending_box = Rect2i()
		_start_country_worker(next_box)


# Conservatively converts a full-res rect to the smallest downsampled rect that covers
# every ds-pixel touching it. Clamped to the downsampled image bounds.
func _full_to_country_ds_rect(full: Rect2i) -> Rect2i:
	var s: int = COUNTRY_SDF_SCALE
	var ds_bounds: Rect2i = Rect2i(0, 0, country_sdf_width, country_sdf_height)
	@warning_ignore("integer_division")
	var x0: int = full.position.x / s
	@warning_ignore("integer_division")
	var y0: int = full.position.y / s
	@warning_ignore("integer_division")
	var x1: int = (full.position.x + full.size.x - 1) / s
	@warning_ignore("integer_division")
	var y1: int = (full.position.y + full.size.y - 1) / s
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1).intersection(ds_bounds)


# Builds a fresh downsampled mask from the full-res border bytes. A ds-pixel is marked as
# border (0) iff any of the SCALExSCALE source pixels covering it is a border pixel.
func _downsample_country_border(full_data: PackedByteArray) -> PackedByteArray:
	country_border_ds_data = PackedByteArray()
	country_border_ds_data.resize(country_sdf_width * country_sdf_height)
	_downsample_country_border_region(full_data, Rect2i(0, 0, country_sdf_width, country_sdf_height))
	return country_border_ds_data


# Writes ds-pixels inside `ds_region` (in downsampled coords) by min-pooling the full-res mask.
# Writes go directly into country_border_ds_data to avoid PackedByteArray copy-on-write surprises.
func _downsample_country_border_region(full_data: PackedByteArray, ds_region: Rect2i) -> void:
	var s: int = COUNTRY_SDF_SCALE
	for ly in range(ds_region.size.y):
		var ds_y: int = ds_region.position.y + ly
		var fy0: int = ds_y * s
		var fy1: int = min(fy0 + s, height)
		var ds_row: int = ds_y * country_sdf_width
		for lx in range(ds_region.size.x):
			var ds_x: int = ds_region.position.x + lx
			var fx0: int = ds_x * s
			var fx1: int = min(fx0 + s, width)
			var is_border: int = 255
			for fy in range(fy0, fy1):
				var full_row: int = fy * width
				for fx in range(fx0, fx1):
					if full_data[full_row + fx] == 0:
						is_border = 0
						break
				if is_border == 0:
					break
			country_border_ds_data[ds_row + ds_x] = is_border


# Runs JFA on the smallest crop containing every pixel whose SDF could have changed
# (dirty_box padded by SDF_AFFECT_RANGE) plus another SDF_AFFECT_RANGE so the JFA can
# see all borders that any affected pixel could reach. The crop result is blitted back
# into sdf_image at the affected sub-region, then the whole image is re-uploaded.
func _refresh_sdf_bounded(sdf_image: Image, sdf_texture: ImageTexture, border_bytes: PackedByteArray, dirty_box: Rect2i) -> void:
	var image_bounds: Rect2i = Rect2i(0, 0, width, height)
	var affected: Rect2i = dirty_box.grow(SDF_AFFECT_RANGE).intersection(image_bounds)
	var crop: Rect2i = affected.grow(SDF_AFFECT_RANGE).intersection(image_bounds)
	var crop_data: PackedByteArray = MapTextureSDF.build_sdf_region(border_bytes, width, height, crop)
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


func _is_territory_border_pixel(x: int, y: int, src_idx: int, r: int, g: int, b: int, _cache: Dictionary, db: Database) -> bool:
	var territory: Territory = _cached_territory(r, g, b, _cache, db)
	for offset in NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			continue
		var ni: int = src_idx + offset.x * bpp + offset.y * src_stride
		if _cached_territory(src_data[ni], src_data[ni + 1], src_data[ni + 2], _cache, db) != territory:
			return true
	return false


# Memoizes the per-color territory lookup so callers can avoid a Color allocation and a
# Color-keyed dict lookup on every pixel. Each dirty region typically contains only a
# handful of distinct province colors, so after the first miss the cache is mostly hits.
func _cached_territory(r: int, g: int, b: int, _cache: Dictionary, db: Database) -> Territory:
	var key: int = (r << 16) | (g << 8) | b
	if _cache.has(key):
		return _cache[key]
	var province: Province = db.color_to_province.get(Color(r / 255.0, g / 255.0, b / 255.0))
	var territory: Territory = province.territory if province != null else null
	_cache[key] = territory
	return territory


func _is_country_border_pixel(x: int, y: int, src_idx: int, r: int, g: int, b: int, _cache: Dictionary, db: Database) -> bool:
	var owner: Country = _cached_owner(r, g, b, _cache, db)
	for offset in NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			continue
		var ni: int = src_idx + offset.x * bpp + offset.y * src_stride
		if _cached_owner(src_data[ni], src_data[ni + 1], src_data[ni + 2], _cache, db) != owner:
			return true
	return false


# Memoizes the per-color owner lookup. See _cached_territory for the rationale.
func _cached_owner(r: int, g: int, b: int, _cache: Dictionary, db: Database) -> Country:
	var key: int = (r << 16) | (g << 8) | b
	if _cache.has(key):
		return _cache[key]
	var province: Province = db.color_to_province.get(Color(r / 255.0, g / 255.0, b / 255.0))
	var owner: Country = province.province_owner if province != null else null
	_cache[key] = owner
	return owner


func set_map_textures(shader_material: ShaderMaterial) -> void:
	shader_material.set_shader_parameter("lookup_image", lookup_texture)
	shader_material.set_shader_parameter("province_border_image", border_texture)
	shader_material.set_shader_parameter("territory_border_image", territory_border_texture)
	shader_material.set_shader_parameter("province_sdf_image", province_sdf_texture)
	shader_material.set_shader_parameter("territory_sdf_image", territory_sdf_texture)
	shader_material.set_shader_parameter("country_sdf_image", country_sdf_texture)
