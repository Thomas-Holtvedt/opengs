extends BaseImporter
class_name TerritoryImporter

func import_definition(db: Database) -> void:
	for line: String in read_lines("res://data/definitions/territories.txt"):
		var fields: PackedStringArray = line.split(";")
		if fields.size() < 1:
			continue

		var color: Color = Color.BLACK
		if fields.size() >= 5:
			color = Color(fields[2].to_int() / 255.0, fields[3].to_int() / 255.0, fields[4].to_int() / 255.0)
		var territory: Territory = Territory.new(fields[0], color)
		db.id_to_territory[territory.id] = territory


func import_history(db: Database) -> void:
	var all_data: Dictionary = read_json("res://data/history/territories/territories.json")

	for tid: String in db.id_to_territory.keys():
		if not all_data.has(tid):
			continue
		var data: Dictionary = all_data[tid]
		if not data.has("provinces"):
			continue

		var territory: Territory = db.id_to_territory[tid]

		for pid: String in data["provinces"]:
			# The territory setter maintains Territory.provinces.
			db.id_to_province[pid].territory = territory
