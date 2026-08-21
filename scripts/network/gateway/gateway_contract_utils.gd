extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const PROTOCOL_VERSION: int = 1

const CHANNELS: Array[String] = [
	"SESSION_CONTROL",
	"INPUT_MOVEMENT",
	"AUTHORITATIVE_SNAPSHOT",
	"WORLD_OPERATION",
	"WORLD_PROJECTION",
	"RECOVERY_FULL_STATE",
	"TELEMETRY",
]
const DIRECTIONS: Array[String] = ["CLIENT_TO_WORLD", "WORLD_TO_CLIENT"]
const ROUTE_ROLES: Array[String] = ["ACTIVE", "WARM", "PROJECTION", "DRAIN"]
const SESSION_STATES: Array[String] = ["ATTACHING", "ATTACHED", "RESUMING", "DETACHED"]
const GATEWAY_HEALTH_STATES: Array[String] = ["HEALTHY", "DEGRADED", "DRAINING", "UNHEALTHY"]
const MUTATING_CLIENT_CHANNELS: Array[String] = ["INPUT_MOVEMENT", "WORLD_OPERATION"]

# Legacy exact spellings remain as diagnostics/defense-in-depth. R7 topology
# neutrality no longer depends on this finite list: client payloads are admitted
# only through an explicit versioned schema policy and WorldGraph extension
# objects are closed semantic sub-schemas.
const CLIENT_SURFACE_FORBIDDEN_FIELDS: Array[String] = [
	"simulation_server_endpoint",
	"simulation_server_endpoints",
	"server_instance_id",
	"server_endpoint",
	"backend_link_id",
	"backend_links",
	"backend_connection_id",
	"backend_connections",
	"backend_peer_id",
	"peer_id",
	"peer_ids",
	"transport_peer_id",
	"transport_connection_id",
	"transport_session_id",
	"transport_route_id",
	"route_binding_id",
	"physical_connection_id",
	"physical_link_id",
	"socket_id",
]
const WORLD_GRAPH_RUNTIME_FORBIDDEN_FIELDS: Array[String] = [
	"simulation_server_endpoint",
	"simulation_server_endpoints",
	"server_instance_id",
	"server_endpoint",
	"backend_link_id",
	"backend_links",
	"backend_connection_id",
	"backend_connections",
	"backend_peer_id",
	"peer_id",
	"peer_ids",
	"transport_peer_id",
	"transport_connection_id",
	"transport_session_id",
	"transport_route_id",
	"route_binding_id",
	"physical_connection_id",
	"physical_link_id",
	"socket_id",
	"gateway_instance_id",
	"gateway_session_id",
	"session_slot",
	"upstream_connection_id",
	"upstream_connections",
]

const CLIENT_WORLD_OPERATION_FIELDS: Array[String] = ["operation_id", "command", "target_id"]
const CLIENT_INPUT_FIELDS: Array[String] = ["input_seq", "axis_x"]
const CLIENT_WORLD_PROJECTION_FIELDS: Array[String] = ["read_only", "source_revision", "entities"]
const CLIENT_SNAPSHOT_FIELDS: Array[String] = ["revision"]

# EG1 session-control wire schemas (registered client surface payloads).
const EG1_SESSION_HELLO_PAYLOAD_SCHEMA := "planet_simulator.eg1_session_hello.v1"
const EG1_SESSION_DETACH_PAYLOAD_SCHEMA := "planet_simulator.eg1_session_detach.v1"
const EG1_SESSION_ATTACHED_ACK_PAYLOAD_SCHEMA := "planet_simulator.eg1_session_attached_ack.v1"
const EG1_SESSION_DETACHED_ACK_PAYLOAD_SCHEMA := "planet_simulator.eg1_session_detached_ack.v1"
const EG1_SESSION_HELLO_FIELDS: Array[String] = [
	"client_session_id",
	"logical_player_id",
	"player_entity_id",
	"world_id",
]
const EG1_SESSION_DETACH_FIELDS: Array[String] = []
const EG1_SESSION_ATTACHED_ACK_FIELDS: Array[String] = ["gateway_session_id", "session_slot", "state"]
const EG1_SESSION_DETACHED_ACK_FIELDS: Array[String] = ["gateway_session_id", "state"]


