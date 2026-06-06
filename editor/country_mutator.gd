extends Node
class_name CountryMutator

# Owns mutations of country state. Callers pass in the country to act on;
# this node hides side-effects on the database keys and any map refresh required.


func create_country(db: Database) -> Country:
	var tag: String = _generate_unique_tag(db)
	var country: Country = Country.new(tag)
	country.ideology = Country.Ideology.DEMOCRACY
	db.tag_to_country[tag] = country
	return country


func _generate_unique_tag(db: Database) -> String:
	if not "NEW" in db.tag_to_country:
		return "NEW"
	var i: int = 2
	while ("NEW" + str(i)) in db.tag_to_country:
		i += 1
	return "NEW" + str(i)


func set_tag(country: Country, new_tag: String, db: Database) -> bool:
	if new_tag.is_empty() or new_tag == country.tag:
		return false
	if new_tag in db.tag_to_country:
		return false
	db.tag_to_country.erase(country.tag)
	country.tag = new_tag
	db.tag_to_country[new_tag] = country
	return true


func set_base_name(country: Country, new_name: String, map: Map) -> void:
	country.base_name = new_name
	map.update_country_label(country)


func set_map_color(country: Country, new_color: Color, map: Map) -> void:
	country.map_color = new_color
	for province in country.owned_provinces:
		map.update_map_modes(province, false)
	map.commit_map_modes()
	map.update_map()
	map.update_country_label(country)


func set_ideology(country: Country, index: int, map: Map) -> void:
	country.ideology = Country.Ideology.values()[index]
	for province in country.owned_provinces:
		map.update_map_modes(province, false)
	map.commit_map_modes()
	map.update_map()
