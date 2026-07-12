extends StaticBody3D
class_name Map

# Must match the material's resting selection_thickness (map2D.tres).
const SELECTION_PULSE_BASELINE: float = 0.0
const SELECTION_PULSE_PEAK: float = 6.0
const SELECTION_PULSE_HALF_PERIOD: float = 0.2
# Must match the selected_territory_ids array size in map2d.gdshader.
const MAX_SELECTED_TERRITORIES: int = 8

@onready var map_sprite: Sprite2D = $MeshInstance3D/SubViewport/Sprite2D
@onready var map_material_2d: ShaderMaterial = $MeshInstance3D/SubViewport/Sprite2D.material
@onready var map_material_3d: ShaderMaterial = $MeshInstance3D.mesh.material
@onready var map_mesh: MeshInstance3D = $MeshInstance3D

# Country-border ribbons: traced chains extruded into real 3D geometry (not the fixed-res
# SubViewport), so they stay crisp at any zoom. Rebuilt when country ownership changes.
@export var show_border_ribbons: bool = true
# Ribbon width in world units (map plane is 500 wide over 5000 px, so 1.0 ≈ 10 px).
@export var border_ribbon_width: float = 0.5
# RDP deviation threshold in source pixels; 0 disables simplification.
@export var border_simplify_epsilon: float = 1.5
# Chaikin smoothing passes; 0 shows the raw staircase (for comparison).
@export var border_smooth_iterations: int = 2
# Brush painted along each ribbon (U across width, V along length). Leave null to use a
# generated soft-edged stroke; assign a PNG to use real art.
@export var border_brush: Texture2D = null
# World-space length of one brush tile along the ribbon (drives V tiling).
@export var border_brush_length: float = 3.0
# When true, hue-cycle chains for debugging; when false, paint every ribbon border_color.
@export var border_debug_hue: bool = false
@export var border_color: Color = Color(0.12, 0.09, 0.07, 1.0)
# Plane spans 500x250 world units over the 5000x2500 lookup image (1 px = 0.1 units), centred
# on origin; lifted just above the plane to avoid z-fighting. Mirrors CountryLabel3D.
const BORDER_PIXEL_TO_WORLD: float = 0.1
const BORDER_IMAGE_HALF: Vector2 = Vector2(2500.0, 1250.0)
const BORDER_HEIGHT: float = 0.06
var _border_ribbons_3d: Node3D = null
var _border_ribbon_mesh: MeshInstance3D = null
# Coalesce rebuilds: if ownership changes again while the worker runs, rebuild once more after.
var _border_worker_busy: bool = false
var _border_rebuild_pending: bool = false

var db: Database
var current_map_mode: MapMode
var current_selection: Array[Province] = []
var all_map_modes: Dictionary[int, MapMode]
var province_image: Image
var province_image_offset: Vector2i
var texture_generator: MapTextureGenerator
var _selection_pulse_tween: Tween = null


# Single entry point for scene roots; builds every map resource that depends on the database.
func initialize(database: Database) -> void:
	db = database
	create_map_textures()
	create_map_modes()
	create_country_labels()
	save_debug_previews()
	refresh_border_ribbons()


func deactivate_height() -> void:
	map_material_3d.set_shader_parameter("height_scale", 0.0)
	%CountryLabels3D.show()
	if _border_ribbons_3d != null:
		_border_ribbons_3d.show()

func activate_height() -> void:
	map_material_3d.set_shader_parameter("height_scale", 3.0)
	%CountryLabels3D.hide()
	if _border_ribbons_3d != null:
		_border_ribbons_3d.hide()
	
func create_map_textures() -> void:
	province_image = map_sprite.texture.get_image()
	@warning_ignore("integer_division")
	province_image_offset = Vector2i(province_image.get_width() / 2, province_image.get_height() / 2)
	texture_generator = MapTextureGenerator.new(province_image, db)
	texture_generator.selection_sdf_ready.connect(_apply_selection_sdf)
	texture_generator.create_map_textures()
	texture_generator.set_map_textures(map_material_2d)


