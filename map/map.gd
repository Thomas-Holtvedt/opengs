extends StaticBody3D
class_name Map

const SELECTION_PULSE_BASELINE: float = 1.0
const SELECTION_PULSE_PEAK: float = 6.0
const SELECTION_PULSE_HALF_PERIOD: float = 0.2

@onready var map_sprite: Sprite2D = $MeshInstance3D/SubViewport/Sprite2D
@onready var map_material_2d: ShaderMaterial = $MeshInstance3D/SubViewport/Sprite2D.material
@onready var map_material_3d: ShaderMaterial = $MeshInstance3D.mesh.material
@onready var map_mesh: MeshInstance3D = $MeshInstance3D

var current_map_mode: MapMode
var current_highlight: MapHighlight
var all_map_modes: Dictionary[int, MapMode]
var province_image: Image
var province_image_offset: Vector2i
var tex_gen: MapTextureGenerator
var _selection_pulse_tween: Tween = null

func deactivate_height() -> void:
	map_material_3d.set_shader_parameter("height_scale", 0.0)
	%CountryLabels3D.show()
	
func activate_height() -> void:
	map_material_3d.set_shader_parameter("height_scale", 3.0)
	%CountryLabels3D.hide()
	
func create_map_textures(db: Database) -> void:
	province_image = map_sprite.texture.get_image()
	@warning_ignore("integer_division")
	province_image_offset = Vector2i(province_image.get_width() / 2, province_image.get_height() / 2)
	tex_gen = MapTextureGenerator.new(province_image)
	tex_gen.create_map_textures(db)
	tex_gen.set_map_textures(map_material_2d)


func update_map_texture(province: Province, db: Database, refresh: bool = true) -> void:
	tex_gen.update_map_texture(db, province.center, province.bounding_box, refresh)


func refresh_territory_sdf() -> void:
	tex_gen.refresh_territory_sdf()


func update_country_borders(province: Province, db: Database, refresh: bool = true) -> void:
	tex_gen.update_country_borders(db, province.center, province.bounding_box, refresh)


func refresh_country_sdf() -> void:
	tex_gen.refresh_country_sdf()


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


func create_map_modes(db: Database) -> void:
	for map_mode in MapMode.Type:
		all_map_modes[MapMode.Type[map_mode]] = MapMode.new(db.province_color_to_lookup, db.color_to_province, MapMode.Type[map_mode])
	current_map_mode = all_map_modes[0]
	update_map()


const COUNTRY_LABEL_SCENE: PackedScene = preload("res://map/country_label.tscn")
const COUNTRY_LABEL_3D_SCENE: PackedScene = preload("res://map/country_label_3d.tscn")


func create_country_labels(db: Database) -> void:
	for country: Country in db.tag_to_country.values():
		create_country_label(country)


func create_country_label(country: Country) -> void:
	var country_label: CountryLabel = COUNTRY_LABEL_SCENE.instantiate()
	country_label.initial_data(country)
	%CountryLabels.add_child(country_label)
	country_label.update_data(country)

	var label_3d: CountryLabel3D = COUNTRY_LABEL_3D_SCENE.instantiate()
	label_3d.initial_data(country)
	%CountryLabels3D.add_child(label_3d)
	label_3d.update_data(country)


func rename_country_label(old_tag: String, new_tag: String) -> void:
	if %CountryLabels.has_node(old_tag):
		%CountryLabels.get_node(old_tag).name = new_tag
	if %CountryLabels3D.has_node(old_tag):
		%CountryLabels3D.get_node(old_tag).name = new_tag


func update_country_label(country: Country) -> void:
	if country != null:
		var label: CountryLabel = %CountryLabels.get_node(country.tag)
		label.update_data(country)
		var label_3d: CountryLabel3D = %CountryLabels3D.get_node(country.tag)
		label_3d.update_data(country)


func update_map() -> void:
	map_material_2d.set_shader_parameter("color_map_image", current_map_mode)
	var apply_fade: bool = current_map_mode.type == MapMode.Type.POLITICAL or current_map_mode.type == MapMode.Type.IDEOLOGY
	map_material_2d.set_shader_parameter("apply_country_fade", apply_fade)


func set_map_mode(map_mode: MapMode.Type) -> void:
	if current_highlight != null:
		current_map_mode = current_highlight.remove_highlights(current_map_mode)
	current_map_mode = all_map_modes[map_mode]
	if current_highlight != null:
		current_map_mode = current_highlight.apply_highlights(current_map_mode)
	update_map()


func update_map_modes(province: Province, commit: bool = true) -> void:
	for mm in all_map_modes.values():
		mm.update_province(province)
		if commit:
			mm.commit()


func commit_map_modes() -> void:
	for mm in all_map_modes.values():
		mm.commit()


func highlight_province(province: Province):
	highlight_provinces([province])


func highlight_provinces(provinces: Array[Province]):
	if current_highlight != null:
		current_map_mode = current_highlight.remove_highlights(current_map_mode)
	current_highlight = MapHighlight.new(provinces)
	current_map_mode = current_highlight.apply_highlights(current_map_mode)
	update_map()


func get_preview_images(): # debug-only: dumps preview PNGs into res:// while running through the editor
	if not OS.has_feature("editor"):
		return
	map_material_2d.get_shader_parameter("lookup_image").get_image().save_png("res://map/map_data/lut_preview.png")
	map_material_2d.get_shader_parameter("province_border_image").get_image().save_png("res://map/map_data/bt_preview.png")
	map_material_2d.get_shader_parameter("territory_border_image").get_image().save_png("res://map/map_data/tbt_preview.png")
	tex_gen.province_sdf_texture.get_image().save_png("res://map/map_data/sdf_preview.png")
	tex_gen.territory_sdf_texture.get_image().save_png("res://map/map_data/territory_sdf_preview.png")
	tex_gen.country_sdf_texture.get_image().save_png("res://map/map_data/country_sdf_preview.png")
	current_map_mode.get_image().save_png("res://map/map_data/cmap_preview.png")
