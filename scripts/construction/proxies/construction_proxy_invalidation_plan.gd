extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_proxy_invalidation_plan.v1"
const FIELDS: Array[String] = ["schema", "construct_id", "from_source_checksum", "to_source_checksum", "dirty_part_ids", "dirty_section_ids", "invalidated_artifact_ids", "reused_artifact_ids", "shell_rebuilt", "checksum"]

static func create(construct_id: String, from_source_checksum: String, to_source_checksum: String, dirty_part_ids: Array, dirty_section_ids: Array, invalidated_artifact_ids: Array, reused_artifact_ids: Array, shell_rebuilt: bool) -> Dictionary:
	var value := {"schema": SCHEMA, "construct_id": construct_id, "from_source_checksum": from_source_checksum, "to_source_checksum": to_source_checksum, "dirty_part_ids": C.sorted_strings(dirty_part_ids), "dirty_section_ids": C.sorted_strings(dirty_section_ids), "invalidated_artifact_ids": C.sorted_strings(invalidated_artifact_ids), "reused_artifact_ids": C.sorted_strings(reused_artifact_ids), "shell_rebuilt": shell_rebuilt, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("construct_id", "")), "construct/") or not C.hash64(String(value.get("from_source_checksum", ""))) or not C.hash64(String(value.get("to_source_checksum", ""))): return C.failure("INVALID_CONSTRUCTION_PROXY_INVALIDATION_SOURCE")
	if not C.sorted_unique_strings(value.get("dirty_part_ids"), "part/") or not C.sorted_unique_strings(value.get("dirty_section_ids"), "section/") or not C.sorted_unique_strings(value.get("invalidated_artifact_ids"), "proxy-artifact/") or not C.sorted_unique_strings(value.get("reused_artifact_ids"), "proxy-artifact/") or typeof(value.get("shell_rebuilt")) != TYPE_BOOL: return C.failure("INVALID_CONSTRUCTION_PROXY_INVALIDATION_CONTENT")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_INVALIDATION_CHECKSUM_MISMATCH")
	return C.success()
static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
