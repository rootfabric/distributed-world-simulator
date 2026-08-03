extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_proxy_manifest.v1"
const FIELDS: Array[String] = ["schema", "construct_id", "root_item_instance_id", "source_revision", "source_checksum", "authority_epoch", "authority_mode", "compiler_node_id", "compiler_version", "bounds_min_m", "bounds_max_m", "section_size_m", "local_distance_m", "section_distance_m", "shell_distance_m", "topology_checksum", "shell_artifact_id", "section_artifacts", "interior_artifacts", "portals", "total_part_count", "total_section_count", "total_exposed_faces", "estimated_cache_bytes", "checksum"]

static func create(request: Dictionary, topology: Dictionary, shell_artifact: Dictionary, section_artifacts: Array, interior_artifacts: Array, portals: Array, bounds_min_m: Array, bounds_max_m: Array, total_exposed_faces: int, estimated_cache_bytes: int) -> Dictionary:
	var snapshot: Dictionary = request["runtime_projection_request"]["construct_snapshot"]
	var section_refs: Array = []
	for artifact in section_artifacts:
		section_refs.append({"section_id": String(artifact["section_ids"][0]), "artifact_id": String(artifact["artifact_id"]), "bounds_min_m": artifact["bounds_min_m"].duplicate(true), "bounds_max_m": artifact["bounds_max_m"].duplicate(true), "part_count": int(artifact["part_count"]), "estimated_bytes": int(artifact["estimated_bytes"])})
	section_refs.sort_custom(func(a, b): return String(a["section_id"]) < String(b["section_id"]))
	var interior_refs: Array = []
	for pair in interior_artifacts:
		var artifact: Dictionary = pair["artifact"]
		interior_refs.append({"cell_id": String(pair["cell_id"]), "artifact_id": String(artifact["artifact_id"]), "bounds_min_m": artifact["bounds_min_m"].duplicate(true), "bounds_max_m": artifact["bounds_max_m"].duplicate(true), "estimated_bytes": int(artifact["estimated_bytes"])})
	interior_refs.sort_custom(func(a, b): return String(a["cell_id"]) < String(b["cell_id"]))
	var value := {"schema": SCHEMA, "construct_id": String(snapshot["construct_id"]), "root_item_instance_id": String(snapshot["root_item_instance_id"]), "source_revision": int(snapshot["state_revision"]), "source_checksum": String(snapshot["checksum"]), "authority_epoch": int(request["authority_epoch"]), "authority_mode": String(request["authority_mode"]), "compiler_node_id": String(request["compiler_node_id"]), "compiler_version": 1, "bounds_min_m": bounds_min_m.duplicate(true), "bounds_max_m": bounds_max_m.duplicate(true), "section_size_m": float(request["section_size_m"]), "local_distance_m": float(request["local_distance_m"]), "section_distance_m": float(request["section_distance_m"]), "shell_distance_m": float(request["shell_distance_m"]), "topology_checksum": String(topology["checksum"]), "shell_artifact_id": String(shell_artifact["artifact_id"]), "section_artifacts": section_refs, "interior_artifacts": interior_refs, "portals": portals.duplicate(true), "total_part_count": snapshot["parts"].size(), "total_section_count": section_refs.size(), "total_exposed_faces": total_exposed_faces, "estimated_cache_bytes": estimated_cache_bytes, "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("construct_id", "")), "construct/") or not C.path_id(String(value.get("root_item_instance_id", "")), "item/"): return C.failure("INVALID_CONSTRUCTION_PROXY_MANIFEST_IDENTITY")
	if not Utils.is_json_integer(value.get("source_revision")) or int(value["source_revision"]) < 0 or not C.hash64(String(value.get("source_checksum", ""))) or not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1: return C.failure("INVALID_CONSTRUCTION_PROXY_MANIFEST_SOURCE")
	if not String(value.get("authority_mode", "")) in ["OWNER", "READ_ONLY"] or not C.path_id(String(value.get("compiler_node_id", "")), "server/") or int(value.get("compiler_version", 0)) != 1: return C.failure("INVALID_CONSTRUCTION_PROXY_MANIFEST_COMPILER")
	for field in ["bounds_min_m", "bounds_max_m"]:
		if not C.finite_vector(value.get(field), 3): return C.failure("INVALID_CONSTRUCTION_PROXY_MANIFEST_BOUNDS")
	if not C.hash64(String(value.get("topology_checksum", ""))) or not C.path_id(String(value.get("shell_artifact_id", "")), "proxy-artifact/"): return C.failure("INVALID_CONSTRUCTION_PROXY_MANIFEST_ARTIFACT")
	if typeof(value.get("section_artifacts")) != TYPE_ARRAY or typeof(value.get("interior_artifacts")) != TYPE_ARRAY or typeof(value.get("portals")) != TYPE_ARRAY: return C.failure("INVALID_CONSTRUCTION_PROXY_MANIFEST_COLLECTIONS")
	var previous := ""
	for ref in value["section_artifacts"]:
		if typeof(ref) != TYPE_DICTIONARY or not C.path_id(String(ref.get("section_id", "")), "section/") or not C.path_id(String(ref.get("artifact_id", "")), "proxy-artifact/"): return C.failure("INVALID_CONSTRUCTION_PROXY_SECTION_REFERENCE")
		if not previous.is_empty() and String(ref["section_id"]) <= previous: return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_SECTION_REFERENCES")
		previous = String(ref["section_id"])
	previous = ""
	for ref in value["interior_artifacts"]:
		if typeof(ref) != TYPE_DICTIONARY or not C.path_id(String(ref.get("cell_id", "")), "interior-cell/") or not C.path_id(String(ref.get("artifact_id", "")), "proxy-artifact/"): return C.failure("INVALID_CONSTRUCTION_PROXY_INTERIOR_REFERENCE")
		if not previous.is_empty() and String(ref["cell_id"]) <= previous: return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_INTERIOR_REFERENCES")
		previous = String(ref["cell_id"])
	for field in ["total_part_count", "total_section_count", "total_exposed_faces", "estimated_cache_bytes"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return C.failure("INVALID_CONSTRUCTION_PROXY_MANIFEST_METRICS")
	if int(value["total_section_count"]) != Array(value["section_artifacts"]).size(): return C.failure("CONSTRUCTION_PROXY_MANIFEST_SECTION_COUNT_MISMATCH")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_MANIFEST_CHECKSUM_MISMATCH")
	return C.success()

static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
