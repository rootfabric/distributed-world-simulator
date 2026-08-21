extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")
const InteractionTimeScript = preload("res://scripts/network/gateway/interaction_time.gd")
const DomainSegmentScript = preload("res://scripts/network/gateway/interaction_domain_segment.gd")

const SCHEMA := "planet_simulator.collision_query.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"interaction_id",
	"interaction_time",
	"domain_segment",
	"world_graph_revision",
	"authority_epoch_observed",
	"query_revision",
]


static func create(
		interaction_id: String,
		interaction_time: Dictionary,
		domain_segment: Dictionary,
		world_graph_revision: int,
		authority_epoch_observed: int,
		query_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"interaction_id": interaction_id,
		"interaction_time": interaction_time.duplicate(true),
		"domain_segment": domain_segment.duplicate(true),
		"world_graph_revision": world_graph_revision,
		"authority_epoch_observed": authority_epoch_observed,
		"query_revision": query_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		CwipUtilsScript.require_id(value, "interaction_id", "interaction"),
		CwipUtilsScript.require_positive_integer(value, "world_graph_revision"),
		CwipUtilsScript.require_positive_integer(value, "authority_epoch_observed"),
		CwipUtilsScript.require_positive_integer(value, "query_revision"),
	]:
		if not bool(check.get("success", false)):
			return check
	if typeof(value.get("interaction_time")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_INTERACTION_TIME", "interaction_time must be a Dictionary")
	var time_check: Dictionary = InteractionTimeScript.validate(Dictionary(value.get("interaction_time")))
	if not bool(time_check.get("success", false)):
		return time_check
	if typeof(value.get("domain_segment")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_DOMAIN_SEGMENT", "domain_segment must be a Dictionary")
	var segment: Dictionary = Dictionary(value.get("domain_segment"))
	var segment_check: Dictionary = DomainSegmentScript.validate(segment)
	if not bool(segment_check.get("success", false)):
		return segment_check
	var evidence: Dictionary = Dictionary(segment.get("reference_frame_evidence"))
	if int(evidence.get("world_graph_revision")) != int(value.get("world_graph_revision")):
		return NetworkUtilsScript.validation_failure(
			"STALE_WORLD_GRAPH_EVIDENCE",
			"CollisionQuery world_graph_revision must match reference-frame evidence",
		)
	return NetworkUtilsScript.validation_success()
