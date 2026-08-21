extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const SessionBindingScript = preload("res://scripts/network/gateway/gateway_session_binding.gd")
const RouteBindingScript = preload("res://scripts/network/gateway/gateway_route_binding.gd")

const SCHEMA := "planet_simulator.gateway_connect_gate.v1"
const PROTOCOL_VERSION := 1
const PLACEMENT_SOURCE_OWNER := "SESSION_PLACEMENT"
const DIRECTORY_SOURCE_OWNER := "WORLD_DIRECTORY"
const READY_SOURCE_OWNER := "AUTHORITY"
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"connect_attempt_id",
	"transport_connection_id",
	"gateway_instance_id",
	"gateway_session_id",
	"client_session_id",
	"route_binding_id",
	"logical_player_id",
	"player_entity_id",
	"world_id",
	"authority_id",
	"server_instance_id",
	"protocol_admission_revision",
	"identity_verification_revision",
	"session_revision",
	"placement_revision",
	"directory_generation",
	"authority_epoch",
	"route_revision",
	"ready_snapshot_revision",
	"protocol_admitted",
	"identity_verified",
	"session_resolved",
	"placement_resolved",
	"authority_resolved",
	"backend_route_attached",
	"player_domain_ready",
	"world_ready",
	"gate_revision",
	"session_binding",
	"placement_evidence",
	"directory_authority_evidence",
	"route_binding",
	"ready_snapshot_evidence",
]
const PLACEMENT_EVIDENCE_FIELDS: Array[String] = [
	"placement_evidence_id",
	"source_owner",
	"client_session_id",
	"logical_player_id",
	"player_entity_id",
	"world_id",
	"placement_revision",
]
const DIRECTORY_EVIDENCE_FIELDS: Array[String] = [
	"authority_resolution_id",
	"source_owner",
	"player_entity_id",
	"world_id",
	"authority_id",
	"server_instance_id",
	"directory_generation",
	"authority_epoch",
]
const READY_EVIDENCE_FIELDS: Array[String] = [
	"ready_snapshot_id",
	"source_owner",
	"gateway_session_id",
	"player_entity_id",
	"world_id",
	"authority_id",
	"authority_epoch",
	"snapshot_revision",
]

static func create(
		connect_attempt_id: String,
		transport_connection_id: String,
		gateway_instance_id: String,
		protocol_admission_revision: int,
		identity_verification_revision: int,
		protocol_admitted: bool,
		identity_verified: bool,
		session_resolved: bool,
		placement_resolved: bool,
		authority_resolved: bool,
		backend_route_attached: bool,
		player_domain_ready: bool,
		world_ready: bool,
		gate_revision: int,
		session_binding: Dictionary,
		placement_evidence: Dictionary,
		directory_authority_evidence: Dictionary,
		route_binding: Dictionary,
		ready_snapshot_evidence: Dictionary,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"connect_attempt_id": connect_attempt_id,
		"transport_connection_id": transport_connection_id,
		"gateway_instance_id": gateway_instance_id,
		"gateway_session_id": String(session_binding.get("gateway_session_id", "")),
		"client_session_id": String(session_binding.get("client_session_id", "")),
		"route_binding_id": String(route_binding.get("route_binding_id", "")),
		"logical_player_id": String(session_binding.get("logical_player_id", "")),
		"player_entity_id": String(session_binding.get("player_entity_id", "")),
		"world_id": String(placement_evidence.get("world_id", "")),
		"authority_id": String(directory_authority_evidence.get("authority_id", "")),
		"server_instance_id": String(directory_authority_evidence.get("server_instance_id", "")),
		"protocol_admission_revision": protocol_admission_revision,
		"identity_verification_revision": identity_verification_revision,
		"session_revision": int(session_binding.get("binding_revision", 0)),
		"placement_revision": int(placement_evidence.get("placement_revision", 0)),
		"directory_generation": int(directory_authority_evidence.get("directory_generation", 0)),
		"authority_epoch": int(directory_authority_evidence.get("authority_epoch", 0)),
		"route_revision": int(route_binding.get("route_revision", 0)),
		"ready_snapshot_revision": int(ready_snapshot_evidence.get("snapshot_revision", 0)),
		"protocol_admitted": protocol_admitted,
		"identity_verified": identity_verified,
		"session_resolved": session_resolved,
		"placement_resolved": placement_resolved,
		"authority_resolved": authority_resolved,
		"backend_route_attached": backend_route_attached,
		"player_domain_ready": player_domain_ready,
		"world_ready": world_ready,
		"gate_revision": gate_revision,
		"session_binding": session_binding.duplicate(true),
		"placement_evidence": placement_evidence.duplicate(true),
		"directory_authority_evidence": directory_authority_evidence.duplicate(true),
		"route_binding": route_binding.duplicate(true),
		"ready_snapshot_evidence": ready_snapshot_evidence.duplicate(true),
	}

