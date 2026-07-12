
class_name MapTextureGenerator

# Main thread; selection_province_sdf_texture / selection_rect are safe to bind after this.
signal selection_sdf_ready

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
]
# Max SDF distance any shader uniform reads (country_fade_* etc). Bounded refreshes pad
# their dirty rect by this, so it must stay >= the largest such uniform value.
const SDF_AFFECT_RANGE: int = 128
# Padding around the selection SDF crop; must exceed the widest ring the shader can draw
# (selection_thickness at its pulse peak + selection_fade).
const SELECTION_MARGIN: int = 24

var lookup_texture: ImageTexture
var border_texture: ImageTexture
# Distance field around every province boundary. Province shapes never change at runtime,
# so this is built once; the shader draws the AA border line from its B-channel distance.
var province_sdf_texture: ImageTexture
var country_sdf_texture: ImageTexture
# Distance field around every territory boundary, built once and disk-cached. The white
# selection ring reads it directly, so selecting a huge territory costs nothing per click.
var territory_sdf_texture: ImageTexture

# Lookup-indexed territory identity map (same 256-wide layout as MapMode): entry = the
# territory's color, black = none. Compared against selected_territory_ids in the shader.
var territory_id_image: Image
var territory_id_texture: ImageTexture

# Crop-sized SDF around the current selection's province boundaries, rebuilt per selection
# change; the green ring is drawn purely from this.
var selection_province_sdf_texture: ImageTexture
var selection_rect: Rect2i

# Async selection build state (main thread only). The request id makes newer selections
# win: a finishing worker only publishes if its id is still current.
var _selection_worker_busy: bool = false
var _selection_request_id: int = 0
var _selection_pending: Array[Province] = []

# country_border_image exists only so cold gen can write the L8 mask into the disk cache;
# the shader never samples it, so it is never uploaded as a texture.
# The SDF images are kept so partial JFA results can be blitted in before re-uploading.
var territory_border_image: Image
var territory_sdf_image: Image
var country_border_image: Image
var country_sdf_image: Image

# Raw L8 mask bytes; byte writes are ~50x faster than Image.set_pixel in GDScript.
# Territory bytes are mutated on the main thread, country bytes only by the SDF worker.
var territory_border_bytes: PackedByteArray
var country_border_bytes: PackedByteArray

# Accumulated bounding boxes of mask mutations awaiting refresh; no area = nothing pending.
var _territory_dirty_box: Rect2i
var _country_dirty_box: Rect2i

# Country SDF worker state: busy while a task is in flight; regions arriving meanwhile
# accumulate in _country_pending_box and run as a follow-up task.
var _country_worker_busy: bool = false
var _country_pending_box: Rect2i

# Injected once; workers only read provinces/ownership from it, never mutate.
var db: Database

var province_image: Image
var width: int
var height: int
var src_data: PackedByteArray
var bpp: int
var src_stride: int

var cache: MapTextureCache


func _init(p_province_image: Image, p_db: Database) -> void:
	province_image = p_province_image
	db = p_db
	width = province_image.get_width()
	height = province_image.get_height()
	src_data = province_image.get_data()
	@warning_ignore("integer_division")
	bpp = src_data.size() / (width * height)
	src_stride = width * bpp
	cache = MapTextureCache.new(src_data)


func create_map_textures() -> void:
	if cache.available:
		print("Loading Map from cache - Start")
		_load_from_cache()
		print("Loading Map from cache - End")
	else:
		print("Generating Map - Start")
		_generate()
		print("Generating Map - End")


