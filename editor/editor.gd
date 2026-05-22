extends Node3D

# Belongs here: _ready bootstrap (DB import, Map/UI init), signal wiring between controllers.

var db: Database = Database.new()

@onready var map = $Map
@onready var camera: CameraController = $CameraControllerEditor
@onready var selection: SelectionController = $SelectionController
@onready var mutator: ProvinceMutator = $ProvinceMutator
@onready var province_editor: CanvasLayer = $ProvinceEditor


func _ready() -> void:
	DataImporter.new(db)
	map.create_map_textures(db)
	map.create_map_modes(db)
	map.create_country_labels(db)
	map.get_preview_images()

	province_editor.database = db
	province_editor.populate_buttons()


func _on_camera_controller_province_selected(world_pos: Vector2, additive: bool) -> void:
	selection.select_at(world_pos, additive, self.map, self.db)


func _on_selection_changed(provinces: Array[Province]) -> void:
	province_editor.update_labels(provinces[0])


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
