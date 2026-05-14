shader_type spatial;

// Images
uniform sampler2D terrain_image: source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D subview_image: source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normalmap_image: hint_normal, repeat_enable;
uniform sampler2D heightmap_image: hint_default_black, filter_linear, repeat_disable;

// Parameters
uniform float terrain_saturation: hint_range(0.0, 3.0) = 1.4;
uniform float height_scale = 0.0;
uniform float normal_strength = 1.0;

// 0x87 / 0xFF — sea level reference: #878787 maps to elevation 0.
const float SEA_LEVEL = 0.52941176;

void vertex() {
	vec2 texel = 1.0 / vec2(textureSize(heightmap_image, 0));
	float h = texture(heightmap_image, UV).r - SEA_LEVEL;
	VERTEX.y += h * height_scale;

	// Per-vertex normal from heightmap gradient (central differences).
	float h_l = texture(heightmap_image, UV - vec2(texel.x, 0.0)).r;
	float h_r = texture(heightmap_image, UV + vec2(texel.x, 0.0)).r;
	float h_d = texture(heightmap_image, UV - vec2(0.0, texel.y)).r;
	float h_u = texture(heightmap_image, UV + vec2(0.0, texel.y)).r;
	NORMAL = normalize(vec3((h_l - h_r) * height_scale, normal_strength, (h_d - h_u) * height_scale));
}

void fragment() {
	vec4 subview_texture = texture(subview_image, UV);
	vec3 terrain_texture = texture(terrain_image, UV).rgb;
	float terrain_lum = dot(terrain_texture, vec3(0.2126, 0.7152, 0.0722));
	terrain_texture = mix(vec3(terrain_lum), terrain_texture, terrain_saturation);
	vec3 normalmap_texture = texture(normalmap_image, UV).rgb;

	// subview alpha controls how strongly the 2D map color overrides the terrain.
	// alpha = 1: same look as before (65% subview, 35% terrain).
	// alpha = 0: pure terrain (used inside countries when the country fade has fully faded out).
	float subview_strength = subview_texture.a * 0.65;
	ALBEDO = mix(terrain_texture, subview_texture.rgb, subview_strength);
	NORMAL_MAP = normalmap_texture;
}
