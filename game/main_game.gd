extends Node3D

var db: Database = Database.new()

@onready var map: Map = $Map
@onready var selection: SelectionController = $SelectionController
@onready var province_panel: ProvinceSelected = $ProvinceSelected
@onready var text_flag_generator: TextFlagGenerator = $FlagIconGenerator


func _ready() -> void:
	DataImporter.new(db)
	await text_flag_generator.create_all_text_flags(db)
	map.initialize(db)
	selection.setup(map, db)


func _on_player_province_selected(mouse_pos: Vector2) -> void:
	selection.select_at(mouse_pos, false)


func _on_selection_changed(provinces: Array[Province]) -> void:
	province_panel.show_province(provinces.back())


func _on_map_modes_map_mode_selected(mode: MapMode.Type) -> void:
	map.set_map_mode(mode)
