extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.world_relation.v1"
const PROTOCOL_VERSION := 1
const RELATION_KINDS: Array[String] = [
	"NEIGHBOR",
	"OVERLAP",
	"CONTAINS",
	"REFERENCE_FRAME_PARENT",
	"REFERENCE_FRAME_CHILD",
	"PORTAL_OR_TRANSITION",
	"VISUALLY_RELEVANT",
]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"relation_id",
	"world_a",
	"world_b",
	"relation_kind",
	"intersection_or_transition_region",
	"reference_frame_relation",
	"projection_policy",
	"relation_revision",
]


static func create(
		relation_id: String,
		world_a: String,
		world_b: String,
		relation_kind: String,
		intersection_or_transition_region: Dictionary,
		reference_frame_relation: Dictionary,
		projection_policy: Dictionary,
		relation_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"relation_id": relation_id,
		"world_a": world_a,
		"world_b": world_b,
		"relation_kind": relation_kind,
		"intersection_or_transition_region": intersection_or_transition_region.duplicate(true),
		"reference_frame_relation": reference_frame_relation.duplicate(true),
		"projection_policy": projection_policy.duplicate(true),
		"relation_revision": relation_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["relation_id", "world-relation"],
		["world_a", "world"],
		["world_b", "world"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_enum(value, "relation_kind", RELATION_KINDS),
		GatewayUtilsScript.require_positive_integer(value, "relation_revision"),
	]:
		if not bool(check.get("success", false)):
			return check
	for field in ["intersection_or_transition_region", "reference_frame_relation", "projection_policy"]:
		var payload_check: Dictionary = GatewayUtilsScript.validate_payload(value.get(String(field)))
		if not bool(payload_check.get("success", false)):
			return payload_check
	var projection_policy: Dictionary = Dictionary(value.get("projection_policy"))
	if bool(projection_policy.get("allows_mutation", false)):
		return NetworkUtilsScript.validation_failure(
			"PROJECTION_MUTATION_AUTHORITY_FORBIDDEN",
			"World relation projection policy cannot grant mutation authority",
		)
	return NetworkUtilsScript.validation_success()


static func validate_newer(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var candidate_check: Dictionary = validate(candidate)
	if not bool(candidate_check.get("success", false)):
		return candidate_check
	var current_check: Dictionary = validate(current)
	if not bool(current_check.get("success", false)):
		return current_check
	if String(candidate.get("relation_id")) != String(current.get("relation_id")):
		return NetworkUtilsScript.validation_failure("RELATION_ID_MISMATCH", "Cannot compare different relations")
	if int(candidate.get("relation_revision")) <= int(current.get("relation_revision")):
		return NetworkUtilsScript.validation_failure("STALE_RELATION_REVISION", "relation_revision must advance")
	return NetworkUtilsScript.validation_success()
