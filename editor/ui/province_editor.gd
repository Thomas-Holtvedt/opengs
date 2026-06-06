extends PanelContainer
class_name ProvinceEditor

@onready var id_label: Label = $GridContainer/LabelProvinceID
@onready var color_picker: ColorPickerButton = $GridContainer/ColorPickerProvinceColor
@onready var type_dropdown: OptionButton = $GridContainer/OBProvinceType
@onready var terrain_dropdown: OptionButton = $GridContainer/OBProvinceTerrain
@onready var owner_dropdown: OptionButton = $GridContainer/OBProvinceOwner
@onready var controller_dropdown: OptionButton = $GridContainer/OBProvinceController
@onready var territory_owner_dropdown: OptionButton = $GridContainer/OBTerritoryOwner
@onready var territory_controller_dropdown: OptionButton = $GridContainer/OBTerritoryController
@onready var territory_dropdown: OptionButton = $GridContainer/OBTerritory

@onready var center_label: Label = $GridContainer/LabelPosition

signal change_type(index: int)
signal change_terrain(index: int)
signal change_owner(new_owner: Country)
signal change_controller(controller: Country)
signal change_owner_territory(new_owner: Country)
signal change_controller_territory(controller: Country)
signal change_territory(new_territory: Territory)
signal export_requested
signal is_setting_center

var database: Database

var index_to_tag: Dictionary[int, String]
var tag_to_index: Dictionary[String, int]

var index_to_territory_id: Dictionary[int, String]
var territory_id_to_index: Dictionary[String, int]


func populate_buttons() -> void:
	populate_type_button()
	populate_terrain_button()
	populate_owner_button()
	populate_territory_button()


func show_province(province: Province):
	id_label.text  = str(province.id)
	color_picker.color = province.color
	type_dropdown.select(province.type)
	terrain_dropdown.select(province.terrain)
	territory_owner_dropdown.select(-1)
	territory_controller_dropdown.select(-1)
	center_label.text = str(province.center)
	territory_dropdown.select(territory_id_to_index[province.territory.id])
	if province.type == Province.Type.LAND:
		owner_dropdown.select(tag_to_index[province.province_owner.tag])
		controller_dropdown.select(tag_to_index[province.province_controller.tag])
	else:
		owner_dropdown.select(-1)
		controller_dropdown.select(-1)


func populate_territory_button() -> void:
	var i: int = 0
	for tid in database.id_to_territory:
		territory_dropdown.add_item(tid)
		index_to_territory_id[i] = tid
		territory_id_to_index[tid] = i
		i += 1


func populate_type_button() -> void:
	for type in Province.Type:
		type_dropdown.add_item(type)


func populate_terrain_button() -> void:
	for terrain in Province.Terrain:
		terrain_dropdown.add_item(terrain)


func refresh_country_buttons() -> void:
	owner_dropdown.clear()
	controller_dropdown.clear()
	territory_owner_dropdown.clear()
	territory_controller_dropdown.clear()
	index_to_tag.clear()
	tag_to_index.clear()
	populate_owner_button()


func populate_owner_button() -> void:
	var i: int = 0
	for tag in database.tag_to_country:
		owner_dropdown.add_item(tag)
		controller_dropdown.add_item(tag)
		territory_owner_dropdown.add_item(tag)
		territory_controller_dropdown.add_item(tag)
		index_to_tag[i] = tag
		tag_to_index[tag] = i
		i += 1


# BUTTONS

func _on_ob_territory_item_selected(index: int) -> void:
	var new_territory: Territory = database.id_to_territory[index_to_territory_id[index]]
	change_territory.emit(new_territory)


func _on_ob_province_type_item_selected(index: int) -> void:
	change_type.emit(index)


func _on_ob_province_terrain_item_selected(index: int) -> void:
	change_terrain.emit(index)


func _on_ob_province_owner_item_selected(index: int) -> void:
	var new_owner: Country = database.tag_to_country[index_to_tag[index]]
	change_owner.emit(new_owner)


func _on_ob_province_controller_item_selected(index: int) -> void:
	var new_controller: Country = database.tag_to_country[index_to_tag[index]]
	change_controller.emit(new_controller)


func _on_ob_territory_owner_item_selected(index: int) -> void:
	var new_owner: Country = database.tag_to_country[index_to_tag[index]]
	change_owner_territory.emit(new_owner)


func _on_ob_territory_controller_item_selected(index: int) -> void:
	var new_controller: Country = database.tag_to_country[index_to_tag[index]]
	change_controller_territory.emit(new_controller)


# SAVE BUTTON
func _on_button_gen_prv_button_up() -> void:
	export_requested.emit()


func _on_button_set_center_button_up() -> void:
	is_setting_center.emit()
