extends Resource
class_name CountryExporter


func write_definition(db: Database) -> void:
	var path: String = "res://data/definitions/countries.txt"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	for country: Country in db.tag_to_country.values():
		var converter: CountryConverter = CountryConverter.new(country)
		file.store_line(";".join(converter.definition_data.map(func(value: Variant) -> String: return str(value))))
	file.close()


func write_history(db: Database) -> void:
	var folder: String = "res://data/history/countries/"
	for country: Country in db.tag_to_country.values():
		var converter: CountryConverter = CountryConverter.new(country)
		if converter.history_data.is_empty():
			continue
		var path: String = folder + country.tag + ".json"
		var json_string: String = JSON.stringify(converter.history_data, "\t")
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(json_string)
		file.close()
