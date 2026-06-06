extends Resource
class_name CountryExporter


func write_definition(db: Database) -> void:
	var path = "res://data/definitions/countries.txt"
	var file = FileAccess.open(path, FileAccess.WRITE)
	for country: Country in db.tag_to_country.values():
		var data = CountryConverter.new(country)
		file.store_line(";".join(data.definition_data.map(func(v): return str(v))))
	file.close()


func write_history(db: Database) -> void:
	var folder = "res://data/history/countries/"
	for country: Country in db.tag_to_country.values():
		var data = CountryConverter.new(country)
		if data.history_data.is_empty():
			continue
		var path = folder + country.tag + ".json"
		var json_string = JSON.stringify(data.history_data, "\t")
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(json_string)
		file.close()