func _load_from_cache() -> void:
	lookup_texture = ImageTexture.create_from_image(cache.load_lookup())
	var border_image: Image = cache.load_border()
	border_texture = ImageTexture.create_from_image(border_image)
	# The province SDF isn't disk-cached; one extra GPU JFA at load rebuilds it from the mask.
	province_sdf_texture = ImageTexture.create_from_image(
			MapTextureSDF.build_sdf(border_image.get_data(), width, height))
	territory_border_image = cache.load_territory_border()
	territory_border_bytes = territory_border_image.get_data()
	territory_sdf_image = cache.load_territory_sdf()
	territory_sdf_texture = ImageTexture.create_from_image(territory_sdf_image)
	country_border_image = cache.load_country_border()
	country_border_bytes = country_border_image.get_data()
	country_sdf_image = cache.load_country_sdf()
	country_sdf_texture = ImageTexture.create_from_image(country_sdf_image)
	cache.load_color_map(db)
	_apply_province_bounds(cache.load_province_bounds())
	_build_territory_id_map()


# Keys are packed RGB province colors ((r << 16) | (g << 8) | b).
func _apply_province_bounds(province_bounds: Dictionary) -> void:
	for key: int in province_bounds:
		var color: Color = Color(
				((key >> 16) & 0xFF) / 255.0, ((key >> 8) & 0xFF) / 255.0, (key & 0xFF) / 255.0)
		var province: Province = db.color_to_province.get(color)
		if province != null:
			province.pixel_bounds = province_bounds[key]


func _generate() -> void:
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

	# Per-province pixel bounds, accumulated per lookup index (lookup.y * 256 + lookup.x).
	# Packed arrays instead of a Dictionary keep the per-pixel cost to compares.
	var bounds_min_x: PackedInt32Array = PackedInt32Array()
	bounds_min_x.resize(65536)
	bounds_min_x.fill(width)
	var bounds_min_y: PackedInt32Array = PackedInt32Array()
	bounds_min_y.resize(65536)
	bounds_min_y.fill(height)
	var bounds_max_x: PackedInt32Array = PackedInt32Array()
	bounds_max_x.resize(65536)
	bounds_max_x.fill(-1)
	var bounds_max_y: PackedInt32Array = PackedInt32Array()
	bounds_max_y.resize(65536)
	bounds_max_y.fill(-1)

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

			var bounds_idx: int = lookup.y * 256 + lookup.x
			if x < bounds_min_x[bounds_idx]:
				bounds_min_x[bounds_idx] = x
			if x > bounds_max_x[bounds_idx]:
				bounds_max_x[bounds_idx] = x
			if y < bounds_min_y[bounds_idx]:
				bounds_min_y[bounds_idx] = y
			if y > bounds_max_y[bounds_idx]:
				bounds_max_y[bounds_idx] = y

			var is_border: bool = _is_border_pixel(x, y, src_idx, r, g, b)
			border_data[border_idx] = 0 if is_border else 255

			var is_territory_border: bool = _is_territory_border_pixel(x, y, src_idx, r, g, b, territory_cache)
			territory_border_data[border_idx] = 0 if is_territory_border else 255

			var is_country_border: bool = _is_country_border_pixel(x, y, src_idx, r, g, b, owner_cache)
			country_border_data[border_idx] = 0 if is_country_border else 255

	var lut_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RG8, lut_data)
	lookup_texture = ImageTexture.create_from_image(lut_image)
	var border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, border_data)
	border_texture = ImageTexture.create_from_image(border_image)
	print("  Province SDF (GPU JFA) - Start")
	province_sdf_texture = ImageTexture.create_from_image(MapTextureSDF.build_sdf(border_data, width, height))
	print("  Province SDF (GPU JFA) - End")
	territory_border_image = Image.create_from_data(width, height, false, Image.FORMAT_L8, territory_border_data)
	territory_border_bytes = territory_border_data
	print("  Territory SDF (GPU JFA) - Start")
	territory_sdf_image = MapTextureSDF.build_sdf(territory_border_data, width, height)
	print("  Territory SDF (GPU JFA) - End")
	territory_sdf_texture = ImageTexture.create_from_image(territory_sdf_image)
	country_border_image = Image.create_from_data(width, height, false, Image.FORMAT_L8, country_border_data)
	country_border_bytes = country_border_data
	print("  Country SDF (GPU JFA) - Start")
	country_sdf_image = MapTextureSDF.build_sdf(country_border_data, width, height)
	print("  Country SDF (GPU JFA) - End")
	country_sdf_texture = ImageTexture.create_from_image(country_sdf_image)

	var province_bounds: Dictionary[int, Rect2i] = {}
	for key: int in color_key_to_lookup:
		var lookup: Vector2i = color_key_to_lookup[key]
		var bounds_idx: int = lookup.y * 256 + lookup.x
		if bounds_max_x[bounds_idx] < 0:
			continue
		province_bounds[key] = Rect2i(
				bounds_min_x[bounds_idx], bounds_min_y[bounds_idx],
				bounds_max_x[bounds_idx] - bounds_min_x[bounds_idx] + 1,
				bounds_max_y[bounds_idx] - bounds_min_y[bounds_idx] + 1)
	_apply_province_bounds(province_bounds)
	_build_territory_id_map()

	cache.save(lut_image, border_image, territory_border_image, territory_sdf_image, country_border_image, country_sdf_image, province_bounds, db)


