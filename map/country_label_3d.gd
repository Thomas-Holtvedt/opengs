extends Node3D

class_name CountryLabel3D

const PATH_SAMPLES: int = 20
const FONT_FILL_RATIO: float = 1.6
const MIN_FONT_SIZE: int = 10
const MAX_SAGITTA_RATIO: float = 0.15
# Plane spans 500x250 world units mapped to a 5000x2500 lookup image,
# i.e. 1 pixel = 0.1 world units, centred on origin.
const PIXEL_TO_WORLD: float = 0.1
const PROVINCE_IMAGE_HALF_SIZE: Vector2 = Vector2(2500.0, 1250.0)
# Lift the text slightly so it doesn't z-fight the map plane.
const HEIGHT_OFFSET: float = 0.05

@export var label_settings: LabelSettings

var country_name: String = ""


func setup(country: Country) -> void:
	name = country.tag
	country_name = country.base_name


func refresh(country: Country) -> void:
	country_name = country.base_name
	for child: Node in get_children():
		child.queue_free()

	var pixel_points: PackedVector2Array = _compute_curve_points(country)
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
	# used by the old 2D version, so the formula keeps its tuning.
	var font_size: int = max(
		MIN_FONT_SIZE,
		int(path_length_world / PIXEL_TO_WORLD / name_length * FONT_FILL_RATIO),
	)
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
		glyph.outline_size = 0  # Label3D defaults to 12; 0 disables the outline.
		glyph.modulate = label_settings.font_color
		glyph.pixel_size = PIXEL_TO_WORLD
		glyph.shaded = false
		glyph.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# Keep alpha_cut at its default (ALPHA_CUT_DISABLED): the opaque pre-pass mode
		# suppresses the Label3D outline, and these glyphs lie flat above the map with
		# nothing transparent to sort against.
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


# --- Label curve fitting (in lookup-image pixel space) ---

# Fits a gentle curve through the country's province centers for the text to follow.
static func _compute_curve_points(country: Country) -> PackedVector2Array:
	var owned_cities: Array = country.owned_provinces.filter(
		func(p: Province) -> bool: return p.center != Vector2i(0, 0)
	)
	if owned_cities.size() < 2 or country.tag == "NNN":
		return PackedVector2Array()

	var x_lo: float = INF
	var x_hi: float = -INF
	for city: Province in owned_cities:
		x_lo = min(x_lo, float(city.center.x))
		x_hi = max(x_hi, float(city.center.x))

	var points: PackedVector2Array = PackedVector2Array()
	var quad: Variant = null
	if owned_cities.size() >= 3:
		quad = _calculate_quadratic_regression(owned_cities)

	if quad != null:
		var mean_x: float = 0.0
		for city: Province in owned_cities:
			mean_x += float(city.center.x)
		mean_x /= float(owned_cities.size())

		# Recenter OLS coefficients around mean_x so c controls only curvature.
		var y_at_mean: float = quad.x + quad.y * mean_x + quad.z * mean_x * mean_x
		var slope_at_mean: float = quad.y + 2.0 * quad.z * mean_x
		var c: float = quad.z

		var width: float = x_hi - x_lo
		var was_clamped: bool = false
		if width > 0.0:
			var max_c: float = 4.0 * MAX_SAGITTA_RATIO / width
			var clamped_c: float = clamp(c, -max_c, max_c)
			if clamped_c != c:
				c = clamped_c
				was_clamped = true

		if was_clamped:
			# OLS coefficients were extreme; re-anchor at the city centroid
			# using the linear regression slope.
			var mean_y: float = 0.0
			for city: Province in owned_cities:
				mean_y += float(city.center.y)
			mean_y /= float(owned_cities.size())
			var line: Vector2 = _calculate_linear_regression(owned_cities)
			y_at_mean = mean_y
			slope_at_mean = line.y

		for i: int in range(PATH_SAMPLES + 1):
			var t: float = float(i) / PATH_SAMPLES
			var x: float = lerp(x_lo, x_hi, t)
			var u: float = x - mean_x
			var y: float = y_at_mean + slope_at_mean * u + c * u * u
			points.append(Vector2(x, y))
	else:
		var line: Vector2 = _calculate_linear_regression(owned_cities)
		points.append(Vector2(x_lo, line.x + line.y * x_lo))
		points.append(Vector2(x_hi, line.x + line.y * x_hi))

	return points


# Returns Vector2(intercept, slope) for y = intercept + slope * x.
static func _calculate_linear_regression(points: Array) -> Vector2:
	var n: int = points.size()
	var sum_x: float = 0.0
	var sum_y: float = 0.0
	var sum_xy: float = 0.0
	var sum_x_squared: float = 0.0

	for point: Province in points:
		var x: float = point.center.x
		var y: float = point.center.y
		sum_x += x
		sum_y += y
		sum_xy += x * y
		sum_x_squared += x * x

	var slope: float = (n * sum_xy - sum_x * sum_y) / (n * sum_x_squared - sum_x * sum_x)
	var intercept: float = (sum_y - slope * sum_x) / n
	return Vector2(intercept, slope)


# Returns Vector3(a, b, c) for y = a + b*x + c*x^2, or null if the system is degenerate.
static func _calculate_quadratic_regression(points: Array) -> Variant:
	var n: float = float(points.size())
	var sx: float = 0.0
	var sx2: float = 0.0
	var sx3: float = 0.0
	var sx4: float = 0.0
	var sy: float = 0.0
	var sxy: float = 0.0
	var sx2y: float = 0.0

	for point: Province in points:
		var x: float = point.center.x
		var y: float = point.center.y
		var x2: float = x * x
		sx += x
		sx2 += x2
		sx3 += x2 * x
		sx4 += x2 * x2
		sy += y
		sxy += x * y
		sx2y += x2 * y

	# Cramer's rule on the 3x3 normal-equation matrix for y = a + b*x + c*x^2.
	var det: float = n * (sx2 * sx4 - sx3 * sx3) \
			- sx * (sx * sx4 - sx3 * sx2) \
			+ sx2 * (sx * sx3 - sx2 * sx2)
	if absf(det) < 1e-9:
		return null

	var det_a: float = sy * (sx2 * sx4 - sx3 * sx3) \
			- sx * (sxy * sx4 - sx3 * sx2y) \
			+ sx2 * (sxy * sx3 - sx2 * sx2y)
	var det_b: float = n * (sxy * sx4 - sx3 * sx2y) \
			- sy * (sx * sx4 - sx3 * sx2) \
			+ sx2 * (sx * sx2y - sxy * sx2)
	var det_c: float = n * (sx2 * sx2y - sxy * sx3) \
			- sx * (sx * sx2y - sxy * sx2) \
			+ sy * (sx * sx3 - sx2 * sx2)

	return Vector3(det_a / det, det_b / det, det_c / det)
