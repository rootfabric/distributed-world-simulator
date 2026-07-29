extends RefCounted

const StateScript = preload("res://scripts/simulation/transactions/aggregate_transaction_state.gd")
const TxUtilsScript = preload("res://scripts/simulation/transactions/transaction_contract_utils.gd")

const MAX_REPLACE_ATTEMPTS: int = 5
const RETRY_DELAY_MS: int = 10

var root_path: String = ""
var active_path: String = ""
var previous_path: String = ""


func configure(root: String) -> Dictionary:
	if root.strip_edges().is_empty(): return TxUtilsScript.failure("TRANSACTION_REPOSITORY_ROOT_REQUIRED")
	root_path = _global(root).simplify_path()
	if DirAccess.make_dir_recursive_absolute(root_path) != OK and not DirAccess.dir_exists_absolute(root_path): return TxUtilsScript.failure("TRANSACTION_REPOSITORY_CREATE_FAILED")
	active_path = root_path.path_join("aggregate-transaction-state.json")
	previous_path = root_path.path_join("aggregate-transaction-state.previous.json")
	return TxUtilsScript.success({"active_path": active_path})


func load_or_empty() -> Dictionary:
	if active_path.is_empty(): return TxUtilsScript.failure("TRANSACTION_REPOSITORY_NOT_CONFIGURED")
	if FileAccess.file_exists(active_path): return _read_state(active_path)
	if FileAccess.file_exists(previous_path):
		var previous := _read_state(previous_path)
		if bool(previous.get("success", false)): previous["details"]["source"] = "PREVIOUS"
		return previous
	return TxUtilsScript.success({"state": StateScript.empty(), "source": "EMPTY", "pending_files": list_pending_files()})


func prepare_atomic(state: Dictionary) -> Dictionary:
	if active_path.is_empty(): return TxUtilsScript.failure("TRANSACTION_REPOSITORY_NOT_CONFIGURED")
	var validation := StateScript.validate(state)
	if not bool(validation.get("success", false)): return TxUtilsScript.failure("INVALID_TRANSACTION_STATE", {"cause": validation})
	var pending := root_path.path_join(".aggregate-transaction-state.%d.%d.pending.json" % [int(state["generation"]), Time.get_ticks_usec()])
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null: return TxUtilsScript.failure("TRANSACTION_PENDING_OPEN_FAILED")
	file.store_string(JSON.stringify(state, "", true, true)); file.flush(); file.close()
	var verify := _read_state(pending)
	if not bool(verify.get("success", false)): return TxUtilsScript.failure("TRANSACTION_PENDING_VERIFY_FAILED", {"cause": verify})
	return TxUtilsScript.success({"pending_path": pending})


func commit_prepared(pending_path: String) -> Dictionary:
	var normalized := _global(pending_path).simplify_path()
	if normalized.get_base_dir() != root_path or not normalized.get_file().ends_with(".pending.json"): return TxUtilsScript.failure("INVALID_TRANSACTION_PENDING_PATH")
	var pending := _read_state(normalized)
	if not bool(pending.get("success", false)): return TxUtilsScript.failure("TRANSACTION_PENDING_INVALID", {"cause": pending})
	var had_active := FileAccess.file_exists(active_path)
	for _attempt in range(MAX_REPLACE_ATTEMPTS):
		if had_active:
			_remove(previous_path)
			if DirAccess.rename_absolute(active_path, previous_path) != OK:
				OS.delay_msec(RETRY_DELAY_MS); continue
		if DirAccess.rename_absolute(normalized, active_path) == OK:
			var verify := _read_state(active_path)
			if bool(verify.get("success", false)): return TxUtilsScript.success({"state": verify["details"]["state"], "generation": int(verify["details"]["state"]["generation"])})
			_remove(active_path)
			if had_active and FileAccess.file_exists(previous_path): DirAccess.rename_absolute(previous_path, active_path)
			return TxUtilsScript.failure("TRANSACTION_COMMIT_VERIFY_FAILED")
		if had_active and FileAccess.file_exists(previous_path) and not FileAccess.file_exists(active_path): DirAccess.rename_absolute(previous_path, active_path)
		OS.delay_msec(RETRY_DELAY_MS)
	return TxUtilsScript.failure("TRANSACTION_ATOMIC_REPLACE_FAILED")


func save_atomic(state: Dictionary) -> Dictionary:
	var prepared := prepare_atomic(state)
	if not bool(prepared.get("success", false)): return prepared
	return commit_prepared(String(prepared["details"]["pending_path"]))


func list_pending_files() -> Array[String]:
	var result: Array[String] = []
	if root_path.is_empty(): return result
	var directory := DirAccess.open(root_path)
	if directory == null: return result
	directory.include_hidden = true
	for file_name in directory.get_files():
		if file_name.begins_with(".aggregate-transaction-state.") and file_name.ends_with(".pending.json"): result.append(root_path.path_join(file_name))
	result.sort(); return result


func cleanup_pending_files() -> Dictionary:
	var removed := 0
	for path in list_pending_files():
		if _remove(path): removed += 1
	return TxUtilsScript.success({"removed": removed})


func _read_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return TxUtilsScript.failure("TRANSACTION_STATE_NOT_FOUND")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return TxUtilsScript.failure("TRANSACTION_STATE_OPEN_FAILED")
	var text := file.get_as_text(); file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY: return TxUtilsScript.failure("TRANSACTION_STATE_JSON_INVALID")
	var state: Dictionary = parsed
	var validation := StateScript.validate(state)
	if not bool(validation.get("success", false)): return TxUtilsScript.failure("TRANSACTION_STATE_INVALID", {"cause": validation})
	return TxUtilsScript.success({"state": state, "source": "ACTIVE", "pending_files": list_pending_files()})


func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path


func _remove(path: String) -> bool:
	return not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK
