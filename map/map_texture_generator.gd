
class_name MapTextureGenerator

# Emitted on the main thread when an async selection SDF build has finished and the
# selection_*_sdf_texture / selection_rect members are safe to bind.
signal selection_sdf_ready

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
]
# Bounded SDF refresh assumes max distance any shader cares about. Must be >= the largest
# value the consuming uniforms (country_fade_inwards/outwards/color_fade) can hit.
# Used to derive the JFA crop region from the per-batch dirty rect.
const SDF_AFFECT_RANGE: int = 128
# Padding around the selection's bounding box when building the selection SDF crop. Must
# comfortably exceed the widest ring the shader can draw (selection_thickness at its pulse
# peak + selection_fade).
const SELECTION_MARGIN: int = 24

var lookup_texture: ImageTexture
var border_texture: ImageTexture
var country_sdf_texture: ImageTexture

# Crop-sized SDFs around the current selection, rebuilt from scratch on every selection
# change (update_selection_sdf). The shader draws the green province ring and white
# territory ring purely from these — smooth at any zoom, no per-fragment border heuristics.
var selection_province_sdf_texture: ImageTexture
var selection_territory_sdf_texture: ImageTexture
var selection_rect: Rect2i

# Async selection SDF state (main-thread-only, same pattern as the country SDF worker).
# The request id makes newer selections win: a finishing worker only publishes if its id is
# still current, and _selection_pending holds the latest superseding request.
var _selection_worker_busy: bool = false
var _selection_request_id: int = 0
var _selection_pending: Array[Province] = []
# Note: there is no country_border_texture. country_border_image is kept around purely so
# we can write the L8 mask into the disk cache during cold gen, but the shader has no
# country_border_image uniform — only country_sdf_image is sampled. Re-uploading the L8
# mask on every refresh was a ~10 ms wasted GPU transfer per province change.

# CPU-side mirrors so we can mutate masks and SDF tiles without going through the GPU
# per province. The country SDF image is also kept here so partial JFA results can be
# blitted into a known-good full image before re-uploading.
var country_border_image: Image
var country_sdf_image: Image

# Raw byte mirror of the L8 country border mask, mutated only by the country SDF worker
# thread (see _country_worker_run). PackedByteArray byte writes are ~50x faster than
# Image.set_pixel in GDScript, which is what made this worth keeping.
var country_border_bytes: PackedByteArray

# Accumulated bounding box of regions whose mask has been mutated since the last refresh.
# Empty (has_area()==false) means no pending change.
var _country_dirty_box: Rect2i

# Async refresh state for the country SDF (main-thread-only).
# _country_worker_busy is true while a WorkerThreadPool task is mid-flight (from add_task
# until its deferred _country_sdf_apply has run on the main thread).
# _country_pending_box accumulates any new dirty regions that come in while the worker is
# busy; once the in-flight task finishes, the apply step kicks off a follow-up task with it.
var _country_worker_busy: bool = false
var _country_pending_box: Rect2i

# Injected once at construction. The country SDF worker reads it to re-derive border
# pixels; it only reads provinces/ownership, never mutates them.
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
	border_texture = ImageTexture.create_from_image(cache.load_border())
	country_border_image = cache.load_country_border()
	country_border_bytes = country_border_image.get_data()
	country_sdf_image = cache.load_country_sdf()
	country_sdf_texture = ImageTexture.create_from_image(country_sdf_image)
	cache.load_color_map(db)
	_apply_province_bounds(cache.load_province_bounds())


# Writes measured pixel bounds onto the Province objects. Keys are packed RGB province
# colors ((r << 16) | (g << 8) | b), matching _selection_color_key.
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
	var country_border_data: PackedByteArray = PackedByteArray()
	country_border_data.resize(border_size)

	var color_key_to_lookup: Dictionary[int, Vector2i] = {}
	var color_map_r: int = 0
	var color_map_g: int = 0
	var owner_cache: Dictionary[int, Country] = {}

	# Exact per-province pixel bounds, accumulated per lookup index (lookup.y * 256 +
	# lookup.x). Packed arrays instead of a Dictionary keep the per-pixel cost to compares.
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

			var is_country_border: bool = _is_country_border_pixel(x, y, src_idx, r, g, b, owner_cache)
			country_border_data[border_idx] = 0 if is_country_border else 255

	var lut_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_RG8, lut_data)
	lookup_texture = ImageTexture.create_from_image(lut_image)
	var border_image: Image = Image.create_from_data(width, height, false, Image.FORMAT_L8, border_data)
	border_texture = ImageTexture.create_from_image(border_image)
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

	cache.save(lut_image, border_image, country_border_image, country_sdf_image, province_bounds, db)


