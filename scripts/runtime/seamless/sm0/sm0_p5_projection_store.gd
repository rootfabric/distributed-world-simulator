extends RefCounted

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const ProjectionContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_contract.gd")

var _local_authority_id := ""
var _projections: Dictionary = {}


func setup(local_authority_id: String) -> Dictionary:
	if local_authority_id not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B]:
		return _failure("SM0_P5_PROJECTION_STORE_AUTHORITY_INVALID")
	_local_authority_id = local_authority_id
	_projections.clear()
	return _success()


func accept(snapshot: Dictionary) -> Dictionary:
	if _local_authority_id.is_empty():
		return _failure("SM0_P5_PROJECTION_STORE_NOT_READY")
	var validation := ProjectionContract.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation

	var owner_authority_id := String(snapshot.get("owner_authority_id", ""))
	if owner_authority_id == _local_authority_id:
		return _failure("SM0_P5_LOCAL_OWNER_PROJECTION_FORBIDDEN")

	var logical_player_id := String(snapshot.get("logical_player_id", ""))
	if _projections.has(logical_player_id):
		var current: Dictionary = Dictionary(_projections[logical_player_id])
		var current_owner := String(current.get("owner_authority_id", ""))
		if owner_authority_id != current_owner:
			return _failure("SM0_P5_OWNER_CHANGE_REQUIRES_P6")

		var current_authority_epoch := int(current.get("authority_epoch", 0))
		var incoming_authority_epoch := int(snapshot.get("authority_epoch", 0))
		if incoming_authority_epoch < current_authority_epoch:
			return _failure("SM0_P5_PROJECTION_AUTHORITY_EPOCH_ROLLBACK")
		if incoming_authority_epoch == current_authority_epoch:
			var current_state_revision := int(current.get("state_revision", 0))
			var incoming_state_revision := int(snapshot.get("state_revision", 0))
			if incoming_state_revision < current_state_revision:
				return _failure("SM0_P5_PROJECTION_REVISION_ROLLBACK")
			if incoming_state_revision == current_state_revision:
				if String(snapshot.get("checksum", "")) == String(current.get("checksum", "")):
					return _success({"replay": true, "projection": current.duplicate(true)})
				return _failure("SM0_P5_PROJECTION_SAME_REVISION_MUTATION")

	_projections[logical_player_id] = snapshot.duplicate(true)
	return _success({"replay": false, "projection": snapshot.duplicate(true)})


func reject_mutation(logical_player_id: String, operation: String) -> Dictionary:
	if not _projections.has(logical_player_id):
		return _failure("SM0_P5_PROJECTION_NOT_FOUND", {"logical_player_id": logical_player_id})
	return _failure("SM0_P5_PROJECTION_READ_ONLY", {
		"logical_player_id": logical_player_id,
		"operation": operation,
		"owner_authority_id": String(Dictionary(_projections[logical_player_id]).get("owner_authority_id", "")),
	})


func get_projection(logical_player_id: String) -> Dictionary:
	return Dictionary(_projections.get(logical_player_id, {})).duplicate(true)


func all_projections() -> Dictionary:
	return _projections.duplicate(true)


func size() -> int:
	return _projections.size()


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}