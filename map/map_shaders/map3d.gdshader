shader_type spatial;

// Images
uniform sampler2D terrain_image: source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D subview_image: source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normalmap_image: hint_normal, repeat_enable;

// Parameters
uniform float threshold = 0.1;
uniform float aa_scale = 17.6;
uniform float base_line_thickness = 0.38197;
uniform float terrain_saturation: hint_range(0.0, 3.0) = 1.4;
const int ML = 0;

// Diagonal line blending logic
bool diag(inout vec4 sum, vec2 ip, vec2 p1, vec2 p2, float thickness, float scale) {
	vec4 v1 = texelFetch(subview_image, ivec2(ip + p1), ML);
	vec4 v2 = texelFetch(subview_image, ivec2(ip + p2), ML);

	if (length(v1 - v2) < threshold) {
		vec2 dir = normalize(vec2((p2 - p1).y, -(p2 - p1).x));
		vec2 lp = ip - (floor(ip + p1) + vec2(0.5));
		// float l = clamp((thickness - dot(lp, dir)) * aa_scale, 0.0, 1.0);
		float l = clamp((thickness - dot(lp, dir)) * scale, 0.0, 1.0);
		sum = mix(sum, v1, l);
		return true;
	}
	return false;
}

void fragment() {
	// Textures

	vec3 subview_texture = texture(subview_image,UV).rgb;
	vec3 terrain_texture = texture(terrain_image,UV).rgb;
	float terrain_lum = dot(terrain_texture, vec3(0.2126, 0.7152, 0.0722));
	terrain_texture = mix(vec3(terrain_lum), terrain_texture, terrain_saturation);
	vec3 normalmap_texture = texture(normalmap_image,UV).rgb;

	// Apply smoothing
	vec2 tex_size = vec2(textureSize(subview_image, 0));
	vec2 ip = UV * tex_size;
	vec4 s = texelFetch(subview_image, ivec2(ip), ML);

	// Derive AA scale from screen-space derivatives so the blend zone is ~1
	// screen pixel wide regardless of camera zoom.
	vec2 dp = fwidth(ip);
	float pixel_in_texels = max(max(dp.x, dp.y), 1e-4);
	float scale = 1.0 / pixel_in_texels;
	// float scale = min(1.0 / pixel_in_texels, aa_scale); // capped version
	// float scale = aa_scale; // original fixed behavior

	float base_thick = base_line_thickness;
	float sub_thick = 0.25;

	// if (diag(s, ip, vec2(-1, 0), vec2(0, 1), base_line_thickness)) {
	// 	diag(s, ip, vec2(-1, 0), vec2(1, 1), 0.25);
	// 	diag(s, ip, vec2(-1, -1), vec2(0, 1), 0.25);
	// }
	// if (diag(s, ip, vec2(0, 1), vec2(1, 0), base_line_thickness)) {
	// 	diag(s, ip, vec2(0, 1), vec2(1, -1), 0.25);
	// 	diag(s, ip, vec2(-1, 1), vec2(1, 0), 0.25);
	// }
	// if (diag(s, ip, vec2(1, 0), vec2(0, -1), base_line_thickness)) {
	// 	diag(s, ip, vec2(1, 0), vec2(-1, -1), 0.25);
	// 	diag(s, ip, vec2(1, 1), vec2(0, -1), 0.25);
	// }
	// if (diag(s, ip, vec2(0, -1), vec2(-1, 0), base_line_thickness)) {
	// 	diag(s, ip, vec2(0, -1), vec2(-1, 1), 0.25);
	// 	diag(s, ip, vec2(1, -1), vec2(-1, 0), 0.25);
	// }
	if (diag(s, ip, vec2(-1, 0), vec2(0, 1), base_thick, scale)) {
		diag(s, ip, vec2(-1, 0), vec2(1, 1), sub_thick, scale);
		diag(s, ip, vec2(-1, -1), vec2(0, 1), sub_thick, scale);
	}
	if (diag(s, ip, vec2(0, 1), vec2(1, 0), base_thick, scale)) {
		diag(s, ip, vec2(0, 1), vec2(1, -1), sub_thick, scale);
		diag(s, ip, vec2(-1, 1), vec2(1, 0), sub_thick, scale);
	}
	if (diag(s, ip, vec2(1, 0), vec2(0, -1), base_thick, scale)) {
		diag(s, ip, vec2(1, 0), vec2(-1, -1), sub_thick, scale);
		diag(s, ip, vec2(1, 1), vec2(0, -1), sub_thick, scale);
	}
	if (diag(s, ip, vec2(0, -1), vec2(-1, 0), base_thick, scale)) {
		diag(s, ip, vec2(0, -1), vec2(-1, 1), sub_thick, scale);
		diag(s, ip, vec2(1, -1), vec2(-1, 0), sub_thick, scale);
	}


	//ALBEDO = s.rgb; //final_color;//s.rgb; //mix(s.rgb, terrain_texture, 0.4);
	ALBEDO = mix(s.rgb, terrain_texture, 0.35);
	NORMAL_MAP = normalmap_texture;
}
