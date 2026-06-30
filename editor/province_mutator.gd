extends Node
class_name ProvinceMutator

# Owns the multi-step transactions that mutate the selected provinces and refresh
# the map, hiding the required call ordering (update_map_modes → commit →
# refresh SDF → update_map → update labels). Dependencies are injected once via
# setup() so UI signals can connect straight to these methods.

var map: Map
var db: Database
var selection: SelectionController


func setup(target_map: Map, database: Database, selection_controller: SelectionController) -> void:
	map = target_map
	db = database
	selection = selection_controller


func set_province_owner(new_owner: Country) -> void:
	_set_owner_of(selection.selected_provinces, new_owner)


func set_province_owner_for_territory(new_owner: Country) -> void:
	_set_owner_of(_expand_to_territories(selection.selected_provinces), new_owner)


func set_province_controller(new_controller: Country) -> void:
	_set_controller_of(selection.selected_provinces, new_controller)


func set_province_controller_for_territory(new_controller: Country) -> void:
	_set_controller_of(_expand_to_territories(selection.selected_provinces), new_controller)


func set_type(index: int) -> void:
	for province: Province in selection.selected_provinces:
		province.type = Province.Type.values()[index]


func set_terrain(index: int) -> void:
	for province: Province in selection.selected_provinces:
		province.terrain = Province.Terrain.values()[index]
		map.update_map_modes(province, false)
	map.commit_map_modes()
	map.update_map()


func set_territory(new_territory: Territory) -> void:
	for province: Province in selection.selected_provinces:
		province.territory = new_territory
		map.update_map_texture(province, false)
	map.refresh_territory_sdf()


func _set_owner_of(provinces: Array[Province], new_owner: Country) -> void:
	var old_owners: Array[Country] = []
	for province: Province in provinces:
		if province.province_owner not in old_owners:
			old_owners.append(province.province_owner)
		province.province_owner = new_owner
		map.update_map_modes(province, false)
		map.update_country_borders(province, false)
	map.commit_map_modes()
	map.refresh_country_sdf()
	map.update_map()
	map.update_country_label(new_owner)
	for old_owner: Country in old_owners:
		map.update_country_label(old_owner)
	_set_controller_of(provinces, new_owner) # Set both


func _set_controller_of(provinces: Array[Province], new_controller: Country) -> void:
	for province: Province in provinces:
		province.province_controller = new_controller
		map.update_map_modes(province, false)
	map.commit_map_modes()
	map.update_map()


func _expand_to_territories(provinces: Array[Province]) -> Array[Province]:
	var visited: Dictionary[Province, bool] = {}
	var result: Array[Province] = []
	for selected: Province in provinces:
		if selected.territory == null:
			continue
		for province: Province in selected.territory.provinces:
			if province in visited:
				continue
			visited[province] = true
			result.append(province)
	return result
