extends Resource

class_name Territory

var id: String
# Unique identity color from territories.txt. Stable across membership changes — the map
# shader compares it against the selected_territory_ids uniform to draw the white ring.
var color: Color
var provinces: Array[Province]

func _init(territory_id: String, territory_color: Color = Color.BLACK) -> void:
	self.id = territory_id
	self.color = territory_color
