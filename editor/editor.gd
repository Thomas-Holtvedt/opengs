extends Node3D

# Belongs here: _ready bootstrap (DB import, Map/UI init), signal wiring between controllers.
# Simple mutations connect straight to the mutators; only handlers that coordinate
# several controllers live here.

var db: Database = Database.new()

@onready var map: Map = $Map
@onready var selection: SelectionController = $SelectionController
@onready var province_mutator: ProvinceMutator = $ProvinceMutator
@onready var country_mutator: CountryMutator = $CountryMutator
@onready var ui_editor: UIEditor = $UIEditor
@onready var text_flag_generator: TextFlagGenerator = $FlagIconGenerator

var is_setting_province_center: bool = false

func _ready() -> void:
	DataImporter.new(db)
	await text_flag_generator.create_all_text_flags(db)
	map.initialize(db)

	selection.setup(map, db)
	province_mutator.setup(map, db, selection)
	country_mutator.setup(map, db)

	ui_editor.database = db
	ui_editor.populate_buttons()
	_connect_ui_editor_signals()


func _connect_ui_editor_signals() -> void:
	var province_ui: ProvinceEditor = ui_editor.province_editor
	province_ui.change_owner.connect(province_mutator.set_province_owner)
	province_ui.change_controller.connect(province_mutator.set_province_controller)
	province_ui.change_owner_territory.connect(province_mutator.set_province_owner_for_territory)
	province_ui.change_controller_territory.connect(province_mutator.set_province_controller_for_territory)
	province_ui.change_type.connect(province_mutator.set_type)
	province_ui.change_terrain.connect(province_mutator.set_terrain)
	province_ui.change_territory.connect(province_mutator.set_territory)
	province_ui.export_requested.connect(_on_province_editor_export_requested)
	province_ui.is_setting_center.connect(_on_province_editor_is_setting_center)

	var country_ui: CountryEditor = ui_editor.country_editor
	country_ui.change_tag.connect(_on_country_editor_change_tag)
	country_ui.change_base_name.connect(country_mutator.set_base_name)
	country_ui.change_map_color.connect(country_mutator.set_map_color)
	country_ui.change_ideology.connect(country_mutator.set_ideology)
	country_ui.export_requested.connect(_on_country_editor_export_requested)
	country_ui.create_country_requested.connect(_on_country_editor_create_country_requested)
	
	var flag_ui: FlagEditor = ui_editor.flag_editor
	flag_ui.export_requested.connect(_on_flag_editor_export_requested)


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
	selection.select_at(world_pos, additive)


func _on_selection_changed(provinces: Array[Province]) -> void:
	ui_editor.show_province(provinces[0])

func _on_flag_editor_export_requested() -> void:
	var exporter: FlagExporter = FlagExporter.new()
	exporter.write_history(db)
	
func _on_province_editor_export_requested() -> void:
	var exporter: ProvinceExporter = ProvinceExporter.new()
	exporter.write_definition(db)
	exporter.write_history(db)


func _on_map_modes_map_mode_selected(mode: MapMode.Type) -> void:
	map.set_map_mode(mode)


func _on_province_editor_is_setting_center() -> void:
	is_setting_province_center = true


func _on_country_editor_change_tag(country: Country, new_tag: String) -> void:
	if country_mutator.set_tag(country, new_tag):
		ui_editor.refresh_country_buttons()


func _on_country_editor_export_requested() -> void:
	var exporter: CountryExporter = CountryExporter.new()
	exporter.write_definition(db)
	exporter.write_history(db)
	for country: Country in db.tag_to_country.values():
		map.update_country_label(country)


func _on_country_editor_create_country_requested() -> void:
	var new_country: Country = country_mutator.create_country()
	map.create_country_label(new_country)
	ui_editor.refresh_country_buttons()
	ui_editor.show_country(new_country)
