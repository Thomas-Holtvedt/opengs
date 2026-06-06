extends PanelContainer
class_name CountryEditor

@onready var country_dropdown: OptionButton = $GridContainer/OBCountrySelect
@onready var tag_edit: LineEdit = $GridContainer/LineEditTag
@onready var base_name_edit: LineEdit = $GridContainer/LineEditBaseName
@onready var map_color_picker: ColorPickerButton = $GridContainer/ColorPickerMapColor
@onready var ideology_dropdown: OptionButton = $GridContainer/OBIdeology

signal change_tag(country: Country, new_tag: String)
signal change_base_name(country: Country, new_base_name: String)
signal change_map_color(country: Country, new_color: Color)
signal change_ideology(country: Country, index: int)
signal export_requested
signal create_country_requested

var database: Database
var selected_country: Country

var index_to_tag: Dictionary[int, String]
var tag_to_index: Dictionary[String, int]


func populate_buttons() -> void:
	populate_country_button()
	populate_ideology_button()


func show_country(country: Country):
	if country == null:
		return
	selected_country = country
	country_dropdown.select(tag_to_index[country.tag])
	tag_edit.text = country.tag
	base_name_edit.text = country.base_name
	map_color_picker.color = country.map_color
	ideology_dropdown.select(country.ideology)


func refresh_country_button() -> void:
	country_dropdown.clear()
	index_to_tag.clear()
	tag_to_index.clear()
	populate_country_button()
	if selected_country != null:
		country_dropdown.select(tag_to_index[selected_country.tag])


func populate_country_button() -> void:
	var i: int = 0
	for tag in database.tag_to_country:
		country_dropdown.add_item(tag)
		index_to_tag[i] = tag
		tag_to_index[tag] = i
		i += 1


func populate_ideology_button() -> void:
	for ideology in Country.Ideology:
		ideology_dropdown.add_item(ideology)


# BUTTONS

func _on_ob_country_select_item_selected(index: int) -> void:
	var country: Country = database.tag_to_country[index_to_tag[index]]
	show_country(country)


func _on_line_edit_tag_text_changed(new_text: String) -> void:
	if selected_country == null:
		return
	change_tag.emit(selected_country, new_text)


func _on_line_edit_base_name_text_changed(new_text: String) -> void:
	if selected_country == null:
		return
	change_base_name.emit(selected_country, new_text)


func _on_color_picker_map_color_color_changed(color: Color) -> void:
	if selected_country == null:
		return
	change_map_color.emit(selected_country, color)


func _on_ob_ideology_item_selected(index: int) -> void:
	if selected_country == null:
		return
	change_ideology.emit(selected_country, index)


# SAVE BUTTON
func _on_button_save_countries_button_up() -> void:
	export_requested.emit()


func _on_button_create_country_button_up() -> void:
	create_country_requested.emit()
