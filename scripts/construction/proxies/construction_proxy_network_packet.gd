extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Plan = preload("res://scripts/construction/proxies/construction_proxy_stream_plan.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")
const SCHEMA := "planet_simulator.construction_proxy_network_packet.v1"
const FIELDS: Array[String] = ["schema", "observer_id", "construct_id", "root_item_instance_id", "source_revision", "source_checksum", "authority_epoch", "world_origin_m", "world_rotation_quaternion", "bounds_min_m", "bounds_max_m", "summary", "detail_mode", "plan_checksum", "artifact_payloads", "interactive_part_descriptors", "suppressed_part_count", "checksum"]

static func create(manifest: Dictionary, runtime_request: Dictionary, interest: Dictionary, plan: Dictionary, cache, descriptor_by_part: Dictionary) -> Dictionary:
	var payloads: Array = []
	for artifact_id in plan["artifact_ids"]:
		var artifact: Dictionary = cache.get_artifact(artifact_id)
		if artifact.is_empty(): return C.failure("CONSTRUCTION_PROXY_PACKET_CACHE_MISS")
		payloads.append(artifact)
	payloads.sort_custom(func(a, b): return String(a["artifact_id"]) < String(b["artifact_id"]))
	var interactive: Array = []
	for part_id in plan["interactive_part_ids"]:
		if not descriptor_by_part.has(part_id): return C.failure("CONSTRUCTION_PROXY_PACKET_INTERACTIVE_PART_MISSING")
		interactive.append(descriptor_by_part[part_id].duplicate(true))
	interactive.sort_custom(func(a, b): return String(a["part_id"]) < String(b["part_id"]))
	var value := {"schema": SCHEMA, "observer_id": String(interest["observer_id"]), "construct_id": String(manifest["construct_id"]), "root_item_instance_id": String(manifest["root_item_instance_id"]), "source_revision": int(manifest["source_revision"]), "source_checksum": String(manifest["source_checksum"]), "authority_epoch": int(manifest["authority_epoch"]), "world_origin_m": runtime_request["world_origin_m"].duplicate(true), "world_rotation_quaternion": runtime_request["world_rotation_quaternion"].duplicate(true), "bounds_min_m": manifest["bounds_min_m"].duplicate(true), "bounds_max_m": manifest["bounds_max_m"].duplicate(true), "summary": {"part_count": int(manifest["total_part_count"]), "section_count": int(manifest["total_section_count"]), "proxy_cache_bytes": int(manifest["estimated_cache_bytes"]), "manifest_checksum": String(manifest["checksum"])}, "detail_mode": String(plan["detail_mode"]), "plan_checksum": String(plan["checksum"]), "artifact_payloads": payloads, "interactive_part_descriptors": interactive, "suppressed_part_count": int(plan["suppressed_part_count"]), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return C.success({"packet": value})

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("observer_id", "")), "observer/") or not C.path_id(String(value.get("construct_id", "")), "construct/") or not C.path_id(String(value.get("root_item_instance_id", "")), "item/"): return C.failure("INVALID_CONSTRUCTION_PROXY_PACKET_IDENTITY")
	if not Utils.is_json_integer(value.get("source_revision")) or int(value["source_revision"]) < 0 or not C.hash64(String(value.get("source_checksum", ""))) or not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1: return C.failure("INVALID_CONSTRUCTION_PROXY_PACKET_SOURCE")
	if not C.finite_vector(value.get("world_origin_m"), 3) or not C.finite_vector(value.get("world_rotation_quaternion"), 4) or not C.finite_vector(value.get("bounds_min_m"), 3) or not C.finite_vector(value.get("bounds_max_m"), 3): return C.failure("INVALID_CONSTRUCTION_PROXY_PACKET_SPATIAL")
	if typeof(value.get("summary")) != TYPE_DICTIONARY or not Plan.MODES.has(String(value.get("detail_mode", ""))) or not C.hash64(String(value.get("plan_checksum", ""))): return C.failure("INVALID_CONSTRUCTION_PROXY_PACKET_PLAN")
	if typeof(value.get("artifact_payloads")) != TYPE_ARRAY or typeof(value.get("interactive_part_descriptors")) != TYPE_ARRAY: return C.failure("INVALID_CONSTRUCTION_PROXY_PACKET_PAYLOAD")
	var previous := ""
	for artifact in value["artifact_payloads"]:
		var checked := Artifact.validate(artifact); if not bool(checked.get("success", false)): return checked
		if not previous.is_empty() and String(artifact["artifact_id"]) <= previous: return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_PACKET_ARTIFACTS")
		previous = String(artifact["artifact_id"])
	previous = ""
	for descriptor in value["interactive_part_descriptors"]:
		if typeof(descriptor) != TYPE_DICTIONARY or not C.path_id(String(descriptor.get("part_id", "")), "part/"): return C.failure("INVALID_CONSTRUCTION_PROXY_PACKET_INTERACTIVE_PART")
		if not previous.is_empty() and String(descriptor["part_id"]) <= previous: return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_PACKET_PARTS")
		previous = String(descriptor["part_id"])
	if not Utils.is_json_integer(value.get("suppressed_part_count")) or int(value["suppressed_part_count"]) < 0: return C.failure("INVALID_CONSTRUCTION_PROXY_PACKET_SUPPRESSED_COUNT")
	if String(value["detail_mode"]) == Plan.DISTANT_SHELL and (Array(value["artifact_payloads"]).size() != 1 or not value["interactive_part_descriptors"].is_empty()): return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_DISTANT_PACKET")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_PACKET_CHECKSUM_MISMATCH")
	return C.success()
static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
