extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.aggregated_interest_plan.v1"
const PROTOCOL_VERSION := 1
const SOURCE_ROLES: Array[String] = ["ACTIVE", "WARM", "PROJECTION", "MACRO", "CELESTIAL"]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"plan_id",
	"source_world_id",
	"source_role",
	"representation_or_lod",
	"subscriber_sessions",
	"aggregate_priority",
	"aggregate_budget",
	"graph_revision",
	"interest_revision",
	"read_only",
]


static func create(
		plan_id: String,
		source_world_id: String,
		source_role: String,
		representation_or_lod: String,
		subscriber_sessions: Array,
		aggregate_priority: int,
		aggregate_budget: Dictionary,
		graph_revision: int,
		interest_revision: int,
		read_only: bool = true,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"plan_id": plan_id,
		"source_world_id": source_world_id,
		"source_role": source_role,
		"representation_or_lod": representation_or_lod,
		"subscriber_sessions": subscriber_sessions.duplicate(true),
		"aggregate_priority": aggregate_priority,
		"aggregate_budget": aggregate_budget.duplicate(true),
		"graph_revision": graph_revision,
		"interest_revision": interest_revision,
		"read_only": read_only,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["plan_id", "interest-plan"],
		["source_world_id", "world"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_enum(value, "source_role", SOURCE_ROLES),
		GatewayUtilsScript.require_nonnegative_integer(value, "aggregate_priority"),
		GatewayUtilsScript.require_positive_integer(value, "graph_revision"),
		GatewayUtilsScript.require_positive_integer(value, "interest_revision"),
		GatewayUtilsScript.validate_derived_routing_payload(value.get("aggregate_budget")),
	]:
		if not bool(check.get("success", false)):
			return check
	if not BusUtilsScript.is_semantic_name(value.get("representation_or_lod"), false):
		return NetworkUtilsScript.validation_failure(
			"INVALID_REPRESENTATION",
			"representation_or_lod must be a canonical semantic name",
		)
	if typeof(value.get("read_only")) != TYPE_BOOL or not bool(value.get("read_only")):
		return NetworkUtilsScript.validation_failure(
			"INTEREST_PLAN_NOT_READ_ONLY",
			"AggregatedInterestPlan is derived routing demand and must be read_only=true",
		)
	if typeof(value.get("subscriber_sessions")) != TYPE_ARRAY or Array(value.get("subscriber_sessions")).is_empty():
		return NetworkUtilsScript.validation_failure(
			"INVALID_SUBSCRIBER_SESSIONS",
			"subscriber_sessions must be a non-empty Array",
		)
	var seen: Dictionary = {}
	for session_id in Array(value.get("subscriber_sessions")):
		if not BusUtilsScript.is_canonical_id(session_id, "gateway-session"):
			return NetworkUtilsScript.validation_failure("INVALID_SUBSCRIBER_SESSION", "Invalid gateway session id")
		var key: String = String(session_id)
		if seen.has(key):
			return NetworkUtilsScript.validation_failure("DUPLICATE_SUBSCRIBER_SESSION", "Subscriber session duplicated")
		seen[key] = true
	return NetworkUtilsScript.validation_success()


static func validate_newer(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var candidate_check: Dictionary = validate(candidate)
	if not bool(candidate_check.get("success", false)):
		return candidate_check
	var current_check: Dictionary = validate(current)
	if not bool(current_check.get("success", false)):
		return current_check
	if String(candidate.get("source_world_id")) != String(current.get("source_world_id")):
		return NetworkUtilsScript.validation_failure("SOURCE_WORLD_MISMATCH", "Cannot compare plans for different source worlds")
	if int(candidate.get("graph_revision")) < int(current.get("graph_revision")):
		return NetworkUtilsScript.validation_failure("STALE_GRAPH_REVISION", "graph_revision cannot rewind")
	if int(candidate.get("interest_revision")) <= int(current.get("interest_revision")):
		return NetworkUtilsScript.validation_failure("STALE_INTEREST_REVISION", "interest_revision must advance")
	return NetworkUtilsScript.validation_success()
