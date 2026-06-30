extends Node3D

var db: Database = Database.new()
var selected_province: Province

@onready var map: Map = $Map
@onready var province_panel: ProvinceSelected = $ProvinceSelected


func _ready() -> void:
	DataImporter.new(db)
	map.initialize(db)


func _on_player_province_selected(mouse_pos: Vector2) -> void:
	var selected_province_color: Color = map.get_pixel_lookup_color(mouse_pos)
	selected_province = db.color_to_province[selected_province_color]
	map.highlight_province(selected_province)
	province_panel.show_province(selected_province)


func _on_map_modes_map_mode_selected(mode: MapMode.Type) -> void:
	map.set_map_mode(mode)
