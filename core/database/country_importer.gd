extends BaseImporter
class_name CountryImporter

func import_definition(db: Database) -> void:
	for line in read_lines("res://data/definitions/countries.txt"):
		var a = line.split(";")
		if a.size() < 1:
			continue
		var country = Country.new(a[0])
		db.tag_to_country[country.tag] = country

func import_history(db: Database) -> void:
	var folder = "res://data/history/countries/"

	for tag in db.tag_to_country.keys():
		var data = read_json(folder + tag + ".json")
		if data.is_empty():
			continue

		var country: Country = db.tag_to_country[tag]

		if data.has("map_color"):
			var c = data["map_color"]
			country.map_color = Color(c[0], c[1], c[2])

		if data.has("base_name"):
			country.base_name = data["base_name"]

		if data.has("ideology"):
			match data["ideology"]:
				"DEMOCRACY":
					country.ideology = Country.Ideology.DEMOCRACY
				"COMMUNISM":
					country.ideology = Country.Ideology.COMMUNISM
				_:
					push_warning("Unknown ideology '%s' for country %s" % [data["ideology"], tag])
