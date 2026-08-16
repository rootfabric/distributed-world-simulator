extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")

const SCHEMA := "distributed_world_simulator.sm0_p5_player_projection.v1"

const REQUIRED_FIELDS: Array[String] = [
	"schema",
	"world_id",
	"logical_player_id",
	"player_entity_id",
	"owner_authority_id",
	"owner_zone_id",
	"authority_epoch",
	"player_ownership_epoch",
	"state_revision",
	"last_input_sequence",
	"connected",
	"position",
	"velocity",
	"orientation_yaw",
	"read_only",
	"checksum",
]


static func create_from_player(
	player: Dictionary,
	owner_authority_id: String,
	owner_zone_id: String,
	authority_epoch: int
) -> Dictionary:
	return Utils.finalize_json_checksum({
		"schema": SCHEMA,
		"world_id": "earth",
		"logical_player_id": String(player.get("logical_player_id", "")),
		"player_entity_id": String(player.get("player_entity_id", "")),
		"owner_authority_id": owner_authority_id,
		"owner_zone_id": owner_zone_id,
		"authority_epoch": authority_epoch,
		"player_ownership_epoch": int(player.get("ownership_epoch", 0)),
		"state_revision": int(player.get("state_revision", 0)),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"connected": bool(player.get("connected", false)),
		"position": Dictionary(player.get("position", {})).duplicate(true),
		"velocity": Dictionary(player.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(player.get("orientation_yaw", 0.0)),
		"read_only": true,
		"checksum": "",
	})


static func validate(value: Dictionary) -> Dictionary:
	var fields := Utils.validate_exact_fields(value, REQUIRED_FIELDS)
	if not bool(fields.get("success", false)):
		return _failure("SM0_P5_PROJECTION_FIELDS_INVALID", {"cause": fields})

	if String(value.get("schema", "")) != SCHEMA:
		return _failure("SM0_P5_PROJECTION_SCHEMA_INVALID")
	if String(value.get("world_id", "")) != "earth":
		return _failure("SM0_P5_PROJECTION_WORLD_INVALID")

	var logical_player_id := String(value.get("logical_player_id", "")).strip_edges()
	if logical_player_id.is_empty():
		return _failure("SM0_P5_PROJECTION_PLAYER_ID_REQUIRED")
	if String(value.get("player_entity_id", "")) != "player/%s" % logical_player_id:
		return _failure("SM0_P5_PROJECTION_ENTITY_ID_MISMATCH")

	var owner_authority_id := String(value.get("owner_authority_id", ""))
	var owner_zone_id := String(value.get("owner_zone_id", ""))
	if owner_authority_id not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B]:
		return _failure("SM0_P5_PROJECTION_OWNER_INVALID")
	if Contracts.authority_for_zone(owner_zone_id) != owner_authority_id:
		return _failure("SM0_P5_PROJECTION_ZONE_OWNER_MISMATCH")

	if not Utils.is_json_integer(value.get("authority_epoch")) or int(value.get("authority_epoch", 0)) < 1:
		return _failure("SM0_P5_PROJECTION_AUTHORITY_EPOCH_INVALID")
	if not Utils.is_json_integer(value.get("player_ownership_epoch")) or int(value.get("player_ownership_epoch", 0)) < 1:
		return _failure("SM0_P5_PROJECTION_OWNERSHIP_EPOCH_INVALID")
	if not Utils.is_json_integer(value.get("state_revision")) or int(value.get("state_revision", 0)) < 1:
		return _failure("SM0_P5_PROJECTION_STATE_REVISION_INVALID")
	if not Utils.is_json_integer(value.get("last_input_sequence")) or int(value.get("last_input_sequence", -1)) < 0:
		return _failure("SM0_P5_PROJECTION_INPUT_SEQUENCE_INVALID")

	if typeof(value.get("connected")) != TYPE_BOOL:
		return _failure("SM0_P5_PROJECTION_CONNECTED_INVALID")
	if value.get("read_only") != true:
		return _failure("SM0_P5_PROJECTION_MUST_BE_READ_ONLY")
	if not value.get("position") is Dictionary or not value.get("velocity") is Dictionary:
		return _failure("SM0_P5_PROJECTION_SPATIAL_STATE_REQUIRED")
	if not _validate_vec3(Dictionary(value.get("position", {}))) or not _validate_vec3(Dictionary(value.get("velocity", {}))):
		return _failure("SM0_P5_PROJECTION_SPATIAL_STATE_INVALID")
	if typeof(value.get("orientation_yaw")) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("SM0_P5_PROJECTION_ORIENTATION_INVALID")
	var orientation_yaw := float(value.get("orientation_yaw", 0.0))
	if is_nan(orientation_yaw) or is_inf(orientation_yaw):
		return _failure("SM0_P5_PROJECTION_ORIENTATION_INVALID")

	var expected_checksum := String(value.get("checksum", ""))
	var payload := value.duplicate(true)
	payload.erase("checksum")
	if expected_checksum.is_empty() or expected_checksum != Utils.payload_hash(payload):
		return _failure("SM0_P5_PROJECTION_CHECKSUM_MISMATCH")
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