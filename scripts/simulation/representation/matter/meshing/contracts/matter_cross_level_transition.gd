extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")

const SCHEMA := "planet_simulator.matter_cross_level_transition.v1"
const STATUS_EMPTY := "EMPTY"
const STATUS_READY := "READY"
const MEDIA_TYPE := "application/vnd.planet-simulator.matter-transition-mesh"
const HASH_SCALE: float = 1000000.0
const FIELDS: Array[String] = [
	"schema",
	"representation_key",
	"fine_representation_key",
	"coarse_representation_key",
	"fine_artifact_hash",
	"coarse_artifact_hash",
	"axis",
	"direction",
	"plane_coordinate_m",
	"skirt_depth_m",
	"geometric_error_m",
	"boundary_segment_count",
	"boundary_segment_hash",
	"origin_body_local_m",
	"status",
	"vertices",
	"normals",
	"colors",
	"indices",
	"triangle_count",
	"content_hash",
]


static func create(
	representation_key: Dictionary,
	fine_key: Dictionary,
	coarse_key: Dictionary,
	fine_artifact_hash: String,
	coarse_artifact_hash: String,
	axis: int,
	direction: int,
	plane_coordinate_m: float,
	skirt_depth_m: float,
	geometric_error_m: float,
	boundary_segment_count: int,
	boundary_segment_hash: String,
	origin_body_local_m: Vector3,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> Dictionary:
	var triangle_count: int = int(indices.size() / 3)
	var value: Dictionary = {
		"schema": SCHEMA,
		"representation_key": representation_key.duplicate(true),
		"fine_representation_key": fine_key.duplicate(true),
		"coarse_representation_key": coarse_key.duplicate(true),
		"fine_artifact_hash": fine_artifact_hash,
		"coarse_artifact_hash": coarse_artifact_hash,
		"axis": axis,
		"direction": direction,
		"plane_coordinate_m": plane_coordinate_m,
		"skirt_depth_m": skirt_depth_m,
		"geometric_error_m": geometric_error_m,
		"boundary_segment_count": boundary_segment_count,
		"boundary_segment_hash": boundary_segment_hash,
		"origin_body_local_m": origin_body_local_m,
		"status": STATUS_EMPTY if triangle_count == 0 else STATUS_READY,
		"vertices": vertices.duplicate(),
		"normals": normals.duplicate(),
		"colors": colors.duplicate(),
		"indices": indices.duplicate(),
		"triangle_count": triangle_count,
		"content_hash": "",
	}
	value["content_hash"] = _compute_hash(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	for field in FIELDS:
		if not value.has(field):
			return RepresentationUtils.failure("MISSING_MATTER_TRANSITION_FIELD", {"field": field})
	if value.size() != FIELDS.size() or value.get("schema") != SCHEMA:
		return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_SCHEMA")
	for field in ["representation_key", "fine_representation_key", "coarse_representation_key"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_KEY", {"field": field})
		var checked: Dictionary = RepresentationKey.validate(value[field])
		if not bool(checked.get("success", false)):
			return checked
	var representation_key: Dictionary = value["representation_key"]
	var fine_key: Dictionary = value["fine_representation_key"]
	var coarse_key: Dictionary = value["coarse_representation_key"]
	if String(representation_key["scope_id"]) != String(fine_key["scope_id"]) \
		or int(representation_key["lod_level"]) != int(fine_key["lod_level"]) \
		or String(representation_key["artifact_kind"]) != String(fine_key["artifact_kind"]):
		return RepresentationUtils.failure("MATTER_TRANSITION_REPRESENTATION_KEY_MISMATCH")
	if int(coarse_key["lod_level"]) != int(fine_key["lod_level"]) + 1:
		return RepresentationUtils.failure("MATTER_TRANSITION_REQUIRES_ADJACENT_LOD")
	var fine_source: Dictionary = fine_key["source_revision"]
	var coarse_source: Dictionary = coarse_key["source_revision"]
	for field in ["fine_artifact_hash", "coarse_artifact_hash"]:
		if not RepresentationUtils.is_lower_hex_64(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_ARTIFACT_HASH", {"field": field})
	var transition_source: Dictionary = representation_key["source_revision"]
	if String(fine_source["source_domain"]) != "MATTER" \
		or String(coarse_source["source_domain"]) != "MATTER" \
		or String(fine_source["source_id"]) != String(coarse_source["source_id"]) \
		or int(fine_source["authority_epoch"]) != int(coarse_source["authority_epoch"]) \
		or String(transition_source["source_domain"]) != "MATTER" \
		or String(transition_source["source_id"]) != String(fine_source["source_id"]) \
		or int(transition_source["authority_epoch"]) != int(fine_source["authority_epoch"]):
		return RepresentationUtils.failure("MATTER_TRANSITION_SOURCE_MISMATCH")
	var expected_pair_hash: String = RepresentationUtils.payload_hash([
		{
			"role": "FINE",
			"key_checksum": String(fine_key["checksum"]),
			"artifact_hash": String(value["fine_artifact_hash"]),
		},
		{
			"role": "COARSE",
			"key_checksum": String(coarse_key["checksum"]),
			"artifact_hash": String(value["coarse_artifact_hash"]),
		},
	])
	var expected_dependency_hash: String = RepresentationUtils.payload_hash({
		"fine_source_checksum": String(fine_source["checksum"]),
		"coarse_source_checksum": String(coarse_source["checksum"]),
		"boundary_segment_hash": String(value.get("boundary_segment_hash", "")),
	})
	if int(transition_source["source_revision"]) != maxi(
		int(fine_source["source_revision"]), int(coarse_source["source_revision"])
	) or String(transition_source["source_hash"]) != expected_pair_hash \
		or String(transition_source["dependency_hash"]) != expected_dependency_hash:
		return RepresentationUtils.failure("MATTER_TRANSITION_PROVENANCE_MISMATCH")
	if not RepresentationUtils.is_json_integer(value.get("axis")) or int(value["axis"]) < 0 or int(value["axis"]) > 2:
		return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_AXIS")
	if not RepresentationUtils.is_json_integer(value.get("direction")) or int(value["direction"]) not in [-1, 1]:
		return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_DIRECTION")
	for field in ["plane_coordinate_m", "skirt_depth_m", "geometric_error_m"]:
		if not RepresentationUtils.is_finite_number(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_NUMBER", {"field": field})
	if float(value["skirt_depth_m"]) <= 0.0 \
		or float(value["geometric_error_m"]) < 0.0 \
		or float(value["skirt_depth_m"]) < float(value["geometric_error_m"]):
		return RepresentationUtils.failure("MATTER_TRANSITION_DEPTH_BELOW_ERROR")
	if not RepresentationUtils.is_json_integer(value.get("boundary_segment_count")) \
		or int(value["boundary_segment_count"]) < 0 \
		or not RepresentationUtils.is_lower_hex_64(value.get("boundary_segment_hash")):
		return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_BOUNDARY")
	if typeof(value.get("origin_body_local_m")) != TYPE_VECTOR3 \
		or not _finite_vector(value["origin_body_local_m"]):
		return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_ORIGIN")
	if typeof(value.get("status")) != TYPE_STRING or String(value["status"]) not in [STATUS_EMPTY, STATUS_READY]:
		return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_STATUS")
	if typeof(value.get("vertices")) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(value.get("normals")) != TYPE_PACKED_VECTOR3_ARRAY \
		or typeof(value.get("colors")) != TYPE_PACKED_COLOR_ARRAY \
		or typeof(value.get("indices")) != TYPE_PACKED_INT32_ARRAY:
		return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_ARRAYS")
	var vertices: PackedVector3Array = value["vertices"]
	var normals: PackedVector3Array = value["normals"]
	var colors: PackedColorArray = value["colors"]
	var indices: PackedInt32Array = value["indices"]
	if vertices.size() != normals.size() or vertices.size() != colors.size() or indices.size() % 3 != 0:
		return RepresentationUtils.failure("MATTER_TRANSITION_ARRAY_SIZE_MISMATCH")
	for index in range(vertices.size()):
		if not _finite_vector(vertices[index]) or not _finite_vector(normals[index]) \
			or absf(normals[index].length_squared() - 1.0) > 0.0001:
			return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_VERTEX", {"index": index})
		var color: Color = colors[index]
		if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) \
			or not is_finite(color.a) or color.r < 0.0 or color.r > 1.0 \
			or color.g < 0.0 or color.g > 1.0 or color.b < 0.0 or color.b > 1.0 \
			or color.a < 0.0 or color.a > 1.0:
			return RepresentationUtils.failure("INVALID_MATTER_TRANSITION_COLOR", {"index": index})
	for index in indices:
		if index < 0 or index >= vertices.size():
			return RepresentationUtils.failure("MATTER_TRANSITION_INDEX_OUT_OF_RANGE")
	if not RepresentationUtils.is_json_integer(value.get("triangle_count")) \
		or int(value["triangle_count"]) != int(indices.size() / 3):
		return RepresentationUtils.failure("MATTER_TRANSITION_TRIANGLE_COUNT_MISMATCH")
	if int(value["boundary_segment_count"]) == 0:
		if String(value["status"]) != STATUS_EMPTY or int(value["triangle_count"]) != 0:
			return RepresentationUtils.failure("EMPTY_MATTER_TRANSITION_MISMATCH")
	else:
		if String(value["status"]) != STATUS_READY \
			or int(value["triangle_count"]) != int(value["boundary_segment_count"]) * 4:
			return RepresentationUtils.failure("READY_MATTER_TRANSITION_MISMATCH")
	if not RepresentationUtils.is_lower_hex_64(value.get("content_hash")) \
		or String(value["content_hash"]) != _compute_hash(value):
		return RepresentationUtils.failure("MATTER_TRANSITION_CONTENT_HASH_MISMATCH")
	return RepresentationUtils.success()


static func to_artifact_manifest(value: Dictionary, build_generation: int) -> Dictionary:
	if not bool(validate(value).get("success", false)) or build_generation < 1:
		return {}
	var byte_size: int = maxi(1, 256 + value["vertices"].size() * 80 + value["indices"].size() * 4)
	var origin: Vector3 = value["origin_body_local_m"]
	var bounds: Array = [origin.x, origin.y, origin.z, origin.x, origin.y, origin.z]
	if not value["vertices"].is_empty():
		var minimum_m: Vector3 = origin + value["vertices"][0]
		var maximum_m: Vector3 = minimum_m
		for vertex in value["vertices"]:
			var world: Vector3 = origin + vertex
			minimum_m = Vector3(minf(minimum_m.x, world.x), minf(minimum_m.y, world.y), minf(minimum_m.z, world.z))
			maximum_m = Vector3(maxf(maximum_m.x, world.x), maxf(maximum_m.y, world.y), maxf(maximum_m.z, world.z))
		bounds = [minimum_m.x, minimum_m.y, minimum_m.z, maximum_m.x, maximum_m.y, maximum_m.z]
	return ArtifactManifest.create(
		value["representation_key"], String(value["content_hash"]), byte_size, "RAW", MEDIA_TYPE,
		float(value["geometric_error_m"]), bounds, false, false, build_generation
	)


static func _compute_hash(value: Dictionary) -> String:
	var geometry: Array = []
	var vertices: PackedVector3Array = value.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = value.get("normals", PackedVector3Array())
	var colors: PackedColorArray = value.get("colors", PackedColorArray())
	for index in range(vertices.size()):
		var vertex: Vector3 = vertices[index]
		var normal: Vector3 = normals[index]
		var color: Color = colors[index]
		geometry.append([
			int(round(vertex.x * HASH_SCALE)), int(round(vertex.y * HASH_SCALE)), int(round(vertex.z * HASH_SCALE)),
			int(round(normal.x * HASH_SCALE)), int(round(normal.y * HASH_SCALE)), int(round(normal.z * HASH_SCALE)),
			int(round(color.r * HASH_SCALE)), int(round(color.g * HASH_SCALE)), int(round(color.b * HASH_SCALE)), int(round(color.a * HASH_SCALE)),
		])
	return RepresentationUtils.payload_hash({
		"representation_key_checksum": Dictionary(value.get("representation_key", {})).get("checksum", ""),
		"fine_key_checksum": Dictionary(value.get("fine_representation_key", {})).get("checksum", ""),
		"coarse_key_checksum": Dictionary(value.get("coarse_representation_key", {})).get("checksum", ""),
		"fine_artifact_hash": value.get("fine_artifact_hash", ""),
		"coarse_artifact_hash": value.get("coarse_artifact_hash", ""),
		"axis": value.get("axis", -1), "direction": value.get("direction", 0),
		"plane_coordinate_m": value.get("plane_coordinate_m", 0.0),
		"skirt_depth_m": value.get("skirt_depth_m", 0.0),
		"boundary_segment_hash": value.get("boundary_segment_hash", ""),
		"geometry": geometry,
		"indices": Array(value.get("indices", PackedInt32Array())),
	})


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
