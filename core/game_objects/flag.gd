extends Resource
class_name Flag

var id: String = "temp"
var background_image: String = "plain"
var background_color_1: Color = Color(0.0, 0.0, 0.0, 1.0)
var background_color_2: Color = Color(0.0, 0.0, 0.0, 1.0)
var background_color_3: Color = Color(0.0, 0.0, 0.0, 1.0)

var icon_1_image: String = "no_icon"
var icon_1_color: Color = Color(0.0, 0.0, 0.0, 1.0)
var icon_1_offset: Vector2 = Vector2.ZERO

var icon_2_image: String = "no_icon"
var icon_2_color: Color = Color(0.0, 0.0, 0.0, 1.0)
var icon_2_offset: Vector2 = Vector2.ZERO

var icon_colored_image: String = "no_icon"
var icon_colored_offset: Vector2 = Vector2.ZERO

# Canton: a mini-flag composited into the upper-hoist corner.
var canton_size: Vector2 = Vector2.ZERO

var canton_background_image: String = "plain"
var canton_background_color_1: Color = Color(0.0, 0.0, 0.0, 1.0)
var canton_background_color_2: Color = Color(0.0, 0.0, 0.0, 1.0)
var canton_background_color_3: Color = Color(0.0, 0.0, 0.0, 1.0)

var canton_icon_1_image: String = "no_icon"
var canton_icon_1_color: Color = Color(0.0, 0.0, 0.0, 1.0)
var canton_icon_1_offset: Vector2 = Vector2.ZERO

var canton_icon_2_image: String = "no_icon"
var canton_icon_2_color: Color = Color(0.0, 0.0, 0.0, 1.0)
var canton_icon_2_offset: Vector2 = Vector2.ZERO

var canton_icon_colored_image: String = "no_icon"
var canton_icon_colored_offset: Vector2 = Vector2.ZERO

# Build this flag's canton from another flag
func set_canton_from_flag(flag_input: Flag) -> void:
	if flag_input == null:
		push_warning("set_canton_from_flag called with a null flag")
		return
	self.canton_size = Vector2(0.5, 0.5)
	self.canton_background_image = flag_input.background_image
	self.canton_background_color_1 = flag_input.background_color_1
	self.canton_background_color_2 = flag_input.background_color_2
	self.canton_background_color_3 = flag_input.background_color_3
	self.canton_icon_1_image = flag_input.icon_1_image
	self.canton_icon_1_color = flag_input.icon_1_color
	self.canton_icon_1_offset = flag_input.icon_1_offset
	self.canton_icon_2_image = flag_input.icon_2_image
	self.canton_icon_2_color = flag_input.icon_2_color
	self.canton_icon_2_offset = flag_input.icon_2_offset
	self.canton_icon_colored_image = flag_input.icon_colored_image
	self.canton_icon_colored_offset = flag_input.icon_colored_offset


# Remove the canton: reset every canton_ field to its default
func remove_canton() -> void:
	self.canton_size = Vector2.ZERO
	self.canton_background_image = "plain"
	self.canton_background_color_1 = Color(0.0, 0.0, 0.0, 1.0)
	self.canton_background_color_2 = Color(0.0, 0.0, 0.0, 1.0)
	self.canton_background_color_3 = Color(0.0, 0.0, 0.0, 1.0)
	self.canton_icon_1_image = "no_icon"
	self.canton_icon_1_color = Color(0.0, 0.0, 0.0, 1.0)
	self.canton_icon_1_offset = Vector2.ZERO
	self.canton_icon_2_image = "no_icon"
	self.canton_icon_2_color = Color(0.0, 0.0, 0.0, 1.0)
	self.canton_icon_2_offset = Vector2.ZERO
	self.canton_icon_colored_image = "no_icon"
	self.canton_icon_colored_offset = Vector2.ZERO
