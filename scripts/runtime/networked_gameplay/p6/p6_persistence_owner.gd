extends RefCounted

## P6 R3 persistence adapter.
##
## P6 is not allowed to own a filesystem, envelope schema or save format.
## Durability is delegated to the already accepted authoritative recovery
## coordinator, which atomically checkpoints canonical authority_state and
## replay_state through AuthoritativeRecoveryRepository.

const OwnershipMapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")

const SCHEMA := "planet_simulator.p6_persistence_adapter.v2"
const OWNER_ID := OwnershipMapScript.EXISTING_PERSISTENCE_OWNER_ID

var _coordinator = null
var _persists: int = 0
var _recoveries: int = 0
var _failures: int = 0
var _last_error_code: String = ""


func configure(coordinator) -> Dictionary:
	if (
		coordinator == null
		or not coordinator.has_method("persist_checkpoint")
		or not coordinator.has_method("recover_latest")
	):
		return _reject("AUTHORITATIVE_RECOVERY_COORDINATOR_REQUIRED")
	_coordinator = coordinator
	_last_error_code = ""
	return {
		"success": true,
		"details": {
			"persistence_owner": OWNER_ID,
			"private_filesystem": false,
			"private_save_format": false,
		},
	}


func persist_checkpoint(
		checkpoint_id: String,
		generation: int,
		previous_generation: int,
		committed_operation_id: String = "",
) -> Dictionary:
	if _coordinator == null:
		return _reject("PERSISTENCE_ADAPTER_NOT_CONFIGURED")
	var result: Dictionary = _coordinator.persist_checkpoint(
		checkpoint_id,
		generation,
		previous_generation,
		committed_operation_id,
	)
	if not bool(result.get("success", false)):
		return _reject("AUTHORITATIVE_CHECKPOINT_PERSIST_FAILED", {"cause": result})
	_persists += 1
	_last_error_code = ""
	return {
		"success": true,
		"details": {
			"persistence_owner": OWNER_ID,
			"checkpoint": Dictionary(result.get("details", {}).get("checkpoint", {})).duplicate(true),
			"repository": Dictionary(result.get("details", {}).get("repository", {})).duplicate(true),
		},
	}


func recover_latest() -> Dictionary:
	if _coordinator == null:
		return _reject("PERSISTENCE_ADAPTER_NOT_CONFIGURED")
	var result: Dictionary = _coordinator.recover_latest()
	if not bool(result.get("success", false)):
		return _reject("AUTHORITATIVE_CHECKPOINT_RECOVERY_FAILED", {"cause": result})
	_recoveries += 1
	_last_error_code = ""
	var details := Dictionary(result.get("details", {})).duplicate(true)
	details["persistence_owner"] = OWNER_ID
	return {"success": true, "details": details}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"persistence_owner": OWNER_ID,
		"private_filesystem": false,
		"private_save_format": false,
		"configured": _coordinator != null,
		"persists": _persists,
		"recoveries": _recoveries,
		"failures": _failures,
		"last_error_code": _last_error_code,
	}


func _reject(error_code: String, details: Dictionary = {}) -> Dictionary:
	_failures += 1
	_last_error_code = error_code
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
