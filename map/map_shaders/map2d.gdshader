shader_type canvas_item;

uniform sampler2D lookup_image: source_color, filter_nearest;
uniform sampler2D color_map_image: source_color, filter_nearest;
uniform sampler2D province_border_image: source_color, filter_nearest;
// Province boundary SDF: B = scalar distance (drives the AA border line), RG = JFA offset
// to the nearest boundary pixel (used for fill-edge AA).
uniform sampler2D province_sdf_image: filter_linear;
// Half-width of the province border line, in source pixels. Centered on the true boundary
// and anti-aliased over one screen pixel via fwidth, so it holds thickness at any zoom.
uniform float province_border_width: hint_range(0.0, 4.0) = 0.75;
// How much the border line darkens the fill underneath it (1.0 = no darkening).
uniform float province_border_darkness: hint_range(0.0, 1.0) = 0.85;
// Optional coverage AA of the province fill step: blends toward the neighboring province's
// color near the boundary (up to 50% on the line). 0.0 = off.
uniform float province_fill_aa: hint_range(0.0, 1.0) = 0.0;
uniform sampler2D country_sdf_image: filter_linear;
// Full-map territory boundary SDF, precomputed at load; the white ring reads it directly.
uniform sampler2D territory_sdf_image: filter_linear;
// Lookup-indexed territory identity map: entry = the territory's color, black = none.
uniform sampler2D territory_id_image: filter_nearest;
// Identity colors of the selected provinces' territories; count = 0 → no white ring.
uniform vec3 selected_territory_ids[8];
uniform int selected_territory_count = 0;
// Crop-sized SDF around the current selection, rebuilt per click.
uniform sampler2D selection_province_sdf: filter_linear;
// Crop placement in map pixels: xy = origin, zw = size. zw = 0 → nothing selected.
uniform vec4 selection_sdf_rect = vec4(0.0);

uniform float selection_thickness: hint_range(0.0, 16.0) = 2.0;
// Fade-out width past the ring's solid core, on both sides of the boundary.
uniform float selection_fade: hint_range(0.0, 16.0) = 1.0;
uniform bool apply_country_fade = false;
// How far the band fades into the country's own territory.
uniform float country_fade_inwards: hint_range(0.0, 128.0) = 48.0;
// How far the shadow fades into unowned area (ocean / no-owner pixels).
uniform float country_fade_outwards: hint_range(0.0, 128.0) = 48.0;
// How far the nearest country's color bleeds outwards to anti-alias the coastline. The
// owner color is fetched via the SDF's RG offset, which always lands on an owned pixel
// (the country border mask is one-sided).
uniform float country_color_fade_outwards: hint_range(0.0, 128.0) = 3.0;
// Baseline opacity of the owner color over the whole country interior.
uniform float country_fill_strength: hint_range(0.0, 1.0) = 0.3;
// B-channel scalar distance = dist / SDF_DIST_MAX pixels. Read this, NOT length(offset):
// linear filtering of opposing offsets cancels to ~zero on the medial axis, which reads as
// "on a border" and paints a bright line down big country interiors.
// Must match DIST_NORM_MAX in jfa_encode.glsl.
const float SDF_DIST_MAX = 128.0;

// Convert integer pixel coordinates to texel-center UV for pixel-perfect sampling
vec2 cm_uv(int px, int py, ivec2 cm_size) {
	return (vec2(float(px), float(py)) + 0.5) / vec2(cm_size);
}

// Extract integer lookup coordinates from a lookup texture sample
ivec2 lut_coords(vec3 lut_sample) {
	return ivec2(int(lut_sample.r * 255.0 + 0.5), int(lut_sample.g * 255.0 + 0.5));
}

// Ring alpha: solid for selection_thickness, fading over selection_fade. Pixel centers
// never get closer than 0.5 to the boundary, so thickness below 0.5 gives a sub-pixel
// line whose peak alpha drops below 1.0, like coverage AA.
float ring_profile(float boundary_dist) {
	return 1.0 - smoothstep(selection_thickness, selection_thickness + max(selection_fade, 0.001), boundary_dist);
}

