extends Resource
class_name ProvinceConverter

var history_data: Dictionary = {}
var definition_data: Array = []

func _init(province: Province) -> void:
	if province.type == Province.Type.LAND:
		history_data["province_owner"] = province.province_owner.tag
		history_data["province_controller"] = province.province_controller.tag
	definition_data.append(province.id)
	definition_data.append(Province.Type.keys()[province.type].to_lower())
	definition_data.append(int(province.color.r*255))
	definition_data.append(int(province.color.g*255))
	definition_data.append(int(province.color.b*255))
	definition_data.append(province.center.x)
	definition_data.append(province.center.y)
	definition_data.append(Province.Terrain.keys()[province.terrain].to_lower())
