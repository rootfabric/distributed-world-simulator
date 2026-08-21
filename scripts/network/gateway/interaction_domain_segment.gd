extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")
const ReferenceFrameEvidenceScript = preload("res://scripts/network/gateway/reference_frame_evidence.gd")

const SCHEMA := "planet_simulator.interaction_domain_segment.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"world_id",
	"authority_ref",
	"path_t_start",
	"path_t_end",
	"reference_frame_evidence",
	"relation_revision",
]


static func create(
		world_id: String,
		authority_ref: String,
		path_t_start: float,
		path_t_end: float,
		reference_frame_evidence: Dictionary,
		relation_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"world_id": world_id,
		"authority_ref": authority_ref,
		"path_t_start": path_t_start,
		"path_t_end": path_t_end,
		"reference_frame_evidence": reference_frame_evidence.duplicate(true),
		"relation_revision": relation_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [["world_id", "world"], ["authority_ref", "authority"]]:
		var id_check: Dictionary = CwipUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(id_check.get("success", false)):
			return id_check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		CwipUtilsScript.require_path_range(value),
		CwipUtilsScript.require_positive_integer(value, "relation_revision"),
	]:
		if not bool(check.get("success", false)):
			return check
	if typeof(value.get("reference_frame_evidence")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_REFERENCE_FRAME_EVIDENCE", "reference_frame_evidence must be a Dictionary")
	var evidence_check: Dictionary = ReferenceFrameEvidenceScript.validate(Dictionary(value.get("reference_frame_evidence")))
	if not bool(evidence_check.get("success", false)):
		return evidence_check
	return NetworkUtilsScript.validation_success()