# Just tracks the dirty region on the main thread; the actual border-mask rewrite happens
# on a worker thread inside _country_worker_run, kicked off by refresh_country_sdf.
func update_country_borders(box: Rect2i, refresh: bool = true) -> void:
	var clamped: Rect2i = box.intersection(Rect2i(0, 0, width, height))
	if not clamped.has_area():
		return
	_country_dirty_box = clamped if not _country_dirty_box.has_area() else _country_dirty_box.merge(clamped)
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


# Worker-thread function: rewrites country_border_bytes for the dirty region (the expensive
# GDScript pixel loops), then hands the affected region back to the main thread, which runs
# the GPU JFA + blit + texture upload.
# The JFA must NOT run here: MapTextureSDF's shared local RenderingDevice is created on
# the main thread (cold gen / territory refresh) and Godot only allows a RenderingDevice
# to be used from the thread that created it.
# Notes on concurrency:
#  - country_border_bytes: written only by this worker after init; the main thread reads it
#    only in _country_sdf_apply, which runs after this task has finished (call_deferred),
#    so there is no concurrent access.
#  - src_data, width/height/bpp/src_stride: written once at init, then read-only.
#  - db.color_to_province: built during DataImporter and never mutated afterwards.
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
			var is_country_border: bool = _is_country_border_pixel(x, y, src_idx, r, g, b, owner_cache)
			country_border_bytes[row + x] = 0 if is_country_border else 255

	_country_sdf_apply.call_deferred(dirty_box)


# Runs on the main thread (via call_deferred from the worker): GPU JFA on the dirty crop,
# then blit + texture upload. All of this must stay on the main thread — the JFA because
# of the RenderingDevice thread restriction, the blit/update because they touch rendering
# resources.
func _country_sdf_apply(dirty_box: Rect2i) -> void:
	_refresh_sdf_bounded(country_sdf_image, country_sdf_texture, country_border_bytes, dirty_box)

	_country_worker_busy = false
	if _country_pending_box.has_area():
		var next_box: Rect2i = _country_pending_box
		_country_pending_box = Rect2i()
		_start_country_worker(next_box)


# Rebuilds the selection SDFs for the given provinces: one distance field around the union
# of the selected provinces' boundaries, one around their territories' outer boundary. The
# expensive pixel passes run on a WorkerThreadPool task; selection_sdf_ready is emitted once
# the textures are live (typically the next frame, since the crop uses exact pixel bounds).
# A newer call while a build is in flight supersedes it — stale results are never shown.
func update_selection_sdf(provinces: Array[Province]) -> void:
	_selection_request_id += 1
	if _selection_worker_busy:
		_selection_pending = provinces.duplicate()
		return
	_start_selection_worker(provinces, _selection_request_id)


# Resolves everything that touches game objects (provinces, territories) here on the main
# thread; the worker only reads src_data (immutable after init) and the plain dictionaries
# built here.
func _start_selection_worker(provinces: Array[Province], request_id: int) -> void:
	_selection_worker_busy = true
	var prov_keys: Dictionary[int, bool] = {}
	var terr_keys: Dictionary[int, bool] = {}
	var box: Rect2i = _province_box(provinces[0])
	for province in provinces:
		prov_keys[_selection_color_key(province.color)] = true
		box = box.merge(_province_box(province))
		if province.territory == null:
			continue
		for t_province in province.territory.provinces:
			terr_keys[_selection_color_key(t_province.color)] = true
			box = box.merge(_province_box(t_province))
	box = box.grow(SELECTION_MARGIN).intersection(Rect2i(0, 0, width, height))
	WorkerThreadPool.add_task(_selection_worker_run.bind(prov_keys, terr_keys, box, request_id))


