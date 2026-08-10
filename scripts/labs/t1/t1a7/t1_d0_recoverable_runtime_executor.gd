extends "res://scripts/labs/t1/t1_d0_interactive_runtime_executor.gd"

const RuntimePersistenceScript = preload("res://scripts/construction/behavior/construction_runtime_persistence_state.gd")

var _recovered_from_m0: bool = false
var _runtime_checkpoint_revision: int = -1


func _reuse_existing_m0_on_setup() -> bool:
	return true


func setup(m0_root: String) -> Dictionary:
	var base: Dictionary = super.setup(m0_root)
	if not bool(base.get("success", false)):
		return base
	var restored: Dictionary = _restore_runtime_from_m0()
	if not bool(restored.get("success", false)):
		return _recovery_failure("T1A7_RUNTIME_RECOVERY_FAILED", {"cause": restored})
	return _recovery_success({
		"report": get_report(),
		"recovered_from_m0": _recovered_from_m0,
		"runtime_checkpoint_revision": _runtime_checkpoint_revision,
	})


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	if report.is_empty():
		return report
	report["recovered_from_m0"] = _recovered_from_m0
	report["runtime_checkpoint_revision"] = _runtime_checkpoint_revision
	return report


func export_recovery_state() -> Dictionary:
	if not _configured or _runtime_store == null or _runtime_ledger == null:
		return {}
	var state: Dictionary = RuntimePersistenceScript.create(
		CONSTRUCT_ID,
		String(_profile.get("construct_checksum", "")),
		_runtime_store.to_dict(),
		_runtime_ledger.to_dict(),
		_power_tick,
		_power_storage,
		_power_execution_profile
	)
	var validation: Dictionary = RuntimePersistenceScript.validate(state)
	return state if bool(validation.get("success", false)) else {}


func checkpoint_runtime(operation_id: String) -> Dictionary:
	if not _configured:
		return _recovery_failure("T1A7_RUNTIME_NOT_CONFIGURED")
	var state: Dictionary = export_recovery_state()
	if state.is_empty():
		return _recovery_failure("T1A7_RUNTIME_RECOVERY_STATE_INVALID")
	var bridge = _bound.get("bridge")
	var adapter = _bound.get("adapter")
	if bridge == null or not bridge.has_method("checkpoint_runtime"):
		return _recovery_failure("T1A7_RUNTIME_M0_BRIDGE_REQUIRED")
	if adapter == null or not adapter.has_method("get_authority_report"):
		return _recovery_failure("T1A7_RUNTIME_AUTHORITY_REPORT_REQUIRED")
	var authority: Dictionary = adapter.get_authority_report()
	var checkpoint_tick: int = maxi(int(authority.get("server_tick", 0)), _power_tick)
	var committed: Dictionary = bridge.checkpoint_runtime(
		operation_id,
		state,
		String(authority.get("authority_owner_id", "")),
		int(authority.get("authority_epoch", 0)),
		checkpoint_tick
	)
	if not bool(committed.get("success", false)):
		return _recovery_failure("T1A7_RUNTIME_CHECKPOINT_FAILED", {"cause": committed})
	_runtime_checkpoint_revision = int(committed.get("details", {}).get("revision", _runtime_checkpoint_revision))
	return _recovery_success({
		"replay": bool(committed.get("details", {}).get("replay", false)),
		"unchanged": bool(committed.get("details", {}).get("unchanged", false)),
		"runtime_checkpoint_revision": _runtime_checkpoint_revision,
		"m0_generation": int(committed.get("details", {}).get("generation", 0)),
		"state_checksum": String(state.get("checksum", "")),
	})


