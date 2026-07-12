extends Resource
class_name DataImporter

var province_importer: ProvinceImporter = ProvinceImporter.new()
var territory_importer: TerritoryImporter = TerritoryImporter.new()
var country_importer: CountryImporter = CountryImporter.new()
var flag_importer: FlagImporter = FlagImporter.new()

func _init(db: Database) -> void:
	import_definitions(db)
	import_histories(db)
	import_flags(db)

func import_definitions(db: Database) -> void:
	province_importer.import_definition(db)
	territory_importer.import_definition(db)
	country_importer.import_definition(db)
	
func import_histories(db: Database) -> void:
	province_importer.import_history(db)
	territory_importer.import_history(db)
	country_importer.import_history(db)

func import_flags(db: Database) -> void:
	flag_importer.import_components(db)
	flag_importer.import_history(db)
	
