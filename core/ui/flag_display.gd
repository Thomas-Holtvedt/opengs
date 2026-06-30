extends TextureRect
class_name FlagDisplay

@onready var shader_material: ShaderMaterial = self.material

# Needed to resolve texture-name fields (e.g. background_image) against the
# loaded flag components. Must be assigned before apply_flag is called.
var database: Database


func apply_flag(flag: Flag) -> void:
	for shader_parameter in shader_material.shader.get_shader_uniform_list():
		var parameter_name: String = shader_parameter.get("name")
		if not (parameter_name in flag):
			continue
		var value: Variant = flag.get(parameter_name)
		if value is String:
			value = _resolve_texture(value)
		shader_material.set_shader_parameter(parameter_name, value)


func _resolve_texture(texture_name: String) -> Texture2D:
	if database == null:
		push_warning("FlagDisplay has no database; cannot resolve texture '%s'" % texture_name)
		return null
	if database.flag_backgrounds.has(texture_name):
		return database.flag_backgrounds[texture_name]
	if database.flag_icons.has(texture_name):
		return database.flag_icons[texture_name]
	if database.flag_icons_colored.has(texture_name):
		return database.flag_icons_colored[texture_name]
	push_warning("Unknown flag texture '%s'" % texture_name)
	return null
