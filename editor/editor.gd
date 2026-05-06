extends Node3D

var db: Database = Database.new()
var selected_provinces: Array[Province] = []

func _ready() -> void:
	DataImporter.new(db)
	$Map.create_map_textures(db)
	$Map.create_map_modes(db)
	$Map.create_country_labels(db)
	$Map.get_preview_images()

	$ProvinceEditor.database = db
	$ProvinceEditor.populate_buttons()

func _on_controller_province_selected(mouse_pos: Vector2, additive: bool) -> void:
	var selected_province_color: Color = $Map.get_pixel_lookup_color(mouse_pos)
	var clicked: Province = db.color_to_province[selected_province_color]

	if additive:
		if clicked in selected_provinces:
			if selected_provinces.size() > 1:
				selected_provinces.erase(clicked)
		else:
			selected_provinces.append(clicked)
	else:
		selected_provinces = [clicked]

	$Map.highlight_provinces(selected_provinces)
	$ProvinceEditor.update_labels(selected_provinces[0])


func _on_province_editor_change_owner(province_owner: Country) -> void:
	var old_owner_list: Array[Country]
	for province: Province in selected_provinces:
		if province.province_owner not in old_owner_list:
			old_owner_list.append(province.province_owner)
		province.province_owner = province_owner
		$Map.update_map_modes(province, province_owner, MapMode.PRIMARY_OFFSET)
	$Map.update_map()
	$Map.update_country_label(province_owner)
	for old_owner: Country in old_owner_list:
		$Map.update_country_label(old_owner)


func _on_province_editor_change_controller(controller: Country) -> void:
	for province: Province in selected_provinces:
		province.province_controller = controller
		$Map.update_map_modes(province, controller, $Map.current_map_mode.secondary_offset)
	$Map.update_map()


func _on_province_editor_change_owner_territory(province_owner: Country) -> void:
	var old_owner_list: Array[Country]
	var visited: Dictionary = {}
	for selected: Province in selected_provinces:
		if selected.territory == null:
			continue
		for province: Province in selected.territory.provinces:
			if province in visited:
				continue
			visited[province] = true
			if province.province_owner not in old_owner_list:
				old_owner_list.append(province.province_owner)
			province.province_owner = province_owner
			$Map.update_map_modes(province, province_owner, MapMode.PRIMARY_OFFSET)
	$Map.update_map()
	$Map.update_country_label(province_owner)
	for old_owner: Country in old_owner_list:
		$Map.update_country_label(old_owner)


func _on_province_editor_change_type(index: int) -> void:
	for province: Province in selected_provinces:
		province.type = Province.Type.values()[index]

func _on_province_editor_change_terrain(index: int) -> void:
	for province: Province in selected_provinces:
		province.terrain = Province.Terrain.values()[index]
		$Map.update_terrain_map_mode(province)
	$Map.update_map()

func _on_province_editor_change_controller_territory(controller: Country) -> void:
	var visited: Dictionary = {}
	for selected: Province in selected_provinces:
		if selected.territory == null:
			continue
		for province: Province in selected.territory.provinces:
			if province in visited:
				continue
			visited[province] = true
			province.province_controller = controller
			$Map.update_map_modes(province, controller, $Map.current_map_mode.secondary_offset)
	$Map.update_map()


func _on_province_editor_export_requested() -> void:
	var exporter = ProvinceExporter.new()
	exporter.write_definition(db)
	exporter.write_history(db)


func _on_province_editor_change_territory(new_territory: Territory) -> void:
	for province: Province in selected_provinces:
		province.set_territory(new_territory)
		$Map.update_map_texture(province, db)


func _on_map_modes_map_mode_selected(mode: MapMode.Type) -> void:
	$Map.set_map_mode(mode)
