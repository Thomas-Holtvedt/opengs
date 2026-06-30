extends Node
class_name CountryMutator

# Owns mutations of country state, hiding side-effects on the database keys and
# any map refresh required. Dependencies are injected once via setup() so UI
# signals can connect straight to these methods.

var map: Map
var db: Database


func setup(target_map: Map, database: Database) -> void:
	map = target_map
	db = database


func create_country() -> Country:
	var tag: String = _generate_unique_tag()
	var country: Country = Country.new(tag)
	country.ideology = Country.Ideology.DEMOCRACY
	db.tag_to_country[tag] = country
	return country


func set_tag(country: Country, new_tag: String) -> bool:
	if new_tag.is_empty() or new_tag == country.tag:
		return false
	if new_tag in db.tag_to_country:
		return false
	var old_tag: String = country.tag
	db.tag_to_country.erase(old_tag)
	country.tag = new_tag
	db.tag_to_country[new_tag] = country
	map.rename_country_label(old_tag, new_tag)
	return true


func set_base_name(country: Country, new_name: String) -> void:
	country.base_name = new_name
	map.update_country_label(country)


func set_map_color(country: Country, new_color: Color) -> void:
	country.map_color = new_color
	for province: Province in country.owned_provinces:
		map.update_map_modes(province, false)
	map.commit_map_modes()
	map.update_map()
	map.update_country_label(country)


func set_ideology(country: Country, index: int) -> void:
	country.ideology = Country.Ideology.values()[index]
	for province: Province in country.owned_provinces:
		map.update_map_modes(province, false)
	map.commit_map_modes()
	map.update_map()


func _generate_unique_tag() -> String:
	if not "NEW" in db.tag_to_country:
		return "NEW"
	var i: int = 2
	while ("NEW" + str(i)) in db.tag_to_country:
		i += 1
	return "NEW" + str(i)