// Whether the province under the given map UV belongs to one of the selected territories.
bool selected_territory_at(vec2 uv) {
	ivec2 l = lut_coords(texture(lookup_image, uv).rgb);
	vec2 id_uv = (vec2(l) + 0.5) / vec2(textureSize(territory_id_image, 0));
	vec3 id = texture(territory_id_image, id_uv).rgb;
	for (int i = 0; i < selected_territory_count; i++) {
		if (distance(id, selected_territory_ids[i]) < 0.002) {
			return true;
		}
	}
	return false;
}

// Whether the selected territory lies on this or the far side of the boundary the SDF
// offset points to. Inside the two-sided seed band the offset is ~zero, so the
// 4-neighborhood is tapped instead of stepping across.
bool selection_across(vec2 off, vec2 uv, vec2 map_size) {
	if (selected_territory_at(uv)) {
		return true;
	}
	float off_len = length(off);
	if (off_len < 0.5) {
		vec2 texel = 1.0 / map_size;
		return selected_territory_at(uv + vec2(texel.x, 0.0))
				|| selected_territory_at(uv - vec2(texel.x, 0.0))
				|| selected_territory_at(uv + vec2(0.0, texel.y))
				|| selected_territory_at(uv - vec2(0.0, texel.y));
	}
	// Step 1.5px past the nearest border pixel to land on the far side of the boundary.
	return selected_territory_at(uv + (off + off / off_len * 1.5) / map_size);
}


