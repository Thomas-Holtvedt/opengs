extends Node3D

var db: Database = Database.new()
var selected_province: Province

func _ready() -> void:
	DataImporter.new(db)

	# Store compact lookup color table (switch keys and values)
	db.lookup_to_color_province = {}
	for k in $Map.tex_gen.province_color_to_lookup.keys():
		var v = $Map.tex_gen.province_color_to_lookup[k]
		db.lookup_to_color_province[v] = k
	
	$Map.create_map_modes(db)
	$Map.create_country_labels(db)


func _on_player_province_selected(mouse_pos: Vector2) -> void:
	var rg_color: Color = $Map.get_pixel_lookup_color(mouse_pos)
	var selected_province_color: Color = db.lookup_to_color_province[rg_color]
	selected_province = db.color_to_province[selected_province_color]
	$Map.highlight_province(selected_province)
	$ProvinceSelected.update_labels(selected_province)


func _on_map_modes_map_mode_selected(mode: MapMode.Type) -> void:
	$Map.set_map_mode(mode)