func update_country_borders(province: Province, refresh: bool = true) -> void:
	texture_generator.update_country_borders(_province_dirty_box(province), refresh)


# Rebuilds the ribbons from current ownership. The heavy full-map pass runs on a worker
# thread; overlapping requests coalesce so rapid edits don't pile up.
func refresh_border_ribbons() -> void:
	if not show_border_ribbons or texture_generator == null:
		return
	if _border_worker_busy:
		_border_rebuild_pending = true
		return
	_border_worker_busy = true
	WorkerThreadPool.add_task(_border_ribbon_worker)


func _border_ribbon_worker() -> void:
	var chains: Array[PackedVector2Array] = texture_generator.build_country_border_chains(
			border_simplify_epsilon, border_smooth_iterations)
	_apply_border_ribbons.call_deferred(chains)


# Main thread: fold every chain into one ArrayMesh — a single draw and a cheap swap on rebuild.
func _apply_border_ribbons(chains: Array[PackedVector2Array]) -> void:
	_border_worker_busy = false
	_ensure_border_ribbon_nodes()
	_border_ribbon_mesh.mesh = _build_ribbons_mesh(chains, border_ribbon_width)
	if _border_rebuild_pending:
		_border_rebuild_pending = false
		refresh_border_ribbons()


func _ensure_border_ribbon_nodes() -> void:
	if _border_ribbons_3d != null:
		return
	_border_ribbons_3d = Node3D.new()
	_border_ribbons_3d.name = "BorderRibbons3D"
	add_child(_border_ribbons_3d)
	_border_ribbon_mesh = MeshInstance3D.new()
	_border_ribbon_mesh.name = "RibbonMesh"
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Brush RGB is white so vertex colour tints it; alpha carries the stroke shape. V tiles
	# every border_brush_length world units, U keeps its 0..1 width profile.
	mat.albedo_texture = border_brush if border_brush != null else _make_default_brush()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.uv1_scale = Vector3(1.0, 1.0 / maxf(border_brush_length, 0.001), 1.0)
	_border_ribbon_mesh.material_override = mat
	_border_ribbons_3d.add_child(_border_ribbon_mesh)