# Only tracks the dirty region; the mask rewrite happens on the worker in _country_worker_run.
func update_country_borders(box: Rect2i, refresh: bool = true) -> void:
	var clamped: Rect2i = box.intersection(Rect2i(0, 0, width, height))
	if not clamped.has_area():
		return
	_country_dirty_box = clamped if not _country_dirty_box.has_area() else _country_dirty_box.merge(clamped)
	if refresh:
		refresh_country_sdf()


# Hands the accumulated dirty region to a worker task and returns immediately; the visible
# fade band updates once the deferred apply runs on a later main-thread frame.
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


# Worker thread: rewrites country_border_bytes for the dirty region, then defers the GPU
# work back to the main thread. The JFA must NOT run here; Godot restricts a RenderingDevice
# to the thread that created it, and MapTextureSDF's is created on the main thread.
# Concurrency: country_border_bytes is only read by main after this task finishes
# (call_deferred); src_data and db.color_to_province are immutable after init; ownership can
# change mid-task, but the next refresh reconciles that.
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
			var is_country_border: bool = _is_country_border_pixel(x, y, src_idx, r, g, b, owner_cache)
			country_border_bytes[row + x] = 0 if is_country_border else 255

	_country_sdf_apply.call_deferred(dirty_box)


# Main thread (deferred from the worker): GPU JFA on the dirty crop, blit, texture upload.
func _country_sdf_apply(dirty_box: Rect2i) -> void:
	_refresh_sdf_bounded(country_sdf_image, country_sdf_texture, country_border_bytes, dirty_box)

	_country_worker_busy = false
	if _country_pending_box.has_area():
		var next_box: Rect2i = _country_pending_box
		_country_pending_box = Rect2i()
		_start_country_worker(next_box)


# Synchronous on the main thread: territory reassignment is an editor-only action on small
# regions, so it doesn't need the worker handoff the country ownership churn gets.
func update_territory_borders(box: Rect2i, refresh: bool = true) -> void:
	var clamped: Rect2i = box.intersection(Rect2i(0, 0, width, height))
	if not clamped.has_area():
		return
	var territory_cache: Dictionary[int, Territory] = {}
	for y in range(clamped.position.y, clamped.end.y):
		var row: int = y * width
		for x in range(clamped.position.x, clamped.end.x):
			var src_idx: int = y * src_stride + x * bpp
			var is_territory_border: bool = _is_territory_border_pixel(
					x, y, src_idx, src_data[src_idx], src_data[src_idx + 1], src_data[src_idx + 2], territory_cache)
			territory_border_bytes[row + x] = 0 if is_territory_border else 255
	_territory_dirty_box = clamped if not _territory_dirty_box.has_area() else _territory_dirty_box.merge(clamped)
	if refresh:
		refresh_territory_sdf()


func refresh_territory_sdf() -> void:
	if not _territory_dirty_box.has_area():
		return
	_refresh_sdf_bounded(territory_sdf_image, territory_sdf_texture, territory_border_bytes, _territory_dirty_box)
	_territory_dirty_box = Rect2i()


