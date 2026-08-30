extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_compile_result.v1"
const FIELDS: Array[String] = ["schema", "status", "artifact", "reason", "diagnostics", "checksum"]
const BAKE_READY := "BAKE_READY"
const NO_SAFE_BAKE := "NO_SAFE_BAKE"
const STATUSES: Array[String] = [BAKE_READY, NO_SAFE_BAKE]
const NO_SAFE_REASONS: Array[String] = [
	"AUTHORITY_ENVELOPE_CROSSED", "INSUFFICIENT_COMPLEXITY_REDUCTION",
	"NEAR_CRITICAL_DYNAMICS", "RANK_DEFICIENCY", "RECONSTRUCTION_UNAVAILABLE",
	"UNCERTIFIABLE_ERROR_ENVELOPE", "UNCERTIFIABLE_REFINEMENT_GUARD",
	"UNSAFE_ELIMINATION", "UNSUPPORTED_DISTRIBUTED_BAKE_PROTOCOL",
	"UNSUPPORTED_HYBRID_MODE",
]

static func ready(artifact: Dictionary, diagnostics: Dictionary = {}) -> Dictionary:
	return _create(BAKE_READY, artifact, "", diagnostics)

static func no_safe(reason: String, diagnostics: Dictionary = {}) -> Dictionary:
	return _create(NO_SAFE_BAKE, {}, reason, diagnostics)

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BAKE_COMPILE_RESULT_SCHEMA")
	if not STATUSES.has(String(value.get("status", ""))):
		return Utils.failure("INVALID_BAKE_COMPILE_STATUS")
	if typeof(value.get("artifact")) != TYPE_DICTIONARY or typeof(value.get("diagnostics")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_BAKE_COMPILE_RESULT_PAYLOAD")
	if Utils.canonical_hash(value["diagnostics"]).is_empty():
		return Utils.failure("NON_CANONICAL_BAKE_DIAGNOSTICS")
	if String(value["status"]) == BAKE_READY:
		if not String(value.get("reason", "")).is_empty():
			return Utils.failure("BAKE_READY_WITH_REASON")
		checked = Artifact.validate(value["artifact"])
		if not bool(checked.get("success", false)):
			return checked
	else:
		if not value["artifact"].is_empty():
			return Utils.failure("NO_SAFE_BAKE_WITH_ARTIFACT")
		if not NO_SAFE_REASONS.has(String(value.get("reason", ""))):
			return Utils.failure("INVALID_NO_SAFE_BAKE_REASON")
	return Utils.validate_checksum(value)

static func _create(status: String, artifact: Dictionary, reason: String, diagnostics: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"status": status,
		"artifact": artifact.duplicate(true),
		"reason": reason,
		"diagnostics": diagnostics.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}