# Worker-thread function: the per-pixel membership and boundary-mask passes. The GPU JFA
# must NOT run here (RenderingDevice thread restriction) — the masks are handed back to the
# main thread via call_deferred.
func _selection_worker_run(prov_keys: Dictionary[int, bool], terr_keys: Dictionary[int, bool], box: Rect2i, request_id: int) -> void:
	var cw: int = box.size.x
	var ch: int = box.size.y

	# Pass 1: membership byte per crop pixel (bit 1 = selected province, bit 2 = territory),
	# memoized per province color so the src_data key extraction runs once per pixel.
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
				m = (1 if prov_keys.has(key) else 0) | (2 if terr_keys.has(key) else 0)
				memo[key] = m
			membership[local_row + lx] = m

	# Pass 2: two-sided boundary masks (0 = boundary seed, 255 = empty) from membership
	# transitions. Two-sided keeps the distance field symmetric around the true boundary,
	# which sits half a pixel past the seed row on each side (the shader adds the 0.5).
	var prov_mask: PackedByteArray = PackedByteArray()
	prov_mask.resize(cw * ch)
	prov_mask.fill(255)
	var terr_mask: PackedByteArray = PackedByteArray()
	terr_mask.resize(cw * ch)
	terr_mask.fill(255)
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
			if diff & 1:
				prov_mask[idx] = 0
			if diff & 2:
				terr_mask[idx] = 0

	_selection_sdf_apply.call_deferred(prov_mask, terr_mask, box, terr_keys.is_empty(), request_id)


# Main thread (via call_deferred from the worker): GPU JFA + texture creation, then publish
# through selection_sdf_ready — unless a newer selection arrived while the worker ran, in
# which case this result is dropped and the pending request starts immediately.
func _selection_sdf_apply(prov_mask: PackedByteArray, terr_mask: PackedByteArray, box: Rect2i, no_territory: bool, request_id: int) -> void:
	_selection_worker_busy = false
	if request_id == _selection_request_id:
		var cw: int = box.size.x
		var ch: int = box.size.y
		var crop: Rect2i = Rect2i(0, 0, cw, ch)
		var prov_bytes: PackedByteArray = MapTextureSDF.build_sdf_region(prov_mask, cw, ch, crop)
		selection_province_sdf_texture = ImageTexture.create_from_image(
				Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, prov_bytes))
		if no_territory:
			selection_territory_sdf_texture = _far_sdf_texture()
		else:
			var terr_bytes: PackedByteArray = MapTextureSDF.build_sdf_region(terr_mask, cw, ch, crop)
			selection_territory_sdf_texture = ImageTexture.create_from_image(
					Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, terr_bytes))
		selection_rect = box
		selection_sdf_ready.emit()
	if not _selection_pending.is_empty():
		var next: Array[Province] = _selection_pending
		_selection_pending = []
		_start_selection_worker(next, _selection_request_id)


# Exact measured bounds when the map generator has produced them; the conservative
# center/bounding_radius square otherwise.
func _province_box(province: Province) -> Rect2i:
	if province.pixel_bounds.has_area():
		return province.pixel_bounds
	var r: int = province.bounding_radius
	return Rect2i(province.center.x - r, province.center.y - r, r * 2 + 1, r * 2 + 1)


func _selection_color_key(color: Color) -> int:
	return (int(round(color.r * 255.0)) << 16) | (int(round(color.g * 255.0)) << 8) | int(round(color.b * 255.0))


# 1x1 "everything is far away" SDF stand-in, used when the selection has no territory so
# the white ring stays hidden. Matches the jfa_encode sentinel encoding (B = max distance).
func _far_sdf_texture() -> ImageTexture:
	var data: PackedByteArray = PackedByteArray([128, 128, 255, 255])
	return ImageTexture.create_from_image(Image.create_from_data(1, 1, false, Image.FORMAT_RGBA8, data))


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


# One-sided: only owned pixels are marked, so unowned pixels adjacent to a country are NOT
# border. This way the SDF's RG offset always points at a pixel carrying the owner's color,
# which map2d.gdshader relies on to bleed the country color outwards across the border.
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


# Memoizes the per-color owner lookup so callers can avoid a Color allocation and a
# Color-keyed dict lookup on every pixel. Each dirty region typically contains only a
# handful of distinct province colors, so after the first miss the cache is mostly hits.
func _cached_owner(r: int, g: int, b: int, _cache: Dictionary) -> Country:
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
	shader_material.set_shader_parameter("country_sdf_image", country_sdf_texture)