# Runs once after cold gen / cache load; editor reassignment patches single entries.
func _build_territory_id_map() -> void:
	var num_rows: int = maxi(1, ceili(float(db.province_color_to_lookup.size()) / 256.0))
	territory_id_image = Image.create(256, num_rows, false, Image.FORMAT_RGB8)
	for province_color: Color in db.color_to_province:
		_write_territory_id(db.color_to_province[province_color])
	territory_id_texture = ImageTexture.create_from_image(territory_id_image)


func update_territory_id(province: Province) -> void:
	_write_territory_id(province)
	territory_id_texture.update(territory_id_image)


func _write_territory_id(province: Province) -> void:
	if not db.province_color_to_lookup.has(province.color):
		return
	var lookup: Color = db.province_color_to_lookup[province.color]
	var id_color: Color = province.territory.color if province.territory != null else Color.BLACK
	territory_id_image.set_pixel(roundi(lookup.r * 255), roundi(lookup.g * 255), id_color)


# Builds a distance field around the union of the selected provinces' boundaries, cropped
# to their pixel bounds, on a worker task; selection_sdf_ready fires once the texture is
# live. A newer call supersedes any build in flight, so stale results are never shown.
func update_selection_sdf(provinces: Array[Province]) -> void:
	_selection_request_id += 1
	if _selection_worker_busy:
		_selection_pending = provinces.duplicate()
		return
	_start_selection_worker(provinces, _selection_request_id)


# Everything touching game objects resolves here on the main thread; the worker only reads
# src_data and the plain dictionary built here.
func _start_selection_worker(provinces: Array[Province], request_id: int) -> void:
	_selection_worker_busy = true
	var prov_keys: Dictionary[int, bool] = {}
	var box: Rect2i = _province_box(provinces[0])
	for province in provinces:
		prov_keys[_selection_color_key(province.color)] = true
		box = box.merge(_province_box(province))
	box = box.grow(SELECTION_MARGIN).intersection(Rect2i(0, 0, width, height))
	WorkerThreadPool.add_task(_selection_worker_run.bind(prov_keys, box, request_id))


# Worker thread: membership/boundary passes and the JFA seed-buffer build. Only the GPU
# JFA itself must stay on the main thread (RenderingDevice thread restriction).
func _selection_worker_run(prov_keys: Dictionary[int, bool], box: Rect2i, request_id: int) -> void:
	var cw: int = box.size.x
	var ch: int = box.size.y

	# Pass 1: membership byte per crop pixel (1 = selected province), memoized per color.
	var membership: PackedByteArray = PackedByteArray()
	membership.resize(cw * ch)
	var memo: Dictionary[int, int] = {}
	for ly in range(ch):
		var gy: int = box.position.y + ly
		var src_row: int = gy * src_stride
		var local_row: int = ly * cw
		for lx in range(cw):
			var si: int = src_row + (box.position.x + lx) * bpp
			var key: int = (src_data[si] << 16) | (src_data[si + 1] << 8) | src_data[si + 2]
			var m: int
			if memo.has(key):
				m = memo[key]
			else:
				m = 1 if prov_keys.has(key) else 0
				memo[key] = m
			membership[local_row + lx] = m

	# Pass 2: two-sided boundary mask (0 = seed, 255 = empty). Two-sided keeps the field
	# symmetric around the true boundary, half a pixel past the seed rows (shader adds 0.5).
	var prov_mask: PackedByteArray = PackedByteArray()
	prov_mask.resize(cw * ch)
	prov_mask.fill(255)
	for ly in range(ch):
		var local_row: int = ly * cw
		for lx in range(cw):
			var idx: int = local_row + lx
			var m: int = membership[idx]
			var diff: int = 0
			if lx > 0:
				diff |= m ^ membership[idx - 1]
			if lx < cw - 1:
				diff |= m ^ membership[idx + 1]
			if ly > 0:
				diff |= m ^ membership[idx - cw]
			if ly < ch - 1:
				diff |= m ^ membership[idx + cw]
			if diff != 0:
				prov_mask[idx] = 0

	var seeds: PackedByteArray = MapTextureSDF.build_seeds_region(prov_mask, cw, ch, Rect2i(0, 0, cw, ch))
	_selection_sdf_apply.call_deferred(seeds, box, request_id)


