shader_type canvas_item;

uniform sampler2D lookup_image: source_color, filter_nearest;
uniform sampler2D color_map_image: source_color, filter_nearest;
uniform sampler2D province_border_image: source_color, filter_nearest;
uniform sampler2D territory_border_image: source_color, filter_nearest;
uniform sampler2D province_sdf_image: filter_linear;
uniform sampler2D territory_sdf_image: filter_linear;
uniform sampler2D country_sdf_image: filter_linear;
// Crop-sized SDFs around the current selection (MapTextureGenerator.update_selection_sdf):
// distance to the selected province boundary / its territory boundary.
uniform sampler2D selection_province_sdf: filter_linear;
uniform sampler2D selection_territory_sdf: filter_linear;
// Where the selection SDF crop sits in map pixels: xy = origin, zw = size. zw = 0 → nothing
// is selected and the ring pass is skipped entirely.
uniform vec4 selection_sdf_rect = vec4(0.0);

uniform float selection_thickness: hint_range(0.0, 16.0) = 2.0;
// How far the selection ring fades out past its solid core. The ring is centered on the
// selection boundary: solid for selection_thickness pixels and fading over selection_fade
// pixels, on BOTH sides of the boundary.
uniform float selection_fade: hint_range(0.0, 16.0) = 1.0;
uniform bool apply_country_fade = false;
// How far the band fades into the country's own territory (where the pixel has an owner color).
uniform float country_fade_inwards: hint_range(0.0, 128.0) = 48.0;
// How far the shadow fades into unowned area (ocean / no-owner pixels, where the lookup hits no map-mode color).
uniform float country_fade_outwards: hint_range(0.0, 128.0) = 48.0;
// How far the nearest country's own color bleeds into unowned area. A few pixels of bleed
// anti-aliases the coastline; the owner color is fetched by following the SDF's RG offset,
// which always lands on an owned pixel (the country border mask is one-sided, owned pixels only).
uniform float country_color_fade_outwards: hint_range(0.0, 128.0) = 3.0;
// Baseline opacity of the owner color over the whole country interior. 0.0 restores the old
// behavior (interior fully fades out); 1.0 paints the entire country solid.
uniform float country_fill_strength: hint_range(0.0, 1.0) = 0.3;
// Scalar distance is encoded in every SDF's B channel as `dist / SDF_DIST_MAX` (in
// pixels). Reading this scalar instead of `length(offset)` avoids the medial-axis
// cancellation: linearly filtering opposing offset vectors collapses to ~zero length, which
// the old code interpreted as "on a border" and produced a bright line down the middle of
// big country interiors (and would do the same to the selection rings when zoomed in).
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

// Ring alpha as a function of distance to the true geometric boundary: solid for
// selection_thickness, then fading out over selection_fade. The closest any pixel center
// gets to the boundary is 0.5 (the seed rows), so selection_thickness below 0.5 gives a
// sub-pixel line — the peak alpha drops below 1.0, exactly like coverage-based AA.
float ring_profile(float boundary_dist) {
	return 1.0 - smoothstep(selection_thickness, selection_thickness + max(selection_fade, 0.001), boundary_dist);
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

	// Set checkers
	vec4 final_color = mix(map_mode_primary, map_mode_secondary, float(checkers_pattern));

	// Darken province borders
	float is_border = 1.0 - province_border_texture.r;
	final_color.rgb = mix(final_color.rgb, final_color.rgb * 0.85, is_border);

	// Country fade: in political-style modes, the owner color is fully opaque near country
	// borders, fades toward the country interior down to a baseline fill (country_fill_strength),
	// and bleeds a short distance outwards so coastlines stay smooth. Beyond the color bleed,
	// a shadow band fades into unowned area. All distances are independent uniforms.
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
			// Source-over: owner color at bleed_alpha composited over the shadow at
			// shadow_alpha. The rgb must stay straight-alpha (NOT pre-scaled by bleed_alpha):
			// the SubViewport multiplies rgb by alpha when compositing over its transparent
			// background, and pre-scaling would darken the bleed quadratically — it reads as
			// a black fringe instead of a smooth colored edge.
			final_alpha = bleed_alpha + shadow_alpha * (1.0 - bleed_alpha);
			if (bleed_alpha > 0.0) {
				// Follow the (unfiltered) SDF offset to the nearest owned pixel and use its
				// map-mode color, so the bleed carries the neighboring country's color.
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

	// Selection rings: green around the selected province, white around its territory, read
	// from the dedicated selection SDF crop. The B-channel scalar distance is shifted by
	// 0.5 so it measures to the true geometric boundary (the seed rows sit half a pixel
	// inside each side) — see ring_profile for how that enables sub-pixel-thin lines.
	// Ring colors must match MapHighlight.province_hl / territory_hl.
	float green_alpha = 0.0;
	float white_alpha = 0.0;
	if (selection_sdf_rect.z > 0.5) {
		vec2 map_px = UV * vec2(texture_width, texture_height);
		vec2 sel_uv = (map_px - selection_sdf_rect.xy) / selection_sdf_rect.zw;
		if (all(greaterThanEqual(sel_uv, vec2(0.0))) && all(lessThan(sel_uv, vec2(1.0)))) {
			float prov_dist = texture(selection_province_sdf, sel_uv).b * SDF_DIST_MAX + 0.5;
			float terr_dist = texture(selection_territory_sdf, sel_uv).b * SDF_DIST_MAX + 0.5;
			green_alpha = ring_profile(prov_dist);
			white_alpha = ring_profile(terr_dist);
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
