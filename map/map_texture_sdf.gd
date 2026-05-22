extends RefCounted
class_name MapTextureSDF

const JFA_SHADER_PATH: String = "res://map/map_shaders/jfa.glsl"
const ENCODE_SHADER_PATH: String = "res://map/map_shaders/jfa_encode.glsl"
const LOCAL_SIZE: int = 8
const SENTINEL: int = 0xFFFF

# Cached compute device + compiled shaders. Creating a local RenderingDevice and compiling
# the SPIR-V shaders is the dominant cost of a JFA build (several hundred ms on Vulkan/Windows
# in practice), so we set them up lazily on first use and reuse them for every subsequent
# build_sdf / build_sdf_region call. The RIDs live for the lifetime of the process.
static var _rd: RenderingDevice = null
static var _jfa_shader: RID
static var _jfa_pipeline: RID
static var _encode_shader: RID
static var _encode_pipeline: RID


static func _ensure_compute_resources() -> bool:
	if _rd != null:
		return true
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		push_error("MapTextureSDF: could not create local RenderingDevice")
		return false
	var jfa_file: RDShaderFile = load(JFA_SHADER_PATH)
	_jfa_shader = _rd.shader_create_from_spirv(jfa_file.get_spirv())
	_jfa_pipeline = _rd.compute_pipeline_create(_jfa_shader)
	var encode_file: RDShaderFile = load(ENCODE_SHADER_PATH)
	_encode_shader = _rd.shader_create_from_spirv(encode_file.get_spirv())
	_encode_pipeline = _rd.compute_pipeline_create(_encode_shader)
	return true


# Convenience: runs GPU JFA over the full L8 border mask and returns an RGBA8 Image.
static func build_sdf(border_data: PackedByteArray, width: int, height: int) -> Image:
	var bytes: PackedByteArray = build_sdf_region(border_data, width, height, Rect2i(0, 0, width, height))
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)


# Runs GPU JFA on a sub-region of the border mask. Returns RGBA8 bytes sized to `region`.
# Seed coordinates inside the result are encoded as offsets relative to the region pixel,
# so the result tile can be blitted into the larger SDF image without translation fixups.
# JFA correctness relies on `border_data` covering the full image — callers should pad
# `region` by the max SDF range so every affected pixel can find its true nearest border.
static func build_sdf_region(border_data: PackedByteArray, full_width: int, full_height: int, region: Rect2i) -> PackedByteArray:
	var rw: int = region.size.x
	var rh: int = region.size.y
	if rw <= 0 or rh <= 0:
		return PackedByteArray()

	if not _ensure_compute_resources():
		return PackedByteArray()
	var rd: RenderingDevice = _rd
	var jfa_shader: RID = _jfa_shader
	var jfa_pipeline: RID = _jfa_pipeline
	var encode_shader: RID = _encode_shader
	var encode_pipeline: RID = _encode_pipeline

	var seed_format: RDTextureFormat = RDTextureFormat.new()
	seed_format.format = RenderingDevice.DATA_FORMAT_R16G16_UINT
	seed_format.width = rw
	seed_format.height = rh
	seed_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var view: RDTextureView = RDTextureView.new()

	var init_data: PackedByteArray = _build_initial_seeds_region(border_data, full_width, full_height, region)
	var seed_a: RID = rd.texture_create(seed_format, view, [init_data])
	var empty: PackedByteArray = PackedByteArray()
	empty.resize(rw * rh * 4)
	var seed_b: RID = rd.texture_create(seed_format, view, [empty])

	var out_format: RDTextureFormat = RDTextureFormat.new()
	out_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	out_format.width = rw
	out_format.height = rh
	out_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var out_tex: RID = rd.texture_create(out_format, view, [])

	var max_dim: int = max(rw, rh)
	var step: int = 1
	while step < max_dim:
		step *= 2
	@warning_ignore("integer_division")
	step /= 2

	@warning_ignore("integer_division")
	var groups_x: int = (rw + LOCAL_SIZE - 1) / LOCAL_SIZE
	@warning_ignore("integer_division")
	var groups_y: int = (rh + LOCAL_SIZE - 1) / LOCAL_SIZE

	var uniform_sets: Array[RID] = []

	var src: RID = seed_a
	var dst: RID = seed_b
	var compute_list: int = rd.compute_list_begin()

	rd.compute_list_bind_compute_pipeline(compute_list, jfa_pipeline)
	while step >= 1:
		var uniform_set: RID = _make_image_pair_set(rd, jfa_shader, src, dst)
		uniform_sets.append(uniform_set)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, _jfa_push(step, rw, rh), 16)
		rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(compute_list)

		var tmp: RID = src
		src = dst
		dst = tmp
		@warning_ignore("integer_division")
		step /= 2

	rd.compute_list_bind_compute_pipeline(compute_list, encode_pipeline)
	var encode_set: RID = _make_image_pair_set(rd, encode_shader, src, out_tex)
	uniform_sets.append(encode_set)
	rd.compute_list_bind_uniform_set(compute_list, encode_set, 0)
	rd.compute_list_set_push_constant(compute_list, _encode_push(rw, rh), 16)
	rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	var rgba_bytes: PackedByteArray = rd.texture_get_data(out_tex, 0)

	for u in uniform_sets:
		rd.free_rid(u)
	rd.free_rid(out_tex)
	rd.free_rid(seed_a)
	rd.free_rid(seed_b)
	# Pipelines and shaders are cached on the class — do NOT free them here. They live for
	# the lifetime of the process and get reused on every JFA call.

	return rgba_bytes


static func _make_image_pair_set(rd: RenderingDevice, shader: RID, image_0: RID, image_1: RID) -> RID:
	var u0: RDUniform = RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(image_0)
	var u1: RDUniform = RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(image_1)
	return rd.uniform_set_create([u0, u1], shader, 0)


static func _jfa_push(step: int, width: int, height: int) -> PackedByteArray:
	var push: PackedByteArray = PackedByteArray()
	push.resize(16)
	push.encode_s32(0, step)
	push.encode_s32(4, width)
	push.encode_s32(8, height)
	push.encode_s32(12, 0)
	return push


static func _encode_push(width: int, height: int) -> PackedByteArray:
	var push: PackedByteArray = PackedByteArray()
	push.resize(16)
	push.encode_s32(0, width)
	push.encode_s32(4, height)
	push.encode_s32(8, 0)
	push.encode_s32(12, 0)
	return push


# Builds the seed-coord init buffer for a region. Seed coordinates are LOCAL to the region,
# so the encode shader produces offsets that work when the result is blitted at the region
# origin. Pre-fills with 0xFF (sentinel) and only writes border pixels inside the region.
static func _build_initial_seeds_region(border_data: PackedByteArray, full_width: int, full_height: int, region: Rect2i) -> PackedByteArray:
	var rw: int = region.size.x
	var rh: int = region.size.y
	var data: PackedByteArray = PackedByteArray()
	data.resize(rw * rh * 4)
	data.fill(0xFF)
	for ly in range(rh):
		var fy: int = region.position.y + ly
		var full_row: int = fy * full_width
		var local_row: int = ly * rw
		for lx in range(rw):
			var fx: int = region.position.x + lx
			if border_data[full_row + fx] == 0:
				var bi: int = (local_row + lx) * 4
				data.encode_u16(bi, lx)
				data.encode_u16(bi + 2, ly)
	return data
