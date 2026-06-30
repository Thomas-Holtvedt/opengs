extends PanelContainer
class_name FlagEditor

@onready var flag: FlagDisplay = %FlagDisplay
@onready var generator: TextFlagGenerator = $VB/FlagIconGenerator
@onready var text_flag_label: RichTextLabel = $VB/HBoxContainer/RTLTextFlag

@onready var background_dropdown: OptionButton = $VB/OBBackground
@onready var color_1_picker: ColorPickerButton = $VB/CPBBackground1
@onready var color_2_picker: ColorPickerButton = $VB/CPBBackground2
@onready var color_3_picker: ColorPickerButton = $VB/CPBBackground3
@onready var icon_1_dropdown: OptionButton = $VB/OBIcon1
@onready var icon_1_color_picker: ColorPickerButton = $VB/CPBIcon1
@onready var icon_1_x_slider: HSlider = $VB/HSIcon1X
@onready var icon_1_y_slider: HSlider = $VB/HSIcon1Y
@onready var icon_2_dropdown: OptionButton = $VB/OBIcon2
@onready var icon_2_color_picker: ColorPickerButton = $VB/CPBIcon2
@onready var icon_2_x_slider: HSlider = $VB/HSIcon2X
@onready var icon_2_y_slider: HSlider = $VB/HSIcon2Y
@onready var icon_colored_dropdown: OptionButton = $VB/OBIconColored
@onready var icon_colored_x_slider: HSlider = $VB/HSIconColoredX
@onready var icon_colored_y_slider: HSlider = $VB/HSIconColoredY
@onready var canton_dropdown: OptionButton = $VB/OBCanton
@onready var canton_x_slider: HSlider = $VB/HSCantonX
@onready var canton_y_slider: HSlider = $VB/HSCantonY

signal export_requested

var database: Database
var selected_country: Country
var backgrounds: DropdownIndex
var icons_1: DropdownIndex
var icons_2: DropdownIndex
var icons_colored: DropdownIndex
var countries: DropdownIndex

func populate_buttons() -> void:
	flag.database = database
	# The generator has its OWN FlagDisplay; it needs the database too, or every
	# texture resolves to null and the text flag renders white.
	generator.flag.database = database
	backgrounds = DropdownIndex.new([background_dropdown])
	backgrounds.populate(database.flag_backgrounds.keys())
	icons_1 = DropdownIndex.new([icon_1_dropdown])
	icons_1.populate(database.flag_icons.keys())
	icons_2 = DropdownIndex.new([icon_2_dropdown])
	icons_2.populate(database.flag_icons.keys())
	icons_colored = DropdownIndex.new([icon_colored_dropdown])
	icons_colored.populate(database.flag_icons_colored.keys())
	countries = DropdownIndex.new([canton_dropdown])
	countries.populate(database.tag_to_country.keys())


func show_country(country: Country) -> void:
	if country == null:
		return
	selected_country = country
	flag.apply_flag(country.flag)

	background_dropdown.select(backgrounds.id_to_index[country.flag.background_image])
	color_1_picker.color = country.flag.background_color_1
	color_2_picker.color = country.flag.background_color_2
	color_3_picker.color = country.flag.background_color_3

	icon_1_dropdown.select(icons_1.id_to_index[country.flag.icon_1_image])
	icon_1_color_picker.color = country.flag.icon_1_color
	icon_1_x_slider.value = country.flag.icon_1_offset.x * 100.0
	icon_1_y_slider.value = country.flag.icon_1_offset.y * 100.0

	icon_2_dropdown.select(icons_2.id_to_index[country.flag.icon_2_image])
	icon_2_color_picker.color = country.flag.icon_2_color
	icon_2_x_slider.value = country.flag.icon_2_offset.x * 100.0
	icon_2_y_slider.value = country.flag.icon_2_offset.y * 100.0

	icon_colored_dropdown.select(icons_colored.id_to_index[country.flag.icon_colored_image])
	icon_colored_x_slider.value = country.flag.icon_colored_offset.x * 100.0
	icon_colored_y_slider.value = country.flag.icon_colored_offset.y * 100.0

	# The canton's source country isn't stored on the flag, so the dropdown is
	# left as-is; the sliders reflect the current canton size (0 = no canton).
	canton_x_slider.value = country.flag.canton_size.x
	canton_y_slider.value = country.flag.canton_size.y

	_show_text_flag(country)


