@tool
extends Path2D


@export var text: String:
	set(value):
		if text != value:
			text = value
			queue_redraw()


@export var debug_draw: bool = false:
	set(value):
		debug_draw = value
		queue_redraw()

@export var debug_color: Color = Color(1, 0, 1, 0.8):
	set(value):
		debug_color = value
		queue_redraw()


@export var label_settings: LabelSettings:
	set(value):
		if is_instance_valid(label_settings) and label_settings.changed.is_connected(queue_redraw):
			label_settings.changed.disconnect(queue_redraw)

		label_settings = value

		if is_instance_valid(label_settings):
			label_settings.changed.connect(queue_redraw)


var _line: TextLine = TextLine.new()


func _draw() -> void:
	if curve == null or curve.point_count < 2:
		return

	var font: Font = ThemeDB.fallback_font
	var font_size: int = ThemeDB.fallback_font_size
	var font_color: Color = Color.WHITE
	var outline_size: int = 0
	var outline_color: Color = Color(0, 0, 0, 1)

	if is_instance_valid(label_settings):
		font = label_settings.font
		font_size = label_settings.font_size
		font_color = label_settings.font_color
		outline_size = label_settings.outline_size
		outline_color = label_settings.outline_color

	_line.clear()
	_line.add_string(text, font, font_size)

	var text_server: TextServer = TextServerManager.get_primary_interface()
	var glyphs: Array = text_server.shaped_text_get_glyphs(_line.get_rid())

	if debug_draw:
		var baked: PackedVector2Array = curve.get_baked_points()
		if baked.size() >= 2:
			draw_polyline(baked, debug_color, 2.0)

	var text_width: float = _line.get_size().x
	var curve_length: float = curve.get_baked_length()
	# Shift the baseline so the visual middle of the glyph row sits on the curve.
	var baseline_offset: float = (_line.get_line_ascent() - _line.get_line_descent()) * 0.5
	var glyph_pos: Vector2 = Vector2(0.0, baseline_offset)

	var offset: float = (curve_length - text_width) * 0.5
	for glyph_data: Dictionary in glyphs:
		var trans: Transform2D = curve.sample_baked_with_rotation(offset)
		draw_set_transform_matrix(trans)
		if outline_size > 0 and outline_color.a > 0.0:
			text_server.font_draw_glyph_outline(
				glyph_data["font_rid"],
				get_canvas_item(),
				font_size,
				outline_size,
				glyph_pos,
				glyph_data["index"],
				outline_color,
			)
		text_server.font_draw_glyph(
			glyph_data["font_rid"],
			get_canvas_item(),
			font_size,
			glyph_pos,
			glyph_data["index"],
			font_color,
		)
		offset += glyph_data.get("advance", 0.0)
