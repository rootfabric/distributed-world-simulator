extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CheckpointScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_checkpoint.gd")

var _configured: bool = false
var _body: Dictionary = {}
var _grid_profile: Dictionary = {}
var _cell_level: int = 0
var _store = null
var _receiver = null
var _journal = null
var _repository = null


func configure(
	body: Dictionary,
	grid_profile: Dictionary,
	cell_level: int,
	store,
	receiver,
	journal,
	repository
) -> Dictionary:
	if not bool(BodyScript.validate(body).get("success", false)) \
		or not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
		or cell_level < 1 or cell_level > int(grid_profile.get("max_level", -1)):
		return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_CONFIGURATION")
	if String(body["body_id"]) != String(grid_profile["body_id"]) \
		or String(body["body_frame_id"]) != String(grid_profile["body_frame_id"]):
		return MatterUtilsScript.failure("MATTER_PERSISTENCE_BODY_GRID_MISMATCH")
	if store == null or not store.has_method("export_persistence_state") \
		or not store.has_method("validate_restore_state") \
		or not store.has_method("restore_persistence_state"):
		return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_STORE")
	if receiver == null or not receiver.has_method("export_persistence_state") \
		or not receiver.has_method("validate_restore_state") \
		or not receiver.has_method("restore_persistence_state") \
		or not receiver.has_method("container_id"):
		return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_RECEIVER")
	if journal == null or not journal.has_method("export_persistence_state") \
		or not journal.has_method("validate_restore_state") \
		or not journal.has_method("restore_persistence_state"):
		return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_JOURNAL")
	if repository == null or not repository.has_method("save_atomic") \
		or not repository.has_method("load_committed") \
		or not repository.has_method("repair_active_from_previous"):
		return MatterUtilsScript.failure("INVALID_MATTER_PERSISTENCE_REPOSITORY")
	_body = body.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_cell_level = cell_level
	_store = store
	_receiver = receiver
	_journal = journal
	_repository = repository
	_configured = true
	return MatterUtilsScript.success()


func create_checkpoint(generation: int, server_tick: int, previous_checksum: String) -> Dictionary:
	if not _configured:
		return {}
	var store_state: Dictionary = _store.export_persistence_state()
	var receiver_state: Dictionary = _receiver.export_persistence_state()
	var journal_state: Dictionary = _journal.export_persistence_state()
	if store_state.is_empty() or receiver_state.is_empty() or journal_state.is_empty():
		return {}
	var checkpoint: Dictionary = CheckpointScript.create({
		"checkpoint_id": "matter-checkpoint/%s/generation/%d" % [
			String(_body["body_id"]).sha256_text(), generation,
		],
		"generation": generation,
		"body_id": _body["body_id"],
		"body_definition_hash": _body["checksum"],
		"generator_version": _body["generator_version"],
		"generator_seed": _body["generator_seed"],
		"grid_profile_hash": GridProfileScript.content_hash(_grid_profile),
		"cell_level": _cell_level,
		"container_id": _receiver.container_id(),
		"server_tick": server_tick,
		"previous_checkpoint_checksum": previous_checksum,
		"store_state": store_state,
		"receiver_state": receiver_state,
		"journal_state": journal_state,
	})
	return checkpoint if bool(CheckpointScript.validate(checkpoint).get("success", false)) else {}


func save_next(server_tick: int) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_PERSISTENCE_NOT_CONFIGURED")
	var generation: int = 1
	var previous_checksum: String = ""
	var current: Dictionary = _repository.load_committed()
	if bool(current.get("success", false)):
		var previous: Dictionary = current["details"]["checkpoint"]
		generation = int(previous["generation"]) + 1
		previous_checksum = String(previous["checksum"])
	elif String(current.get("error_code", "")) != "MATTER_CHECKPOINT_NOT_FOUND":
		return current
	var checkpoint: Dictionary = create_checkpoint(generation, server_tick, previous_checksum)
	if checkpoint.is_empty():
		return MatterUtilsScript.failure("MATTER_CHECKPOINT_BUILD_FAILED")
	var saved: Dictionary = _repository.save_atomic(checkpoint)
	if not bool(saved.get("success", false)):
		return saved
	return MatterUtilsScript.success({
		"checkpoint": checkpoint,
		"path": saved["details"].get("path", ""),
		"generation": generation,
	})