static func validate_schema(value: Dictionary, expected_schema: String) -> Dictionary:
	if value.get("schema") != expected_schema:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "schema mismatch")
	if not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) \
			or int(value.get("protocol_version")) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "protocol_version mismatch")
	return NetworkUtilsScript.validation_success()


static func require_id(value: Dictionary, field: String, prefix: String) -> Dictionary:
	if not BusUtilsScript.is_canonical_id(value.get(field), prefix):
		return NetworkUtilsScript.validation_failure(
			"INVALID_ID",
			"%s must be a canonical %s/* id" % [field, prefix],
		)
	return NetworkUtilsScript.validation_success()


static func require_enum(value: Dictionary, field: String, allowed: Array[String]) -> Dictionary:
	if typeof(value.get(field)) != TYPE_STRING or not allowed.has(String(value.get(field))):
		return NetworkUtilsScript.validation_failure(
			"INVALID_ENUM",
			"%s must be one of %s" % [field, allowed],
		)
	return NetworkUtilsScript.validation_success()


static func require_positive_integer(value: Dictionary, field: String) -> Dictionary:
	if not NetworkUtilsScript.is_json_integer(value.get(field)) or int(value.get(field)) < 1:
		return NetworkUtilsScript.validation_failure("INVALID_INTEGER", "%s must be >= 1" % field)
	return NetworkUtilsScript.validation_success()


static func require_nonnegative_integer(value: Dictionary, field: String) -> Dictionary:
	if not NetworkUtilsScript.is_json_integer(value.get(field)) or int(value.get(field)) < 0:
		return NetworkUtilsScript.validation_failure("INVALID_INTEGER", "%s must be >= 0" % field)
	return NetworkUtilsScript.validation_success()


static func require_payload_schema(value: Dictionary, field: String = "payload_schema") -> Dictionary:
	if not BusUtilsScript.is_payload_schema(value.get(field)):
		return NetworkUtilsScript.validation_failure(
			"INVALID_PAYLOAD_SCHEMA",
			"%s must be a versioned planet_simulator.* schema" % field,
		)
	return NetworkUtilsScript.validation_success()


static func validate_payload(payload) -> Dictionary:
	return BusUtilsScript.validate_payload(payload)


static func validate_client_surface_payload(payload, payload_schema: String) -> Dictionary:
	var base_check: Dictionary = validate_payload(payload)
	if not bool(base_check.get("success", false)):
		return base_check
	var legacy_fence: Dictionary = _validate_forbidden_fields(
		payload,
		CLIENT_SURFACE_FORBIDDEN_FIELDS,
		"CLIENT_TOPOLOGY_METADATA_FORBIDDEN",
		"ClientWorldFrame payload",
	)
	if not bool(legacy_fence.get("success", false)):
		return legacy_fence
	if typeof(payload) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_TYPE", "payload must be a Dictionary")
	return _validate_registered_client_payload(Dictionary(payload), payload_schema)


static func validate_world_graph_payload(payload) -> Dictionary:
	var base_check: Dictionary = validate_payload(payload)
	if not bool(base_check.get("success", false)):
		return base_check
	return _validate_forbidden_fields(
		payload,
		WORLD_GRAPH_RUNTIME_FORBIDDEN_FIELDS,
		"WORLD_GRAPH_RUNTIME_METADATA_FORBIDDEN",
		"WorldGraph semantic payload",
	)


