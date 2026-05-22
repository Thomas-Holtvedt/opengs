extends Resource

class_name Province

enum Type { LAND, LAKE, OCEAN }
enum Terrain { FOREST, HILLS, MOUNTAIN, PLAINS, URBAN, JUNGLE, MARSH, DESERT, DEEP_OCEAN, SHALLOW_SEA, FJORDS, LAKES }

var id: String
var color: Color
var type: Type
var terrain: Terrain
var center: Vector2i
var territory: Territory
var bounding_box: int = 150
		
var province_owner: Country:
	set(value):
		if province_owner != null:
			province_owner.owned_provinces.erase(self)
		province_owner = value
		province_owner.owned_provinces.append(self)
var province_controller: Country

func _init(province_id: String, province_type: Type, province_color: Color,  province_center: Vector2, province_terrain: Terrain) -> void:
	self.id = province_id
	self.color = province_color
	self.center = province_center
	self.type = province_type
	self.terrain = province_terrain

func set_territory(new_territory: Territory):
	if territory != null:
		territory.provinces.erase(self)
	territory = new_territory
	territory.provinces.append(self)
	
