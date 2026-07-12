extends RefCounted
class_name MapBorderTracer

# Stages 1-2 of the border-ribbon pipeline: turns a per-pixel country-ownership grid into
# boundary polylines ("chains"). Each chain is the shared border between exactly two owners,
# traced once, running from one junction (a lattice vertex where 3+ regions meet, or where a
# border reaches the map edge) to the next. Downstream stages (simplify, smooth, ribbon mesh)
# consume these point lists.
#
# Coordinates live on the integer LATTICE of pixel CORNERS: a chain point (x, y) is the corner
# shared by pixels, x in [0, width], y in [0, height]. Because the map Sprite2D is uncentered
# at the origin, these map 1:1 onto its local space (and thus into the SubViewport).
#
# Pure CPU, no RenderingDevice or scene access — safe to run on a WorkerThreadPool task.
#
# Edge model: a boundary "crack" between two differing pixels is one unit lattice edge.
#  - Horizontal edge H(x, y): from vertex (x, y) to (x+1, y)   [separates the pixels above/below]
#  - Vertical   edge V(x, y): from vertex (x, y) to (x, y+1)   [separates the pixels left/right]

# 1 = boundary edge present/unused, 0 = absent or already consumed. Kept as members (not
# passed as arguments) because PackedByteArray is copy-on-write: a mutating helper receiving
# one as a parameter would edit a detached copy.
var _h_present: PackedByteArray
var _v_present: PackedByteArray
# Lattice-vertex key (vy * _w1 + vx) -> count of incident boundary edges. Used only to decide
# junction (!= 2) vs. mid-chain (== 2); consumption is tracked by the _present arrays.
var _degree: Dictionary
var _width: int
var _height: int
var _w1: int  # width + 1, the lattice-vertex row stride


func trace(owner_ids: PackedInt32Array, width: int, height: int) -> Array[PackedVector2Array]:
	_width = width
	_height = height
	_w1 = width + 1
	_h_present = PackedByteArray()
	_h_present.resize(width * (height + 1))
	_v_present = PackedByteArray()
	_v_present.resize(_w1 * height)
	_degree = {}

	_build_edges(owner_ids)

	var chains: Array[PackedVector2Array] = []
	# Junction-anchored chains: every edge incident to a junction spawns one chain.
	for key: int in _degree:
		if _degree[key] == 2:
			continue
		var vx: int = key % _w1
		@warning_ignore("integer_division")
		var vy: int = key / _w1
		while true:
			var pts: PackedVector2Array = _walk(vx, vy)
			if pts.size() < 2:
				break
			chains.append(pts)
	# Whatever edges remain form junction-free loops (e.g. an enclave fully inside one country).
	_trace_loops(chains)
	return chains


func _build_edges(owner_ids: PackedInt32Array) -> void:
	for y in range(_height):
		var row: int = y * _width
		var below: int = row + _width
		for x in range(_width):
			var o: int = owner_ids[row + x]
			# Differ with right neighbour -> vertical crack at column x+1.
			if x + 1 < _width and o != owner_ids[row + x + 1]:
				_v_present[y * _w1 + (x + 1)] = 1
				_bump(y * _w1 + (x + 1))
				_bump((y + 1) * _w1 + (x + 1))
			# Differ with lower neighbour -> horizontal crack at row y+1.
			if y + 1 < _height and o != owner_ids[below + x]:
				_h_present[(y + 1) * _width + x] = 1
				_bump((y + 1) * _w1 + x)
				_bump((y + 1) * _w1 + (x + 1))


func _bump(key: int) -> void:
	_degree[key] = _degree.get(key, 0) + 1


# Consumes the first present incident edge at the given vertex and follows through degree-2
# vertices until a junction (or a dead end). Returns the ordered lattice points; a lone start
# point (size 1) means nothing was incident.
func _walk(start_vx: int, start_vy: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2(start_vx, start_vy))
	var step: Vector3i = _consume_incident(start_vx, start_vy)
	if step.z == 0:
		return pts
	var cvx: int = step.x
	var cvy: int = step.y
	pts.append(Vector2(cvx, cvy))
	# Continue only while the current vertex is mid-chain. Junctions terminate the chain and
	# keep their remaining edges for their own chains (no double-tracing).
	while _degree.get(cvy * _w1 + cvx, 0) == 2:
		var nstep: Vector3i = _consume_incident(cvx, cvy)
		if nstep.z == 0:
			break
		cvx = nstep.x
		cvy = nstep.y
		pts.append(Vector2(cvx, cvy))
	return pts