static func validate_derived_routing_payload(payload) -> Dictionary:
	var base_check: Dictionary = validate_payload(payload)
	if not bool(base_check.get("success", false)):
		return base_check
	return _validate_forbidden_fields(
		payload,
		WORLD_GRAPH_RUNTIME_FORBIDDEN_FIELDS,
		"DERIVED_ROUTING_RUNTIME_METADATA_FORBIDDEN",
		"Derived routing payload",
	)


static func validate_world_graph_semantic_fields(
		payload,
		allowed_fields: Array[String],
		label: String,
) -> Dictionary:
	var base_check: Dictionary = validate_world_graph_payload(payload)
	if not bool(base_check.get("success", false)):
		return base_check
	return _validate_allowed_semantic_fields(Dictionary(payload), allowed_fields, label)


static func validate_derived_routing_semantic_fields(
		payload,
		allowed_fields: Array[String],
		label: String,
) -> Dictionary:
	var base_check: Dictionary = validate_derived_routing_payload(payload)
	if not bool(base_check.get("success", false)):
		return base_check
	return _validate_allowed_semantic_fields(Dictionary(payload), allowed_fields, label)


static func is_mutating_client_channel(channel: String) -> bool:
	return MUTATING_CLIENT_CHANNELS.has(channel)


static func validate_client_frame_semantics(value: Dictionary) -> Dictionary:
	var channel: String = String(value.get("channel", ""))
	var payload = value.get("payload")
	if typeof(payload) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_TYPE", "payload must be a Dictionary")
	var payload_dict: Dictionary = Dictionary(payload)

	match channel:
		"WORLD_OPERATION":
			if not BusUtilsScript.is_canonical_id(payload_dict.get("operation_id"), "operation"):
				return NetworkUtilsScript.validation_failure(
					"INVALID_OPERATION_ID",
					"WORLD_OPERATION requires canonical operation_id",
				)
		"INPUT_MOVEMENT":
			if not NetworkUtilsScript.is_json_integer(payload_dict.get("input_seq")) \
					or int(payload_dict.get("input_seq")) < 1:
				return NetworkUtilsScript.validation_failure(
					"INVALID_INPUT_SEQUENCE",
					"INPUT_MOVEMENT requires positive input_seq",
				)
		"WORLD_PROJECTION":
			if typeof(payload_dict.get("read_only")) != TYPE_BOOL or not bool(payload_dict.get("read_only")):
				return NetworkUtilsScript.validation_failure(
					"PROJECTION_NOT_READ_ONLY",
					"WORLD_PROJECTION payload must declare read_only=true",
				)
	return NetworkUtilsScript.validation_success()


