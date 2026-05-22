extends Resource

class_name Country

enum Ideology { DEMOCRACY, COMMUNISM }

var tag: String
var base_name: String
var map_color: Color
var ideology: Ideology
var owned_provinces:  Array[Province]


func _init(country_tag: String) -> void:
	self.tag = country_tag
