extends Node3D

# Belongs here: _ready bootstrap (DB import, Map/UI init), signal wiring between controllers.

var db: Database = Database.new()

@onready var map: Map = $Map
@onready var camera: CameraController = $CameraControllerEditor
@onready var selection: SelectionController = $SelectionController
@onready var mutator: ProvinceMutator = $ProvinceMutator
@onready var country_mutator: CountryMutator = $CountryMutator
@onready var ui_editor: UIEditor = $UIEditor

var is_setting_province_center: bool = false


func _ready() -> void:
	DataImporter.new(db)
	map.create_map_textures(db)
	map.create_map_modes(db)
	map.create_country_labels(db)
	map.get_preview_images()

	ui_editor.database = db
	ui_editor.populate_buttons()
	_connect_ui_editor_signals()


func _connect_ui_editor_signals() -> void:
	var pe = ui_editor.province_editor
	pe.change_owner.connect(_on_province_editor_change_owner)
	pe.change_controller.connect(_on_province_editor_change_controller)
	pe.change_owner_territory.connect(_on_province_editor_change_owner_territory)
	pe.change_controller_territory.connect(_on_province_editor_change_controller_territory)
	pe.change_type.connect(_on_province_editor_change_type)
	pe.change_terrain.connect(_on_province_editor_change_terrain)
	pe.change_territory.connect(_on_province_editor_change_territory)
	pe.export_requested.connect(_on_province_editor_export_requested)
	pe.is_setting_center.connect(_on_province_editor_is_setting_center)

	var ce = ui_editor.country_editor
	ce.change_tag.connect(_on_country_editor_change_tag)
	ce.change_base_name.connect(_on_country_editor_change_base_name)
	ce.change_map_color.connect(_on_country_editor_change_map_color)
	ce.change_ideology.connect(_on_country_editor_change_ideology)
	ce.export_requested.connect(_on_country_editor_export_requested)
	ce.create_country_requested.connect(_on_country_editor_create_country_requested)


func _on_camera_controller_province_selected(world_pos: Vector2, additive: bool) -> void:
	if is_setting_province_center:
		is_setting_province_center = false
		var color: Color = map.get_pixel_lookup_color(world_pos)
		var clicked: Province = db.color_to_province[color]
		if not selection.selected_provinces.is_empty() and clicked == selection.selected_provinces[0]:
			clicked.center = Vector2i(
				int(world_pos.x * 10) + map.province_image_offset.x,
				int(world_pos.y * 10) + map.province_image_offset.y,
			)
			ui_editor.show_province(clicked)
			return
	selection.select_at(world_pos, additive, self.map, self.db)


func _on_selection_changed(provinces: Array[Province]) -> void:
	ui_editor.show_province(provinces[0])


func _on_province_editor_change_owner(new_owner: Country) -> void:
	mutator.set_province_owner(selection.selected_provinces, new_owner, self.map, self.db)


func _on_province_editor_change_controller(new_controller: Country) -> void:
	mutator.set_province_controller(selection.selected_provinces, new_controller, self.map)


func _on_province_editor_change_owner_territory(new_owner: Country) -> void:
	mutator.set_province_owner_for_territory(selection.selected_provinces, new_owner, self.map, self.db)


func _on_province_editor_change_controller_territory(new_controller: Country) -> void:
	mutator.set_province_controller_for_territory(selection.selected_provinces, new_controller, self.map)


func _on_province_editor_change_type(index: int) -> void:
	mutator.set_type(selection.selected_provinces, index)


func _on_province_editor_change_terrain(index: int) -> void:
	mutator.set_terrain(selection.selected_provinces, index, self.map)


func _on_province_editor_change_territory(new_territory: Territory) -> void:
	mutator.set_territory(selection.selected_provinces, new_territory, self.map, self.db)


func _on_province_editor_export_requested() -> void:
	var exporter = ProvinceExporter.new()
	exporter.write_definition(db)
	exporter.write_history(db)


func _on_map_modes_map_mode_selected(mode: MapMode.Type) -> void:
	map.set_map_mode(mode)


func _on_camera_controller_far_map(is_far: bool) -> void:
	if is_far:
		$Map.deactivate_height()
	else:
		$Map.activate_height()


func _on_province_editor_is_setting_center() -> void:
	is_setting_province_center = true


func _on_country_editor_change_tag(country: Country, new_tag: String) -> void:
	var old_tag: String = country.tag
	if country_mutator.set_tag(country, new_tag, db):
		map.rename_country_label(old_tag, new_tag)
		ui_editor.refresh_country_buttons()


func _on_country_editor_change_base_name(country: Country, new_name: String) -> void:
	country_mutator.set_base_name(country, new_name, self.map)


func _on_country_editor_change_map_color(country: Country, new_color: Color) -> void:
	country_mutator.set_map_color(country, new_color, self.map)


func _on_country_editor_change_ideology(country: Country, index: int) -> void:
	country_mutator.set_ideology(country, index, self.map)


func _on_country_editor_export_requested() -> void:
	var exporter = CountryExporter.new()
	exporter.write_definition(db)
	exporter.write_history(db)
	for country in db.tag_to_country.values():
		map.update_country_label(country)


func _on_country_editor_create_country_requested() -> void:
	var new_country: Country = country_mutator.create_country(db)
	map.create_country_label(new_country)
	ui_editor.refresh_country_buttons()
	ui_editor.country_editor.show_country(new_country)
