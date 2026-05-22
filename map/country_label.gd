extends Node2D

class_name CountryLabel

const PATH_SAMPLES: int = 20
const FONT_FILL_RATIO: float = 1.6
const MIN_FONT_SIZE: int = 10
const MAX_SAGITTA_RATIO: float = 0.15


func initial_data(country: Country) -> void:
	name = country.tag
	$Path2D.text = country.base_name
	modulate.a = 0.9


func update_data(country: Country) -> void:
	var points: PackedVector2Array = compute_curve_points(country)
	if points.is_empty():
		$Path2D.hide()
		return
	$Path2D.show()

	$Path2D.curve.clear_points()
	for p: Vector2 in points:
		$Path2D.curve.add_point(p)

	var path_length: float = $Path2D.curve.get_baked_length()
	var name_length: int = max(1, country.base_name.length())
	var font_size: int = max(
		MIN_FONT_SIZE, int(path_length / name_length * FONT_FILL_RATIO)
	)
	$Path2D.label_settings.font_size = font_size
	$Path2D.label_settings.outline_size = max(1, int(font_size * 0.04))
	$Path2D.label_settings.outline_color = Color("BLACK")


static func compute_curve_points(country: Country) -> PackedVector2Array:
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
		quad = calculate_quadratic_regression(owned_cities)

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
			var line: Vector2 = calculate_linear_regression(owned_cities)
			y_at_mean = mean_y
			slope_at_mean = line.y

		for i: int in range(PATH_SAMPLES + 1):
			var t: float = float(i) / PATH_SAMPLES
			var x: float = lerp(x_lo, x_hi, t)
			var u: float = x - mean_x
			var y: float = y_at_mean + slope_at_mean * u + c * u * u
			points.append(Vector2(x, y))
	else:
		var line: Vector2 = calculate_linear_regression(owned_cities)
		points.append(Vector2(x_lo, line.x + line.y * x_lo))
		points.append(Vector2(x_hi, line.x + line.y * x_hi))

	return points


static func calculate_linear_regression(points: Array) -> Vector2:
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


static func calculate_quadratic_regression(points: Array) -> Variant:
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
