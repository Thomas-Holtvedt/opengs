extends CanvasLayer
@onready var province_id = $PanelContainer/GridContainer/LabelProvinceID
@onready var province_color = $PanelContainer/GridContainer/ColorPickerProvinceColor
@onready var province_type = $PanelContainer/GridContainer/LabelProvinceType
@onready var province_owner = $PanelContainer/GridContainer/LabelOwner
@onready var province_controller = $PanelContainer/GridContainer/LabelController
@onready var province_territory = $PanelContainer/GridContainer/LabelTerritory
@onready var province_center = $PanelContainer/GridContainer/LabelPosition
@onready var province_terrain = $PanelContainer/GridContainer/LabelTerrain

func update_labels(province: Province):
	province_id.text  = str(province.id)
	province_color.color = province.color
	province_type.text = Province.Type.keys()[province.type]
	province_terrain.text = Province.Terrain.keys()[province.terrain]
	province_center.text = str(province.center)
	province_territory.text = str(province.territory.id)
	if province.type == Province.Type.LAND:
		province_owner.text = province.province_owner.tag
		province_controller.text = province.province_controller.tag	
	else:
		province_owner.text = ""
		province_controller.text = ""
