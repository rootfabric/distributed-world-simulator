extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_performance.gd"

# SM0-P2.2: branch-local bounded handoff/recovery replay experiment.
#
# P2.1 already bounds movement replay records and recovery-file history. P2.2
# additionally bounds historical SM0 service-operation replay and target-side
# transfer maps before each durable recovery snapshot. The current transfer and
# the latest durable movement replay remain protected.

const P22_PROFILE := "p22"
const SM0_OPERATION_PREFIX := "operation/sm0/"

var _p22_enabled := false


func setup(config: Dictionary) -> Dictionary:
	var requested := String(config.get("recovery_performance", "")).strip_edges().to_lower()
	if requested != P22_PROFILE:
		return _failure("SM0_P22_PERFORMANCE_PROFILE_REQUIRED", {
			"recovery_performance": requested,
		})

	# Reuse the proven P2.1 movement/file compaction implementation unchanged.
	# Parent setup requires its own profile literal, so adapt only the local copy.
	var parent_config := config.duplicate(true)
	parent_config["recovery_performance"] = P21_PROFILE
	_p22_enabled = true
	var result: Dictionary = super.setup(parent_config)
	if bool(result.get("success", false)):
		_event("SM0_P22_BOUNDED_REPLAY_ENABLED", {
			"profile": P22_PROFILE,
			"movement_operation_prefix": MOVEMENT_OPERATION_PREFIX,
			"recovery_generations_to_keep": RECOVERY_GENERATIONS_TO_KEEP,
		})
	return result


func _persist_recovery_snapshot(phase: String, transfer_id: String) -> Dictionary:
	if not _p22_enabled:
		return super._persist_recovery_snapshot(phase, transfer_id)

	var transfer_compaction := _p22_compact_transfer_history(phase, transfer_id)
	if not bool(transfer_compaction.get("success", false)):
		return transfer_compaction
	var replay_compaction := _p22_compact_service_replay_history()
	if not bool(replay_compaction.get("success", false)):
		return replay_compaction

	var result: Dictionary = super._persist_recovery_snapshot(phase, transfer_id)
	if not bool(result.get("success", false)):
		return result

	var replay_details: Dictionary = Dictionary(replay_compaction.get("details", {}))
	var transfer_details: Dictionary = Dictionary(transfer_compaction.get("details", {}))
	_event("SM0_P22_BOUNDED_REPLAY_PROFILE", {
		"phase": phase,
		"transfer_id": transfer_id,
		"generation": _recovery_generation,
		"service_operations_before": int(replay_details.get("before", 0)),
		"service_operations_after": int(replay_details.get("after", 0)),
		"service_operations_removed": int(replay_details.get("removed", 0)),
		"retained_operation_classes": int(replay_details.get("retained_classes", 0)),
		"prepared_transfers_before": int(transfer_details.get("prepared_before", 0)),
		"prepared_transfers_after": int(transfer_details.get("prepared_after", 0)),
		"committed_transfers_before": int(transfer_details.get("committed_before", 0)),
		"committed_transfers_after": int(transfer_details.get("committed_after", 0)),
		"current_transfer_id": String(transfer_details.get("current_transfer_id", "")),
		"snapshot_bytes": int(result.get("details", {}).get("snapshot_bytes", -1)),
	})
	return result


func _p22_compact_service_replay_history() -> Dictionary:
	var gameplay_service = _authority.get_networked_gameplay_service_for_tests()
	if gameplay_service == null:
		return _failure("SM0_P22_GAMEPLAY_SERVICE_NOT_AVAILABLE")
	var ledger_value = gameplay_service.get("_operation_ledger")
	if not ledger_value is Dictionary:
		return _failure("SM0_P22_REPLAY_LEDGER_NOT_AVAILABLE")
	var ledger: Dictionary = Dictionary(ledger_value)
	var before := ledger.size()
	if before <= 1:
		return _success({
			"before": before,
			"after": before,
			"removed": 0,
			"retained_classes": before,
		})

	# Keep every non-SM0 record untouched. For SM0 records retain the strongest
	# (highest player state revision, then lexical operation id) record per
	# operation class. Movement is one dedicated class, preserving the exact
	# latest durable movement replay required by active-owner recovery.
	var keep_by_class: Dictionary = {}
	var non_sm0: Dictionary = {}
	for operation_id_value in ledger.keys():
		var operation_id := String(operation_id_value)
		var entry: Dictionary = Dictionary(ledger[operation_id_value]).duplicate(true)
		if not operation_id.begins_with(SM0_OPERATION_PREFIX):
			non_sm0[operation_id] = entry
			continue
		var operation_class := _p22_operation_class(operation_id)
		var candidate := {
			"operation_id": operation_id,
			"entry": entry,
			"score": _p22_operation_score(entry),
		}
		if not keep_by_class.has(operation_class):
			keep_by_class[operation_class] = candidate
			continue
		var current: Dictionary = Dictionary(keep_by_class[operation_class])
		var candidate_score := int(candidate.get("score", -1))
		var current_score := int(current.get("score", -1))
		if (
			candidate_score > current_score
			or (
				candidate_score == current_score
				and operation_id > String(current.get("operation_id", ""))
			)
		):
			keep_by_class[operation_class] = candidate

	var compacted: Dictionary = {}
	var non_sm0_ids := non_sm0.keys()
	non_sm0_ids.sort()
	for operation_id_value in non_sm0_ids:
		compacted[String(operation_id_value)] = Dictionary(non_sm0[operation_id_value]).duplicate(true)
	var classes := keep_by_class.keys()
	classes.sort()
	for class_value in classes:
		var kept: Dictionary = Dictionary(keep_by_class[class_value])
		compacted[String(kept.get("operation_id", ""))] = Dictionary(kept.get("entry", {})).duplicate(true)

	gameplay_service.set("_operation_ledger", compacted)
	return _success({
		"before": before,
		"after": compacted.size(),
		"removed": maxi(0, before - compacted.size()),
		"retained_classes": keep_by_class.size(),
	})


