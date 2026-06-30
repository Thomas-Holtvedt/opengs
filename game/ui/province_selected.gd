extends CanvasLayer
class_name ProvinceSelected

@onready var id_label: Label = $PanelContainer/GridContainer/LabelProvinceID
@onready var color_picker: ColorPickerButton = $PanelContainer/GridContainer/ColorPickerProvinceColor
@onready var type_label: Label = $PanelContainer/GridContainer/LabelProvinceType
@onready var owner_label: Label = $PanelContainer/GridContainer/LabelOwner
@onready var controller_label: Label = $PanelContainer/GridContainer/LabelController
@onready var territory_label: Label = $PanelContainer/GridContainer/LabelTerritory
@onready var center_label: Label = $PanelContainer/GridContainer/LabelPosition
@onready var terrain_label: Label = $PanelContainer/GridContainer/LabelTerrain


func show_province(province: Province) -> void:
	id_label.text = str(province.id)
	color_picker.color = province.color
	type_label.text = Province.Type.keys()[province.type]
	terrain_label.text = Province.Terrain.keys()[province.terrain]
	center_label.text = str(province.center)
	territory_label.text = str(province.territory.id) if province.territory != null else ""
	if province.type == Province.Type.LAND:
		owner_label.text = province.province_owner.tag
		controller_label.text = province.province_controller.tag
	else:
		owner_label.text = ""
		controller_label.text = ""
