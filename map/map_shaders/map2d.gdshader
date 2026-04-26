shader_type canvas_item;

uniform sampler2D lookup_image: source_color, filter_nearest;
uniform sampler2D color_map_image: source_color, filter_nearest;
uniform sampler2D province_border_image: source_color, filter_nearest;
uniform sampler2D territory_border_image: source_color, filter_nearest;

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
	vec3 territory_border_texture = texture(territory_border_image, UV).rgb;

	// Integer lookup coordinates for pixel-perfect color map sampling
	ivec2 lut = lut_coords(lookup_texture);

	vec4 map_mode_primary = texture(color_map_image, cm_uv(lut.x, lut.y, cm_size));
	vec4 map_mode_secondary = texture(color_map_image, cm_uv(lut.x, lut.y + num_rows, cm_size));
	vec4 selected_color = texture(color_map_image, cm_uv(lut.x, lut.y + 2 * num_rows, cm_size));

	// Set checkers
	vec4 final_color = mix(map_mode_primary, map_mode_secondary, float(checkers_pattern));

	// Darken province borders
	float is_border = 1.0 - province_border_texture.r;
	float is_territory_border = 1.0 - territory_border_texture.r;
	final_color.rgb = mix(final_color.rgb, final_color.rgb * 0.9, is_border);

	// Selection edge highlighting (green = selected province, white = its territory)
	if (length(selected_color.rgb) > 0.01) {
		bool is_province_hl = selected_color.r < 0.9;
		if (!is_province_hl && is_territory_border > 0.01) {
			final_color = vec4(1.0);
		}
		if (is_province_hl && is_border > 0.01) {
			final_color = selected_color;
		}
	}

	COLOR = final_color;
}
