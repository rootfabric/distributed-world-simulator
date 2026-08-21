extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.world_relation.v1"
const PROTOCOL_VERSION := 1
const TRANSITION_REGION_FIELDS: Array[String] = ["id", "kind"]
const REFERENCE_FRAME_RELATION_FIELDS: Array[String] = ["kind"]
const PROJECTION_POLICY_FIELDS: Array[String] = ["read_only", "allows_mutation"]
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
	for semantic_check in [
		_validate_transition_region(value.get("intersection_or_transition_region")),
		_validate_reference_frame_relation(value.get("reference_frame_relation")),
		_validate_projection_policy(value.get("projection_policy")),
	]:
		if not bool(semantic_check.get("success", false)):
			return semantic_check
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


static func _validate_transition_region(raw_value) -> Dictionary:
	var fields: Dictionary = GatewayUtilsScript.validate_world_graph_semantic_fields(raw_value, TRANSITION_REGION_FIELDS, "WorldRelation.intersection_or_transition_region")
	if not bool(fields.get("success", false)):
		return fields
	var value: Dictionary = Dictionary(raw_value)
	for field in value.keys():
		if not BusUtilsScript.is_semantic_name(value.get(field), false):
			return NetworkUtilsScript.validation_failure("INVALID_TRANSITION_REGION", "%s must be semantic" % field)
	return NetworkUtilsScript.validation_success()


static func _validate_reference_frame_relation(raw_value) -> Dictionary:
	var fields: Dictionary = GatewayUtilsScript.validate_world_graph_semantic_fields(raw_value, REFERENCE_FRAME_RELATION_FIELDS, "WorldRelation.reference_frame_relation")
	if not bool(fields.get("success", false)):
		return fields
	var value: Dictionary = Dictionary(raw_value)
	if value.has("kind") and not BusUtilsScript.is_semantic_name(value.get("kind"), false):
		return NetworkUtilsScript.validation_failure("INVALID_REFERENCE_FRAME_RELATION", "kind must be semantic")
	return NetworkUtilsScript.validation_success()


static func _validate_projection_policy(raw_value) -> Dictionary:
	var fields: Dictionary = GatewayUtilsScript.validate_world_graph_semantic_fields(raw_value, PROJECTION_POLICY_FIELDS, "WorldRelation.projection_policy")
	if not bool(fields.get("success", false)):
		return fields
	var value: Dictionary = Dictionary(raw_value)
	for field in value.keys():
		if typeof(value.get(field)) != TYPE_BOOL:
			return NetworkUtilsScript.validation_failure("INVALID_PROJECTION_POLICY", "projection policy fields must be Boolean")
	return NetworkUtilsScript.validation_success()
