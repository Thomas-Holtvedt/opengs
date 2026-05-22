#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg16ui) uniform readonly uimage2D seed_tex;
layout(set = 0, binding = 1, rgba8) uniform writeonly image2D out_tex;

layout(push_constant, std430) uniform Params {
	int width;
	int height;
	int pad0;
	int pad1;
} params;

const uint SENTINEL = 0xFFFFu;
// Max distance (in texel units) representable in the B channel. Distances beyond saturate
// to 1.0 — fine for consumers, which treat far-away pixels as "outside the fade band".
// The country-fade shader path multiplies this back to texel units, so the constant here
// must match the one the consumer uses (see map2d.gdshader: COUNTRY_SDF_DIST_MAX).
const float DIST_NORM_MAX = 128.0;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= params.width || p.y >= params.height) {
		return;
	}

	uvec2 seed = imageLoad(seed_tex, p).xy;
	vec4 out_color;
	if (seed.x == SENTINEL) {
		out_color = vec4(128.0 / 255.0, 128.0 / 255.0, 1.0, 1.0);
	} else {
		ivec2 raw_d = ivec2(seed) - p;
		ivec2 d = clamp(raw_d, ivec2(-127), ivec2(127));
		float dist_norm = clamp(length(vec2(raw_d)) / DIST_NORM_MAX, 0.0, 1.0);
		out_color = vec4(float(d.x + 128) / 255.0, float(d.y + 128) / 255.0, dist_norm, 1.0);
	}
	imageStore(out_tex, p, out_color);
}
