extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")

const SCHEMA := "planet_simulator.matter_multiresolution_mesh_data.v1"
const STATUS_EMPTY := "EMPTY"
const STATUS_READY := "READY"
const MEDIA_TYPE := "application/vnd.planet-simulator.matter-mesh"
const HASH_SCALE: float = 1000000.0
const FIELDS: Array[String] = [
	"schema",
	"representation_key",
	"source_field_hash",
	"source_snapshot_set_hash",
	"origin_body_local_m",
	"bounds_m",
	"iso_level_m",
	"sample_spacing_m",
	"geometric_error_m",
	"status",
	"vertices",
	"normals",
	"colors",
	"indices",
	"triangle_count",
	"surface_bounds_min_m",
	"surface_bounds_max_m",
	"content_hash",
]


static func create(
	representation_key: Dictionary,
	source_field_hash: String,
	source_snapshot_set_hash: String,
	origin_body_local_m: Vector3,
	bounds_m: Array,
	iso_level_m: float,
	sample_spacing_m: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> Dictionary:
	var surface_bounds: Dictionary = _bounds(vertices)
	var triangle_count: int = int(indices.size() / 3)
	var value: Dictionary = {
		"schema": SCHEMA,
		"representation_key": representation_key.duplicate(true),
		"source_field_hash": source_field_hash,
		"source_snapshot_set_hash": source_snapshot_set_hash,
		"origin_body_local_m": origin_body_local_m,
		"bounds_m": bounds_m.duplicate(true),
		"iso_level_m": iso_level_m,
		"sample_spacing_m": sample_spacing_m,
		"geometric_error_m": sample_spacing_m * sqrt(3.0) * 0.5,
		"status": STATUS_EMPTY if triangle_count == 0 else STATUS_READY,
		"vertices": vertices.duplicate(),
		"normals": normals.duplicate(),
		"colors": colors.duplicate(),
		"indices": indices.duplicate(),
		"triangle_count": triangle_count,
		"surface_bounds_min_m": surface_bounds["minimum_m"],
		"surface_bounds_max_m": surface_bounds["maximum_m"],
		"content_hash": "",
	}
	value["content_hash"] = _compute_content_hash(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	for field in FIELDS:
		if not value.has(field):
			return RepresentationUtils.failure("MISSING_MATTER_MULTIRESOLUTION_MESH_FIELD", {"field": field})
	if value.size() != FIELDS.size():
		return RepresentationUtils.failure("UNEXPECTED_MATTER_MULTIRESOLUTION_MESH_FIELD")
	if value.get("schema") != SCHEMA:
		return RepresentationUtils.failure("UNSUPPORTED_MATTER_MULTIRESOLUTION_MESH_SCHEMA")
	if typeof(value.get("representation_key")) != TYPE_DICTIONARY:
		return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_MESH_KEY")
	var checked: Dictionary = RepresentationKey.validate(value["representation_key"])
	if not bool(checked.get("success", false)):
		return checked
	var key: Dictionary = value["representation_key"]
	var lod_level: int = int(key["lod_level"])
	var expected_kind: String = "DETAIL" if lod_level == 0 else ("SIMPLIFIED_MESH" if lod_level == 1 else "MACRO_PROXY")
	if lod_level < 0 or lod_level > 2 or String(key["artifact_kind"]) != expected_kind:
		return RepresentationUtils.failure("MATTER_MULTIRESOLUTION_MESH_ARTIFACT_KIND_MISMATCH")
	for field in ["source_field_hash", "source_snapshot_set_hash"]:
		if not RepresentationUtils.is_lower_hex_64(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_SOURCE_HASH", {"field": field})
	if typeof(value.get("origin_body_local_m")) != TYPE_VECTOR3 \
		or not _finite_vector(value["origin_body_local_m"]):
		return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_MESH_ORIGIN")
	checked = RepresentationUtils.validate_bounds_m(value.get("bounds_m"))
	if not bool(checked.get("success", false)):
		return checked
	for field in ["iso_level_m", "sample_spacing_m", "geometric_error_m"]:
		if not RepresentationUtils.is_finite_number(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_MESH_NUMBER", {"field": field})
	if float(value["sample_spacing_m"]) <= 0.0 or float(value["geometric_error_m"]) < 0.0:
		return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_MESH_ERROR")
	if not is_equal_approx(
		float(value["geometric_error_m"]), float(value["sample_spacing_m"]) * sqrt(3.0) * 0.5
	):
		return RepresentationUtils.failure("MATTER_MULTIRESOLUTION_GEOMETRIC_ERROR_MISMATCH")
	if typeof(value.get("status")) != TYPE_STRING \
		or String(value["status"]) not in [STATUS_EMPTY, STATUS_READY]:
		return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_MESH_STATUS")
	if typeof(value.get("vertices")) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(value.get("normals")) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(value.get("colors")) != TYPE_PACKED_COLOR_ARRAY \
		or typeof(value.get("indices")) != TYPE_PACKED_INT32_ARRAY:
		return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_MESH_ARRAYS")
	var vertices: PackedVector3Array = value["vertices"]
	var normals: PackedVector3Array = value["normals"]
	var colors: PackedColorArray = value["colors"]
	var indices: PackedInt32Array = value["indices"]
	if vertices.size() != normals.size() or vertices.size() != colors.size():
		return RepresentationUtils.failure("MATTER_MULTIRESOLUTION_ATTRIBUTE_SIZE_MISMATCH")
	if indices.size() % 3 != 0:
		return RepresentationUtils.failure("MATTER_MULTIRESOLUTION_INDEX_COUNT_MISMATCH")
	for index in range(vertices.size()):
		if not _finite_vector(vertices[index]) or not _finite_vector(normals[index]) \
			or absf(normals[index].length_squared() - 1.0) > 0.0001:
			return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_VERTEX", {"index": index})
		var color: Color = colors[index]
		if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a) \
			or color.r < 0.0 or color.r > 1.0 or color.g < 0.0 or color.g > 1.0 \
			or color.b < 0.0 or color.b > 1.0 or color.a < 0.0 or color.a > 1.0:
			return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_COLOR", {"index": index})
	for index in indices:
		if index < 0 or index >= vertices.size():
			return RepresentationUtils.failure("MATTER_MULTIRESOLUTION_INDEX_OUT_OF_RANGE")
	if not RepresentationUtils.is_json_integer(value.get("triangle_count")) \
		or int(value["triangle_count"]) != int(indices.size() / 3):
		return RepresentationUtils.failure("MATTER_MULTIRESOLUTION_TRIANGLE_COUNT_MISMATCH")
	if int(value["triangle_count"]) == 0:
		if String(value["status"]) != STATUS_EMPTY \
			or not vertices.is_empty() or not normals.is_empty() or not colors.is_empty():
			return RepresentationUtils.failure("EMPTY_MATTER_MULTIRESOLUTION_MESH_MISMATCH")
	elif String(value["status"]) != STATUS_READY or vertices.is_empty():
		return RepresentationUtils.failure("READY_MATTER_MULTIRESOLUTION_MESH_MISMATCH")
	for field in ["surface_bounds_min_m", "surface_bounds_max_m"]:
		if typeof(value.get(field)) != TYPE_VECTOR3 or not _finite_vector(value[field]):
			return RepresentationUtils.failure("INVALID_MATTER_MULTIRESOLUTION_SURFACE_BOUNDS")
	var expected_bounds: Dictionary = _bounds(vertices)
	if not value["surface_bounds_min_m"].is_equal_approx(expected_bounds["minimum_m"]) \
		or not value["surface_bounds_max_m"].is_equal_approx(expected_bounds["maximum_m"]):
		return RepresentationUtils.failure("MATTER_MULTIRESOLUTION_SURFACE_BOUNDS_MISMATCH")
	if not RepresentationUtils.is_lower_hex_64(value.get("content_hash")) \
		or String(value["content_hash"]) != _compute_content_hash(value):
		return RepresentationUtils.failure("MATTER_MULTIRESOLUTION_CONTENT_HASH_MISMATCH")
	return RepresentationUtils.success()


static func to_artifact_manifest(
	value: Dictionary,
	collision_capable: bool,
	interior_capable: bool,
	build_generation: int
) -> Dictionary:
	if not bool(validate(value).get("success", false)) or build_generation < 1:
		return {}
	var artifact_kind: String = String(value["representation_key"]["artifact_kind"])
	if collision_capable and artifact_kind != "DETAIL":
		return {}
	if interior_capable and artifact_kind == "MACRO_PROXY":
		return {}
	return ArtifactManifest.create(
		value["representation_key"],
		String(value["content_hash"]),
		estimated_byte_size(value),
		"RAW",
		MEDIA_TYPE,
		float(value["geometric_error_m"]),
		value["bounds_m"],
		collision_capable,
		interior_capable,
		build_generation
	)


static func estimated_byte_size(value: Dictionary) -> int:
	if not bool(validate(value).get("success", false)):
		return 0
	var vertices: PackedVector3Array = value["vertices"]
	var normals: PackedVector3Array = value["normals"]
	var colors: PackedColorArray = value["colors"]
	var indices: PackedInt32Array = value["indices"]
	return maxi(1, 256 + vertices.size() * 24 + normals.size() * 24 + colors.size() * 32 + indices.size() * 4)


static func world_vertex(value: Dictionary, index: int) -> Vector3:
	if not bool(validate(value).get("success", false)):
		return Vector3(INF, INF, INF)
	var vertices: PackedVector3Array = value["vertices"]
	if index < 0 or index >= vertices.size():
		return Vector3(INF, INF, INF)
	return value["origin_body_local_m"] + vertices[index]


static func _bounds(vertices: PackedVector3Array) -> Dictionary:
	if vertices.is_empty():
		return {"minimum_m": Vector3.ZERO, "maximum_m": Vector3.ZERO}
	var minimum_m: Vector3 = vertices[0]
	var maximum_m: Vector3 = vertices[0]
	for vertex in vertices:
		minimum_m = Vector3(minf(minimum_m.x, vertex.x), minf(minimum_m.y, vertex.y), minf(minimum_m.z, vertex.z))
		maximum_m = Vector3(maxf(maximum_m.x, vertex.x), maxf(maximum_m.y, vertex.y), maxf(maximum_m.z, vertex.z))
	return {"minimum_m": minimum_m, "maximum_m": maximum_m}


static func _compute_content_hash(value: Dictionary) -> String:
	var vertices: PackedVector3Array = value.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = value.get("normals", PackedVector3Array())
	var colors: PackedColorArray = value.get("colors", PackedColorArray())
	var indices: PackedInt32Array = value.get("indices", PackedInt32Array())
	var signature: Array = []
	for index in range(vertices.size()):
		var vertex: Vector3 = vertices[index]
		var normal: Vector3 = normals[index]
		var color: Color = colors[index]
		signature.append([
			int(round(vertex.x * HASH_SCALE)), int(round(vertex.y * HASH_SCALE)), int(round(vertex.z * HASH_SCALE)),
			int(round(normal.x * HASH_SCALE)), int(round(normal.y * HASH_SCALE)), int(round(normal.z * HASH_SCALE)),
			int(round(color.r * HASH_SCALE)), int(round(color.g * HASH_SCALE)), int(round(color.b * HASH_SCALE)), int(round(color.a * HASH_SCALE)),
		])
	return RepresentationUtils.payload_hash({
		"representation_key_checksum": Dictionary(value.get("representation_key", {})).get("checksum", ""),
		"source_field_hash": value.get("source_field_hash", ""),
		"source_snapshot_set_hash": value.get("source_snapshot_set_hash", ""),
		"bounds_m": value.get("bounds_m", []),
		"iso_level_m": value.get("iso_level_m", 0.0),
		"sample_spacing_m": value.get("sample_spacing_m", 0.0),
		"geometry": signature,
		"indices": Array(indices),
	})


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