func _restore_runtime_from_m0() -> Dictionary:
	var bridge = _bound.get("bridge")
	var adapter = _bound.get("adapter")
	if bridge == null or not bridge.has_method("get_runtime_state"):
		return _recovery_failure("T1A7_RUNTIME_M0_BRIDGE_REQUIRED")
	if adapter == null or not adapter.has_method("get_authority_report"):
		return _recovery_failure("T1A7_RUNTIME_AUTHORITY_REPORT_REQUIRED")
	var loaded: Dictionary = bridge.get_runtime_state(CONSTRUCT_ID)
	if not bool(loaded.get("success", false)):
		if String(loaded.get("error_code", "")) == "TRANSACTION_AGGREGATE_NOT_FOUND":
			_recovered_from_m0 = false
			_runtime_checkpoint_revision = -1
			return _recovery_success({"recovered": false})
		return loaded
	var state: Dictionary = Dictionary(loaded.get("details", {}).get("state", {}))
	var validation: Dictionary = RuntimePersistenceScript.validate(state)
	if not bool(validation.get("success", false)):
		return _recovery_failure("T1A7_RUNTIME_PERSISTED_STATE_INVALID", {"cause": validation})
	if String(state.get("construct_id", "")) != CONSTRUCT_ID:
		return _recovery_failure("T1A7_RUNTIME_RECOVERY_CONSTRUCT_MISMATCH")
	if String(state.get("construct_checksum", "")) != String(_profile.get("construct_checksum", "")):
		return _recovery_failure("T1A7_RUNTIME_RECOVERY_CONSTRUCT_CHECKSUM_MISMATCH")
	var authority: Dictionary = adapter.get_authority_report()
	if String(loaded.get("details", {}).get("authority_owner_id", "")) != String(authority.get("authority_owner_id", "")):
		return _recovery_failure("T1A7_RUNTIME_RECOVERY_AUTHORITY_OWNER_MISMATCH")
	if int(loaded.get("details", {}).get("authority_epoch", 0)) != int(authority.get("authority_epoch", 0)):
		return _recovery_failure("T1A7_RUNTIME_RECOVERY_AUTHORITY_EPOCH_MISMATCH")

	var runtime_backup: Dictionary = _runtime_store.to_dict()
	var ledger_backup: Dictionary = _runtime_ledger.to_dict()
	var power_tick_backup: int = _power_tick
	var power_storage_backup: Dictionary = _power_storage.duplicate(true)
	var power_profile_backup: Dictionary = _power_execution_profile.duplicate(true)

	var runtime_load: Dictionary = _runtime_store.load_dict(Dictionary(state["runtime_state"]))
	if not bool(runtime_load.get("success", false)):
		return _recovery_failure("T1A7_RUNTIME_STORE_RESTORE_FAILED", {"cause": runtime_load})
	var ledger_load: Dictionary = _runtime_ledger.load_dict(Dictionary(state["operation_ledger"]))
	if not bool(ledger_load.get("success", false)):
		_runtime_store.load_dict(runtime_backup)
		return _recovery_failure("T1A7_RUNTIME_LEDGER_RESTORE_FAILED", {"cause": ledger_load})

	_power_tick = int(state["power_tick"])
	_power_storage = Dictionary(state["power_storage"]).duplicate(true)
	_power_execution_profile = Dictionary(state["power_execution_profile"]).duplicate(true)
	var restored_state: Dictionary = export_recovery_state()
	if restored_state.is_empty() or String(restored_state.get("checksum", "")) != String(state.get("checksum", "")):
		_runtime_store.load_dict(runtime_backup)
		_runtime_ledger.load_dict(ledger_backup)
		_power_tick = power_tick_backup
		_power_storage = power_storage_backup
		_power_execution_profile = power_profile_backup
		return _recovery_failure("T1A7_RUNTIME_RECOVERY_POST_RESTORE_MISMATCH")

	_recovered_from_m0 = true
	_runtime_checkpoint_revision = int(loaded.get("details", {}).get("revision", -1))
	return _recovery_success({
		"recovered": true,
		"runtime_checkpoint_revision": _runtime_checkpoint_revision,
		"state_checksum": String(state.get("checksum", "")),
	})


static func _recovery_success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _recovery_failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
