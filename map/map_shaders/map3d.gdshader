shader_type spatial;

// Images
uniform sampler2D terrain_image: source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D subview_image: source_color, filter_linear, repeat_disable;
uniform sampler2D normalmap_image: hint_normal, repeat_enable;
uniform sampler2D heightmap_image: hint_default_black, filter_linear, repeat_disable;

// Parameters
uniform float terrain_saturation: hint_range(0.0, 3.0) = 1.4;
uniform float subview_saturation: hint_range(0.0, 3.0) = 1.0;
// 0 = pure additive overlay (full-strength subview colors).
// 1 = blended 80% toward terrain (washed-out look).
uniform float terrain_mix: hint_range(0.0, 1.0) = 0.0;
uniform float height_scale = 0.0;
// Strength of the per-vertex heightmap-gradient normals (only visible when height_scale > 0).
uniform float normal_strength: hint_range(0.0, 4.0) = 1.0;
// Strength of the normal map texture (surface bump intensity).
uniform float normalmap_strength: hint_range(0.0, 4.0) = 1.0;

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

	// Subview saturation. Works directly on the premultiplied rgb: luminance scales
	// linearly with alpha, so the result stays premultiplied.
	float subview_lum = dot(subview_texture.rgb, vec3(0.2126, 0.7152, 0.0722));
	subview_texture.rgb = mix(vec3(subview_lum), subview_texture.rgb, subview_saturation);

	// The SubViewport (transparent_bg) composites its sprite over a transparent-black
	// clear, so its texture is PREMULTIPLIED alpha: rgb is already scaled by alpha.
	// Source-over for premultiplied alpha is additive, not mix() — using mix() here
	// double-darkens faded regions and washes out the colors.
	vec3 overlay = subview_texture.rgb + terrain_texture * (1.0 - subview_texture.a);
	// terrain_mix blends from the additive overlay (0) toward 80% terrain (1).
	ALBEDO = mix(overlay, terrain_texture, terrain_mix * 0.8);
	NORMAL_MAP = normalmap_texture;
	NORMAL_MAP_DEPTH = normalmap_strength;
}
