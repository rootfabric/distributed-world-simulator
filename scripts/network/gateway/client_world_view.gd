extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.client_world_view.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"view_id",
	"gateway_session_id",
	"anchor_world_id",
	"reference_frame_id",
	"active_authority_world",
	"warm_worlds",
	"projection_streams",
	"macro_sources",
	"graph_revision",
	"view_revision",
	"interest_revision",
	"read_only",
]
const PROJECTION_FIELDS: Array[String] = [
	"source_world_id",
	"projection_stream_id",
	"lod_class",
	"priority",
	"visibility_reason",
	"interest_revision",
	"projection_grant",
]


static func create(
		view_id: String,
		gateway_session_id: String,
		anchor_world_id: String,
		reference_frame_id: String,
		active_authority_world: String,
		warm_worlds: Array,
		projection_streams: Array,
		macro_sources: Array,
		graph_revision: int,
		view_revision: int,
		interest_revision: int,
		read_only: bool = true,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"view_id": view_id,
		"gateway_session_id": gateway_session_id,
		"anchor_world_id": anchor_world_id,
		"reference_frame_id": reference_frame_id,
		"active_authority_world": active_authority_world,
		"warm_worlds": warm_worlds.duplicate(true),
		"projection_streams": projection_streams.duplicate(true),
		"macro_sources": macro_sources.duplicate(true),
		"graph_revision": graph_revision,
		"view_revision": view_revision,
		"interest_revision": interest_revision,
		"read_only": read_only,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["view_id", "world-view"],
		["gateway_session_id", "gateway-session"],
		["anchor_world_id", "world"],
		["reference_frame_id", "reference-frame"],
		["active_authority_world", "world"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for field in ["graph_revision", "view_revision", "interest_revision"]:
		var revision_check: Dictionary = GatewayUtilsScript.require_positive_integer(value, String(field))
		if not bool(revision_check.get("success", false)):
			return revision_check
	var schema_check: Dictionary = GatewayUtilsScript.validate_schema(value, SCHEMA)
	if not bool(schema_check.get("success", false)):
		return schema_check
	if typeof(value.get("read_only")) != TYPE_BOOL or not bool(value.get("read_only")):
		return NetworkUtilsScript.validation_failure("VIEW_NOT_READ_ONLY", "ClientWorldView is derived read-only metadata")
	if typeof(value.get("warm_worlds")) != TYPE_ARRAY:
		return NetworkUtilsScript.validation_failure("INVALID_WARM_WORLDS", "warm_worlds must be an Array")
	for world_id in Array(value.get("warm_worlds")):
		if not BusUtilsScript.is_canonical_id(world_id, "world"):
			return NetworkUtilsScript.validation_failure("INVALID_WARM_WORLD_ID", "warm_worlds contains invalid world id")
	for field in ["projection_streams", "macro_sources"]:
		var list_check: Dictionary = _validate_projection_entries(value.get(String(field)), String(field))
		if not bool(list_check.get("success", false)):
			return list_check
	return NetworkUtilsScript.validation_success()


static func validate_newer(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var candidate_check: Dictionary = validate(candidate)
	if not bool(candidate_check.get("success", false)):
		return candidate_check
	var current_check: Dictionary = validate(current)
	if not bool(current_check.get("success", false)):
		return current_check
	if String(candidate.get("gateway_session_id")) != String(current.get("gateway_session_id")):
		return NetworkUtilsScript.validation_failure("SESSION_MISMATCH", "Cannot compare views for different sessions")
	if int(candidate.get("graph_revision")) < int(current.get("graph_revision")):
		return NetworkUtilsScript.validation_failure("STALE_GRAPH_REVISION", "graph_revision cannot rewind")
	if int(candidate.get("view_revision")) <= int(current.get("view_revision")):
		return NetworkUtilsScript.validation_failure("STALE_VIEW_REVISION", "view_revision must advance")
	if int(candidate.get("interest_revision")) < int(current.get("interest_revision")):
		return NetworkUtilsScript.validation_failure("STALE_INTEREST_REVISION", "interest_revision cannot rewind")
	return NetworkUtilsScript.validation_success()


static func _validate_projection_entries(raw_value, field: String) -> Dictionary:
	if typeof(raw_value) != TYPE_ARRAY:
		return NetworkUtilsScript.validation_failure("INVALID_PROJECTION_LIST", "%s must be an Array" % field)
	for raw_entry in Array(raw_value):
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return NetworkUtilsScript.validation_failure("INVALID_PROJECTION_ENTRY", "%s contains non-Dictionary" % field)
		var entry: Dictionary = Dictionary(raw_entry)
		var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(entry, PROJECTION_FIELDS)
		if not bool(exact.get("success", false)):
			return exact
		for pair in [
			["source_world_id", "world"],
			["projection_stream_id", "projection-stream"],
			["projection_grant", "projection-grant"],
		]:
			var id_check: Dictionary = GatewayUtilsScript.require_id(entry, String(pair[0]), String(pair[1]))
			if not bool(id_check.get("success", false)):
				return id_check
		if not BusUtilsScript.is_semantic_name(entry.get("lod_class"), false):
			return NetworkUtilsScript.validation_failure("INVALID_LOD_CLASS", "lod_class must be semantic name")
		if not BusUtilsScript.is_semantic_name(entry.get("visibility_reason"), false):
			return NetworkUtilsScript.validation_failure("INVALID_VISIBILITY_REASON", "visibility_reason must be semantic name")
		for integer_field in ["priority", "interest_revision"]:
			var integer_check: Dictionary = GatewayUtilsScript.require_nonnegative_integer(entry, String(integer_field))
			if not bool(integer_check.get("success", false)):
				return integer_check
	return NetworkUtilsScript.validation_success()
