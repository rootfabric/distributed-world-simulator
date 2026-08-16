extends RefCounted

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProjectionContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_contract.gd")

const SCHEMA := "distributed_world_simulator.sm0_p5_projection_view.v1"


static func create(
	viewer_authority_id: String,
	viewer_zone_id: String,
	view_sequence: int,
	local_player: Dictionary,
	remote_projection: Dictionary,
	authority_epoch: int = 1
) -> Dictionary:
	var local_view := ProjectionContract.create_from_player(
		local_player,
		viewer_authority_id,
		viewer_zone_id,
		authority_epoch
	)
	return Utils.finalize_json_checksum({
		"schema": SCHEMA,
		"viewer_authority_id": viewer_authority_id,
		"viewer_zone_id": viewer_zone_id,
		"view_sequence": view_sequence,
		"local_player": local_view,
		"remote_projection": remote_projection.duplicate(true),
		"remote_present": not remote_projection.is_empty(),
		"command_channel": false,
		"checksum": "",
	})


static func validate(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("SM0_P5_VIEW_SCHEMA_INVALID")
	var viewer_authority := String(value.get("viewer_authority_id", ""))
	var viewer_zone := String(value.get("viewer_zone_id", ""))
	if viewer_authority not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B]:
		return _failure("SM0_P5_VIEW_AUTHORITY_INVALID")
	if Contracts.authority_for_zone(viewer_zone) != viewer_authority:
		return _failure("SM0_P5_VIEW_ZONE_INVALID")
	if int(value.get("view_sequence", 0)) < 1:
		return _failure("SM0_P5_VIEW_SEQUENCE_INVALID")
	if bool(value.get("command_channel", true)):
		return _failure("SM0_P5_VIEW_COMMAND_CHANNEL_FORBIDDEN")
	if not value.get("local_player") is Dictionary or not value.get("remote_projection") is Dictionary:
		return _failure("SM0_P5_VIEW_PLAYER_PAYLOAD_INVALID")
	var local_player := Dictionary(value.get("local_player", {}))
	var local_check := ProjectionContract.validate(local_player)
	if not bool(local_check.get("success", false)):
		return _failure("SM0_P5_VIEW_LOCAL_PROJECTION_INVALID", {"cause": local_check})
	if String(local_player.get("owner_authority_id", "")) != viewer_authority:
		return _failure("SM0_P5_VIEW_LOCAL_OWNER_MISMATCH")
	var expected_local := "a" if viewer_authority == Contracts.AUTHORITY_A else "b"
	if String(local_player.get("logical_player_id", "")) != expected_local:
		return _failure("SM0_P5_VIEW_LOCAL_PLAYER_MISMATCH")
	var remote_projection := Dictionary(value.get("remote_projection", {}))
	if bool(value.get("remote_present", false)) != not remote_projection.is_empty():
		return _failure("SM0_P5_VIEW_REMOTE_PRESENCE_MISMATCH")
	if not remote_projection.is_empty():
		var remote_check := ProjectionContract.validate(remote_projection)
		if not bool(remote_check.get("success", false)):
			return _failure("SM0_P5_VIEW_REMOTE_PROJECTION_INVALID", {"cause": remote_check})
		if String(remote_projection.get("owner_authority_id", "")) != Contracts.peer_authority(viewer_authority):
			return _failure("SM0_P5_VIEW_REMOTE_OWNER_MISMATCH")
		var expected_remote := "b" if expected_local == "a" else "a"
		if String(remote_projection.get("logical_player_id", "")) != expected_remote:
			return _failure("SM0_P5_VIEW_REMOTE_PLAYER_MISMATCH")
		if not bool(remote_projection.get("read_only", false)):
			return _failure("SM0_P5_VIEW_REMOTE_NOT_READ_ONLY")
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("SM0_P5_VIEW_CHECKSUM_MISMATCH")
	return _success()


static func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
