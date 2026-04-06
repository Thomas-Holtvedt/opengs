extends BaseImporter
class_name ProvinceImporter

func import_definition(db: Database) -> void:
	for line in read_lines("res://data/definitions/provinces.txt"):
		var a = line.split(";")
		if a.size() < 7:
			continue

		var province = Province.new(
			a[0],
			Province.Type[a[1].to_upper()],
			Color(a[2].to_float()/255, a[3].to_float()/255, a[4].to_float()/255),
			Vector2(a[5].to_float(), a[6].to_float()),
			Province.Terrain[a[7].to_upper()]
		)

		db.id_to_province[province.id] = province
		db.color_to_province[province.color] = province

func import_history(db: Database) -> void:
	var all_data = read_json("res://data/history/provinces/provinces.json")

	for pid in db.id_to_province.keys():
		var province: Province = db.id_to_province[pid]
		if province.type == Province.Type.LAND:
			province.province_owner = db.tag_to_country["NNN"]
			province.province_controller = db.tag_to_country["NNN"]
			if all_data.has(pid):
				var data: Dictionary = all_data[pid]
				if data.has("province_owner"):
					province.province_owner = db.tag_to_country[data["province_owner"]]
				if data.has("province_controller"):
					province.province_controller = db.tag_to_country[data["province_controller"]]
