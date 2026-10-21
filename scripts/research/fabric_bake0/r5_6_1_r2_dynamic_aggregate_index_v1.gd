extends RefCounted
## FABRIC R5.6.1 R2 — derived, bounded, updateable physical moment index.
## Point-mass/position floor of canonical ConstructionPartRecord.v1 ONLY.
## One O(N) build of 10 Fenwick moments, O(k log N) *moment/index work* per
## owner-validated part update. Full canonical snapshot/proposal checks are
## intentionally external and may still cost O(N); no total O(local) claim.
## This index must be used behind an externally-fenced canonical Store session.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")

const SCHEMA := "planet_simulator.fabric_r56_r2_dynamic_moments.v1"
const RESULT_SCHEMA := "planet_simulator.fabric_r56_r2_point_mass_aggregate.v1"
const MOMENTS := ["mass", "sx", "sy", "sz", "jxx", "jxy", "jxz", "jyy", "jyz", "jzz"]
const MAX_CHANGED_PARTS := 16
const MAX_PARTS := 100000
const MASS_ABS_TOL := 1.0e-8
const MASS_REL_TOL := 1.0e-10
## Conservative numerical conditioning, NOT a rigorous interval proof.
## The raw-minus-centroid inertia formula can silently lose all variance
## when finite source coordinates have a very large shared offset. Index
## moments are therefore relative to one source part; range subtraction
## additionally fails closed when double-roundoff could dominate the result.
const DOUBLE_EPSILON := 2.220446049250313e-16
const ROUNDING_GUARD_FACTOR := 64.0
const INERTIA_ABS_PRECISION := 1.0e-6
const INERTIA_REL_PRECISION := 1.0e-8
## Research point-mass descriptor contract: at most 1 micrometer of error
## solely from representing a source-relative COM in an absolute Float64.
## This is a bounded publication envelope, not a universal physical error
## guarantee for Fenwick rounding, canonical geometry or other worlds.
## Returning an anchored pair would require a new consumer/schema contract.
const COM_ABS_PRECISION_M := 1.0e-6

var _count: int = 0
var _construct_id := ""
var _source_checksum := ""
var _revision: int = -1
var _origin: Vector3 = Vector3.ZERO
var _index_by_id: Dictionary = {}
var _mass := PackedFloat64Array()
var _x := PackedFloat64Array()
var _y := PackedFloat64Array()
var _z := PackedFloat64Array()
var _trees: Array = [] # ten PackedFloat64Array moments, each size N+1
var _built_parts: int = 0
var _updated_parts: int = 0
var _touched_nodes: int = 0
var _update_full_scans: int = 0
var _accepted_updates: int = 0

func initialize(snapshot: Dictionary) -> Dictionary:
	if _count != 0:
		return U.failure("R56_R2_INDEX_ALREADY_INITIALIZED")
	var valid: Dictionary = Snapshot.validate(snapshot)
	if not bool(valid.get("success", false)):
		return U.failure("R56_R2_SOURCE_INVALID", {"cause": valid.get("error_code", "")})
	var rows: Array = snapshot.parts
	var n: int = rows.size()
	if n < 1 or n > MAX_PARTS:
		return U.failure("R56_R2_PART_COUNT_UNSUPPORTED", {"count": n})
	var trees: Array = []
	for _field in MOMENTS:
		var tree := PackedFloat64Array()
		tree.resize(n + 1)
		trees.append(tree)
	var next_mass := PackedFloat64Array(); next_mass.resize(n)
	var next_x := PackedFloat64Array(); next_x.resize(n)
	var next_y := PackedFloat64Array(); next_y.resize(n)
	var next_z := PackedFloat64Array(); next_z.resize(n)
	var id_to_index: Dictionary = {}
	# Per-subject reference cancels a common offset before squaring positions.
	# This reference never changes during sparse updates, preserving BIT cost.
	var r0: Array = rows[0].local_position_m
	var origin := Vector3(float(r0[0]), float(r0[1]), float(r0[2]))
	for i in range(n):
		var part: Dictionary = rows[i]
		var moment: PackedFloat64Array = _moment(part, origin)
		if moment.size() != MOMENTS.size():
			return U.failure("R56_R2_PART_MOMENT_INVALID", {"id": part.get("part_id", "")})
		var part_id := String(part.part_id)
		if id_to_index.has(part_id):
			return U.failure("R56_R2_DUPLICATE_PART")
		id_to_index[part_id] = i
		next_mass[i] = float(part.mass_kg)
		next_x[i] = float(part.local_position_m[0])
		next_y[i] = float(part.local_position_m[1])
		next_z[i] = float(part.local_position_m[2])
		var pos := i + 1
		var parent := pos + (pos & -pos)
		for field in range(MOMENTS.size()):
			var tree: PackedFloat64Array = trees[field]
			tree[pos] += moment[field]
			if parent <= n:
				tree[parent] += tree[pos]
			if not is_finite(tree[pos]) or (parent <= n and not is_finite(tree[parent])):
				return U.failure("R56_R2_BUILD_NONFINITE")
			trees[field] = tree
	# No partially initialized index is published before every row is checked.
	_count = n
	_trees = trees
	_index_by_id = id_to_index
	_mass = next_mass
	_x = next_x
	_y = next_y
	_z = next_z
	_origin = origin
	_construct_id = String(snapshot.construct_id)
	_source_checksum = String(snapshot.checksum)
	_revision = int(snapshot.state_revision)
	_built_parts = n
	return U.success(status())

