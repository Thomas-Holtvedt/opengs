extends Node3D

class_name CountryLabel3D

const FONT_FILL_RATIO: float = 1.6
const MIN_FONT_SIZE: int = 10
# Plane spans 500x250 world units mapped to a 5000x2500 lookup image,
# i.e. 1 pixel = 0.1 world units, centred on origin.
const PIXEL_TO_WORLD: float = 0.1
const PROVINCE_IMAGE_HALF_SIZE: Vector2 = Vector2(2500.0, 1250.0)
# Lift the text slightly so it doesn't z-fight the map plane.
const HEIGHT_OFFSET: float = 0.05

@export var label_settings: LabelSettings

var country_name: String = ""


func initial_data(country: Country) -> void:
	name = country.tag
	country_name = country.base_name


func update_data(country: Country) -> void:
	country_name = country.base_name
	for child in get_children():
		child.queue_free()

	var pixel_points: PackedVector2Array = CountryLabel.compute_curve_points(country)
	if pixel_points.size() < 2:
		return

	var curve: Curve3D = Curve3D.new()
	for p: Vector2 in pixel_points:
		curve.add_point(_pixel_to_world(p))

	var path_length_world: float = curve.get_baked_length()
	if path_length_world <= 0.0 or label_settings == null or label_settings.font == null:
		return

	var name_length: int = max(1, country_name.length())
	# path_length_world / PIXEL_TO_WORLD gives the equivalent pixel-space length
	# used by the 2D version, so the formula stays consistent across both.
	var font_size: int = max(
		MIN_FONT_SIZE,
		int(path_length_world / PIXEL_TO_WORLD / name_length * FONT_FILL_RATIO),
	)
	var outline_size: int = max(1, int(font_size * 0.04))
	var font: Font = label_settings.font

	var widths: PackedFloat32Array = PackedFloat32Array()
	var total_width_world: float = 0.0
	for i: int in range(country_name.length()):
		var ch_unicode: int = country_name.unicode_at(i)
		var w_world: float = font.get_char_size(ch_unicode, font_size).x * PIXEL_TO_WORLD
		widths.append(w_world)
		total_width_world += w_world

	var offset: float = (path_length_world - total_width_world) * 0.5

	for i: int in range(country_name.length()):
		var advance: float = widths[i]
		var glyph_offset: float = clamp(
			offset + advance * 0.5, 0.0, path_length_world
		)
		var pos: Vector3 = curve.sample_baked(glyph_offset)
		pos.y += HEIGHT_OFFSET

		var ahead: float = min(glyph_offset + 0.01, path_length_world)
		var behind: float = max(glyph_offset - 0.01, 0.0)
		var tangent: Vector3 = curve.sample_baked(ahead) - curve.sample_baked(behind)
		if tangent.length_squared() < 1e-12:
			tangent = Vector3.RIGHT
		tangent = tangent.normalized()

		# Lay flat on XZ plane: local X follows the tangent, local Z is world up
		# so the text faces the camera looking down at the map.
		var local_x: Vector3 = tangent
		var local_z: Vector3 = Vector3.UP
		var local_y: Vector3 = local_z.cross(local_x).normalized()

		var glyph: Label3D = Label3D.new()
		glyph.text = country_name[i]
		glyph.font = font
		glyph.font_size = font_size
		glyph.outline_size = outline_size
		glyph.outline_modulate = label_settings.outline_color
		glyph.modulate = label_settings.font_color
		glyph.pixel_size = PIXEL_TO_WORLD
		glyph.shaded = false
		glyph.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		glyph.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.transform = Transform3D(Basis(local_x, local_y, local_z), pos)
		add_child(glyph)

		offset += advance


static func _pixel_to_world(p: Vector2) -> Vector3:
	return Vector3(
		(p.x - PROVINCE_IMAGE_HALF_SIZE.x) * PIXEL_TO_WORLD,
		0.0,
		(p.y - PROVINCE_IMAGE_HALF_SIZE.y) * PIXEL_TO_WORLD,
	)
