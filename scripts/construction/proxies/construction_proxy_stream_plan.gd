extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_proxy_stream_plan.v1"
const DISTANT_SHELL := "DISTANT_SHELL"
const SECTION_HLOD := "SECTION_HLOD"
const LOCAL_EXTERIOR := "LOCAL_EXTERIOR"
const INTERIOR_CELL := "INTERIOR_CELL"
const MODES: Array[String] = [DISTANT_SHELL, SECTION_HLOD, LOCAL_EXTERIOR, INTERIOR_CELL]
const FIELDS: Array[String] = ["schema", "construct_id", "source_checksum", "authority_epoch", "interest_checksum", "detail_mode", "artifact_ids", "section_ids", "interior_cell_ids", "interactive_part_ids", "suppressed_part_count", "estimated_bytes", "checksum"]

static func create(manifest: Dictionary, interest: Dictionary, detail_mode: String, artifact_ids: Array, section_ids: Array, interior_cell_ids: Array, interactive_part_ids: Array, estimated_bytes: int) -> Dictionary:
	var value := {"schema": SCHEMA, "construct_id": String(manifest["construct_id"]), "source_checksum": String(manifest["source_checksum"]), "authority_epoch": int(manifest["authority_epoch"]), "interest_checksum": String(interest["checksum"]), "detail_mode": detail_mode, "artifact_ids": C.sorted_strings(artifact_ids), "section_ids": C.sorted_strings(section_ids), "interior_cell_ids": C.sorted_strings(interior_cell_ids), "interactive_part_ids": C.sorted_strings(interactive_part_ids), "suppressed_part_count": maxi(int(manifest["total_part_count"]) - interactive_part_ids.size(), 0), "estimated_bytes": estimated_bytes, "checksum": ""}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("construct_id", "")), "construct/") or not C.hash64(String(value.get("source_checksum", ""))) or not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1 or not C.hash64(String(value.get("interest_checksum", ""))): return C.failure("INVALID_CONSTRUCTION_PROXY_STREAM_PLAN_SOURCE")
	if not MODES.has(String(value.get("detail_mode", ""))) or not C.sorted_unique_strings(value.get("artifact_ids"), "proxy-artifact/") or not C.sorted_unique_strings(value.get("section_ids"), "section/") or not C.sorted_unique_strings(value.get("interior_cell_ids"), "interior-cell/") or not C.sorted_unique_strings(value.get("interactive_part_ids"), "part/"): return C.failure("INVALID_CONSTRUCTION_PROXY_STREAM_PLAN_CONTENT")
	for field in ["suppressed_part_count", "estimated_bytes"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return C.failure("INVALID_CONSTRUCTION_PROXY_STREAM_PLAN_METRICS")
	if String(value["detail_mode"]) == DISTANT_SHELL and (Array(value["artifact_ids"]).size() != 1 or not value["section_ids"].is_empty() or not value["interactive_part_ids"].is_empty()): return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_DISTANT_PLAN")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_STREAM_PLAN_CHECKSUM_MISMATCH")
	return C.success()
static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