func restore_latest() -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_PERSISTENCE_NOT_CONFIGURED")
	var loaded: Dictionary = _repository.load_committed()
	if not bool(loaded.get("success", false)):
		return loaded
	var checkpoint: Dictionary = loaded["details"]["checkpoint"]
	var identity_error: String = _validate_checkpoint_identity(checkpoint)
	if not identity_error.is_empty():
		return MatterUtilsScript.failure(identity_error)
	var store_validation: Dictionary = _store.validate_restore_state(checkpoint["store_state"])
	if not bool(store_validation.get("success", false)):
		return store_validation
	var receiver_validation: Dictionary = _receiver.validate_restore_state(checkpoint["receiver_state"])
	if not bool(receiver_validation.get("success", false)):
		return receiver_validation
	var journal_validation: Dictionary = _journal.validate_restore_state(checkpoint["journal_state"])
	if not bool(journal_validation.get("success", false)):
		return journal_validation
	var store_backup: Dictionary = _store.export_persistence_state()
	var receiver_backup: Dictionary = _receiver.export_persistence_state()
	var journal_backup: Dictionary = _journal.export_persistence_state()
	if store_backup.is_empty() or receiver_backup.is_empty() or journal_backup.is_empty():
		return MatterUtilsScript.failure("MATTER_RESTORE_TRANSIENT_STATE_PRESENT")
	var source: String = String(loaded["details"].get("source", ""))
	if source == "PREVIOUS" or source == "PREVIOUS_RECOVERY":
		var repair: Dictionary = _repository.repair_active_from_previous()
		if not bool(repair.get("success", false)):
			return MatterUtilsScript.failure("MATTER_PREVIOUS_RECOVERY_REPAIR_FAILED", {
				"cause": repair,
			})
	var store_restore: Dictionary = _store.restore_persistence_state(checkpoint["store_state"])
	if not bool(store_restore.get("success", false)):
		return _restore_failure_with_rollback("MATTER_STORE_RESTORE_FAILED", store_restore,
			store_backup, receiver_backup, journal_backup)
	var receiver_restore: Dictionary = _receiver.restore_persistence_state(checkpoint["receiver_state"])
	if not bool(receiver_restore.get("success", false)):
		return _restore_failure_with_rollback("MATTER_RECEIVER_RESTORE_AFTER_STORE_FAILED", receiver_restore,
			store_backup, receiver_backup, journal_backup)
	var journal_restore: Dictionary = _journal.restore_persistence_state(checkpoint["journal_state"])
	if not bool(journal_restore.get("success", false)):
		return _restore_failure_with_rollback("MATTER_JOURNAL_RESTORE_AFTER_COMPONENTS_FAILED", journal_restore,
			store_backup, receiver_backup, journal_backup)
	return MatterUtilsScript.success({
		"checkpoint": checkpoint,
		"source": loaded["details"].get("source", ""),
		"pending_files": loaded["details"].get("pending_files", []),
		"store_hash": _store.content_hash(),
		"receiver_hash": _receiver.content_hash(),
		"journal_hash": _journal.content_hash(),
	})


func _restore_failure_with_rollback(
	error_code: String,
	cause: Dictionary,
	store_backup: Dictionary,
	receiver_backup: Dictionary,
	journal_backup: Dictionary
) -> Dictionary:
	var store_rollback: Dictionary = _store.restore_persistence_state(store_backup)
	var receiver_rollback: Dictionary = _receiver.restore_persistence_state(receiver_backup)
	var journal_rollback: Dictionary = _journal.restore_persistence_state(journal_backup)
	if not bool(store_rollback.get("success", false)) \
		or not bool(receiver_rollback.get("success", false)) \
		or not bool(journal_rollback.get("success", false)):
		return MatterUtilsScript.failure("MATTER_RESTORE_ROLLBACK_FAILED", {
			"original_error_code": error_code,
			"cause": cause,
			"store_rollback": store_rollback,
			"receiver_rollback": receiver_rollback,
			"journal_rollback": journal_rollback,
		})
	return MatterUtilsScript.failure(error_code, {"cause": cause})


func _validate_checkpoint_identity(checkpoint: Dictionary) -> String:
	if String(checkpoint["body_id"]) != String(_body["body_id"]):
		return "MATTER_RESTORE_BODY_ID_MISMATCH"
	if String(checkpoint["body_definition_hash"]) != String(_body["checksum"]):
		return "MATTER_RESTORE_BODY_DEFINITION_MISMATCH"
	if String(checkpoint["generator_version"]) != String(_body["generator_version"]) \
		or int(checkpoint["generator_seed"]) != int(_body["generator_seed"]):
		return "MATTER_RESTORE_GENERATOR_MISMATCH"
	if String(checkpoint["grid_profile_hash"]) != GridProfileScript.content_hash(_grid_profile):
		return "MATTER_RESTORE_GRID_MISMATCH"
	if int(checkpoint["cell_level"]) != _cell_level:
		return "MATTER_RESTORE_CELL_LEVEL_MISMATCH"
	if String(checkpoint["container_id"]) != String(_receiver.container_id()):
		return "MATTER_RESTORE_CONTAINER_MISMATCH"
	return ""
