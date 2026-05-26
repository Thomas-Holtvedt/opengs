extends CanvasLayer

@onready var province_id = $PanelContainer/GridContainer/LabelProvinceID
@onready var province_color = $PanelContainer/GridContainer/ColorPickerProvinceColor
@onready var province_type = $PanelContainer/GridContainer/OBProvinceType
@onready var province_terrain = $PanelContainer/GridContainer/OBProvinceTerrain
@onready var province_owner = $PanelContainer/GridContainer/OBProvinceOwner
@onready var province_controller = $PanelContainer/GridContainer/OBProvinceController
@onready var territory_owner = $PanelContainer/GridContainer/OBTerritoryOwner
@onready var territory_controller = $PanelContainer/GridContainer/OBTerritoryController
@onready var province_territory = $PanelContainer/GridContainer/OBTerritory

@onready var province_center = $PanelContainer/GridContainer/LabelPosition

signal change_type(index: int)
signal change_terrain(index: int)
signal change_owner(new_owner: Country)
signal change_controller(controller: Country)
signal change_owner_territory(new_owner: Country)
signal change_controller_territory(controller: Country)
signal change_territory(new_territory: Territory)
signal export_requested

var database: Database

var country_order: Dictionary[int, String]
var country_order_rev: Dictionary[String, int]

var territory_id_list: Dictionary[int, String]
var territory_id_list_rev: Dictionary[String, int]

signal is_setting_center
	

func populate_buttons() -> void:
	populate_type_button()
	populate_terrain_button()
	populate_owner_button()
	populate_territory_button() 

func update_labels(province: Province):
	province_id.text  = str(province.id)
	province_color.color = province.color
	province_type.select(province.type)
	province_terrain.select(province.terrain)
	territory_owner.select(-1)
	territory_controller.select(-1)
	province_center.text = str(province.center)
	province_territory.text = str(province.territory.id)
	province_territory.select(territory_id_list_rev[province.territory.id])
	if province.type == Province.Type.LAND:
		province_owner.select(country_order_rev[province.province_owner.tag])
		province_controller.select(country_order_rev[province.province_controller.tag])
	else:
		province_owner.select(-1)
		province_controller.select(-1)
		


func populate_territory_button() -> void:
	var i: int = 0
	for tit in database.id_to_territory:
		province_territory.add_item(tit)
		territory_id_list[i] = tit
		territory_id_list_rev[tit] = i
		i += 1
		

func populate_type_button() -> void:
	for type in Province.Type:
		province_type.add_item(type)

func populate_terrain_button() -> void:
	for terrain in Province.Terrain:
		province_terrain.add_item(terrain)

func populate_owner_button() -> void:
	var i: int = 0
	for tag in database.tag_to_country:
		province_owner.add_item(tag)
		province_controller.add_item(tag)
		territory_owner.add_item(tag)
		territory_controller.add_item(tag)
		country_order[i] = tag
		country_order_rev[tag] = i
		i += 1


# BUTTONS

func _on_ob_territory_item_selected(index: int) -> void:
	var new_territory: Territory = database.id_to_territory[territory_id_list[index]]
	change_territory.emit(new_territory)
	
func _on_ob_province_type_item_selected(index: int) -> void:
	change_type.emit(index)
	
func _on_ob_province_terrain_item_selected(index: int) -> void:
	change_terrain.emit(index)


func _on_ob_province_owner_item_selected(index: int) -> void:
	var new_owner: Country = database.tag_to_country[country_order[index]]
	change_owner.emit(new_owner)


func _on_ob_province_controller_item_selected(index: int) -> void:
	var new_controller: Country = database.tag_to_country[country_order[index]]
	change_controller.emit(new_controller)


func _on_ob_territory_owner_item_selected(index: int) -> void:
	var new_owner: Country = database.tag_to_country[country_order[index]]
	change_owner_territory.emit(new_owner)


func _on_ob_territory_controller_item_selected(index: int) -> void:
	var new_controller: Country = database.tag_to_country[country_order[index]]
	change_controller_territory.emit(new_controller)


# SAVE BUTTON
func _on_button_gen_prv_button_up() -> void:
	export_requested.emit()





func _on_button_set_center_button_up() -> void:
	is_setting_center.emit()
