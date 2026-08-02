extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")

const SCHEMA := "planet_simulator.construction_proxy_mesh_descriptor.v1"
const BACKEND := "ARRAY_MESH_V1"
const FIELDS: Array[String] = [
	"schema", "artifact_id", "content_hash", "backend", "surface_count",
	"material_keys", "vertex_count", "index_count", "triangle_count",
	"bounds_min_m", "bounds_max_m", "estimated_gpu_bytes", "mesh_signature", "checksum",
]

static func create(
	artifact: Dictionary,
	material_keys: Array,
	vertex_count: int,
	index_count: int,
	bounds_min_m: Array,
	bounds_max_m: Array,
	estimated_gpu_bytes: int,
	mesh_signature: String
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"artifact_id": String(artifact["artifact_id"]),
		"content_hash": String(artifact["content_hash"]),
		"backend": BACKEND,
		"surface_count": material_keys.size(),
		"material_keys": C.sorted_strings(material_keys),
		"vertex_count": vertex_count,
		"index_count": index_count,
		"triangle_count": index_count / 3,
		"bounds_min_m": bounds_min_m.duplicate(true),
		"bounds_max_m": bounds_max_m.duplicate(true),
		"estimated_gpu_bytes": estimated_gpu_bytes,
		"mesh_signature": mesh_signature,
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or value.get("backend") != BACKEND:
		return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_DESCRIPTOR_SCHEMA")
	if not C.path_id(String(value.get("artifact_id", "")), "proxy-artifact/"):
		return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_DESCRIPTOR_ARTIFACT")
	if not C.hash64(String(value.get("content_hash", ""))) or not C.hash64(String(value.get("mesh_signature", ""))):
		return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_DESCRIPTOR_HASH")
	if not C.sorted_unique_strings(value.get("material_keys")):
		return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_DESCRIPTOR_MATERIALS")
	for field in ["surface_count", "vertex_count", "index_count", "triangle_count", "estimated_gpu_bytes"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_DESCRIPTOR_METRICS")
	if int(value["surface_count"]) != Array(value["material_keys"]).size():
		return C.failure("CONSTRUCTION_PROXY_MESH_DESCRIPTOR_SURFACE_COUNT_MISMATCH")
	if int(value["index_count"]) % 3 != 0 or int(value["triangle_count"]) != int(value["index_count"]) / 3:
		return C.failure("CONSTRUCTION_PROXY_MESH_DESCRIPTOR_TRIANGLE_COUNT_MISMATCH")
	if int(value["vertex_count"]) % 4 != 0:
		return C.failure("CONSTRUCTION_PROXY_MESH_DESCRIPTOR_VERTEX_LAYOUT_MISMATCH")
	if not C.finite_vector(value.get("bounds_min_m"), 3) or not C.finite_vector(value.get("bounds_max_m"), 3):
		return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_DESCRIPTOR_BOUNDS")
	for axis in range(3):
		if float(value["bounds_max_m"][axis]) < float(value["bounds_min_m"][axis]):
			return C.failure("INVALID_CONSTRUCTION_PROXY_MESH_DESCRIPTOR_BOUNDS")
	if String(value.get("checksum", "")) != compute_checksum(value):
		return C.failure("CONSTRUCTION_PROXY_MESH_DESCRIPTOR_CHECKSUM_MISMATCH")
	return C.success()

static func compute_checksum(value: Dictionary) -> String:
	return C.compute_checksum(value)
