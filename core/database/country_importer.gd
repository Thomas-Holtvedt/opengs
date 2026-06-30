extends BaseImporter
class_name CountryImporter

func import_definition(db: Database) -> void:
	for line: String in read_lines("res://data/definitions/countries.txt"):
		var fields: PackedStringArray = line.split(";")
		if fields.size() < 1:
			continue
		var country: Country = Country.new(fields[0])
		db.tag_to_country[country.tag] = country

func import_history(db: Database) -> void:
	var folder: String = "res://data/history/countries/"

	for tag: String in db.tag_to_country.keys():
		var data: Dictionary = read_json(folder + tag + ".json")
		if data.is_empty():
			continue

		var country: Country = db.tag_to_country[tag]

		set_matching_fields(country, data)

		if data.has("map_color"):
			var c: Array = data["map_color"]
			if c.size() >= 3:
				country.map_color = Color(c[0], c[1], c[2])
			else:
				push_warning("Invalid map_color for country %s, expected 3 components, got %d" % [tag, c.size()])

		if data.has("ideology"):
			match data["ideology"]:
				"DEMOCRACY":
					country.ideology = Country.Ideology.DEMOCRACY
				"COMMUNISM":
					country.ideology = Country.Ideology.COMMUNISM
				_:
					push_warning("Unknown ideology '%s' for country %s" % [data["ideology"], tag])