# Sweeps any edges the junction pass didn't reach; each seeds one closed loop.
func _trace_loops(chains: Array[PackedVector2Array]) -> void:
	for hi: int in range(_h_present.size()):
		if _h_present[hi] != 0:
			@warning_ignore("integer_division")
			var pts: PackedVector2Array = _walk(hi % _width, hi / _width)
			if pts.size() >= 2:
				chains.append(pts)
	for vi: int in range(_v_present.size()):
		if _v_present[vi] != 0:
			@warning_ignore("integer_division")
			var pts: PackedVector2Array = _walk(vi % _w1, vi / _w1)
			if pts.size() >= 2:
				chains.append(pts)


# Finds the first present boundary edge touching vertex (vx, vy), marks it consumed, and
# returns the neighbour vertex as (x, y, 1). Returns (0, 0, 0) when none remain. Order is
# fixed (right, down, left, up) — any consistent order traces the same chains.
func _consume_incident(vx: int, vy: int) -> Vector3i:
	if vx < _width:
		var right: int = vy * _width + vx
		if _h_present[right] != 0:
			_h_present[right] = 0
			return Vector3i(vx + 1, vy, 1)
	if vy < _height:
		var down: int = vy * _w1 + vx
		if _v_present[down] != 0:
			_v_present[down] = 0
			return Vector3i(vx, vy + 1, 1)
	if vx >= 1:
		var left: int = vy * _width + (vx - 1)
		if _h_present[left] != 0:
			_h_present[left] = 0
			return Vector3i(vx - 1, vy, 1)
	if vy >= 1:
		var up: int = (vy - 1) * _w1 + vx
		if _v_present[up] != 0:
			_v_present[up] = 0
			return Vector3i(vx, vy - 1, 1)
	return Vector3i(0, 0, 0)


# --- Stage 3-4: simplify + smooth (static, pure) -----------------------------------------

# Ramer-Douglas-Peucker: drops the staircase down to the vertices that actually define the
# shape (perpendicular deviation > epsilon). Endpoints are always kept, so junction-anchored
# chains stay welded to their neighbours. Iterative (explicit stack) to avoid deep recursion
# on long coastlines. Best used on OPEN chains — a closed loop's coincident endpoints give a
# zero-length baseline, so callers should skip it for loops.
static func simplify(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var n: int = points.size()
	if n < 3 or epsilon <= 0.0:
		return points
	var keep: PackedByteArray = PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var a: int = seg.x
		var b: int = seg.y
		var max_d: float = epsilon
		var idx: int = -1
		for i in range(a + 1, b):
			var d: float = _perp_dist(points[i], points[a], points[b])
			if d > max_d:
				max_d = d
				idx = i
		if idx != -1:
			keep[idx] = 1
			stack.push_back(Vector2i(a, idx))
			stack.push_back(Vector2i(idx, b))
	var out: PackedVector2Array = PackedVector2Array()
	for i in range(n):
		if keep[i] == 1:
			out.append(points[i])
	return out


# Chaikin corner-cutting: each pass replaces every corner with two points at 1/4 and 3/4 of
# its segments, rounding the polyline. Open chains pin their endpoints (junctions stay put);
# closed loops (first point == last) are cut cyclically and re-closed.
static func smooth(points: PackedVector2Array, iterations: int, closed: bool) -> PackedVector2Array:
	var current: PackedVector2Array = points
	for _it in range(iterations):
		current = _chaikin_once(current, closed)
	return current


static func _chaikin_once(pts: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var n: int = pts.size()
	if n < 3:
		return pts
	var out: PackedVector2Array = PackedVector2Array()
	if closed:
		var m: int = n - 1  # last point duplicates the first
		for i in range(m):
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[(i + 1) % m]
			out.append(p0 * 0.75 + p1 * 0.25)
			out.append(p0 * 0.25 + p1 * 0.75)
		out.append(out[0])  # re-close
	else:
		out.append(pts[0])  # pin start (junction)
		for i in range(n - 1):
			var q0: Vector2 = pts[i]
			var q1: Vector2 = pts[i + 1]
			out.append(q0 * 0.75 + q1 * 0.25)
			out.append(q0 * 0.25 + q1 * 0.75)
		out.append(pts[n - 1])  # pin end (junction)
	return out


static func _perp_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.0000001:
		return p.distance_to(a)
	return absf((p.x - a.x) * ab.y - (p.y - a.y) * ab.x) / sqrt(len2)
