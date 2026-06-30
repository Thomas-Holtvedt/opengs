extends Resource
class_name BaseImporter

func read_lines(path: String) -> PackedStringArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open: " + path)
		return []
	var lines: PackedStringArray = file.get_as_text().split("\n", false)
	for i: int in lines.size():
		lines[i] = lines[i].strip_edges()
	return lines


func read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open: " + path)
		return {}
	return JSON.parse_string(file.get_as_text().strip_edges())


# Assigns each JSON entry whose key matches a property on `object`.
func set_matching_fields(object: Object, data: Dictionary) -> void:
	for field in data:
		if field in object:
			object.set(field, data[field])


func import_folder_content(path: String, extension: String) -> Dictionary[String, String]:
	var files: Dictionary[String, String] = {}
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("Failed to open dir: " + path)
		return files
	dir.list_dir_begin()
	for file: String in dir.get_files():
		if not file.ends_with(extension):
			continue
		files[file.get_basename()] = path.path_join(file)
	return files
