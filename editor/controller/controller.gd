extends Node3D
signal province_selected

# Nodes
@onready var camera: Camera3D = $CameraSocket/Camera3D
@onready var camera_socket: Node3D = $CameraSocket

@export_category("Camera Motion Control")
@export var camera_can_process := true
@export var camera_can_move := true
@export var camera_can_zoom := true
@export var camera_can_rotate_by_mouse_offset := true
@export var camera_can_rotate_by_keys := true
@export var camera_can_automatic_pan := false

@export_group("⚠️ Inspector Warning ⚠️")
@export_multiline var inspector_warning_note := """\
Remote/runtime Inspector edits of the properties below are temporary only.
Edit the scene node and save to persist changes.\
"""
@export_category("Camera Move Settings")
@export var camera_move_acceleration_speed_factor := Vector3(0.5, 0.5, 0.5)
@export var camera_move_velocity_half_life := 0.15

@export var camera_position_min_bound := Vector3(-INF, -INF, -INF)
@export var camera_position_max_bound := Vector3(INF, INF, INF)

@export_category("Camera Automatic Pan Settings")
@export var camera_automatic_pan_acceleration_speed_factor := 0.5
@export var camera_automatic_pan_velocity_half_life := 0.06
@export_range(0,32,4) var camera_automatic_pan_margin := 16

@export_category("Camera Rotation Settings")
@export var camera_rotate_mouse_acceleration_speed_factor := Vector2(0.2, 0.2)
@export var camera_rotate_mouse_velocity_half_life := 0.00

@export var camera_rotate_keys_acceleration_speed_factor := Vector2(0.6, 0.6)
@export var camera_rotate_keys_velocity_half_life := 0.15

@export var camera_rotation_min_bound := Vector2(deg_to_rad(-90), -INF)
@export var camera_rotation_max_bound := Vector2(deg_to_rad(-15), INF)

@export_category("Camera Zoom Settings")
@export var camera_zoom_acceleration_speed_factor := 300.0
@export var camera_zoom_velocity_half_life := 0.15
@export var camera_zoom_min_bound := 10.0
@export var camera_zoom_max_bound := 1000.0

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
	var touchpad_frame_acc:Vector2 = Vector2.ZERO
	
	@warning_ignore("unused_parameter")
	func on_input_event(event: InputEvent) -> void:
		pass # TODO: test if this works (no touchpad action registers as this on windows)
		#if event is InputEventPanGesture:
		#	self.touchpad_frame_acc = event.delta
	
	func get_final_frame_acceleration() -> Vector3:
		if Input.is_action_pressed("camera_move_forward"): self.frame_acceleration -= global.transform.basis.z
		if Input.is_action_pressed("camera_move_backward"): self.frame_acceleration += global.transform.basis.z
		if Input.is_action_pressed("camera_move_right"): self.frame_acceleration += global.transform.basis.x
		if Input.is_action_pressed("camera_move_left"): self.frame_acceleration -= global.transform.basis.x
		#self.frame_acceleration.x += self.touchpad_frame_acc.x # Disabled for now, couldn't be tested
		#self.frame_acceleration.z += self.touchpad_frame_acc.y
		self.touchpad_frame_acc = Vector2.ZERO # Reset touchpad movement each frame
		self.frame_acceleration = self.frame_acceleration.normalized()
		return self.frame_acceleration

var camera_move := MovementCalculator.new(
	self, # global_node
	camera_move_acceleration_speed_factor,
	camera_move_velocity_half_life,
	camera_position_min_bound,
	camera_position_max_bound,
	Vector3.ZERO,
)


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

var camera_automatic_pan := AutomaticPanCalculator.new(
	self, # global_node
	camera_automatic_pan_acceleration_speed_factor,
	camera_automatic_pan_velocity_half_life,
	camera_position_min_bound,
	camera_position_max_bound,
	Vector3.ZERO,
)


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
		var mouse_offset := global.get_viewport().get_mouse_position()
		mouse_offset -= self.mouse_last_position
		self.mouse_last_position = global.get_viewport().get_mouse_position()
		self.frame_acceleration.x -= mouse_offset.y # This invertion is intentional
		self.frame_acceleration.y -= mouse_offset.x
		return self.frame_acceleration

var camera_rotate_mouse := MouseRotationCalculator.new(
	self, # global_node
	camera_rotate_mouse_acceleration_speed_factor,
	camera_rotate_mouse_velocity_half_life,
	camera_rotation_min_bound,
	camera_rotation_max_bound,
	Vector2.ZERO,
)


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

var camera_rotate_keys := KeysRotationCalculator.new(
	self, # global_node
	camera_rotate_keys_acceleration_speed_factor,
	camera_rotate_keys_velocity_half_life,
	camera_rotation_min_bound,
	camera_rotation_max_bound,
	Vector2.ZERO,
)


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

var camera_zoom := ZoomCalculator.new(
	self, # global_node
	camera_zoom_acceleration_speed_factor,
	camera_zoom_velocity_half_life,
	camera_zoom_min_bound,
	camera_zoom_max_bound,
	0.0,
)




func _ready() -> void:
	pass
	
func _process(delta:float) -> void:
	if !camera_can_process: return

	if camera_can_move:
		camera_move.process(delta)
	if camera_can_zoom:
		camera_zoom.process(delta)
	if camera_can_rotate_by_mouse_offset:
		camera_rotate_mouse.process(delta)
	if camera_can_rotate_by_keys:
		camera_rotate_keys.process(delta)
	if camera_can_automatic_pan:
		camera_automatic_pan.process(delta)


# Input event handling
func _unhandled_input(event: InputEvent) -> void:
	# Exit
	if Input.is_action_pressed("Exit"):
		get_tree().quit()
	
	# Left Click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		shoot_ray()

	# Pass input events to calculators
	if camera_can_move:
		camera_move.on_input_event(event)
	if camera_can_zoom:
		camera_zoom.on_input_event(event)
	if camera_can_rotate_by_mouse_offset:
		camera_rotate_mouse.on_input_event(event)
	if camera_can_rotate_by_keys:
		camera_rotate_keys.on_input_event(event)
	if camera_can_automatic_pan:
		camera_automatic_pan.on_input_event(event)


func shoot_ray():
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
		province_selected.emit(Vector2(raycast_result.position.x,raycast_result.position.z))
