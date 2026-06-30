extends Resource
class_name FlagConverter

var history_data: Dictionary = {}

func _init(flag: Flag) -> void:
	history_data["background_image"] = flag.background_image
	history_data["background_color_1"] = [flag.background_color_1.r, flag.background_color_1.g, flag.background_color_1.b]
	history_data["background_color_2"] = [flag.background_color_2.r, flag.background_color_2.g, flag.background_color_2.b]
	history_data["background_color_3"] = [flag.background_color_3.r, flag.background_color_3.g, flag.background_color_3.b]
	history_data["icon_1_image"] = flag.icon_1_image
	history_data["icon_1_color"] = [flag.icon_1_color.r, flag.icon_1_color.g, flag.icon_1_color.b]
	history_data["icon_1_offset"] = [flag.icon_1_offset.x, flag.icon_1_offset.y]
	history_data["icon_2_image"] = flag.icon_2_image
	history_data["icon_2_color"] = [flag.icon_2_color.r, flag.icon_2_color.g, flag.icon_2_color.b]
	history_data["icon_2_offset"] = [flag.icon_2_offset.x, flag.icon_2_offset.y]
	history_data["icon_colored_image"] = flag.icon_colored_image
	history_data["icon_colored_offset"] = [flag.icon_colored_offset.x, flag.icon_colored_offset.y]

	# Only serialize the canton when one exists, so cantonless flags stay clean.
	if flag.canton_size != Vector2.ZERO:
		history_data["canton_size"] = [flag.canton_size.x, flag.canton_size.y]
		history_data["canton_background_image"] = flag.canton_background_image
		history_data["canton_background_color_1"] = [flag.canton_background_color_1.r, flag.canton_background_color_1.g, flag.canton_background_color_1.b]
		history_data["canton_background_color_2"] = [flag.canton_background_color_2.r, flag.canton_background_color_2.g, flag.canton_background_color_2.b]
		history_data["canton_background_color_3"] = [flag.canton_background_color_3.r, flag.canton_background_color_3.g, flag.canton_background_color_3.b]
		history_data["canton_icon_1_image"] = flag.canton_icon_1_image
		history_data["canton_icon_1_color"] = [flag.canton_icon_1_color.r, flag.canton_icon_1_color.g, flag.canton_icon_1_color.b]
		history_data["canton_icon_1_offset"] = [flag.canton_icon_1_offset.x, flag.canton_icon_1_offset.y]
		history_data["canton_icon_2_image"] = flag.canton_icon_2_image
		history_data["canton_icon_2_color"] = [flag.canton_icon_2_color.r, flag.canton_icon_2_color.g, flag.canton_icon_2_color.b]
		history_data["canton_icon_2_offset"] = [flag.canton_icon_2_offset.x, flag.canton_icon_2_offset.y]
		history_data["canton_icon_colored_image"] = flag.canton_icon_colored_image
		history_data["canton_icon_colored_offset"] = [flag.canton_icon_colored_offset.x, flag.canton_icon_colored_offset.y]
