extends Resource

class_name Territory

var id: String
var provinces: Array[Province]

func _init(territory_id) -> void:
	self.id = territory_id