## MUST be called only AFTER the owning Construction Store committed an exact
## previously authenticated mutation. changed_rows are already vetted against
## the complete owner-approved successor by the R2 session. This function still
## checks the previously cached part values, source revision, all finite moments,
## and prospective node values before any tree/source mutation.
func apply_owner_verified(changed_rows: Array, old_checksum: String, new_checksum: String,
		new_revision: int, matter_mass_kg: float) -> Dictionary:
	if _count < 1 or _source_checksum != old_checksum or new_revision != _revision + 1:
		return U.failure("R56_R2_INDEX_SOURCE_STALE")
	if changed_rows.size() < 1 or changed_rows.size() > MAX_CHANGED_PARTS:
		return U.failure("R56_R2_DELTA_SIZE_INVALID")
	if not U.is_lower_hex_64(new_checksum) or new_checksum == old_checksum:
		return U.failure("R56_R2_SUCCESSOR_CHECKSUM_INVALID")
	if not is_finite(matter_mass_kg) or matter_mass_kg <= 0.0:
		return U.failure("R56_R2_MATTER_MASS_INVALID")
	var updates: Array = []
	var node_deltas: Dictionary = {} # node int -> vector of 10 moment deltas
	var previous_id := ""
	var total_mass_delta := 0.0
	for row in changed_rows:
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("before")) != TYPE_DICTIONARY or typeof(row.get("after")) != TYPE_DICTIONARY:
			return U.failure("R56_R2_DELTA_SHAPE_INVALID")
		var before: Dictionary = row.before
		var after: Dictionary = row.after
		var part_id := String(before.get("part_id", ""))
		if part_id.is_empty() or not _index_by_id.has(part_id) or String(after.get("part_id", "")) != part_id or (not previous_id.is_empty() and part_id <= previous_id):
			return U.failure("R56_R2_DELTA_PART_ID_INVALID")
		previous_id = part_id
		if not Part.validate(before).success or not Part.validate(after).success:
			return U.failure("R56_R2_DELTA_PART_INVALID")
		var offset: int = int(_index_by_id[part_id])
		if float(before.mass_kg) != _mass[offset] or float(before.local_position_m[0]) != _x[offset] or float(before.local_position_m[1]) != _y[offset] or float(before.local_position_m[2]) != _z[offset]:
			return U.failure("R56_R2_CACHED_PART_MISMATCH", {"part_id": part_id})
		var old_mom: PackedFloat64Array = _moment(before, _origin)
		var new_mom: PackedFloat64Array = _moment(after, _origin)
		if old_mom.size() != MOMENTS.size() or new_mom.size() != MOMENTS.size():
			return U.failure("R56_R2_PART_MOMENT_INVALID", {"part_id": part_id})
		var differences := PackedFloat64Array()
		differences.resize(MOMENTS.size())
		var changed := false
		for field in range(MOMENTS.size()):
			var delta := new_mom[field] - old_mom[field]
			if not is_finite(delta):
				return U.failure("R56_R2_DELTA_NONFINITE")
			differences[field] = delta
			if delta != 0.0:
				changed = true
		if not changed:
			return U.failure("R56_R2_NO_PHYSICAL_MOMENT_CHANGE")
		total_mass_delta += differences[0]
		updates.append({"offset": offset, "new_mass": float(after.mass_kg), "new_x": float(after.local_position_m[0]), "new_y": float(after.local_position_m[1]), "new_z": float(after.local_position_m[2])})
		var node := offset + 1
		while node <= _count:
			var vec: PackedFloat64Array = node_deltas.get(node, PackedFloat64Array())
			if vec.is_empty():
				vec.resize(MOMENTS.size())
			for field in range(MOMENTS.size()):
				vec[field] += differences[field]
				if not is_finite(vec[field]):
					return U.failure("R56_R2_COMBINED_DELTA_NONFINITE")
			node_deltas[node] = vec
			node += node & -node
	var previous_total: Dictionary = query_range(0, _count)
	if not previous_total.success:
		return previous_total
	var predicted_mass := float(previous_total.details.total_mass) + total_mass_delta
	if not _near(predicted_mass, matter_mass_kg):
		return U.failure("R56_R2_MATTER_MASS_MISMATCH", {"predicted": predicted_mass, "matter": matter_mass_kg})
	# Validate every prospective tree node BEFORE any observable mutation.
	for node in node_deltas:
		var v: PackedFloat64Array = node_deltas[node]
		for field in range(MOMENTS.size()):
			if not is_finite(float(_trees[field][node]) + v[field]):
				return U.failure("R56_R2_TREE_UPDATE_NONFINITE")
	# Commit is now infallible: no allocations, hash/validation or external calls.
	for node in node_deltas:
		var d: PackedFloat64Array = node_deltas[node]
		for field in range(MOMENTS.size()):
			var tree: PackedFloat64Array = _trees[field]
			tree[node] += d[field]
			_trees[field] = tree
	for row in updates:
		var i: int = row.offset
		_mass[i] = row.new_mass
		_x[i] = row.new_x
		_y[i] = row.new_y
		_z[i] = row.new_z
	_source_checksum = new_checksum
	_revision = new_revision
	_updated_parts += updates.size()
	_touched_nodes += node_deltas.size()
	_accepted_updates += 1
	return U.success({"parts_updated": updates.size(), "fenwick_nodes_touched": node_deltas.size(), "full_moment_scans": 0, "index_status": status()})