static func _validate_registered_client_payload(payload: Dictionary, payload_schema: String) -> Dictionary:
	# EG0-R7-V-001 repair ordering contract:
	# 1) required/domain semantic fields validate first and keep their
	#    established domain-specific error codes
	#    (INVALID_OPERATION_ID / INVALID_INPUT_SEQUENCE /
	#    PROJECTION_NOT_READ_ONLY / INVALID_CLIENT_PAYLOAD);
	# 2) exact admitted-field enforcement runs last and stays fail-closed,
	#    returning CLIENT_PAYLOAD_SCHEMA_VIOLATION for unregistered extras.
	match payload_schema:
		"planet_simulator.test_world_operation.v1":
			if not BusUtilsScript.is_canonical_id(payload.get("operation_id"), "operation"):
				return NetworkUtilsScript.validation_failure("INVALID_OPERATION_ID", "Invalid operation_id")
			if not BusUtilsScript.is_semantic_name(payload.get("command"), false):
				return NetworkUtilsScript.validation_failure("INVALID_CLIENT_PAYLOAD", "command must be semantic")
			if not BusUtilsScript.is_canonical_id(payload.get("target_id"), "entity"):
				return NetworkUtilsScript.validation_failure("INVALID_CLIENT_PAYLOAD", "target_id must be entity/*")
			var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(payload, CLIENT_WORLD_OPERATION_FIELDS)
			if not bool(exact.get("success", false)):
				return NetworkUtilsScript.validation_failure(
					"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
					"WORLD_OPERATION payload does not match its registered semantic schema",
				)
		"planet_simulator.test_input.v1":
			if not NetworkUtilsScript.is_json_integer(payload.get("input_seq")) or int(payload.get("input_seq")) < 1:
				return NetworkUtilsScript.validation_failure("INVALID_INPUT_SEQUENCE", "input_seq must be positive")
			if not _is_finite_number(payload.get("axis_x")):
				return NetworkUtilsScript.validation_failure("INVALID_CLIENT_PAYLOAD", "axis_x must be finite numeric")
			var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(payload, CLIENT_INPUT_FIELDS)
			if not bool(exact.get("success", false)):
				return NetworkUtilsScript.validation_failure(
					"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
					"INPUT_MOVEMENT payload does not match its registered semantic schema",
				)
		"planet_simulator.test_world_projection.v1":
			if typeof(payload.get("read_only")) != TYPE_BOOL or not bool(payload.get("read_only")):
				return NetworkUtilsScript.validation_failure("PROJECTION_NOT_READ_ONLY", "Projection must be read_only")
			if not NetworkUtilsScript.is_json_integer(payload.get("source_revision")) or int(payload.get("source_revision")) < 1:
				return NetworkUtilsScript.validation_failure("INVALID_CLIENT_PAYLOAD", "source_revision must be positive")
			if typeof(payload.get("entities")) != TYPE_ARRAY:
				return NetworkUtilsScript.validation_failure("INVALID_CLIENT_PAYLOAD", "entities must be an Array")
			for entity_id in Array(payload.get("entities")):
				if not BusUtilsScript.is_canonical_id(entity_id, "entity"):
					return NetworkUtilsScript.validation_failure("INVALID_CLIENT_PAYLOAD", "entities must contain entity/* ids")
			var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(payload, CLIENT_WORLD_PROJECTION_FIELDS)
			if not bool(exact.get("success", false)):
				return NetworkUtilsScript.validation_failure(
					"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
					"WORLD_PROJECTION payload does not match its registered semantic schema",
				)
		"planet_simulator.test_snapshot.v1":
			if not NetworkUtilsScript.is_json_integer(payload.get("revision")) or int(payload.get("revision")) < 1:
				return NetworkUtilsScript.validation_failure("INVALID_CLIENT_PAYLOAD", "revision must be positive")
			var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(payload, CLIENT_SNAPSHOT_FIELDS)
			if not bool(exact.get("success", false)):
				return NetworkUtilsScript.validation_failure(
					"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
					"AUTHORITATIVE_SNAPSHOT payload does not match its registered semantic schema",
				)
		"planet_simulator.eg1_session_hello.v1":
			for pair in [
				["client_session_id", "client-session"],
				["logical_player_id", "player"],
				["player_entity_id", "entity"],
				["world_id", "world"],
			]:
				var id_check: Dictionary = require_id(payload, String(pair[0]), String(pair[1]))
				if not bool(id_check.get("success", false)):
					return NetworkUtilsScript.validation_failure(
						"INVALID_CLIENT_PAYLOAD",
						"%s must be a canonical %s/* id" % [String(pair[0]), String(pair[1])],
					)
			var hello_exact: Dictionary = NetworkUtilsScript.validate_exact_fields(payload, EG1_SESSION_HELLO_FIELDS)
			if not bool(hello_exact.get("success", false)):
				return NetworkUtilsScript.validation_failure(
					"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
					"SESSION_CONTROL hello payload does not match its registered semantic schema",
				)
		"planet_simulator.eg1_session_detach.v1":
			if not payload.is_empty():
				return NetworkUtilsScript.validation_failure(
					"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
					"SESSION_CONTROL detach payload must be empty",
				)
		"planet_simulator.eg1_session_attached_ack.v1":
			for check in [
				require_id(payload, "gateway_session_id", "gateway-session"),
				require_positive_integer(payload, "session_slot"),
				require_enum(payload, "state", [String("ATTACHED")]),
			]:
				if not bool(check.get("success", false)):
					return NetworkUtilsScript.validation_failure(
						"INVALID_CLIENT_PAYLOAD",
						String(check.get("message", "invalid attached ack payload")),
					)
			var attached_exact: Dictionary = NetworkUtilsScript.validate_exact_fields(payload, EG1_SESSION_ATTACHED_ACK_FIELDS)
			if not bool(attached_exact.get("success", false)):
				return NetworkUtilsScript.validation_failure(
					"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
					"SESSION_CONTROL attached ack payload does not match its registered semantic schema",
				)
		"planet_simulator.eg1_session_detached_ack.v1":
			for check in [
				require_id(payload, "gateway_session_id", "gateway-session"),
				require_enum(payload, "state", [String("DETACHED")]),
			]:
				if not bool(check.get("success", false)):
					return NetworkUtilsScript.validation_failure(
						"INVALID_CLIENT_PAYLOAD",
						String(check.get("message", "invalid detached ack payload")),
					)
			var detached_exact: Dictionary = NetworkUtilsScript.validate_exact_fields(payload, EG1_SESSION_DETACHED_ACK_FIELDS)
			if not bool(detached_exact.get("success", false)):
				return NetworkUtilsScript.validation_failure(
					"CLIENT_PAYLOAD_SCHEMA_VIOLATION",
					"SESSION_CONTROL detached ack payload does not match its registered semantic schema",
				)
		_:
			return NetworkUtilsScript.validation_failure(
				"UNREGISTERED_CLIENT_PAYLOAD_SCHEMA",
				"ClientWorldFrame payload schema is not registered for topology-neutral client exposure",
			)
	return NetworkUtilsScript.validation_success()