func _p22_operation_class(operation_id: String) -> String:
	if operation_id.begins_with(MOVEMENT_OPERATION_PREFIX):
		return "movement"
	var parts := operation_id.split("/", false)
	if parts.size() >= 4:
		return "%s/%s" % [String(parts[2]), String(parts[3])]
	return operation_id


func _p22_operation_score(entry: Dictionary) -> int:
	var result: Dictionary = Dictionary(entry.get("result", {}))
	var details: Dictionary = Dictionary(result.get("details", {}))
	var player: Dictionary = Dictionary(details.get("player", {}))
	if not player.is_empty():
		return int(player.get("state_revision", -1))
	var snapshot: Dictionary = Dictionary(details.get("snapshot", {}))
	if not snapshot.is_empty():
		return int(snapshot.get("revision", -1))
	return -1


func _p22_compact_transfer_history(phase: String, transfer_id: String) -> Dictionary:
	var prepared_before := _prepared_transfers.size()
	var committed_before := _committed_transfers.size()
	var current_transfer_id := ""

	if phase in [TARGET_PREPARED_PHASE, "TARGET_COMMITTED"]:
		current_transfer_id = transfer_id.strip_edges()
		if current_transfer_id.is_empty():
			return _failure("SM0_P22_CURRENT_TRANSFER_REQUIRED", {"phase": phase})
	elif phase == ACTIVE_OWNER_PHASE:
		var directory_checksum := String(_directory.get("checksum", ""))
		for transfer_id_value in _committed_transfers.keys():
			var candidate_id := String(transfer_id_value)
			var entry: Dictionary = Dictionary(_committed_transfers[transfer_id_value])
			var committed_directory: Dictionary = Dictionary(entry.get("directory", {}))
			if (
				not directory_checksum.is_empty()
				and String(committed_directory.get("checksum", "")) == directory_checksum
			):
				current_transfer_id = candidate_id
				break
	elif phase == "SOURCE_RETIRED":
		# Current source recovery is fully represented by source_transfer metadata;
		# old target-side prepared/committed maps are no longer the recovery source.
		current_transfer_id = ""
	else:
		return _success({
			"prepared_before": prepared_before,
			"prepared_after": prepared_before,
			"committed_before": committed_before,
			"committed_after": committed_before,
			"current_transfer_id": "",
		})

	var compacted_prepared: Dictionary = {}
	var compacted_committed: Dictionary = {}
	if not current_transfer_id.is_empty():
		if _prepared_transfers.has(current_transfer_id):
			compacted_prepared[current_transfer_id] = Dictionary(_prepared_transfers[current_transfer_id]).duplicate(true)
		if _committed_transfers.has(current_transfer_id):
			compacted_committed[current_transfer_id] = Dictionary(_committed_transfers[current_transfer_id]).duplicate(true)

	if phase == TARGET_PREPARED_PHASE and not compacted_prepared.has(current_transfer_id):
		return _failure("SM0_P22_CURRENT_PREPARED_TRANSFER_MISSING", {
			"transfer_id": current_transfer_id,
		})
	if phase == "TARGET_COMMITTED" and not compacted_committed.has(current_transfer_id):
		return _failure("SM0_P22_CURRENT_COMMITTED_TRANSFER_MISSING", {
			"transfer_id": current_transfer_id,
		})

	_prepared_transfers = compacted_prepared
	_committed_transfers = compacted_committed
	return _success({
		"prepared_before": prepared_before,
		"prepared_after": _prepared_transfers.size(),
		"committed_before": committed_before,
		"committed_after": _committed_transfers.size(),
		"current_transfer_id": current_transfer_id,
	})
