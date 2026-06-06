extends Node3D
class_name CameraController

signal far_map(is_far: bool)

# Nodes
@onready var camera: Camera3D = $CameraSocket/Camera3D
@onready var camera_socket: Node3D = $CameraSocket

@export_category("Camera Motion Control")
@export var camera_can_process: bool = true
@export var camera_can_move: bool = true
@export var camera_can_zoom: bool = true
@export var camera_can_rotate_by_mouse_offset: bool = true
@export var camera_can_rotate_by_keys: bool = true
@export var camera_can_automatic_pan: bool = false

@export_category("Camera Move Settings")
@export var camera_move_acceleration_speed_factor: Vector3 = Vector3(0.5, 0.5, 0.5)
@export var camera_move_velocity_half_life: float = 0.15

@export var camera_position_min_bound: Vector3 = Vector3(-INF, -INF, -INF)
@export var camera_position_max_bound: Vector3 = Vector3(INF, INF, INF)

@export_category("Camera Automatic Pan Settings")
@export var camera_automatic_pan_acceleration_speed_factor: float = 0.5
@export var camera_automatic_pan_velocity_half_life: float = 0.06
@export_range(0, 32, 4) var camera_automatic_pan_margin: int = 16

@export_category("Camera Rotation Settings")
@export var camera_rotate_mouse_acceleration_speed_factor: Vector2 = Vector2(0.2, 0.2)
@export var camera_rotate_mouse_velocity_half_life: float = 0.00

@export var camera_rotate_keys_acceleration_speed_factor: Vector2 = Vector2(0.6, 0.6)
@export var camera_rotate_keys_velocity_half_life: float = 0.15

@export var camera_rotation_min_bound: Vector2 = Vector2(deg_to_rad(-90), -INF)
@export var camera_rotation_max_bound: Vector2 = Vector2(deg_to_rad(-15), INF)

@export_category("Camera Zoom Settings")
@export var camera_zoom_acceleration_speed_factor: float = 3.0
@export var camera_zoom_velocity_half_life: float = 0.15
@export var camera_zoom_min_bound: float = 10.0
@export var camera_zoom_max_bound: float = 1000.0
@export var camera_zoom_threshold: float = 50.0

@export_category("Camera Move-To Settings")
@export var camera_move_to_speed: float = 200.0
@export var camera_move_to_transition: Tween.TransitionType = Tween.TRANS_SINE
@export var camera_move_to_ease: Tween.EaseType = Tween.EASE_OUT



# Control Variables
class CameraTranslationCalculator extends PVACalculator: # Base class for camera movement and panning
	func get_value() -> Vector3:
		return global.position

	func set_value(val) -> void:
		global.position = val

	@warning_ignore("unused_parameter")
	func on_input_event(event: InputEvent) -> void:
		pass

	func update_velocity() -> void:
		# Share zoom-scaled translation behavior for movement and edge panning.
		var safe_zoom = global.camera_zoom._clamp_value(global.camera_zoom.get_value())
		self.velocity += self.get_final_frame_acceleration() * self.acceleration_speed_factor * safe_zoom
		self.frame_acceleration = self.starting_value

# Camera Movement
class MovementCalculator extends CameraTranslationCalculator:
	func get_final_frame_acceleration() -> Vector3:
		if Input.is_action_pressed("camera_move_forward"): self.frame_acceleration -= global.transform.basis.z
		if Input.is_action_pressed("camera_move_backward"): self.frame_acceleration += global.transform.basis.z
		if Input.is_action_pressed("camera_move_right"): self.frame_acceleration += global.transform.basis.x
		if Input.is_action_pressed("camera_move_left"): self.frame_acceleration -= global.transform.basis.x
		self.frame_acceleration = self.frame_acceleration.normalized()
		return self.frame_acceleration

var camera_move: MovementCalculator


