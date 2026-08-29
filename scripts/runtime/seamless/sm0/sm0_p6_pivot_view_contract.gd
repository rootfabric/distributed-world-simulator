extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

const SCHEMA := "distributed_world_simulator.sm0_p6_projection_pivot_view.v1"
const ROLE_CANONICAL := "canonical"
const ROLE_PROJECTION := "projection"
const ROLE_HANDOFF_HOLD := "handoff_hold"

const REQUIRED_FIELDS: Array[String] = [
	"schema",
	"world_id",
	"viewer_authority_id",
	"viewer_zone_id",
	"view_sequence",
	"directory",
	"presentation_role",
	"logical_player_id",
	"player_entity_id",
	"visual_entity_key",
	"owner_authority_id",
	"authority_epoch",
	"state_revision",
	"last_input_sequence",
	"position",
	"velocity",
	"orientation_yaw",
	"canonical_writer",
	"read_only",
	"held",
	"command_channel",
	"checksum",
]


static func create(
	viewer_authority_id: String,
	viewer_zone_id: String,
	view_sequence: int,
	directory: Dictionary,
	presentation_role: String,
	player_state: Dictionary
) -> Dictionary:
	var owner_authority_id := String(directory.get("owner_authority_id", ""))
	var canonical_writer := presentation_role == ROLE_CANONICAL
	var held := presentation_role == ROLE_HANDOFF_HOLD
	return Utils.finalize_json_checksum({
		"schema": SCHEMA,
		"world_id": "earth",
		"viewer_authority_id": viewer_authority_id,
		"viewer_zone_id": viewer_zone_id,
		"view_sequence": view_sequence,
		"directory": directory.duplicate(true),
		"presentation_role": presentation_role,
		"logical_player_id": String(player_state.get("logical_player_id", "")),
		"player_entity_id": String(player_state.get("player_entity_id", "")),
		"visual_entity_key": "earth/%s" % String(player_state.get("player_entity_id", "")),
		"owner_authority_id": owner_authority_id,
		"authority_epoch": int(directory.get("authority_epoch", 0)),
		"state_revision": int(player_state.get("state_revision", 0)),
		"last_input_sequence": int(player_state.get("last_input_sequence", 0)),
		"position": Dictionary(player_state.get("position", {})).duplicate(true),
		"velocity": Dictionary(player_state.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(player_state.get("orientation_yaw", 0.0)),
		"canonical_writer": canonical_writer,
		"read_only": not canonical_writer,
		"held": held,
		"command_channel": false,
		"checksum": "",
	})


static func validate(value: Dictionary) -> Dictionary:
	var fields := Utils.validate_exact_fields(value, REQUIRED_FIELDS)
	if not bool(fields.get("success", false)):
		return _failure("SM0_P6_VIEW_FIELDS_INVALID", {"cause": fields})
	if String(value.get("schema", "")) != SCHEMA or String(value.get("world_id", "")) != "earth":
		return _failure("SM0_P6_VIEW_SCHEMA_INVALID")

	var viewer_authority_id := String(value.get("viewer_authority_id", ""))
	var viewer_zone_id := String(value.get("viewer_zone_id", ""))
	if viewer_authority_id not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B]:
		return _failure("SM0_P6_VIEW_VIEWER_INVALID")
	if Contracts.authority_for_zone(viewer_zone_id) != viewer_authority_id:
		return _failure("SM0_P6_VIEW_ZONE_INVALID")
	if not Utils.is_json_integer(value.get("view_sequence")) or int(value.get("view_sequence", 0)) < 1:
		return _failure("SM0_P6_VIEW_SEQUENCE_INVALID")

	var directory: Dictionary = Dictionary(value.get("directory", {}))
	var directory_check: Dictionary = Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)):
		return _failure("SM0_P6_VIEW_DIRECTORY_INVALID", {"cause": directory_check})
	var owner_authority_id := String(value.get("owner_authority_id", ""))
	if owner_authority_id != String(directory.get("owner_authority_id", "")):
		return _failure("SM0_P6_VIEW_OWNER_DIRECTORY_MISMATCH")
	if int(value.get("authority_epoch", 0)) != int(directory.get("authority_epoch", 0)):
		return _failure("SM0_P6_VIEW_EPOCH_DIRECTORY_MISMATCH")

	var logical_player_id := String(value.get("logical_player_id", "")).strip_edges()
	if logical_player_id != "a":
		return _failure("SM0_P6_VIEW_PLAYER_INVALID")
	if String(value.get("player_entity_id", "")) != "player/a":
		return _failure("SM0_P6_VIEW_ENTITY_ID_CHANGED")
	if String(value.get("visual_entity_key", "")) != "earth/player/a":
		return _failure("SM0_P6_VIEW_VISUAL_KEY_INVALID")

	if not Utils.is_json_integer(value.get("state_revision")) or int(value.get("state_revision", 0)) < 1:
		return _failure("SM0_P6_VIEW_STATE_REVISION_INVALID")
	if not Utils.is_json_integer(value.get("last_input_sequence")) or int(value.get("last_input_sequence", -1)) < 0:
		return _failure("SM0_P6_VIEW_INPUT_SEQUENCE_INVALID")
	if not value.get("position") is Dictionary or not value.get("velocity") is Dictionary:
		return _failure("SM0_P6_VIEW_SPATIAL_STATE_REQUIRED")
	if not _validate_vec3(Dictionary(value.get("position", {}))) or not _validate_vec3(Dictionary(value.get("velocity", {}))):
		return _failure("SM0_P6_VIEW_SPATIAL_STATE_INVALID")
	if typeof(value.get("orientation_yaw")) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("SM0_P6_VIEW_ORIENTATION_INVALID")
	var yaw := float(value.get("orientation_yaw", 0.0))
	if is_nan(yaw) or is_inf(yaw):
		return _failure("SM0_P6_VIEW_ORIENTATION_INVALID")

	if typeof(value.get("canonical_writer")) != TYPE_BOOL or typeof(value.get("read_only")) != TYPE_BOOL or typeof(value.get("held")) != TYPE_BOOL:
		return _failure("SM0_P6_VIEW_ROLE_FLAGS_INVALID")
	if value.get("command_channel") != false:
		return _failure("SM0_P6_VIEW_COMMAND_CHANNEL_FORBIDDEN")

	var role := String(value.get("presentation_role", ""))
	match role:
		ROLE_CANONICAL:
			if owner_authority_id != viewer_authority_id or not bool(value.get("canonical_writer", false)) or bool(value.get("read_only", true)) or bool(value.get("held", true)):
				return _failure("SM0_P6_VIEW_CANONICAL_ROLE_INVALID")
		ROLE_PROJECTION:
			if owner_authority_id == viewer_authority_id or bool(value.get("canonical_writer", true)) or not bool(value.get("read_only", false)) or bool(value.get("held", true)):
				return _failure("SM0_P6_VIEW_PROJECTION_ROLE_INVALID")
		ROLE_HANDOFF_HOLD:
			if bool(value.get("canonical_writer", true)) or not bool(value.get("read_only", false)) or not bool(value.get("held", false)):
				return _failure("SM0_P6_VIEW_HOLD_ROLE_INVALID")
		_:
			return _failure("SM0_P6_VIEW_ROLE_INVALID")

	var expected_checksum := String(value.get("checksum", ""))
	var payload := value.duplicate(true)
	payload.erase("checksum")
	if expected_checksum.is_empty() or expected_checksum != Utils.payload_hash(payload):
		return _failure("SM0_P6_VIEW_CHECKSUM_MISMATCH")
	return _success()


static func _validate_vec3(value: Dictionary) -> bool:
	for axis in ["x", "y", "z"]:
		if not value.has(axis) or typeof(value.get(axis)) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var component := float(value.get(axis, 0.0))
		if is_nan(component) or is_inf(component):
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}