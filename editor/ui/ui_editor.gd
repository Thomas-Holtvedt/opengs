extends CanvasLayer
class_name UIEditor

@onready var province_editor: ProvinceEditor = $ProvinceEditor
@onready var country_editor: CountryEditor = $CountryEditor

var database: Database


func populate_buttons() -> void:
	province_editor.database = database
	province_editor.populate_buttons()
	country_editor.database = database
	country_editor.populate_buttons()


func show_province(province: Province):
	province_editor.show_province(province)
	if province.type == Province.Type.LAND:
		country_editor.show_country(province.province_owner)
	else:
		country_editor.show_country(database.tag_to_country["NNN"])


func refresh_country_buttons() -> void:
	province_editor.refresh_country_buttons()
	country_editor.refresh_country_button()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			focus_owner.release_focus()


func _on_tab_bar_tab_changed(tab: int) -> void:
	if tab == 0:
		province_editor.visible = true
		country_editor.visible = false
	if tab == 1:
		province_editor.visible = false
		country_editor.visible = true