# Camera Panning by screen edges
class AutomaticPanCalculator extends CameraTranslationCalculator:
	func get_final_frame_acceleration() -> Vector3:
		var viewport_current:Viewport = global.get_viewport()
		var viewport_visible_rectangle:Rect2i = Rect2i(viewport_current.get_visible_rect())
		var viewport_size:Vector2i = viewport_visible_rectangle.size
		var current_mouse_position:Vector2 = viewport_current.get_mouse_position()
		var margin:float = global.camera_automatic_pan_margin

		if margin <= 0:
			return Vector3.ZERO

		var pan_direction:Vector2 = Vector2.ZERO
		if current_mouse_position.x < margin:
			pan_direction.x = -1
		elif current_mouse_position.x > viewport_size.x - margin:
			pan_direction.x = 1

		if current_mouse_position.y < margin:
			pan_direction.y = -1
		elif current_mouse_position.y > viewport_size.y - margin:
			pan_direction.y = 1

		return global.transform.basis.x * pan_direction.x + global.transform.basis.z * pan_direction.y

var camera_automatic_pan: AutomaticPanCalculator


# Camera Rotation to Mouse Offsets on X and Y
class MouseRotationCalculator extends PVACalculator:
	var mouse_last_position = null

	func get_value() -> Vector2:
		return Vector2(global.camera_socket.rotation.x, global.rotation.y)

	func set_value(val) -> void:
		global.camera_socket.rotation.x = val.x
		global.rotation.y = val.y

	func on_input_event(event: InputEvent) -> void:
		if event.is_action_pressed("camera_rotate_mouse"):
			self.mouse_last_position = global.get_viewport().get_mouse_position()
		elif event.is_action_released("camera_rotate_mouse"):
			self.mouse_last_position = null

	func get_final_frame_acceleration() -> Vector2:
		if self.mouse_last_position == null:
			return Vector2.ZERO
		var mouse_offset: Vector2 = global.get_viewport().get_mouse_position()
		mouse_offset -= self.mouse_last_position
		self.mouse_last_position = global.get_viewport().get_mouse_position()
		self.frame_acceleration.x -= mouse_offset.y # This invertion is intentional
		self.frame_acceleration.y -= mouse_offset.x
		return self.frame_acceleration

var camera_rotate_mouse: MouseRotationCalculator


# Camera Rotation to Keys on X and Y
class KeysRotationCalculator extends PVACalculator:
	func get_value() -> Vector2:
		return Vector2(global.camera_socket.rotation.x, global.rotation.y)

	func set_value(val) -> void:
		global.camera_socket.rotation.x = val.x
		global.rotation.y = val.y

	@warning_ignore("unused_parameter")
	func on_input_event(event: InputEvent) -> void:
		pass

	func get_final_frame_acceleration() -> Vector2:
		if Input.is_action_pressed("camera_rotate_right"):
			self.frame_acceleration += Vector2(0, 1)
		elif Input.is_action_pressed("camera_rotate_left"):
			self.frame_acceleration += Vector2(0, -1)
		if Input.is_action_pressed("camera_rotate_up"):
			self.frame_acceleration += Vector2(-1, 0)
		elif Input.is_action_pressed("camera_rotate_down"):
			self.frame_acceleration += Vector2(1, 0)
		return self.frame_acceleration

var camera_rotate_keys: KeysRotationCalculator


# Camera Zooming
class ZoomCalculator extends PVACalculator:
	func get_value() -> float:
		return global.camera.position.z

	func set_value(val: float) -> void:
		global.camera.position.z = val

	func on_input_event(event: InputEvent) -> void:
		if event.is_action_pressed("camera_zoom_in"):
			self.frame_acceleration -= 1

		elif  event.is_action_pressed("camera_zoom_out"):
			self.frame_acceleration += 1
		if event is InputEventMagnifyGesture:
			self.frame_acceleration += (1-event.factor)

	func get_final_frame_acceleration() -> float:
		return self.frame_acceleration

	func update_velocity() -> void:
		# Scale step by current zoom: closer = smaller increments, farther = larger.
		# An in-tick reduces z by fraction f = factor * half_life / ln(2); a symmetric
		# out-tick must therefore use multiplier 1/(1-f) so successive in+out cancel.
		var safe_zoom = _clamp_value(get_value())
		var accel = self.get_final_frame_acceleration()
		if accel > 0:
			var in_fraction = clampf(self.acceleration_speed_factor * self.velocity_half_life / log(2), 0.0, 0.95)
			accel /= (1.0 - in_fraction)
		self.velocity += accel * self.acceleration_speed_factor * safe_zoom
		self.frame_acceleration = self.starting_value

