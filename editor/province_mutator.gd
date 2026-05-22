extends Node
class_name ProvinceMutator

# Owns the multi-step transactions that mutate province state and refresh the map.
# Callers pass in the provinces to act on; this node hides the required call ordering
# (update_map_modes → commit → refresh SDF → update_map → update labels).



func set_province_owner(provinces: Array[Province], new_owner: Country, map: Map, db: Database) -> void:
	var old_owners: Array[Country] = []
	for province in provinces:
		if province.province_owner not in old_owners:
			old_owners.append(province.province_owner)
		province.province_owner = new_owner
		map.update_map_modes(province, false)
		map.update_country_borders(province, db, false)
	map.commit_map_modes()
	map.refresh_country_sdf()
	map.update_map()
	map.update_country_label(new_owner)
	for old in old_owners:
		map.update_country_label(old)


func set_province_owner_for_territory(provinces: Array[Province], new_owner: Country, map: Map, db: Database) -> void:
	set_province_owner(_expand_to_territories(provinces), new_owner, map, db)


func set_province_controller(provinces: Array[Province], new_controller: Country, map: Map) -> void:
	for province in provinces:
		province.province_controller = new_controller
		map.update_map_modes(province, false)
	map.commit_map_modes()
	map.update_map()


func set_province_controller_for_territory(provinces: Array[Province], new_controller: Country, map: Map) -> void:
	set_province_controller(_expand_to_territories(provinces), new_controller, map)


func set_type(provinces: Array[Province], index: int) -> void:
	for province in provinces:
		province.type = Province.Type.values()[index]


func set_terrain(provinces: Array[Province], index: int, map: Map) -> void:
	for province in provinces:
		province.terrain = Province.Terrain.values()[index]
		map.update_map_modes(province, false)
	map.commit_map_modes()
	map.update_map()


func set_territory(provinces: Array[Province], new_territory: Territory, map: Map, db: Database) -> void:
	for province in provinces:
		province.set_territory(new_territory)
		map.update_map_texture(province, db, false)
	map.refresh_territory_sdf()


func _expand_to_territories(provinces: Array[Province]) -> Array[Province]:
	var visited: Dictionary = {}
	var result: Array[Province] = []
	for selected in provinces:
		if selected.territory == null:
			continue
		for province in selected.territory.provinces:
			if province in visited:
				continue
			visited[province] = true
			result.append(province)
	return result
