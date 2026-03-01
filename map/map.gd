extends StaticBody3D

@onready var province_image: Image = $MeshInstance3D/SubViewport/Sprite2D.texture.get_image()
@onready var map_material_2d: ShaderMaterial = $MeshInstance3D/SubViewport/Sprite2D.material

var country_label_scene: PackedScene = preload("res://map/country_label.tscn")


var tex_gen: MapTextureGenerator
var mm_political: MapMode
var mm_ideology: MapMode
var mm_province: MapMode
var mm_territory: MapMode
var current_map_mode: MapMode
var current_highlight: MapHighlight

var all_map_modes: Array[MapMode]


func _ready() -> void:
	create_map_textures()


func get_pixel_color(mouse_pos: Vector2) -> Color:
	var offset_x  = int(province_image.get_width()/2.0)
	var offset_y  = int(province_image.get_height()/2.0)
	return province_image.get_pixel(int(mouse_pos.x * 10) + offset_x, int(mouse_pos.y * 10) + offset_y)

func create_map_textures() -> void:
	tex_gen = MapTextureGenerator.new(province_image)
	map_material_2d.set_shader_parameter("lookup_image", tex_gen.lookup_texture)
	map_material_2d.set_shader_parameter("province_border_image", tex_gen.border_texture)
	tex_gen.lookup_texture.get_image().save_png("res://map/map_data/lut_preview.png") # remove in PROD, just for visuals in editor
	tex_gen.border_texture.get_image().save_png("res://map/map_data/bt_preview.png") # remove in PROD, just for visuals in editor

func create_map_modes(db: Database) -> void:
	mm_political = MapMode.new(tex_gen.province_color_to_lookup, db.color_to_province, MapMode.Type.POLITICAL)
	mm_ideology = MapMode.new(tex_gen.province_color_to_lookup, db.color_to_province, MapMode.Type.IDEOLOGY)
	mm_province = MapMode.new(tex_gen.province_color_to_lookup, db.color_to_province, MapMode.Type.PROVINCE)
	mm_territory = MapMode.new(tex_gen.province_color_to_lookup, db.color_to_province, MapMode.Type.TERRITORY)
	all_map_modes = [mm_political, mm_ideology, mm_province, mm_territory]
	set_map_mode(MapMode.Type.POLITICAL)
	mm_political.get_image().save_png("res://map/map_data/cmap_preview.png")
	
func create_country_labels(db: Database) -> void:
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
	match map_mode:
		MapMode.Type.POLITICAL:
			current_map_mode = mm_political
		MapMode.Type.IDEOLOGY:
			current_map_mode = mm_ideology
		MapMode.Type.PROVINCE:
			current_map_mode = mm_province
		MapMode.Type.TERRITORY:
			current_map_mode = mm_territory
	if current_highlight != null:
		current_map_mode = current_highlight.apply_highlights(current_map_mode)
	update_map()
	
func update_map_modes(province: Province, country: Country, offset: int) -> void:
	for mm in all_map_modes:
		mm.update_color_map(province.color, country.map_color, offset)



func highlight_province(province: Province):
	if current_highlight != null:
		current_map_mode = current_highlight.remove_highlights(current_map_mode)
	current_highlight = MapHighlight.new(province)
	current_map_mode = current_highlight.apply_highlights(current_map_mode)
	update_map()
	