func query_range(first: int, end_exclusive: int) -> Dictionary:
	if _count < 1 or first < 0 or end_exclusive > _count or first >= end_exclusive:
		return U.failure("R56_R2_RANGE_INVALID")
	var prefix_right := _prefix(end_exclusive)
	var prefix_left := _prefix(first)
	var m: PackedFloat64Array = PackedFloat64Array()
	m.resize(MOMENTS.size())
	for i in range(MOMENTS.size()):
		m[i] = prefix_right[i] - prefix_left[i]
		if not is_finite(m[i]):
			return U.failure("R56_R2_RANGE_NONFINITE")
	if m[0] <= 0.0:
		return U.failure("R56_R2_RANGE_MASS_INVALID")
	var cx := m[1] / m[0]
	var cy := m[2] / m[0]
	var cz := m[3] / m[0]
	var ix := m[4] - m[0] * (cy * cy + cz * cz)
	var ixy := m[5] + m[0] * cx * cy
	var ixz := m[6] + m[0] * cx * cz
	var iy := m[7] - m[0] * (cx * cx + cz * cz)
	var iyz := m[8] + m[0] * cy * cz
	var iz := m[9] - m[0] * (cx * cx + cy * cy)
	# Numerical risk is dominated by differences of two large Fenwick
	# prefixes and the subsequent parallel-axis shift. Reject an ill-conditioned
	# range rather than publishing a finite but physically false tensor.
	var axes := [4, 5, 6, 7, 8, 9]
	var shifts := [m[0]*(cy*cy+cz*cz), m[0]*cx*cy, m[0]*cx*cz,
		m[0]*(cx*cx+cz*cz), m[0]*cy*cz, m[0]*(cx*cx+cy*cy)]
	var centered := [ix, ixy, ixz, iy, iyz, iz]
	for i in range(axes.size()):
		var k: int = axes[i]
		var uncertainty := ROUNDING_GUARD_FACTOR * DOUBLE_EPSILON * (
			absf(prefix_right[k]) + absf(prefix_left[k]) + absf(shifts[i]))
		var budget := INERTIA_ABS_PRECISION + INERTIA_REL_PRECISION * absf(centered[i])
		if not is_finite(uncertainty) or uncertainty > budget:
			return U.failure("R56_R2_RANGE_NUMERIC_PRECISION_UNSAFE",
				{"component": k, "roundoff_estimate": uncertainty, "accuracy_budget": budget})
	var local_center := [cx, cy, cz]
	var origin_xyz := [_origin.x, _origin.y, _origin.z]
	var world_center := [cx + _origin.x, cy + _origin.y, cz + _origin.z]
	# The source-anchored moments can be accurate while the published absolute
	# Float64 COM cannot represent a sub-ULP local displacement. Round-trip the
	# *actual published value* into the anchor frame and compare the loss to
	# the declared bounded research envelope. Do not claim world-wide accuracy.
	for axis in range(3):
		var published: float = float(world_center[axis])
		var anchored: float = float(local_center[axis])
		if not is_finite(published) or not is_finite(anchored):
			return U.failure("R56_R2_RANGE_CENTER_NONFINITE")
		var reconstructed: float = published - float(origin_xyz[axis])
		var representation_loss: float = absf(reconstructed - anchored)
		if not is_finite(representation_loss) or representation_loss > COM_ABS_PRECISION_M:
			return U.failure("R56_R2_RANGE_CENTER_PRECISION_UNSAFE",
				{"axis": axis, "representation_error_m": representation_loss,
				"absolute_accuracy_budget_m": COM_ABS_PRECISION_M})
	var descriptor := {
		"schema": RESULT_SCHEMA, "construct_id": _construct_id,
		"source_checksum": _source_checksum, "revision": _revision,
		"first": first, "end_exclusive": end_exclusive,
		"total_mass": m[0], "center_of_mass": world_center,
		"inertia_tensor_body": [[ix, ixy, ixz], [ixy, iy, iyz], [ixz, iyz, iz]],
		"checksum": "",
	}
	for row in descriptor.inertia_tensor_body:
		for entry in row:
			if not is_finite(entry):
				return U.failure("R56_R2_RANGE_INERTIA_NONFINITE")
	descriptor.checksum = U.compute_checksum(descriptor)
	return U.success(descriptor)

func status() -> Dictionary:
	return {"schema": SCHEMA, "count": _count, "construct_id": _construct_id,
		"source_checksum": _source_checksum, "revision": _revision,
		"build_scanned_parts": _built_parts, "updated_parts": _updated_parts,
		"fenwick_nodes_touched": _touched_nodes, "update_full_moment_scans": _update_full_scans,
		"accepted_updates": _accepted_updates, "physical_floor": "POINT_MASS_ONLY"}

func _prefix(end_exclusive: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(MOMENTS.size())
	var j := end_exclusive
	while j > 0:
		for field in range(MOMENTS.size()):
			result[field] += float(_trees[field][j])
		j -= j & -j
	return result

static func _moment(part: Dictionary, origin: Vector3 = Vector3.ZERO) -> PackedFloat64Array:
	if not U.is_finite_number(part.get("mass_kg", null)) or float(part.mass_kg) <= 0.0:
		return PackedFloat64Array()
	var xyz: Array = part.get("local_position_m", [])
	if xyz.size() != 3 or not U.is_finite_number(xyz[0]) or not U.is_finite_number(xyz[1]) or not U.is_finite_number(xyz[2]):
		return PackedFloat64Array()
	var m := float(part.mass_kg)
	var x := float(xyz[0]) - origin.x; var y := float(xyz[1]) - origin.y; var z := float(xyz[2]) - origin.z
	var values := PackedFloat64Array([m, m*x, m*y, m*z, m*(y*y+z*z), -m*x*y,
		-m*x*z, m*(x*x+z*z), -m*y*z, m*(x*x+y*y)])
	for v in values:
		if not is_finite(v):
			return PackedFloat64Array()
	return values

static func _near(a: float, b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a-b) <= MASS_ABS_TOL + MASS_REL_TOL*maxf(1.0, maxf(absf(a), absf(b)))
