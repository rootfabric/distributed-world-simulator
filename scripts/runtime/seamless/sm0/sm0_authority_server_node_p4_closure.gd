extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_hardened.gd"

# Final P4 closure shim.
# - canonical replay fingerprint composition;
# - reconciliation between the canonical SOURCE_RETIRED journal and the P4
#   side-journal's SOURCE_FAST_COMPLETE tombstone after a later process restart.
#
# The canonical recovery journal intentionally persists the full retired source
# state before FAST_COMMIT. Once the transfer is fully acknowledged, the P4
# side-journal records SOURCE_FAST_COMPLETE. A later restart must not resurrect
# that already-completed source transfer merely because SOURCE_RETIRED is still
# the latest full canonical snapshot.


func setup(config: Dictionary) -> Dictionary:
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)) or not _p4_enabled:
		return result
	var tombstone := _p4_apply_completed_source_tombstone()
	if not bool(tombstone.get("success", false)):
		return tombstone
	return result


func _p4_compose_commit_fingerprint(
	package_checksum: String,
	prewarm_id: String,
	prewarm_checksum: String,
	directory_checksum: String
) -> String:
	return ("%s|%s|%s|%s" % [
		package_checksum,
		prewarm_id,
		prewarm_checksum,
		directory_checksum,
	]).sha256_text()


func _p4_apply_completed_source_tombstone() -> Dictionary:
	if (
		not _recovery_restored
		or _recovery_last_phase != "SOURCE_RETIRED"
		or _source_transfer.is_empty()
		or _recovery_authority_dir.is_empty()
	):
		return _success({"applied": false})
	var transfer_id := String(_source_transfer.get("transfer_id", ""))
	if transfer_id.is_empty():
		return _success({"applied": false})
	var latest := _p4_latest_valid_side_snapshot()
	if not bool(latest.get("success", false)):
		return latest
	var snapshot: Dictionary = Dictionary(latest.get("details", {}).get("snapshot", {}))
	if snapshot.is_empty():
		return _success({"applied": false})
	if (
		String(snapshot.get("phase", "")) != "SOURCE_FAST_COMPLETE"
		or String(snapshot.get("subject_id", "")) != transfer_id
		or not Dictionary(snapshot.get("source_fast", {})).is_empty()
	):
		return _success({"applied": false})
	_source_transfer.clear()
	_frozen_transfer_id = ""
	_p4_source_fast.clear()
	_p4_fast_source_durable_transfer_id = ""
	_event("SM0_P4_RECOVERY_COMPLETED_SOURCE_TOMBSTONE_APPLIED", {
		"transfer_id": transfer_id,
		"side_generation": int(snapshot.get("generation", 0)),
		"directory": _directory,
	})
	return _success({"applied": true, "transfer_id": transfer_id})


func _p4_latest_valid_side_snapshot() -> Dictionary:
	var dir := DirAccess.open(_recovery_authority_dir)
	if dir == null:
		return _failure("SM0_P4_TOMBSTONE_DIRECTORY_OPEN_FAILED", {"path": _recovery_authority_dir})
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.begins_with(P4_STATE_PREFIX) and name.ends_with(P4_STATE_SUFFIX):
			candidates.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	candidates.sort()
	candidates.reverse()
	if candidates.is_empty():
		return _success({"snapshot": {}})
	for candidate in candidates:
		var path := _recovery_authority_dir.path_join(candidate)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var decoded = JSON.parse_string(file.get_as_text())
		file.close()
		if not decoded is Dictionary:
			continue
		var snapshot: Dictionary = Dictionary(decoded)
		var validation := _p4_validate_state_snapshot(snapshot)
		if not bool(validation.get("success", false)):
			continue
		return _success({"snapshot": snapshot, "path": path})
	return _failure("SM0_P4_TOMBSTONE_NO_VALID_SIDE_SNAPSHOT")
