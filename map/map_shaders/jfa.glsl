#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rg16ui) uniform readonly uimage2D src_tex;
layout(set = 0, binding = 1, rg16ui) uniform writeonly uimage2D dst_tex;

layout(push_constant, std430) uniform Params {
	int step;
	int width;
	int height;
	int pad;
} params;

const uint SENTINEL = 0xFFFFu;

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (p.x >= params.width || p.y >= params.height) {
		return;
	}

	uvec2 best = imageLoad(src_tex, p).xy;
	uint best_dist;
	if (best.x == SENTINEL) {
		best_dist = 0xFFFFFFFFu;
	} else {
		ivec2 d = ivec2(best) - p;
		best_dist = uint(d.x * d.x + d.y * d.y);
	}

	for (int oy = -1; oy <= 1; ++oy) {
		for (int ox = -1; ox <= 1; ++ox) {
			if (ox == 0 && oy == 0) {
				continue;
			}
			ivec2 np = p + ivec2(ox, oy) * params.step;
			if (np.x < 0 || np.y < 0 || np.x >= params.width || np.y >= params.height) {
				continue;
			}
			uvec2 cand = imageLoad(src_tex, np).xy;
			if (cand.x == SENTINEL) {
				continue;
			}
			ivec2 d = ivec2(cand) - p;
			uint dist = uint(d.x * d.x + d.y * d.y);
			if (dist < best_dist) {
				best = cand;
				best_dist = dist;
			}
		}
	}

	imageStore(dst_tex, p, uvec4(best, 0u, 0u));
}
