shader_type canvas_item;

uniform sampler2D overlay_image : source_color, filter_nearest;
uniform float overlay_strength : hint_range(0.0, 4.0) = 1.0;

// --- Main flag ---
uniform sampler2D background_image : source_color, filter_nearest;
uniform vec4 background_color_1 : source_color;
uniform vec4 background_color_2 : source_color;
uniform vec4 background_color_3 : source_color;

uniform sampler2D icon_1_image : source_color, filter_linear;
uniform vec4 icon_1_color : source_color;
uniform vec2 icon_1_offset;

uniform sampler2D icon_2_image : source_color, filter_linear;
uniform vec4 icon_2_color : source_color;
uniform vec2 icon_2_offset;

uniform sampler2D icon_colored_image : source_color, filter_linear;
uniform vec2 icon_colored_offset;

// --- Canton: a mini-flag composited into the upper-hoist (top-left) corner. ---
// canton_size is the fraction of the flag the canton covers (x = width,
// y = height), measured from the top-left. A zero component disables the canton,
// so flags without one render exactly as before.
uniform vec2 canton_size = vec2(0.0);

uniform sampler2D canton_background_image : source_color, filter_nearest;
uniform vec4 canton_background_color_1 : source_color;
uniform vec4 canton_background_color_2 : source_color;
uniform vec4 canton_background_color_3 : source_color;

uniform sampler2D canton_icon_1_image : source_color, filter_linear;
uniform vec4 canton_icon_1_color : source_color;
uniform vec2 canton_icon_1_offset;

uniform sampler2D canton_icon_2_image : source_color, filter_linear;
uniform vec4 canton_icon_2_color : source_color;
uniform vec2 canton_icon_2_offset;

uniform sampler2D canton_icon_colored_image : source_color, filter_linear;
uniform vec2 canton_icon_colored_offset;

// Slight blur applied to the composited flag to soften the hard color seams.
uniform float blur_amount : hint_range(0.0, 0.02) = 0.003;


vec3 apply_icon(vec3 base, sampler2D tex, vec2 uv, vec4 tint) {
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float weight = clamp(texture(tex, uv).a * tint.a * inside, 0.0, 1.0);
	return mix(base, tint.rgb, weight);
}

vec3 apply_colored_icon(vec3 base, sampler2D tex, vec2 uv) {
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec4 icon = texture(tex, uv);
	float weight = clamp(icon.a * inside, 0.0, 1.0);
	return mix(base, icon.rgb, weight);
}

// One self-contained flag (3-region background + its three icons) sampled at
// `uv`. Shared by the main flag and the canton so they composite identically.
vec4 composite(
		vec2 uv,
		sampler2D bg, vec4 c1, vec4 c2, vec4 c3,
		sampler2D i1, vec4 i1_col, vec2 i1_off,
		sampler2D i2, vec4 i2_col, vec2 i2_off,
		sampler2D ic, vec2 ic_off) {
	vec4 background_texture = texture(bg, uv);
	vec4 flag_color;
	if (background_texture.rgb == vec3(1.0)) {
		flag_color = c1;
	} else if (background_texture.rgb == vec3(0.0)) {
		flag_color = c2;
	} else {
		flag_color = c3;
	}
	flag_color.rgb = apply_icon(flag_color.rgb, i1, uv - i1_off, i1_col);
	flag_color.rgb = apply_icon(flag_color.rgb, i2, uv - i2_off, i2_col);
	flag_color.rgb = apply_colored_icon(flag_color.rgb, ic, uv - ic_off);
	return flag_color;
}

// The full flag color at a single point: the canton inside the upper-hoist box,
// the main flag everywhere else. Each call does its own region test + exact
// color-region composite, so averaging several calls produces a clean blur of
// the composite (and softens the canton edge) instead of smearing a texture.
vec4 flag_at(vec2 uv) {
	if (canton_size.x > 0.0 && canton_size.y > 0.0
			&& uv.x < canton_size.x && uv.y < canton_size.y) {
		vec2 local = uv / canton_size; // remap the canton box back to 0..1
		return composite(
			local,
			canton_background_image, canton_background_color_1, canton_background_color_2, canton_background_color_3,
			canton_icon_1_image, canton_icon_1_color, canton_icon_1_offset,
			canton_icon_2_image, canton_icon_2_color, canton_icon_2_offset,
			canton_icon_colored_image, canton_icon_colored_offset);
	}
	return composite(
		uv,
		background_image, background_color_1, background_color_2, background_color_3,
		icon_1_image, icon_1_color, icon_1_offset,
		icon_2_image, icon_2_color, icon_2_offset,
		icon_colored_image, icon_colored_offset);
}

void fragment() {
	// 3x3 box blur of the composited flag.
	vec4 flag_color = vec4(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			flag_color += flag_at(UV + vec2(float(x), float(y)) * blur_amount);
		}
	}
	flag_color /= 9.0;

	// Cloth shading overlay on top of everything (not blurred), applied once over
	// the whole composite so the canton sits under the same fabric as the flag.
	// Blend by the overlay's own alpha so transparent areas leave the flag untouched.
	vec4 overlay_texture = texture(overlay_image, UV);
	float overlay_amount = clamp(overlay_texture.a * overlay_strength, 0.0, 1.0);
	flag_color.rgb = mix(flag_color.rgb, overlay_texture.rgb, overlay_amount);

	// Keep the flag's own alpha so icons/overlay can never make it see-through.
	COLOR = vec4(flag_color.rgb, flag_color.a);
}
