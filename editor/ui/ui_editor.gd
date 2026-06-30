extends CanvasLayer
class_name UIEditor

@onready var province_editor: ProvinceEditor = $ProvinceEditor
@onready var country_editor: CountryEditor = $CountryEditor
@onready var flag_editor: FlagEditor = $FlagEditor

var database: Database


func populate_buttons() -> void:
	province_editor.database = database
	province_editor.populate_buttons()
	country_editor.database = database
	country_editor.populate_buttons()
	flag_editor.database = database
	flag_editor.populate_buttons()
	country_editor.country_selected.connect(show_country)


func show_province(province: Province) -> void:
	province_editor.show_province(province)
	if province.type == Province.Type.LAND:
		show_country(province.province_owner)
	else:
		show_country(database.tag_to_country["NNN"])


func show_country(country: Country) -> void:
	if country == null:
		return
	country_editor.show_country(country)
	flag_editor.show_country(country)


func refresh_country_buttons() -> void:
	province_editor.refresh_country_buttons()
	country_editor.refresh_country_button()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			focus_owner.release_focus()


func _on_tab_bar_tab_changed(tab: int) -> void:
	var panels: Array[Control] = [province_editor, country_editor, flag_editor]
	for index: int in panels.size():
		panels[index].visible = (index == tab)
