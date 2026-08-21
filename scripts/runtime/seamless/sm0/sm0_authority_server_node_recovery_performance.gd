extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_chain_fault.gd"

# SM0-P2.1: branch-local performance experiment for the graphical recovery lab.
#
# H2.4 write-before-ACK durability remains unchanged. The only behavioral
# optimization is that old MOVEMENT_DELTA replay records are discarded once a
# newer movement is itself durable. The exact latest movement replay record is
# retained so duplicate/conflicting retry semantics continue to work after a
# crash. Recovery files are pruned only after a newer generation was written
# successfully.

const P21_PROFILE := "p21"
const MOVEMENT_OPERATION_PREFIX := "operation/sm0/client/a/move/"
const RECOVERY_GENERATIONS_TO_KEEP := 8

var _p21_enabled := false
var _p21_compaction_pending := false
var _p21_compaction_before := 0
var _p21_compaction_after := 0
var _p21_compaction_removed := 0
var _p21_compaction_sequence := -1


func setup(config: Dictionary) -> Dictionary:
	_p21_enabled = String(config.get("recovery_performance", "")).strip_edges().to_lower() == P21_PROFILE
	if not _p21_enabled:
		return _failure("SM0_P21_PERFORMANCE_PROFILE_REQUIRED", {
			"recovery_performance": String(config.get("recovery_performance", "")),
		})
	var result: Dictionary = super.setup(config)
	if bool(result.get("success", false)):
		_event("SM0_P21_RECOVERY_PERFORMANCE_ENABLED", {
			"profile": P21_PROFILE,
			"movement_operation_prefix": MOVEMENT_OPERATION_PREFIX,
			"recovery_generations_to_keep": RECOVERY_GENERATIONS_TO_KEEP,
			"authority_id": _authority_id,
		})
	return result


func _ensure_active_owner_persisted_for_ack(
	host: String,
	port: int,
	message_type: String,
	payload: Dictionary
) -> Dictionary:
	_p21_compaction_pending = false
	if _p21_enabled and message_type == "MOVE_ACK" and bool(payload.get("accepted", false)):
		var player: Dictionary = _authority.get_player("a")
		var sequence := int(player.get("last_input_sequence", -1))
		var compacted := _compact_movement_replay_ledger(sequence)
		if not bool(compacted.get("success", false)):
			return compacted
		var details: Dictionary = Dictionary(compacted.get("details", {}))
		_p21_compaction_pending = true
		_p21_compaction_before = int(details.get("before", 0))
		_p21_compaction_after = int(details.get("after", 0))
		_p21_compaction_removed = int(details.get("removed_movement_operations", 0))
		_p21_compaction_sequence = sequence

	var result: Dictionary = super._ensure_active_owner_persisted_for_ack(
		host,
		port,
		message_type,
		payload
	)
	if bool(result.get("success", false)) and bool(result.get("details", {}).get("replay", false)):
		_p21_reset_pending_compaction()
	return result


func _persist_recovery_snapshot(phase: String, transfer_id: String) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var movement_compaction := _p21_compaction_pending and phase == ACTIVE_OWNER_PHASE
	var compact_before := _p21_compaction_before if movement_compaction else -1
	var compact_after := _p21_compaction_after if movement_compaction else -1
	var compact_removed := _p21_compaction_removed if movement_compaction else 0
	var compact_sequence := _p21_compaction_sequence if movement_compaction else -1

	var result: Dictionary = super._persist_recovery_snapshot(phase, transfer_id)
	var duration_usec := maxi(0, Time.get_ticks_usec() - started_usec)
	if not bool(result.get("success", false)):
		if movement_compaction:
			_p21_reset_pending_compaction()
		return result

	var result_details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	var path := String(result_details.get("path", ""))
	var snapshot_bytes := _p21_file_size(path)
	var cleanup := _p21_prune_old_recovery_snapshots()
	var report: Dictionary = _authority.get_recovery_report()
	var replay_operations := int(report.get("service_operation_count", -1))

	result_details["persist_duration_usec"] = duration_usec
	result_details["snapshot_bytes"] = snapshot_bytes
	result_details["service_operation_count"] = replay_operations
	result_details["recovery_files_removed"] = int(cleanup.get("removed", 0))
	result["details"] = result_details

	_event("SM0_P21_RECOVERY_PERSIST_PROFILE", {
		"phase": phase,
		"transfer_id": transfer_id,
		"generation": _recovery_generation,
		"persist_duration_usec": duration_usec,
		"snapshot_bytes": snapshot_bytes,
		"service_operation_count": replay_operations,
		"movement_compaction": movement_compaction,
		"movement_sequence": compact_sequence,
		"replay_operations_before_compaction": compact_before,
		"replay_operations_after_compaction": compact_after,
		"removed_movement_operations": compact_removed,
		"recovery_files_removed": int(cleanup.get("removed", 0)),
		"recovery_files_retained": int(cleanup.get("retained", 0)),
		"cleanup_failures": Array(cleanup.get("failures", [])).duplicate(),
	})

	if movement_compaction:
		_p21_reset_pending_compaction()
	return result