void fragment() {
	// Variables
	float checkers_width = 10.0;
	float texture_width = float(textureSize(lookup_image, 0).x);
	float texture_height = float(textureSize(lookup_image, 0).y);
	int checkers_pattern = int(mod(floor(UV.x * texture_width / checkers_width) + floor(UV.y * texture_height / checkers_width), 2.0));

	// Color map dimensions and layer offset (height = 2 * num_rows: primary + secondary)
	ivec2 cm_size = textureSize(color_map_image, 0);
	int num_rows = cm_size.y / 2;

	// Textures
	vec3 lookup_texture = texture(lookup_image, UV).rgb;

	// Integer lookup coordinates for pixel-perfect color map sampling
	ivec2 lut = lut_coords(lookup_texture);

	vec4 map_mode_primary = texture(color_map_image, cm_uv(lut.x, lut.y, cm_size));
	vec4 map_mode_secondary = texture(color_map_image, cm_uv(lut.x, lut.y + num_rows, cm_size));

	// Set checkers
	vec4 final_color = mix(map_mode_primary, map_mode_secondary, float(checkers_pattern));

	// Province border line. +0.5 shifts the SDF distance to the true geometric boundary
	// (seed rows sit half a pixel inside each side); fwidth anti-aliases over ~1 screen px.
	float prov_dist = texture(province_sdf_image, UV).b * SDF_DIST_MAX + 0.5;
	float prov_aa = max(fwidth(prov_dist), 0.0001);

	// Fill-edge AA: blend toward the neighbouring province's color across the boundary.
	// Skipped inside the two-sided seed band (offset ~0), where the cross-side direction is
	// undefined; the border line covers that sliver anyway.
	if (province_fill_aa > 0.0) {
		ivec2 psdf_size = textureSize(province_sdf_image, 0);
		ivec2 ppx = ivec2(UV * vec2(psdf_size));
		vec2 prov_off = texelFetch(province_sdf_image, ppx, 0).rg * 255.0 - 128.0;
		float prov_off_len = length(prov_off);
		if (prov_off_len >= 0.5) {
			vec2 across_uv = (vec2(ppx) + prov_off + prov_off / prov_off_len * 1.5 + 0.5) / vec2(psdf_size);
			ivec2 across_lut = lut_coords(texture(lookup_image, across_uv).rgb);
			vec3 across_color = texture(color_map_image, cm_uv(across_lut.x, across_lut.y, cm_size)).rgb;
			float coverage = 0.5 * (1.0 - smoothstep(0.0, prov_aa, prov_dist));
			final_color.rgb = mix(final_color.rgb, across_color, province_fill_aa * coverage);
		}
	}

	// Border line, drawn over the (optionally AA'd) fill.
	float border = 1.0 - smoothstep(province_border_width - prov_aa, province_border_width + prov_aa, prov_dist);
	final_color.rgb = mix(final_color.rgb, final_color.rgb * province_border_darkness, border);

	// Country fade: owner color is opaque at the border, fades inwards to a baseline fill,
	// and bleeds a short distance outwards; beyond the bleed a shadow fades into unowned area.
	float final_alpha = 1.0;
	if (apply_country_fade) {
		float country_dist = texture(country_sdf_image, UV).b * SDF_DIST_MAX;
		bool is_owned = length(map_mode_primary.rgb) > 0.01;
		if (is_owned) {
			float band_alpha = country_fade_inwards <= 0.0 ? 0.0 : 1.0 - smoothstep(0.0, country_fade_inwards, country_dist);
			final_alpha = max(band_alpha, country_fill_strength);
		} else {
			float shadow_alpha = country_fade_outwards <= 0.0 ? 0.0 : 1.0 - smoothstep(0.0, country_fade_outwards, country_dist);
			float bleed_alpha = country_color_fade_outwards <= 0.0 ? 0.0 : 1.0 - smoothstep(0.0, country_color_fade_outwards, country_dist);
			// Source-over. The rgb must stay straight-alpha (NOT pre-scaled by bleed_alpha):
			// the SubViewport multiplies rgb by alpha when compositing, and pre-scaling
			// darkens the bleed quadratically into a black fringe.
			final_alpha = bleed_alpha + shadow_alpha * (1.0 - bleed_alpha);
			if (bleed_alpha > 0.0) {
				// Follow the unfiltered SDF offset to the nearest owned pixel for its color.
				ivec2 sdf_size = textureSize(country_sdf_image, 0);
				ivec2 px = ivec2(UV * vec2(sdf_size));
				vec2 owner_offset = texelFetch(country_sdf_image, px, 0).rg * 255.0 - 128.0;
				vec2 owner_uv = (vec2(px) + owner_offset + 0.5) / vec2(sdf_size);
				ivec2 owner_lut = lut_coords(texture(lookup_image, owner_uv).rgb);
				vec3 owner_color = texture(color_map_image, cm_uv(owner_lut.x, owner_lut.y, cm_size)).rgb;
				float shadow_part = shadow_alpha * (1.0 - bleed_alpha);
				final_color.rgb = (owner_color * bleed_alpha + final_color.rgb * shadow_part) / final_alpha;
			}
		}
	}

	// Selection rings: green around the selected province (per-click crop SDF), white
	// around its territory (full-map SDF). Both distances get the same +0.5 boundary shift.
	float green_alpha = 0.0;
	float white_alpha = 0.0;
	if (selection_sdf_rect.z > 0.5) {
		vec2 map_px = UV * vec2(texture_width, texture_height);
		vec2 sel_uv = (map_px - selection_sdf_rect.xy) / selection_sdf_rect.zw;
		if (all(greaterThanEqual(sel_uv, vec2(0.0))) && all(lessThan(sel_uv, vec2(1.0)))) {
			float prov_dist = texture(selection_province_sdf, sel_uv).b * SDF_DIST_MAX + 0.5;
			green_alpha = ring_profile(prov_dist);
		}
	}
	if (selected_territory_count > 0) {
		vec4 terr_sdf = texture(territory_sdf_image, UV);
		float terr_dist = terr_sdf.b * SDF_DIST_MAX + 0.5;
		// The full-map SDF holds the distance to ANY territory boundary, so gate the ring on
		// the selected territory sitting on either side of that boundary.
		if (terr_dist <= selection_thickness + selection_fade + 1.0) {
			vec2 terr_off = terr_sdf.rg * 255.0 - 128.0;
			if (selection_across(terr_off, UV, vec2(texture_width, texture_height))) {
				white_alpha = ring_profile(terr_dist);
			}
		}
	}

	// Green composites over white, then the rings source-over the base in straight alpha
	// (see the country bleed note above — mix()+max() would double-darken soft edges).
	float ring_alpha = green_alpha + white_alpha * (1.0 - green_alpha);
	if (ring_alpha > 0.001) {
		vec3 ring_rgb = (vec3(0.361, 1.0, 0.192) * green_alpha + vec3(1.0) * white_alpha * (1.0 - green_alpha)) / ring_alpha;
		float base_part = final_alpha * (1.0 - ring_alpha);
		final_alpha = ring_alpha + base_part;
		final_color.rgb = (ring_rgb * ring_alpha + final_color.rgb * base_part) / max(final_alpha, 0.0001);
	}

	COLOR = vec4(final_color.rgb, final_alpha);
}