# Fallback brush: soft-edged white stroke with a seamless along-length ripple.
func _make_default_brush() -> ImageTexture:
	var w: int = 32
	var h: int = 64
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var v: float = float(y) / float(h)
		var length_var: float = 0.85 + 0.15 * sin(v * TAU)  # period = height -> tiles seamlessly
		for x in range(w):
			var u: float = (float(x) + 0.5) / float(w)
			var edge_dist: float = absf(u - 0.5) * 2.0  # 0 at centre, 1 at either edge
			var core: float = 1.0 - smoothstep(0.55, 1.0, edge_dist)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(core * length_var, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _pixel_to_ribbon_xz(p: Vector2) -> Vector2:
	return (p - BORDER_IMAGE_HALF) * BORDER_PIXEL_TO_WORLD


# Extrudes each smoothed chain into a flat ribbon (constant world width) in the XZ plane, all
# merged into one ArrayMesh. Chains are hue-cycled so segments split at junctions read distinct.
func _build_ribbons_mesh(chains: Array[PackedVector2Array], width: float) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var half: float = width * 0.5
	var chain_index: int = 0
	for chain: PackedVector2Array in chains:
		var n: int = chain.size()
		if n < 2:
			chain_index += 1
			continue
		var xz: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in chain:
			xz.append(_pixel_to_ribbon_xz(p))
		var color: Color = Color.from_hsv(fmod(float(chain_index) * 0.13, 1.0), 0.85, 1.0) if border_debug_hue else border_color
		var base: int = verts.size()
		var run_len: float = 0.0
		for i in range(n):
			var nrm: Vector2
			if i == 0:
				nrm = _edge_normal(xz[0], xz[1])
			elif i == n - 1:
				nrm = _edge_normal(xz[n - 2], xz[n - 1])
			else:
				# Miter = averaged adjacent edge normals (no 1/cos correction; borders are thin
				# so the slight width dip at sharp corners is invisible).
				nrm = _edge_normal(xz[i - 1], xz[i]) + _edge_normal(xz[i], xz[i + 1])
				if nrm.length() < 0.0001:
					nrm = _edge_normal(xz[i], xz[i + 1])
				nrm = nrm.normalized()
			if i > 0:
				run_len += xz[i].distance_to(xz[i - 1])
			var left: Vector2 = xz[i] + nrm * half
			var right: Vector2 = xz[i] - nrm * half
			verts.append(Vector3(left.x, BORDER_HEIGHT, left.y))
			verts.append(Vector3(right.x, BORDER_HEIGHT, right.y))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			uvs.append(Vector2(0.0, run_len))
			uvs.append(Vector2(1.0, run_len))
			colors.append(color)
			colors.append(color)
		for i in range(n - 1):
			var v: int = base + i * 2
			indices.append(v)
			indices.append(v + 1)
			indices.append(v + 2)
			indices.append(v + 1)
			indices.append(v + 3)
			indices.append(v + 2)
		chain_index += 1
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Unit normal (in XZ) of the segment a->b, pointing to its left.
func _edge_normal(a: Vector2, b: Vector2) -> Vector2:
	var dir: Vector2 = (b - a).normalized()
	return Vector2(-dir.y, dir.x)


# Measured bounds grown by 1 so border flips on neighbouring provinces' pixels are captured;
# falls back to the conservative center/radius square before the map generator has run.
func _province_dirty_box(province: Province) -> Rect2i:
	if province.pixel_bounds.has_area():
		return province.pixel_bounds.grow(1)
	var r: int = province.bounding_radius
	return Rect2i(province.center.x - r, province.center.y - r, r * 2 + 1, r * 2 + 1)


func refresh_country_sdf() -> void:
	texture_generator.refresh_country_sdf()
	# Every owner-change path funnels through here, so this one hook keeps the ribbons fresh.
	refresh_border_ribbons()


# Editor path: a province changed territory — patch its identity map entry and the
# territory border mask around it. Callers batch with refresh=false + refresh_territory_sdf.
func update_territory(province: Province, refresh: bool = true) -> void:
	texture_generator.update_territory_id(province)
	texture_generator.update_territory_borders(_province_dirty_box(province), refresh)


func refresh_territory_sdf() -> void:
	texture_generator.refresh_territory_sdf()


func get_pixel_lookup_color(mouse_pos: Vector2) -> Color:
	return province_image.get_pixel(
		int(mouse_pos.x * 10) + province_image_offset.x,
		int(mouse_pos.y * 10) + province_image_offset.y,
	)


func pulse_selection(pulse_count: int = 3) -> void:
	if _selection_pulse_tween != null and _selection_pulse_tween.is_running():
		_selection_pulse_tween.kill()
	var set_thickness: Callable = func(v: float) -> void:
		map_material_2d.set_shader_parameter("selection_thickness", v)
	_selection_pulse_tween = create_tween()
	_selection_pulse_tween.set_loops(pulse_count)
	_selection_pulse_tween.tween_method(set_thickness, SELECTION_PULSE_BASELINE, SELECTION_PULSE_PEAK, SELECTION_PULSE_HALF_PERIOD)
	_selection_pulse_tween.tween_method(set_thickness, SELECTION_PULSE_PEAK, SELECTION_PULSE_BASELINE, SELECTION_PULSE_HALF_PERIOD)


func create_map_modes() -> void:
	for map_mode: String in MapMode.Type:
		all_map_modes[MapMode.Type[map_mode]] = MapMode.new(db.province_color_to_lookup, db.color_to_province, MapMode.Type[map_mode])
	current_map_mode = all_map_modes[0]
	update_map()


const COUNTRY_LABEL_3D_SCENE: PackedScene = preload("res://map/country_label_3d.tscn")


func create_country_labels() -> void:
	for country: Country in db.tag_to_country.values():
		create_country_label(country)


func create_country_label(country: Country) -> void:
	var label_3d: CountryLabel3D = COUNTRY_LABEL_3D_SCENE.instantiate()
	label_3d.setup(country)
	%CountryLabels3D.add_child(label_3d)
	label_3d.refresh(country)


func rename_country_label(old_tag: String, new_tag: String) -> void:
	if %CountryLabels3D.has_node(old_tag):
		%CountryLabels3D.get_node(old_tag).name = new_tag


func update_country_label(country: Country) -> void:
	if country != null:
		var label_3d: CountryLabel3D = %CountryLabels3D.get_node(country.tag)
		label_3d.refresh(country)


func update_map() -> void:
	map_material_2d.set_shader_parameter("color_map_image", current_map_mode)
	var apply_fade: bool = current_map_mode.type == MapMode.Type.POLITICAL or current_map_mode.type == MapMode.Type.IDEOLOGY
	map_material_2d.set_shader_parameter("apply_country_fade", apply_fade)


func set_map_mode(map_mode: MapMode.Type) -> void:
	current_map_mode = all_map_modes[map_mode]
	update_map()


func update_map_modes(province: Province, commit: bool = true) -> void:
	for map_mode: MapMode in all_map_modes.values():
		map_mode.update_province(province)
		if commit:
			map_mode.commit()


func commit_map_modes() -> void:
	for map_mode: MapMode in all_map_modes.values():
		map_mode.commit()


func highlight_province(province: Province) -> void:
	highlight_provinces([province])


func highlight_provinces(provinces: Array[Province]) -> void:
	current_selection = provinces.duplicate()
	# The white ring updates this frame (precomputed territory SDF); the green ring follows
	# once the async province crop SDF lands.
	_apply_selected_territories(provinces)
	texture_generator.update_selection_sdf(provinces)


# Rebuilds the selection SDF and territory uniforms for the current selection, e.g. after
# its provinces' territory membership changed underneath it.
func refresh_selection() -> void:
	if not current_selection.is_empty():
		_apply_selected_territories(current_selection)
		texture_generator.update_selection_sdf(current_selection)


func _apply_selected_territories(provinces: Array[Province]) -> void:
	var ids: PackedVector3Array = PackedVector3Array()
	var seen: Dictionary[Territory, bool] = {}
	for province: Province in provinces:
		var territory: Territory = province.territory
		if territory == null or seen.has(territory):
			continue
		seen[territory] = true
		ids.append(Vector3(territory.color.r, territory.color.g, territory.color.b))
		if ids.size() == MAX_SELECTED_TERRITORIES:
			break
	map_material_2d.set_shader_parameter("selected_territory_count", ids.size())
	ids.resize(MAX_SELECTED_TERRITORIES)
	map_material_2d.set_shader_parameter("selected_territory_ids", ids)


# Runs when the async selection SDF build finishes, typically the frame after the click.
# Until then the previous selection's ring stays visible, so there is never a blank gap.
func _apply_selection_sdf() -> void:
	map_material_2d.set_shader_parameter("selection_province_sdf", texture_generator.selection_province_sdf_texture)
	var rect: Rect2i = texture_generator.selection_rect
	map_material_2d.set_shader_parameter("selection_sdf_rect", Vector4(
			rect.position.x, rect.position.y, rect.size.x, rect.size.y))


func clear_selection() -> void:
	current_selection = []
	map_material_2d.set_shader_parameter("selection_sdf_rect", Vector4())
	map_material_2d.set_shader_parameter("selected_territory_count", 0)


# Debug-only: dumps preview PNGs into res:// while running through the editor.
func save_debug_previews() -> void:
	if not OS.has_feature("editor"):
		return
	map_material_2d.get_shader_parameter("lookup_image").get_image().save_png("res://map/map_data/lut_preview.png")
	map_material_2d.get_shader_parameter("province_border_image").get_image().save_png("res://map/map_data/bt_preview.png")
	texture_generator.country_sdf_texture.get_image().save_png("res://map/map_data/country_sdf_preview.png")
	current_map_mode.get_image().save_png("res://map/map_data/cmap_preview.png")
