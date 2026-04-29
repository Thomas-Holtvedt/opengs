extends Node2D

class_name CountryLabel

var intercept: float
var slope: float
var angle: float

func initial_data(country: Country) -> void:
	name = country.tag
	$Label.text = country.base_name
	$Label.modulate.a = 0.9
	#country.map_label = self

func update_data(country: Country) -> void:
	var owned_cites = country.owned_provinces.filter(func(p): return p.center != Vector2i(0,0))
	
	if owned_cites.is_empty() or country.tag == "NNN":
		$Label.hide()
		return
	else:
		$Label.show()
	
	calculate_linear_regression(owned_cites)
	var city_min_x: float = min_x(owned_cites)
	var city_max_x: float = max_x(owned_cites)
	var point_start = Vector2(city_min_x, intercept + (slope * city_min_x))
	var point_end = Vector2(city_max_x, intercept + (slope * city_max_x))
	$Line2D.points = [point_start, point_end]
	
	angle = $Line2D.points[0].angle_to_point($Line2D.points[1])
	angle *= 180/3.14
	if angle > 90:
		angle -= 180
	if angle < -90:
		angle += 180
		
	var center: Vector2 = ($Line2D.points[0]+$Line2D.points[1])/2
	$Label.position = center
	
	$Label.size.y = 1
	var distance = $Line2D.points[0].distance_to($Line2D.points[1])
	var ratio = $Label.size.x / $Label.size.y
	
	var font_size = max(10, ((distance/1.25) / (2 + ratio/1.15)))
	$Label.add_theme_font_size_override("font_size", font_size)
	$Label.size = Vector2(1,1)
	$Label.pivot_offset.x = $Label.get_minimum_size().x / 2.0
	$Label.pivot_offset.y = $Label.get_minimum_size().y / 2.0
	$Label.position.x -= $Label.get_minimum_size().x / 2.0
	$Label.position.y -= $Label.get_minimum_size().y / 2.0
	
	$Label.rotation_degrees = angle
	
func calculate_linear_regression(points: Array):
	var n = points.size()
	var sum_x = 0.0
	var sum_y = 0.0
	var sum_xy = 0.0
	var sum_x_squared = 0.0
	
	for point in points:
		var x = point.center.x
		var y = point.center.y
		sum_x += x
		sum_y += y
		sum_xy += x * y
		sum_x_squared += x * x
		
	slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x_squared - sum_x * sum_x)
	intercept = (sum_y - slope * sum_x) / n

func min_x(cities: Array) -> float:
	var x = 0.0
	for city: Province in cities:
		if city.center.x > x:
			x = city.center.x
	return x

func max_x(cities: Array) -> float:
	var x = 100000.0
	for city: Province in cities:
		if city.center.x < x:
			x = city.center.x
	return x
