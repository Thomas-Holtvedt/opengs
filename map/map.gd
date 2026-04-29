extends StaticBody3D

@onready var map_sprite: Sprite2D = $MeshInstance3D/SubViewport/Sprite2D
@onready var map_material_2d: ShaderMaterial = $MeshInstance3D/SubViewport/Sprite2D.material

var current_map_mode: MapMode
var current_highlight: MapHighlight
var all_map_modes: Dictionary[int, MapMode]
var province_image: Image
var province_image_offset: Vector2i
var tex_gen: MapTextureGenerator


func create_map_textures(db: Database) -> void:
	province_image = map_sprite.texture.get_image()
	@warning_ignore("integer_division")
	province_image_offset = Vector2i(province_image.get_width() / 2, province_image.get_height() / 2)
	tex_gen = MapTextureGenerator.new(province_image)
	tex_gen.create_map_textures(db)
	tex_gen.set_map_textures(map_material_2d)


func update_map_texture(province: Province, db: Database) -> void:
	tex_gen.update_map_texture(db, province.center, province.bounding_box)


func get_pixel_lookup_color(mouse_pos: Vector2) -> Color:
	return province_image.get_pixel(
		int(mouse_pos.x * 10) + province_image_offset.x,
		int(mouse_pos.y * 10) + province_image_offset.y,
	)


func create_map_modes(db: Database) -> void:
	for map_mode in MapMode.Type:
		all_map_modes[MapMode.Type[map_mode]] = MapMode.new(db.province_color_to_lookup, db.color_to_province, MapMode.Type[map_mode])
	current_map_mode = all_map_modes[0]
	update_map()


func create_country_labels(db: Database) -> void:
	var country_label_scene: PackedScene = preload("res://map/country_label.tscn")
	for country: Country in db.tag_to_country.values():
		var country_label: CountryLabel = country_label_scene.instantiate()
		country_label.initial_data(country)
		%CountryLabels.add_child(country_label)
		country_label.update_data(country)


func update_country_label(country: Country) -> void:
	if country != null:
		var label: CountryLabel = %CountryLabels.get_node(country.tag)
		label.update_data(country)


func update_map() -> void:
	map_material_2d.set_shader_parameter("color_map_image", current_map_mode)


func set_map_mode(map_mode: MapMode.Type) -> void:
	if current_highlight != null:
		current_map_mode = current_highlight.remove_highlights(current_map_mode)
	current_map_mode = all_map_modes[map_mode]
	if current_highlight != null:
		current_map_mode = current_highlight.apply_highlights(current_map_mode)
	update_map()


func update_map_modes(province: Province, country: Country, offset: int) -> void:
	for mm in all_map_modes.values():
		mm.update_color_map(province.color, country.map_color, offset)
		mm.commit()


func highlight_province(province: Province):
	highlight_provinces([province])


func highlight_provinces(provinces: Array[Province]):
	if current_highlight != null:
		current_map_mode = current_highlight.remove_highlights(current_map_mode)
	current_highlight = MapHighlight.new(provinces)
	current_map_mode = current_highlight.apply_highlights(current_map_mode)
	update_map()


func get_preview_images(): # remove in PROD, just for visuals in editor
	map_material_2d.get_shader_parameter("lookup_image").get_image().save_png("res://map/map_data/lut_preview.png") 
	map_material_2d.get_shader_parameter("province_border_image").get_image().save_png("res://map/map_data/bt_preview.png")
	map_material_2d.get_shader_parameter("territory_border_image").get_image().save_png("res://map/map_data/tbt_preview.png")
	current_map_mode.get_image().save_png("res://map/map_data/cmap_preview.png")
