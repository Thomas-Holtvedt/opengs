extends Node2D

class_name CountryLabel

const FONT_SUPERSAMPLE: int = 2
const PATH_SAMPLES: int = 20

var intercept: float
var slope: float
var angle: float

var quad_a: float
var quad_b: float
var quad_c: float


func initial_data(country: Country) -> void:
	name = country.tag
	$Label.text = country.base_name
	$Label.modulate.a = 0.9
	#country.map_label = self

	#TEST
	$Path2D.text = country.base_name
	#TEST


func update_data(country: Country) -> void:
	var owned_cities: Array = country.owned_provinces.filter(
		func(p: Province) -> bool: return p.center != Vector2i(0, 0)
	)

	if owned_cities.is_empty() or country.tag == "NNN":
		$Label.hide()
		$Path2D.hide()
		return
	else:
		$Label.show()

	calculate_linear_regression(owned_cities)
	var city_min_x: float = min_x(owned_cities)
	var city_max_x: float = max_x(owned_cities)
	var point_start: Vector2 = Vector2(city_min_x, intercept + (slope * city_min_x))
	var point_end: Vector2 = Vector2(city_max_x, intercept + (slope * city_max_x))
	$Line2D.points = [point_start, point_end]

	#TEST
	$Path2D.curve.clear_points()
	if owned_cities.size() >= 3 and calculate_quadratic_regression(owned_cities):
		var x_lo: float = min(point_start.x, point_end.x)
		var x_hi: float = max(point_start.x, point_end.x)
		for i: int in range(PATH_SAMPLES + 1):
			var t: float = float(i) / PATH_SAMPLES
			var x: float = lerp(x_lo, x_hi, t)
			var y: float = quad_a + quad_b * x + quad_c * x * x
			$Path2D.curve.add_point(Vector2(x, y))
	else:
		$Path2D.curve.add_point(point_end)
		$Path2D.curve.add_point(point_start)
	#TEST

	angle = $Line2D.points[0].angle_to_point($Line2D.points[1])
	angle *= 180 / 3.14
	if angle > 90:
		angle -= 180
	if angle < -90:
		angle += 180

	var center: Vector2 = ($Line2D.points[0] + $Line2D.points[1]) / 2
	$Label.position = center

	$Label.size.y = 1
	var distance: float = $Line2D.points[0].distance_to($Line2D.points[1])
	var ratio: float = $Label.size.x / $Label.size.y

	var font_size: float = max(10, ((distance / 1.25) / (2 + ratio / 1.15)))
	#TEST
	$Path2D.label_settings.font_size = font_size #* FONT_SUPERSAMPLE
	#TEST
	$Label.add_theme_font_size_override("font_size", font_size * FONT_SUPERSAMPLE)
	$Label.scale = Vector2.ONE / FONT_SUPERSAMPLE
	$Label.size = Vector2(1, 1)
	$Label.pivot_offset.x = $Label.get_minimum_size().x / 2.0
	$Label.pivot_offset.y = $Label.get_minimum_size().y / 2.0
	$Label.position.x -= $Label.get_minimum_size().x / 2.0
	$Label.position.y -= $Label.get_minimum_size().y / 2.0

	$Label.rotation_degrees = angle


func calculate_linear_regression(points: Array) -> void:
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

	slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x_squared - sum_x * sum_x)
	intercept = (sum_y - slope * sum_x) / n


func calculate_quadratic_regression(points: Array) -> bool:
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
		return false

	var det_a: float = sy * (sx2 * sx4 - sx3 * sx3) \
			- sx * (sxy * sx4 - sx3 * sx2y) \
			+ sx2 * (sxy * sx3 - sx2 * sx2y)
	var det_b: float = n * (sxy * sx4 - sx3 * sx2y) \
			- sy * (sx * sx4 - sx3 * sx2) \
			+ sx2 * (sx * sx2y - sxy * sx2)
	var det_c: float = n * (sx2 * sx2y - sxy * sx3) \
			- sx * (sx * sx2y - sxy * sx2) \
			+ sy * (sx * sx3 - sx2 * sx2)

	quad_a = det_a / det
	quad_b = det_b / det
	quad_c = det_c / det
	return true


func min_x(cities: Array) -> float:
	var x: float = 0.0
	for city: Province in cities:
		if city.center.x > x:
			x = city.center.x
	return x


func max_x(cities: Array) -> float:
	var x: float = 100000.0
	for city: Province in cities:
		if city.center.x < x:
			x = city.center.x
	return x