static func _validate_allowed_semantic_fields(
		value: Dictionary,
		allowed_fields: Array[String],
		label: String,
) -> Dictionary:
	for raw_key in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return NetworkUtilsScript.validation_failure("INVALID_FIELD_NAME", "%s field names must be String" % label)
		var key: String = String(raw_key)
		if not allowed_fields.has(key):
			return NetworkUtilsScript.validation_failure(
				"UNEXPECTED_SEMANTIC_FIELD",
				"%s contains unregistered semantic field: %s" % [label, key],
			)
	return NetworkUtilsScript.validation_success()


static func _is_finite_number(value) -> bool:
	if typeof(value) == TYPE_INT:
		return NetworkUtilsScript.is_json_integer(value)
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return not is_nan(number) and not is_inf(number) and absf(number) <= float(NetworkUtilsScript.MAX_SAFE_JSON_INTEGER)


static func _validate_forbidden_fields(
		value,
		forbidden_fields: Array[String],
		error_code: String,
		label: String,
) -> Dictionary:
	var path: String = _find_forbidden_field(value, forbidden_fields, "$")
	if not path.is_empty():
		return NetworkUtilsScript.validation_failure(
			error_code,
			"%s contains physical/runtime topology metadata at %s" % [label, path],
		)
	return NetworkUtilsScript.validation_success()


static func _find_forbidden_field(value, forbidden_fields: Array[String], path: String) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			for raw_key in value.keys():
				if typeof(raw_key) != TYPE_STRING:
					return "%s.<non-string-key>" % path
				var key: String = String(raw_key)
				if forbidden_fields.has(key):
					return "%s.%s" % [path, key]
				var nested: String = _find_forbidden_field(
					value[raw_key],
					forbidden_fields,
					"%s.%s" % [path, key],
				)
				if not nested.is_empty():
					return nested
		TYPE_ARRAY:
			for index in range(value.size()):
				var nested: String = _find_forbidden_field(
					value[index],
					forbidden_fields,
					"%s[%d]" % [path, index],
				)
				if not nested.is_empty():
					return nested
	return ""
