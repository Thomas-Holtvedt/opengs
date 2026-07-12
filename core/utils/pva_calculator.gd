extends RefCounted
class_name PVACalculator
# Dataclass to calculate an acceleration, velocity and position system

const NLOG2: float = -0.6931471805599453  # -ln(2), used by half-life dampening

# Variant refers to a float or a vector here
# Constant
var host: Node3D # The node that owns this calculator; gives subclasses access to its state
var acceleration_speed_factor: Variant
var velocity_half_life: float
var min_bound: Variant
var max_bound: Variant

# Internal
var starting_value: Variant

# Changing
var velocity: Variant
var frame_acceleration: Variant # Auto merged into velocity, reset each frame


func _init(host_node: Node3D, _acceleration_speed_factor: Variant, _velocity_half_life: float, _min_bound: Variant, _max_bound: Variant, _starting_value: Variant) -> void:
	host = host_node
	acceleration_speed_factor = _acceleration_speed_factor
	velocity_half_life = _velocity_half_life
	min_bound = _min_bound
	max_bound = _max_bound
	velocity = _starting_value
	frame_acceleration = _starting_value
	starting_value = _starting_value

func process(delta: float) -> void:
	update_velocity()

	# Apply velocity, dampen and clamp to bounds
	var new_value: Variant = get_value() + velocity * delta
	set_value(_clamp_value(new_value))
	velocity *= _dampen_with_half_life(delta)


# Can be overridden by subclases
func update_velocity() -> void:
	# Add acceleration to velocity and reset
	velocity += get_final_frame_acceleration() * acceleration_speed_factor
	frame_acceleration = starting_value


# Must be overridden by subclasses
func get_value() -> Variant:
	push_error("Internal Method of PVACalculator missing implementation")
	return null

# Must be overridden by subclasses
@warning_ignore("unused_parameter")
func set_value(new_value: Variant) -> void:
	push_error("Internal Method of PVACalculator missing implementation")

# Must be overridden by subclasses
func get_final_frame_acceleration() -> Variant:
	push_error("Internal Method of PVACalculator missing implementation")
	return null

# Must be overridden by subclasses
@warning_ignore("unused_parameter")
func on_input_event(event: InputEvent) -> void:
	push_error("Internal Method of PVACalculator missing implementation")



# Helpers (Variant means float or vector)
func _dampen_with_half_life(delta: float) -> Variant:
	if velocity_half_life == 0: return 0 # Fully reset velocity if half_life is 0
	return exp(NLOG2 * delta / velocity_half_life)

func _clamp_value(value: Variant) -> Variant:
	if value is float:
		return clamp(value, min_bound, max_bound)
	else: # vectors
		return value.clamp(min_bound, max_bound)
