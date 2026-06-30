extends BaseImporter
class_name FlagImporter

func import_components(db: Database) -> void:
	db.flag_backgrounds = load_textures("res://assets/flags/backgrounds/")
	db.flag_icons = load_textures("res://assets/flags/icons/")
	db.flag_icons_colored = load_textures("res://assets/flags/icons_colored/")

func load_textures(path: String) -> Dictionary[String, CompressedTexture2D]:
	var textures: Dictionary[String, CompressedTexture2D] = {}
	var files: Dictionary[String, String] = import_folder_content(path, ".png")
	for key: String in files:
		var texture := load(files[key]) as CompressedTexture2D
		if texture == null:
			push_warning("Failed to load: " + files[key])
			continue
		textures[key] = texture
	return textures

func import_history(db: Database) -> void:
	var files: Dictionary[String, String] = import_folder_content("res://data/history/flags/", ".json")
	for tag: String in files:
		var data: Dictionary = read_json(files[tag])
		if data.is_empty():
			push_warning("Empty or invalid flag data: " + files[tag])
			continue
		if not db.tag_to_country.has(tag):
			push_warning("Flag '%s' has no matching country, skipping" % tag)
			continue

		var flag: Flag = Flag.new()
		flag.id = tag
		# String fields (background_image, icon_*_image) map straight through.
		# The actual texture is resolved at display time via the database.
		set_matching_fields(flag, data)

		# Colors and offsets are stored as arrays in JSON, so decode them back.
		flag.background_color_1 = _to_color(tag, "background_color_1", data, flag.background_color_1)
		flag.background_color_2 = _to_color(tag, "background_color_2", data, flag.background_color_2)
		flag.background_color_3 = _to_color(tag, "background_color_3", data, flag.background_color_3)
		flag.icon_1_color = _to_color(tag, "icon_1_color", data, flag.icon_1_color)
		flag.icon_2_color = _to_color(tag, "icon_2_color", data, flag.icon_2_color)
		flag.icon_1_offset = _to_vector2(tag, "icon_1_offset", data, flag.icon_1_offset)
		flag.icon_2_offset = _to_vector2(tag, "icon_2_offset", data, flag.icon_2_offset)
		flag.icon_colored_offset = _to_vector2(tag, "icon_colored_offset", data, flag.icon_colored_offset)

		# Canton (only present in JSON when the flag actually has one). String
		# fields are handled by set_matching_fields above; decode the rest here.
		flag.canton_size = _to_vector2(tag, "canton_size", data, flag.canton_size)
		flag.canton_background_color_1 = _to_color(tag, "canton_background_color_1", data, flag.canton_background_color_1)
		flag.canton_background_color_2 = _to_color(tag, "canton_background_color_2", data, flag.canton_background_color_2)
		flag.canton_background_color_3 = _to_color(tag, "canton_background_color_3", data, flag.canton_background_color_3)
		flag.canton_icon_1_color = _to_color(tag, "canton_icon_1_color", data, flag.canton_icon_1_color)
		flag.canton_icon_2_color = _to_color(tag, "canton_icon_2_color", data, flag.canton_icon_2_color)
		flag.canton_icon_1_offset = _to_vector2(tag, "canton_icon_1_offset", data, flag.canton_icon_1_offset)
		flag.canton_icon_2_offset = _to_vector2(tag, "canton_icon_2_offset", data, flag.canton_icon_2_offset)
		flag.canton_icon_colored_offset = _to_vector2(tag, "canton_icon_colored_offset", data, flag.canton_icon_colored_offset)

		db.id_to_flag[tag] = flag
		db.tag_to_country[tag].flag = flag


func _to_color(tag: String, key: String, data: Dictionary, fallback: Color) -> Color:
	if not data.has(key):
		return fallback
	var c: Array = data[key]
	if c.size() >= 3:
		return Color(c[0], c[1], c[2])
	push_warning("Invalid %s for flag %s, expected 3 components, got %d" % [key, tag, c.size()])
	return fallback


func _to_vector2(tag: String, key: String, data: Dictionary, fallback: Vector2) -> Vector2:
	if not data.has(key):
		return fallback
	var v: Array = data[key]
	if v.size() >= 2:
		return Vector2(v[0], v[1])
	push_warning("Invalid %s for flag %s, expected 2 components, got %d" % [key, tag, v.size()])
	return fallback
