extends Resource
class_name CountryConverter

var history_data: Dictionary = {}
var definition_data: Array = []

func _init(country: Country) -> void:
	history_data["base_name"] = country.base_name
	history_data["map_color"] = [country.map_color.r, country.map_color.g, country.map_color.b]
	history_data["ideology"] = Country.Ideology.keys()[country.ideology]
	definition_data.append(country.tag)
