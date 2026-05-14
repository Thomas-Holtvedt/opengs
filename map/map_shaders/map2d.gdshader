shader_type canvas_item;

uniform sampler2D lookup_image: source_color, filter_nearest;
uniform sampler2D color_map_image: source_color, filter_nearest;
uniform sampler2D province_border_image: source_color, filter_nearest;
uniform sampler2D territory_border_image: source_color, filter_nearest;
uniform sampler2D province_sdf_image: filter_linear;
uniform sampler2D territory_sdf_image: filter_linear;
uniform sampler2D country_sdf_image: filter_linear;

uniform float selection_thickness: hint_range(0.0, 16.0) = 2.0;
uniform bool apply_country_fade = false;
// How far the band fades into the country's own territory (where the pixel has an owner color).
uniform float country_fade_inwards: hint_range(0.0, 128.0) = 48.0;
// How far the band fades into unowned area (ocean / no-owner pixels, where the lookup hits no map-mode color).
uniform float country_fade_outwards: hint_range(0.0, 128.0) = 48.0;

// Convert integer pixel coordinates to texel-center UV for pixel-perfect sampling
vec2 cm_uv(int px, int py, ivec2 cm_size) {
	return (vec2(float(px), float(py)) + 0.5) / vec2(cm_size);
}

// Extract integer lookup coordinates from a lookup texture sample
ivec2 lut_coords(vec3 lut_sample) {
	return ivec2(int(lut_sample.r * 255.0 + 0.5), int(lut_sample.g * 255.0 + 0.5));
}

void fragment() {
	// Variables
	float checkers_width = 10.0;
	float texture_width = float(textureSize(lookup_image, 0).x);
	float texture_height = float(textureSize(lookup_image, 0).y);
	int checkers_pattern = int(mod(floor(UV.x * texture_width / checkers_width) + floor(UV.y * texture_height / checkers_width), 2.0));

	// Color map dimensions and layer offset (height = 3 * num_rows)
	ivec2 cm_size = textureSize(color_map_image, 0);
	int num_rows = cm_size.y / 3;

	// Textures
	vec3 lookup_texture = texture(lookup_image, UV).rgb;
	vec3 province_border_texture = texture(province_border_image, UV).rgb;

	// Integer lookup coordinates for pixel-perfect color map sampling
	ivec2 lut = lut_coords(lookup_texture);

	vec4 map_mode_primary = texture(color_map_image, cm_uv(lut.x, lut.y, cm_size));
	vec4 map_mode_secondary = texture(color_map_image, cm_uv(lut.x, lut.y + num_rows, cm_size));
	vec4 selected_color = texture(color_map_image, cm_uv(lut.x, lut.y + 2 * num_rows, cm_size));

	// Set checkers
	vec4 final_color = mix(map_mode_primary, map_mode_secondary, float(checkers_pattern));

	// Darken province borders
	float is_border = 1.0 - province_border_texture.r;
	final_color.rgb = mix(final_color.rgb, final_color.rgb * 0.85, is_border);

	// Country fade: in political-style modes, the owner color is only fully opaque near
	// country borders and fades to transparent toward the country interior, letting the
	// 3D terrain show through. Owned vs unowned pixels use independent fade distances.
	float final_alpha = 1.0;
	if (apply_country_fade) {
		vec2 country_offset = texture(country_sdf_image, UV).rg * 255.0 - 128.0;
		float country_dist = length(country_offset);
		bool is_owned = length(map_mode_primary.rgb) > 0.01;
		float fade_dist = is_owned ? country_fade_inwards : country_fade_outwards;
		final_alpha = fade_dist <= 0.0 ? 0.0 : 1.0 - smoothstep(0.0, fade_dist, country_dist);
	}

	// Selection edge highlighting (green = selected province, white = its territory).
	// Always fully opaque so the ring stays visible even where the country has faded out.
	if (length(selected_color.rgb) > 0.01) {
		bool is_province_hl = selected_color.r < 0.9;
		vec2 sdf_offset = is_province_hl
			? texture(province_sdf_image, UV).rg * 255.0 - 128.0
			: texture(territory_sdf_image, UV).rg * 255.0 - 128.0;
		float border_dist = length(sdf_offset);
		float sel_alpha = 1.0 - smoothstep(selection_thickness - 0.5, selection_thickness + 0.5, border_dist);
		final_color.rgb = mix(final_color.rgb, selected_color.rgb, sel_alpha);
		final_alpha = max(final_alpha, sel_alpha);
	}

	COLOR = vec4(final_color.rgb, final_alpha);
}
