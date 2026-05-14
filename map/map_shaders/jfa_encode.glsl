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

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= params.width || p.y >= params.height) {
		return;
	}

	uvec2 seed = imageLoad(seed_tex, p).xy;
	vec4 out_color;
	if (seed.x == SENTINEL) {
		out_color = vec4(128.0 / 255.0, 128.0 / 255.0, 0.0, 1.0);
	} else {
		ivec2 d = clamp(ivec2(seed) - p, ivec2(-127), ivec2(127));
		out_color = vec4(float(d.x + 128) / 255.0, float(d.y + 128) / 255.0, 0.0, 1.0);
	}
	imageStore(out_tex, p, out_color);
}
