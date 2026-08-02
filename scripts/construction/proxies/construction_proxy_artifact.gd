extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")

const SCHEMA := "planet_simulator.construction_proxy_artifact.v1"
const SHELL := "SHELL"
const SECTION := "SECTION"
const INTERIOR := "INTERIOR"
const KINDS: Array[String] = [SHELL, SECTION, INTERIOR]
const FIELDS: Array[String] = ["schema", "artifact_id", "construct_id", "source_revision", "source_checksum", "authority_epoch", "artifact_kind", "lod_tier", "section_ids", "bounds_min_m", "bounds_max_m", "part_count", "exposed_face_count", "merged_quad_count", "material_batches", "collision_boxes", "interactive_part_ids", "estimated_bytes", "content_hash", "checksum"]

static func create(construct_id: String, source_revision: int, source_checksum: String, authority_epoch: int, artifact_kind: String, lod_tier: String, section_ids: Array, bounds_min_m: Array, bounds_max_m: Array, part_count: int, exposed_face_count: int, merged_quad_count: int, material_batches: Array, collision_boxes: Array, interactive_part_ids: Array = []) -> Dictionary:
	var value := {"schema": SCHEMA, "artifact_id": "", "construct_id": construct_id, "source_revision": source_revision, "source_checksum": source_checksum, "authority_epoch": authority_epoch, "artifact_kind": artifact_kind, "lod_tier": lod_tier, "section_ids": C.sorted_strings(section_ids), "bounds_min_m": bounds_min_m.duplicate(true), "bounds_max_m": bounds_max_m.duplicate(true), "part_count": part_count, "exposed_face_count": exposed_face_count, "merged_quad_count": merged_quad_count, "material_batches": _sorted_batches(material_batches), "collision_boxes": collision_boxes.duplicate(true), "interactive_part_ids": C.sorted_strings(interactive_part_ids), "estimated_bytes": 256 + merged_quad_count * 64 + material_batches.size() * 48 + collision_boxes.size() * 64 + interactive_part_ids.size() * 48, "content_hash": "", "checksum": ""}
	value["content_hash"] = compute_content_hash(value)
	value["artifact_id"] = "proxy-artifact/%s" % value["content_hash"]
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA or not C.path_id(String(value.get("artifact_id", "")), "proxy-artifact/") or not C.path_id(String(value.get("construct_id", "")), "construct/"): return C.failure("INVALID_CONSTRUCTION_PROXY_ARTIFACT_IDENTITY")
	if not Utils.is_json_integer(value.get("source_revision")) or int(value["source_revision"]) < 0 or not C.hash64(String(value.get("source_checksum", ""))) or not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1: return C.failure("INVALID_CONSTRUCTION_PROXY_ARTIFACT_SOURCE")
	if not KINDS.has(String(value.get("artifact_kind", ""))) or not String(value.get("lod_tier", "")) in ["IMPOSTOR", "SIMPLIFIED", "FULL"]: return C.failure("INVALID_CONSTRUCTION_PROXY_ARTIFACT_KIND")
	if not C.sorted_unique_strings(value.get("section_ids"), "section/") or not C.finite_vector(value.get("bounds_min_m"), 3) or not C.finite_vector(value.get("bounds_max_m"), 3): return C.failure("INVALID_CONSTRUCTION_PROXY_ARTIFACT_BOUNDS")
	for field in ["part_count", "exposed_face_count", "merged_quad_count", "estimated_bytes"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0: return C.failure("INVALID_CONSTRUCTION_PROXY_ARTIFACT_METRICS")
	if typeof(value.get("material_batches")) != TYPE_ARRAY or typeof(value.get("collision_boxes")) != TYPE_ARRAY or not C.sorted_unique_strings(value.get("interactive_part_ids"), "part/"): return C.failure("INVALID_CONSTRUCTION_PROXY_ARTIFACT_PAYLOAD")
	var previous := ""
	for batch in value["material_batches"]:
		if typeof(batch) != TYPE_DICTIONARY or typeof(batch.get("material_key")) != TYPE_STRING or String(batch["material_key"]).is_empty() or not Utils.is_json_integer(batch.get("quad_count")) or int(batch["quad_count"]) < 0 or typeof(batch.get("quads")) != TYPE_ARRAY: return C.failure("INVALID_CONSTRUCTION_PROXY_MATERIAL_BATCH")
		if not previous.is_empty() and String(batch["material_key"]) <= previous: return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_MATERIAL_BATCHES")
		if int(batch["quad_count"]) != Array(batch["quads"]).size(): return C.failure("CONSTRUCTION_PROXY_BATCH_QUAD_COUNT_MISMATCH")
		previous = String(batch["material_key"])
	if not C.hash64(String(value.get("content_hash", ""))) or String(value["artifact_id"]) != "proxy-artifact/%s" % value["content_hash"] or String(value["content_hash"]) != compute_content_hash(value): return C.failure("CONSTRUCTION_PROXY_ARTIFACT_CONTENT_HASH_MISMATCH")
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_ARTIFACT_CHECKSUM_MISMATCH")
	return C.success()

static func compute_content_hash(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	# Geometry/proxy payload is content-addressed independently from the source revision.
	# The manifest pins authoritative provenance, while unchanged proxy bytes can be reused.
	payload["artifact_id"] = ""; payload["content_hash"] = ""; payload["checksum"] = ""
	payload["source_revision"] = 0; payload["source_checksum"] = ""; payload["authority_epoch"] = 0
	return Utils.payload_hash(payload)
static func compute_checksum(value: Dictionary) -> String: return C.compute_checksum(value)
static func _sorted_batches(values: Array) -> Array:
	var result := values.duplicate(true); result.sort_custom(func(a, b): return String(a.get("material_key", "")) < String(b.get("material_key", ""))); return result