# Main thread: GPU JFA + texture creation, published unless a newer selection superseded us.
func _selection_sdf_apply(seeds: PackedByteArray, box: Rect2i, request_id: int) -> void:
	_selection_worker_busy = false
	if request_id == _selection_request_id:
		var cw: int = box.size.x
		var ch: int = box.size.y
		var prov_bytes: PackedByteArray = MapTextureSDF.build_sdf_region_from_seeds(seeds, cw, ch)
		selection_province_sdf_texture = ImageTexture.create_from_image(
				Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, prov_bytes))
		selection_rect = box
		selection_sdf_ready.emit()
	if not _selection_pending.is_empty():
		var next: Array[Province] = _selection_pending
		_selection_pending = []
		_start_selection_worker(next, _selection_request_id)


# Measured bounds when available, the conservative center/radius square otherwise.
func _province_box(province: Province) -> Rect2i:
	if province.pixel_bounds.has_area():
		return province.pixel_bounds
	var r: int = province.bounding_radius
	return Rect2i(province.center.x - r, province.center.y - r, r * 2 + 1, r * 2 + 1)


func _selection_color_key(color: Color) -> int:
	return (int(round(color.r * 255.0)) << 16) | (int(round(color.g * 255.0)) << 8) | int(round(color.b * 255.0))


# JFA on the smallest crop containing every affected pixel (dirty_box + SDF_AFFECT_RANGE),
# padded by another SDF_AFFECT_RANGE so the JFA sees every border those pixels could reach.
func _refresh_sdf_bounded(sdf_image: Image, sdf_texture: ImageTexture, border_bytes: PackedByteArray, dirty_box: Rect2i) -> void:
	var image_bounds: Rect2i = Rect2i(0, 0, width, height)
	var affected: Rect2i = dirty_box.grow(SDF_AFFECT_RANGE).intersection(image_bounds)
	var crop: Rect2i = affected.grow(SDF_AFFECT_RANGE).intersection(image_bounds)
	var crop_data: PackedByteArray = MapTextureSDF.build_sdf_region(border_bytes, width, height, crop)
	var crop_image: Image = Image.create_from_data(crop.size.x, crop.size.y, false, Image.FORMAT_RGBA8, crop_data)
	var local_affected: Rect2i = Rect2i(affected.position - crop.position, affected.size)
	sdf_image.blit_rect(crop_image, local_affected, affected.position)
	sdf_texture.update(sdf_image)


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


# Two-sided: both sides of a territory boundary are marked, so the white ring straddles it.
# The RG offset can land on either side; the shader's across test steps past it.
func _is_territory_border_pixel(x: int, y: int, src_idx: int, r: int, g: int, b: int, _cache: Dictionary) -> bool:
	var territory: Territory = _cached_territory(r, g, b, _cache)
	for offset in NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			continue
		var ni: int = src_idx + offset.x * bpp + offset.y * src_stride
		if _cached_territory(src_data[ni], src_data[ni + 1], src_data[ni + 2], _cache) != territory:
			return true
	return false


# Memoized per packed-RGB key, avoiding a Color allocation and dict lookup per pixel.
func _cached_territory(r: int, g: int, b: int, _cache: Dictionary) -> Territory:
	var key: int = (r << 16) | (g << 8) | b
	if _cache.has(key):
		return _cache[key]
	var province: Province = db.color_to_province.get(Color(r / 255.0, g / 255.0, b / 255.0))
	var territory: Territory = province.territory if province != null else null
	_cache[key] = territory
	return territory