static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["connect_attempt_id", "connect-attempt"],
		["transport_connection_id", "transport-connection"],
		["gateway_instance_id", "gateway"],
		["gateway_session_id", "gateway-session"],
		["client_session_id", "client-session"],
		["route_binding_id", "gateway-route"],
		["logical_player_id", "player"],
		["player_entity_id", "entity"],
		["world_id", "world"],
		["authority_id", "authority"],
		["server_instance_id", "server-instance"],
	]:
		var id_check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(id_check.get("success", false)):
			return id_check
	for field in [
		"protocol_admission_revision",
		"identity_verification_revision",
		"session_revision",
		"placement_revision",
		"directory_generation",
		"authority_epoch",
		"route_revision",
		"ready_snapshot_revision",
		"gate_revision",
	]:
		var integer_check: Dictionary = GatewayUtilsScript.require_positive_integer(value, String(field))
		if not bool(integer_check.get("success", false)):
			return integer_check
	var schema_check: Dictionary = GatewayUtilsScript.validate_schema(value, SCHEMA)
	if not bool(schema_check.get("success", false)):
		return schema_check
	for gate in [
		["protocol_admitted", "PROTOCOL_NOT_ADMITTED"],
		["identity_verified", "IDENTITY_NOT_VERIFIED"],
		["session_resolved", "SESSION_NOT_RESOLVED"],
		["placement_resolved", "PLACEMENT_NOT_RESOLVED"],
		["authority_resolved", "AUTHORITY_NOT_RESOLVED"],
		["backend_route_attached", "BACKEND_ROUTE_NOT_ATTACHED"],
		["player_domain_ready", "PLAYER_DOMAIN_NOT_READY"],
		["world_ready", "WORLD_NOT_READY"],
	]:
		var field := String(gate[0])
		if typeof(value.get(field)) != TYPE_BOOL:
			return NetworkUtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must be Boolean" % field)
		if not bool(value.get(field)):
			return NetworkUtilsScript.validation_failure(String(gate[1]), "%s must be true before WorldReady" % field)

	for field in ["session_binding", "placement_evidence", "directory_authority_evidence", "route_binding", "ready_snapshot_evidence"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return NetworkUtilsScript.validation_failure("INVALID_CONNECT_EVIDENCE", "%s must be a Dictionary" % field)
	var session: Dictionary = Dictionary(value.get("session_binding"))
	var placement: Dictionary = Dictionary(value.get("placement_evidence"))
	var directory: Dictionary = Dictionary(value.get("directory_authority_evidence"))
	var route: Dictionary = Dictionary(value.get("route_binding"))
	var ready: Dictionary = Dictionary(value.get("ready_snapshot_evidence"))

	var session_check: Dictionary = SessionBindingScript.validate(session)
	if not bool(session_check.get("success", false)):
		return session_check
	if String(session.get("state")) != "ATTACHED":
		return NetworkUtilsScript.validation_failure("CONNECT_SESSION_NOT_ATTACHED", "WorldReady requires session_binding.state=ATTACHED")
	var placement_check: Dictionary = _validate_placement_evidence(placement)
	if not bool(placement_check.get("success", false)):
		return placement_check
	var directory_check: Dictionary = _validate_directory_evidence(directory)
	if not bool(directory_check.get("success", false)):
		return directory_check
	var route_check: Dictionary = RouteBindingScript.validate(route)
	if not bool(route_check.get("success", false)):
		return route_check
	if String(route.get("route_role")) != "ACTIVE":
		return NetworkUtilsScript.validation_failure("CONNECT_ROUTE_NOT_ACTIVE", "WorldReady requires route_binding.route_role=ACTIVE")
	var ready_check: Dictionary = _validate_ready_evidence(ready)
	if not bool(ready_check.get("success", false)):
		return ready_check

	var correlation_check: Dictionary = _validate_evidence_correlation(value, session, placement, directory, route, ready)
	if not bool(correlation_check.get("success", false)):
		return correlation_check
	return NetworkUtilsScript.validation_success()

static func _validate_placement_evidence(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, PLACEMENT_EVIDENCE_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("source_owner") != PLACEMENT_SOURCE_OWNER:
		return NetworkUtilsScript.validation_failure("PLACEMENT_SOURCE_OWNER_INVALID", "placement evidence must come from SESSION_PLACEMENT")
	for pair in [
		["placement_evidence_id", "placement-evidence"],
		["client_session_id", "client-session"],
		["logical_player_id", "player"],
		["player_entity_id", "entity"],
		["world_id", "world"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	return GatewayUtilsScript.require_positive_integer(value, "placement_revision")

static func _validate_directory_evidence(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, DIRECTORY_EVIDENCE_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("source_owner") != DIRECTORY_SOURCE_OWNER:
		return NetworkUtilsScript.validation_failure("DIRECTORY_SOURCE_OWNER_INVALID", "authority resolution evidence must come from WORLD_DIRECTORY")
	for pair in [
		["authority_resolution_id", "authority-resolution"],
		["player_entity_id", "entity"],
		["world_id", "world"],
		["authority_id", "authority"],
		["server_instance_id", "server-instance"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for field in ["directory_generation", "authority_epoch"]:
		var check: Dictionary = GatewayUtilsScript.require_positive_integer(value, String(field))
		if not bool(check.get("success", false)):
			return check
	return NetworkUtilsScript.validation_success()

static func _validate_ready_evidence(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, READY_EVIDENCE_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("source_owner") != READY_SOURCE_OWNER:
		return NetworkUtilsScript.validation_failure("READY_SOURCE_OWNER_INVALID", "ready snapshot evidence must come from AUTHORITY")
	for pair in [
		["ready_snapshot_id", "ready-snapshot"],
		["gateway_session_id", "gateway-session"],
		["player_entity_id", "entity"],
		["world_id", "world"],
		["authority_id", "authority"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for field in ["authority_epoch", "snapshot_revision"]:
		var check: Dictionary = GatewayUtilsScript.require_positive_integer(value, String(field))
		if not bool(check.get("success", false)):
			return check
	return NetworkUtilsScript.validation_success()

static func _validate_evidence_correlation(
		gate: Dictionary,
		session: Dictionary,
		placement: Dictionary,
		directory: Dictionary,
		route: Dictionary,
		ready: Dictionary,
) -> Dictionary:
	for field in ["gateway_session_id", "client_session_id", "logical_player_id", "player_entity_id"]:
		if String(gate.get(String(field))) != String(session.get(String(field))):
			return NetworkUtilsScript.validation_failure("CONNECT_SESSION_EVIDENCE_MISMATCH", "%s differs from session binding" % field)
	if int(gate.get("session_revision")) != int(session.get("binding_revision")):
		return NetworkUtilsScript.validation_failure("CONNECT_SESSION_EVIDENCE_MISMATCH", "session_revision differs from binding_revision")

	for field in ["client_session_id", "logical_player_id", "player_entity_id", "world_id"]:
		if String(session.get(String(field))) != String(placement.get(String(field))):
			return NetworkUtilsScript.validation_failure("CONNECT_PLACEMENT_EVIDENCE_MISMATCH", "%s differs between session and placement evidence" % field)
	if String(gate.get("world_id")) != String(placement.get("world_id")) \
			or int(gate.get("placement_revision")) != int(placement.get("placement_revision")):
		return NetworkUtilsScript.validation_failure("CONNECT_PLACEMENT_EVIDENCE_MISMATCH", "gate placement tuple differs from placement evidence")

	for field in ["player_entity_id", "world_id"]:
		if String(placement.get(String(field))) != String(directory.get(String(field))):
			return NetworkUtilsScript.validation_failure("CONNECT_DIRECTORY_EVIDENCE_MISMATCH", "%s differs between placement and Directory evidence" % field)
	for field in ["authority_id", "server_instance_id"]:
		if String(gate.get(String(field))) != String(directory.get(String(field))):
			return NetworkUtilsScript.validation_failure("CONNECT_DIRECTORY_EVIDENCE_MISMATCH", "%s differs from Directory evidence" % field)
	if int(gate.get("directory_generation")) != int(directory.get("directory_generation")) \
			or int(gate.get("authority_epoch")) != int(directory.get("authority_epoch")):
		return NetworkUtilsScript.validation_failure("CONNECT_DIRECTORY_EVIDENCE_MISMATCH", "gate Directory generation/epoch differs from Directory evidence")

	for field in ["gateway_session_id", "player_entity_id", "authority_id", "server_instance_id"]:
		if String(route.get(String(field))) != String(gate.get(String(field))):
			return NetworkUtilsScript.validation_failure("CONNECT_ROUTE_EVIDENCE_MISMATCH", "%s differs from route binding" % field)
	if String(gate.get("route_binding_id")) != String(route.get("route_binding_id")) \
			or int(gate.get("route_revision")) != int(route.get("route_revision")) \
			or int(gate.get("authority_epoch")) != int(route.get("observed_authority_epoch")):
		return NetworkUtilsScript.validation_failure("CONNECT_ROUTE_EVIDENCE_MISMATCH", "gate route tuple differs from route binding")

	for field in ["gateway_session_id", "player_entity_id", "world_id", "authority_id"]:
		if String(ready.get(String(field))) != String(gate.get(String(field))):
			return NetworkUtilsScript.validation_failure("CONNECT_READY_EVIDENCE_MISMATCH", "%s differs from ready snapshot evidence" % field)
	if int(ready.get("authority_epoch")) != int(gate.get("authority_epoch")) \
			or int(ready.get("snapshot_revision")) != int(gate.get("ready_snapshot_revision")):
		return NetworkUtilsScript.validation_failure("CONNECT_READY_EVIDENCE_MISMATCH", "ready snapshot epoch/revision differs from gate")
	return NetworkUtilsScript.validation_success()