# Re-applies the edited flag to the live preview, regenerates its text flag, and
# refreshes the inline preview. Called by every edit handler.
func _refresh() -> void:
	if selected_country == null:
		return
	flag.apply_flag(selected_country.flag)
	selected_country.text_flag = await generator.create_text_flag(selected_country.flag)
	_show_text_flag(selected_country)


# Shows a country's cached text flag in the label (it may be null until the
# generator has produced it).
func _show_text_flag(country: Country) -> void:
	text_flag_label.clear()
	if country != null and country.text_flag != null:
		text_flag_label.add_image(country.text_flag)
		text_flag_label.tooltip_text = country.base_name
		


func _on_ob_background_item_selected(index: int) -> void:
	if selected_country == null:
		return
	selected_country.flag.background_image = backgrounds.index_to_id[index]
	_refresh()


func _on_cpb_background_1_color_changed(color: Color) -> void:
	if selected_country == null:
		return
	selected_country.flag.background_color_1 = color
	_refresh()


func _on_cpb_background_2_color_changed(color: Color) -> void:
	if selected_country == null:
		return
	selected_country.flag.background_color_2 = color
	_refresh()


func _on_cpb_background_3_color_changed(color: Color) -> void:
	if selected_country == null:
		return
	selected_country.flag.background_color_3 = color
	_refresh()


func _on_ob_icon_1_item_selected(index: int) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_1_image = icons_1.index_to_id[index]
	_refresh()


func _on_cpb_icon_1_color_changed(color: Color) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_1_color = color
	_refresh()


func _on_hs_icon_1x_drag_ended(_value_changed: bool) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_1_offset.x = icon_1_x_slider.value / 100.0
	_refresh()


func _on_hs_icon_1y_drag_ended(_value_changed: bool) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_1_offset.y = icon_1_y_slider.value / 100.0
	_refresh()


func _on_ob_icon_2_item_selected(index: int) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_2_image = icons_2.index_to_id[index]
	_refresh()


func _on_cpb_icon_2_color_changed(color: Color) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_2_color = color
	_refresh()


func _on_hs_icon_2x_drag_ended(_value_changed: bool) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_2_offset.x = icon_2_x_slider.value / 100.0
	_refresh()


func _on_hs_icon_2y_drag_ended(_value_changed: bool) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_2_offset.y = icon_2_y_slider.value / 100.0
	_refresh()


func _on_button_button_up() -> void:
	export_requested.emit()


func _on_ob_icon_colored_item_selected(index: int) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_colored_image = icons_colored.index_to_id[index]
	_refresh()


func _on_hs_icon_colored_x_drag_ended(_value_changed: bool) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_colored_offset.x = icon_colored_x_slider.value / 100.0
	_refresh()


func _on_hs_icon_colored_y_drag_ended(_value_changed: bool) -> void:
	if selected_country == null:
		return
	selected_country.flag.icon_colored_offset.y = icon_colored_y_slider.value / 100.0
	_refresh()


func _on_b_clear_canton_button_up() -> void:
	if selected_country == null:
		return
	selected_country.flag.remove_canton()
	canton_x_slider.value = 0.0
	canton_y_slider.value = 0.0
	_refresh()


func _on_hs_canton_x_drag_ended(_value_changed: bool) -> void:
	if selected_country == null:
		return
	selected_country.flag.canton_size.x = canton_x_slider.value
	_refresh()


func _on_hs_canton_y_drag_ended(_value_changed: bool) -> void:
	if selected_country == null:
		return
	selected_country.flag.canton_size.y = canton_y_slider.value
	_refresh()


func _on_ob_canton_item_selected(index: int) -> void:
	if selected_country == null:
		return
	var country: Country = database.tag_to_country[countries.index_to_id[index]]
	selected_country.flag.set_canton_from_flag(country.flag)
	# set_canton_from_flag sizes the canton to the upper-hoist quarter; mirror
	# that onto the sliders so they don't read stale.
	canton_x_slider.value = selected_country.flag.canton_size.x
	canton_y_slider.value = selected_country.flag.canton_size.y
	_refresh()
