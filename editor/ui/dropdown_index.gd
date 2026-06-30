extends RefCounted
class_name DropdownIndex

# Keeps one or more OptionButtons filled with the same ordered set of string ids,
# and maps between item index and id in both directions. Repopulating clears and
# rebuilds every linked dropdown, so the maps can never drift out of sync.

var index_to_id: Dictionary[int, String] = {}
var id_to_index: Dictionary[String, int] = {}

var _dropdowns: Array[OptionButton]


func _init(dropdowns: Array[OptionButton]) -> void:
	_dropdowns = dropdowns


func populate(ids: Array) -> void:
	clear()
	var index: int = 0
	for id: String in ids:
		for dropdown: OptionButton in _dropdowns:
			dropdown.add_item(id)
		index_to_id[index] = id
		id_to_index[id] = index
		index += 1


func clear() -> void:
	for dropdown: OptionButton in _dropdowns:
		dropdown.clear()
	index_to_id.clear()
	id_to_index.clear()
