extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")
const InteractionTimeScript = preload("res://scripts/network/gateway/interaction_time.gd")

const SCHEMA := "planet_simulator.cross_world_interaction_intent.v1"
const PROTOCOL_VERSION := 1
const INTERACTION_KINDS: Array[String] = ["HITSCAN", "SWEEP", "VOLUME", "CONTACT", "GENERIC"]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"interaction_id",
	"operation_id",
	"input_seq",
	"interaction_kind",
	"actor_id",
	"actor_entity_id",
	"action_authority",
	"action_authority_epoch",
	"interaction_time",
	"source_world_id",
	"source_reference_frame_id",
	"origin_or_shape",
	"direction_or_motion",
	"max_range_or_extent",
	"capability_definition_id",
	"capability_definition_revision",
	"optional_projection_target_hint",
	"projection_revision",
	"world_graph_revision",
	"route_revision",
]


static func create(
		interaction_id: String,
		operation_id: String,
		input_seq: int,
		interaction_kind: String,
		actor_id: String,
		actor_entity_id: String,
		action_authority: String,
		action_authority_epoch: int,
		interaction_time: Dictionary,
		source_world_id: String,
		source_reference_frame_id: String,
		origin_or_shape: Dictionary,
		direction_or_motion: Dictionary,
		max_range_or_extent: Dictionary,
		capability_definition_id: String,
		capability_definition_revision: int,
		optional_projection_target_hint,
		projection_revision: int,
		world_graph_revision: int,
		route_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"interaction_id": interaction_id,
		"operation_id": operation_id,
		"input_seq": input_seq,
		"interaction_kind": interaction_kind,
		"actor_id": actor_id,
		"actor_entity_id": actor_entity_id,
		"action_authority": action_authority,
		"action_authority_epoch": action_authority_epoch,
		"interaction_time": interaction_time.duplicate(true),
		"source_world_id": source_world_id,
		"source_reference_frame_id": source_reference_frame_id,
		"origin_or_shape": origin_or_shape.duplicate(true),
		"direction_or_motion": direction_or_motion.duplicate(true),
		"max_range_or_extent": max_range_or_extent.duplicate(true),
		"capability_definition_id": capability_definition_id,
		"capability_definition_revision": capability_definition_revision,
		"optional_projection_target_hint": optional_projection_target_hint,
		"projection_revision": projection_revision,
		"world_graph_revision": world_graph_revision,
		"route_revision": route_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["interaction_id", "interaction"],
		["operation_id", "operation"],
		["actor_id", "player"],
		["actor_entity_id", "entity"],
		["action_authority", "authority"],
		["source_world_id", "world"],
		["source_reference_frame_id", "reference-frame"],
		["capability_definition_id", "capability-definition"],
	]:
		var id_check: Dictionary = CwipUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(id_check.get("success", false)):
			return id_check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_enum(value, "interaction_kind", INTERACTION_KINDS),
		CwipUtilsScript.require_positive_integer(value, "input_seq"),
		CwipUtilsScript.require_positive_integer(value, "action_authority_epoch"),
		CwipUtilsScript.require_positive_integer(value, "capability_definition_revision"),
		CwipUtilsScript.require_nonnegative_integer(value, "projection_revision"),
		CwipUtilsScript.require_positive_integer(value, "world_graph_revision"),
		CwipUtilsScript.require_positive_integer(value, "route_revision"),
	]:
		if not bool(check.get("success", false)):
			return check
	if typeof(value.get("interaction_time")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_INTERACTION_TIME", "interaction_time must be a Dictionary")
	var time_check: Dictionary = InteractionTimeScript.validate(Dictionary(value.get("interaction_time")))
	if not bool(time_check.get("success", false)):
		return time_check
	for field in ["origin_or_shape", "direction_or_motion", "max_range_or_extent"]:
		var payload_check: Dictionary = CwipUtilsScript.require_payload(value, String(field))
		if not bool(payload_check.get("success", false)):
			return payload_check
	var hint_check: Dictionary = CwipUtilsScript.require_optional_id(value, "optional_projection_target_hint", "entity")
	if not bool(hint_check.get("success", false)):
		return NetworkUtilsScript.validation_failure(
			"PROJECTION_TARGET_HINT_NOT_ENTITY",
			"optional_projection_target_hint is only an entity candidate hint, never authority evidence",
		)
	var has_hint := value.get("optional_projection_target_hint") != null
	if has_hint and int(value.get("projection_revision")) < 1:
		return NetworkUtilsScript.validation_failure(
			"INVALID_PROJECTION_REVISION",
			"projection_revision must be >= 1 when a projection target hint is present",
		)
	if not has_hint and int(value.get("projection_revision")) != 0:
		return NetworkUtilsScript.validation_failure(
			"INVALID_PROJECTION_REVISION",
			"projection_revision must be 0 when no projection target hint is present",
		)
	return NetworkUtilsScript.validation_success()