# One-sided: only owned pixels are marked, so the SDF's RG offset always points at a pixel
# carrying the owner's color — map2d.gdshader relies on this to bleed country color outwards.
func _is_country_border_pixel(x: int, y: int, src_idx: int, r: int, g: int, b: int, _cache: Dictionary) -> bool:
	var owner: Country = _cached_owner(r, g, b, _cache)
	if owner == null:
		return false
	for offset in NEIGHBOR_OFFSETS:
		var nx: int = x + offset.x
		var ny: int = y + offset.y
		if nx < 0 or nx >= width or ny < 0 or ny >= height:
			continue
		var ni: int = src_idx + offset.x * bpp + offset.y * src_stride
		if _cached_owner(src_data[ni], src_data[ni + 1], src_data[ni + 2], _cache) != owner:
			return true
	return false


# Memoized per packed-RGB key, avoiding a Color allocation and dict lookup per pixel.
func _cached_owner(r: int, g: int, b: int, _cache: Dictionary) -> Country:
	var key: int = (r << 16) | (g << 8) | b
	if _cache.has(key):
		return _cache[key]
	var province: Province = db.color_to_province.get(Color(r / 255.0, g / 255.0, b / 255.0))
	var owner: Country = province.province_owner if province != null else null
	_cache[key] = owner
	return owner


# Resolves a per-pixel owner-id grid (provinces sharing a country get the same id, so only
# inter-country and country/ocean borders become chains) and hands it to MapBorderTracer.
# Pure reads, safe on a WorkerThreadPool task.
func build_country_border_chains(simplify_epsilon: float = 0.0, smooth_iterations: int = 0) -> Array[PackedVector2Array]:
	var owner_ids: PackedInt32Array = PackedInt32Array()
	owner_ids.resize(width * height)
	# Packed RGB -> owner id, memoized per province color.
	var key_to_id: Dictionary[int, int] = {}
	# Country -> shared owner id (-1 = unowned).
	var owner_to_id: Dictionary[Country, int] = {}
	var next_id: int = 0
	for y in range(height):
		var srow: int = y * src_stride
		var orow: int = y * width
		for x in range(width):
			var si: int = srow + x * bpp
			var r: int = src_data[si]
			var g: int = src_data[si + 1]
			var b: int = src_data[si + 2]
			var rgb: int = (r << 16) | (g << 8) | b
			var id: int
			if key_to_id.has(rgb):
				id = key_to_id[rgb]
			else:
				var province: Province = db.color_to_province.get(Color(r / 255.0, g / 255.0, b / 255.0))
				var owner: Country = province.province_owner if province != null else null
				if owner == null:
					id = -1
				elif owner_to_id.has(owner):
					id = owner_to_id[owner]
				else:
					id = next_id
					next_id += 1
					owner_to_id[owner] = id
				key_to_id[rgb] = id
			owner_ids[orow + x] = id
	var tracer: MapBorderTracer = MapBorderTracer.new()
	var raw: Array[PackedVector2Array] = tracer.trace(owner_ids, width, height)
	if simplify_epsilon <= 0.0 and smooth_iterations <= 0:
		return raw
	var out: Array[PackedVector2Array] = []
	for chain: PackedVector2Array in raw:
		var closed: bool = chain.size() >= 2 and chain[0].is_equal_approx(chain[chain.size() - 1])
		var c: PackedVector2Array = chain
		# RDP needs a non-degenerate baseline, so only simplify open chains; loops go straight
		# to smoothing (they're small enclaves, extra points are cheap).
		if simplify_epsilon > 0.0 and not closed:
			c = MapBorderTracer.simplify(c, simplify_epsilon)
		if smooth_iterations > 0:
			c = MapBorderTracer.smooth(c, smooth_iterations, closed)
		out.append(c)
	return out


func set_map_textures(shader_material: ShaderMaterial) -> void:
	shader_material.set_shader_parameter("lookup_image", lookup_texture)
	shader_material.set_shader_parameter("province_border_image", border_texture)
	shader_material.set_shader_parameter("province_sdf_image", province_sdf_texture)
	shader_material.set_shader_parameter("territory_sdf_image", territory_sdf_texture)
	shader_material.set_shader_parameter("territory_id_image", territory_id_texture)
	shader_material.set_shader_parameter("country_sdf_image", country_sdf_texture)