var camera_zoom: ZoomCalculator


func _ready() -> void:
	camera_move = MovementCalculator.new(
		self,
		camera_move_acceleration_speed_factor,
		camera_move_velocity_half_life,
		camera_position_min_bound,
		camera_position_max_bound,
		Vector3.ZERO,
	)
	camera_automatic_pan = AutomaticPanCalculator.new(
		self,
		camera_automatic_pan_acceleration_speed_factor,
		camera_automatic_pan_velocity_half_life,
		camera_position_min_bound,
		camera_position_max_bound,
		Vector3.ZERO,
	)
	camera_rotate_mouse = MouseRotationCalculator.new(
		self,
		camera_rotate_mouse_acceleration_speed_factor,
		camera_rotate_mouse_velocity_half_life,
		camera_rotation_min_bound,
		camera_rotation_max_bound,
		Vector2.ZERO,
	)
	camera_rotate_keys = KeysRotationCalculator.new(
		self,
		camera_rotate_keys_acceleration_speed_factor,
		camera_rotate_keys_velocity_half_life,
		camera_rotation_min_bound,
		camera_rotation_max_bound,
		Vector2.ZERO,
	)
	camera_zoom = ZoomCalculator.new(
		self,
		camera_zoom_acceleration_speed_factor,
		camera_zoom_velocity_half_life,
		camera_zoom_min_bound,
		camera_zoom_max_bound,
		0.0,
	)


func _process(delta: float) -> void:
	if !camera_can_process: return

	var text_focused: bool = _is_text_input_focused()

	if camera_can_move and not text_focused:
		camera_move.process(delta)
	if camera_can_zoom:
		camera_zoom.process(delta)
	if camera_can_rotate_by_mouse_offset:
		camera_rotate_mouse.process(delta)
	if camera_can_rotate_by_keys and not text_focused:
		camera_rotate_keys.process(delta)
	if camera_can_automatic_pan:
		camera_automatic_pan.process(delta)


func _is_text_input_focused() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Exit"):
		get_tree().quit()

	if event.is_action_pressed("province_select"):
		shoot_ray(event)

	if camera_can_move:
		camera_move.on_input_event(event)
	if camera_can_zoom:
		camera_zoom.on_input_event(event)
		if camera.position.z <= camera_zoom_threshold:
			far_map.emit(false)
		else:
			far_map.emit(true)
			
	if camera_can_rotate_by_mouse_offset:
		camera_rotate_mouse.on_input_event(event)
	if camera_can_rotate_by_keys:
		camera_rotate_keys.on_input_event(event)
	if camera_can_automatic_pan:
		camera_automatic_pan.on_input_event(event)


func shoot_ray(event: InputEvent) -> void:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_length = 2000
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * ray_length
	var space = get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.new()
	ray_query.from = from
	ray_query.to = to
	var raycast_result = space.intersect_ray(ray_query)
	if !raycast_result.is_empty():
		_on_province_click(Vector2(raycast_result.position.x, raycast_result.position.z), event)


@warning_ignore("unused_parameter")
func _on_province_click(world_pos: Vector2, event: InputEvent) -> void:
	pass


var _move_to_tween: Tween = null

func move_to(target: Vector2, multiplier: float = 1.0) -> void:
	if _move_to_tween != null and _move_to_tween.is_running():
		_move_to_tween.kill()
	var destination: Vector3 = Vector3(target.x, global_position.y, target.y)
	var distance: float = global_position.distance_to(destination)
	var speed: float = camera_move_to_speed * multiplier
	var duration: float = distance / speed if speed > 0.0 else 0.0
	_move_to_tween = create_tween()
	_move_to_tween.set_trans(camera_move_to_transition)
	_move_to_tween.set_ease(camera_move_to_ease)
	_move_to_tween.tween_property(self, "global_position", destination, duration)
