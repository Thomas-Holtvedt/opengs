extends BaseImporter
class_name TerritoryImporter

func import_definition(db: Database) -> void:
	for line in read_lines("res://data/definitions/territories.txt"):
		var a = line.split(";")
		if a.size() < 1:
			continue

		var territory = Territory.new(a[0])
		db.id_to_territory[territory.id] = territory



func import_history(db: Database) -> void:
	var all_data = read_json("res://data/history/territories/territories.json")

	for tid in db.id_to_territory.keys():
		if not all_data.has(tid):
			continue
		var data: Dictionary = all_data[tid]
		if not data.has("provinces"):
			continue

		var territory = db.id_to_territory[tid]

		for pid in data["provinces"]:
			var province = db.id_to_province[pid]
			territory.provinces.append(province)
			province.territory = territory