func _compact_movement_replay_ledger(last_input_sequence: int) -> Dictionary:
	if last_input_sequence < 1:
		return _failure("SM0_P21_MOVEMENT_SEQUENCE_REQUIRED", {
			"last_input_sequence": last_input_sequence,
		})
	var gameplay_service = _authority.get_networked_gameplay_service_for_tests()
	if gameplay_service == null:
		return _failure("SM0_P21_GAMEPLAY_SERVICE_NOT_AVAILABLE")
	var ledger_value = gameplay_service.get("_operation_ledger")
	if not ledger_value is Dictionary:
		return _failure("SM0_P21_REPLAY_LEDGER_NOT_AVAILABLE")
	var ledger: Dictionary = Dictionary(ledger_value)
	var before := ledger.size()
	var keep_operation_id := "%s%d" % [MOVEMENT_OPERATION_PREFIX, last_input_sequence]
	var compacted: Dictionary = {}
	var current_movement_found := false
	var removed := 0

	var operation_ids := ledger.keys()
	operation_ids.sort()
	for operation_id_value in operation_ids:
		var operation_id := String(operation_id_value)
		var entry: Dictionary = Dictionary(ledger[operation_id_value]).duplicate(true)
		if operation_id.begins_with(MOVEMENT_OPERATION_PREFIX):
			if operation_id == keep_operation_id:
				compacted[operation_id] = entry
				current_movement_found = true
			else:
				removed += 1
			continue
		compacted[operation_id] = entry

	if not current_movement_found:
		return _failure("SM0_P21_CURRENT_MOVEMENT_REPLAY_MISSING", {
			"operation_id": keep_operation_id,
			"last_input_sequence": last_input_sequence,
			"ledger_size": before,
		})

	gameplay_service.set("_operation_ledger", compacted)
	return _success({
		"before": before,
		"after": compacted.size(),
		"removed_movement_operations": removed,
		"kept_movement_operation_id": keep_operation_id,
	})


func _p21_prune_old_recovery_snapshots() -> Dictionary:
	var result := {
		"removed": 0,
		"retained": 0,
		"failures": [],
	}
	if _recovery_authority_dir.is_empty():
		return result
	var dir := DirAccess.open(_recovery_authority_dir)
	if dir == null:
		result["failures"] = ["OPEN_FAILED"]
		return result
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if (
			not dir.current_is_dir()
			and name.begins_with(RECOVERY_PREFIX)
			and name.ends_with(RECOVERY_SUFFIX)
		):
			candidates.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	candidates.sort()
	result["retained"] = mini(candidates.size(), RECOVERY_GENERATIONS_TO_KEEP)
	var remove_count := maxi(0, candidates.size() - RECOVERY_GENERATIONS_TO_KEEP)
	for index in range(remove_count):
		var path := _recovery_authority_dir.path_join(candidates[index])
		var remove_error := DirAccess.remove_absolute(path)
		if remove_error == OK:
			result["removed"] = int(result.get("removed", 0)) + 1
		else:
			var failures: Array = Array(result.get("failures", []))
			failures.append("%s:%d" % [candidates[index], remove_error])
			result["failures"] = failures
	return result


func _p21_file_size(path: String) -> int:
	if path.is_empty():
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length


func _p21_reset_pending_compaction() -> void:
	_p21_compaction_pending = false
	_p21_compaction_before = 0
	_p21_compaction_after = 0
	_p21_compaction_removed = 0
	_p21_compaction_sequence = -1
