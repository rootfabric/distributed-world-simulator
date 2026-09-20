extends RefCounted
## R5.1 derived range aggregate index.
## One O(N) compile produces prefix physical moments; any contiguous span can
## then be reconstructed without scanning hidden parts again.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Source = preload("res://scripts/research/fabric_bake0/complex3_streaming_canonical_structure_v1.gd")

const SCHEMA := "planet_simulator.fabric_r5_1_range_aggregate_index.v1"
const VERSION := "FABRIC_R5_1_RANGE_INDEX_R1"
const PREFIX_READS_PER_QUERY := 20

static func build(spec: Dictionary) -> Dictionary:
	var count := int(spec.get("part_count", -1))
	if count <= 0 or not spec.has("expanded_part_digest"):
		return U.failure("R5_1_RANGE_INDEX_SOURCE_INVALID")
	var mass := PackedFloat64Array(); mass.resize(count + 1)
	var sx := PackedFloat64Array(); sx.resize(count + 1)
	var sy := PackedFloat64Array(); sy.resize(count + 1)
	var sz := PackedFloat64Array(); sz.resize(count + 1)
	var jxx := PackedFloat64Array(); jxx.resize(count + 1)
	var jxy := PackedFloat64Array(); jxy.resize(count + 1)
	var jxz := PackedFloat64Array(); jxz.resize(count + 1)
	var jyy := PackedFloat64Array(); jyy.resize(count + 1)
	var jyz := PackedFloat64Array(); jyz.resize(count + 1)
	var jzz := PackedFloat64Array(); jzz.resize(count + 1)
	for i in range(count):
		var part := Source.part_model(i)
		var m := float(part.mass)
		var p := Vector3(float(part.position[0]), float(part.position[1]), float(part.position[2]))
		var inertia: Array = part.inertia_tensor
		var n := i + 1
		mass[n] = mass[i] + m
		sx[n] = sx[i] + m * p.x
		sy[n] = sy[i] + m * p.y
		sz[n] = sz[i] + m * p.z
		jxx[n] = jxx[i] + float(inertia[0][0]) + m * (p.y * p.y + p.z * p.z)
		jxy[n] = jxy[i] + float(inertia[0][1]) - m * p.x * p.y
		jxz[n] = jxz[i] + float(inertia[0][2]) - m * p.x * p.z
		jyy[n] = jyy[i] + float(inertia[1][1]) + m * (p.x * p.x + p.z * p.z)
		jyz[n] = jyz[i] + float(inertia[1][2]) - m * p.y * p.z
		jzz[n] = jzz[i] + float(inertia[2][2]) + m * (p.x * p.x + p.y * p.y)
	var prefix := {"mass": mass, "sx": sx, "sy": sy, "sz": sz,
		"jxx": jxx, "jxy": jxy, "jxz": jxz, "jyy": jyy, "jyz": jyz, "jzz": jzz}
	var index := {
		"schema": SCHEMA,
		"version": VERSION,
		"part_count": count,
		"expanded_part_digest": String(spec.expanded_part_digest),
		"prefix": prefix,
		"summary_hash": U.canonical_hash({
			"schema": SCHEMA, "version": VERSION, "part_count": count,
			"expanded_part_digest": String(spec.expanded_part_digest),
			"mass_total": mass[count], "sx_total": sx[count], "sy_total": sy[count], "sz_total": sz[count],
			"jxx_total": jxx[count], "jyy_total": jyy[count], "jzz_total": jzz[count],
		}),
	}
	return U.success({"index": index, "parts_scanned": count})

static func validate(index: Dictionary, spec: Dictionary) -> Dictionary:
	if index.get("schema") != SCHEMA or index.get("version") != VERSION:
		return U.failure("R5_1_RANGE_INDEX_SCHEMA_INVALID")
	var count := int(spec.get("part_count", -1))
	if int(index.get("part_count", -2)) != count or String(index.get("expanded_part_digest", "")) != String(spec.get("expanded_part_digest", "")):
		return U.failure("R5_1_RANGE_INDEX_SOURCE_MISMATCH")
	if typeof(index.get("prefix")) != TYPE_DICTIONARY:
		return U.failure("R5_1_RANGE_INDEX_PREFIX_INVALID")
	for field in ["mass","sx","sy","sz","jxx","jxy","jxz","jyy","jyz","jzz"]:
		if typeof(index.prefix.get(field)) != TYPE_PACKED_FLOAT64_ARRAY or index.prefix[field].size() != count + 1:
			return U.failure("R5_1_RANGE_INDEX_PREFIX_INVALID", {"field": field})
	return U.success()

static func aggregate(index: Dictionary, spec: Dictionary, first: int, end_exclusive: int) -> Dictionary:
	var checked := validate(index, spec)
	if not checked.success:
		return checked
	var count := int(spec.part_count)
	if first < 0 or end_exclusive > count or first >= end_exclusive:
		return U.failure("R5_1_RANGE_INDEX_SPAN_INVALID", {"first": first, "end": end_exclusive, "count": count})
	var p: Dictionary = index.prefix
	var mass := _delta(p.mass, first, end_exclusive)
	if mass <= 0.0 or not is_finite(mass):
		return U.failure("R5_1_RANGE_INDEX_MASS_INVALID")
	var sx := _delta(p.sx, first, end_exclusive)
	var sy := _delta(p.sy, first, end_exclusive)
	var sz := _delta(p.sz, first, end_exclusive)
	var c := Vector3(sx / mass, sy / mass, sz / mass)
	var jxx := _delta(p.jxx, first, end_exclusive)
	var jxy := _delta(p.jxy, first, end_exclusive)
	var jxz := _delta(p.jxz, first, end_exclusive)
	var jyy := _delta(p.jyy, first, end_exclusive)
	var jyz := _delta(p.jyz, first, end_exclusive)
	var jzz := _delta(p.jzz, first, end_exclusive)
	var ixx := jxx - mass * (c.y * c.y + c.z * c.z)
	var iyy := jyy - mass * (c.x * c.x + c.z * c.z)
	var izz := jzz - mass * (c.x * c.x + c.y * c.y)
	var ixy := jxy + mass * c.x * c.y
	var ixz := jxz + mass * c.x * c.z
	var iyz := jyz + mass * c.y * c.z
	var descriptor := {
		"schema": Source.AGGREGATE_SCHEMA,
		"source_checksum": String(spec.checksum),
		"first_part": first,
		"end_exclusive": end_exclusive,
		"part_count": end_exclusive - first,
		"total_mass": mass,
		"center_of_mass": [c.x, c.y, c.z],
		"inertia_tensor_body": [[ixx, ixy, ixz], [ixy, iyy, iyz], [ixz, iyz, izz]],
		"span_hash": U.canonical_hash({"source_checksum": String(spec.checksum), "first": first, "end": end_exclusive}),
		"checksum": "",
	}
	descriptor.checksum = U.compute_checksum(descriptor)
	return U.success({"descriptor": descriptor, "parts_scanned": 0, "prefix_reads": PREFIX_READS_PER_QUERY})

static func _delta(values: PackedFloat64Array, first: int, end_exclusive: int) -> float:
	return float(values[end_exclusive]) - float(values[first])
