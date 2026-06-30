extends Resource
class_name ProvinceExporter


func write_definition(db: Database) -> void:
	var path: String = "res://data/definitions/provinces.txt"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	for province: Province in db.id_to_province.values():
		var converter: ProvinceConverter = ProvinceConverter.new(province)
		file.store_line(";".join(converter.definition_data.map(func(value: Variant) -> String: return str(value))))
	file.close()


func write_history(db: Database) -> void:
	var all_data: Dictionary = {}
	for province: Province in db.id_to_province.values():
		var converter: ProvinceConverter = ProvinceConverter.new(province)
		if not converter.history_data.is_empty():
			all_data[province.id] = converter.history_data
	var path: String = "res://data/history/provinces/provinces.json"
	var json_string: String = JSON.stringify(all_data, "\t")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(json_string)
	file.close()
