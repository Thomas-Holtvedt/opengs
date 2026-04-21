extends Node3D

var db: Database = Database.new()
var selected_province: Province

func _ready() -> void:
	DataImporter.new(db)
	$Map.create_map_textures(db)
	$Map.create_map_modes(db)
	$Map.create_country_labels(db)
	$Map.get_preview_images()


func _on_player_province_selected(mouse_pos: Vector2) -> void:
	var selected_province_color: Color = $Map.get_pixel_lookup_color(mouse_pos)
	selected_province = db.color_to_province[selected_province_color]
	$Map.highlight_province(selected_province)
	$ProvinceSelected.update_labels(selected_province)


func _on_map_modes_map_mode_selected(mode: MapMode.Type) -> void:
	$Map.set_map_mode(mode)
