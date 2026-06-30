extends Resource
class_name FlagExporter

func write_history(db: Database) -> void:
	var folder: String = "res://data/history/flags/"
	var written: int = 0
	for country: Country in db.tag_to_country.values():
		if country.flag == null:
			continue
		var converter: FlagConverter = FlagConverter.new(country.flag)
		if converter.history_data.is_empty():
			continue
		var path: String = folder + country.tag + ".json"
		var json_string: String = JSON.stringify(converter.history_data, "\t")
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			# Most common cause: this is an exported build, where res:// is packed
			# and read-only. Run the editor from the Godot editor to write here.
			push_error("FlagExporter: could not open '%s' for writing (error %d)." % [
				ProjectSettings.globalize_path(path), FileAccess.get_open_error()])
			continue
		file.store_string(json_string)
		file.close()
		written += 1
	print("FlagExporter: wrote %d flag file(s) to %s" % [
		written, ProjectSettings.globalize_path(folder)])
