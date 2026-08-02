extends SceneTree

const Fixture = preload("res://tests/matter/handoff/mw9_test_fixture.gd")
const Coordinator = preload("res://scripts/simulation/matter/handoff/durable/matter_durable_handoff_coordinator.gd")
const Record = preload("res://scripts/simulation/matter/handoff/durable/matter_handoff_journal_record.gd")

const COMMIT_CRASH_EXIT := 91
const PRECOMMIT_CRASH_EXIT := 92


func _init() -> void:
	var options: Dictionary = _options()
	var phase: String = String(options.get("phase", ""))
	var repository_root: String = String(options.get("repository-root", ""))
	var report_path: String = String(options.get("report-file", ""))
	var owner_id: String = String(options.get("owner-id", ""))
	var ready_file: String = String(options.get("ready-file", ""))
	var go_file: String = String(options.get("go-file", ""))
	match phase:
		"seed-commit":
			_seed(repository_root, true)
			quit(COMMIT_CRASH_EXIT)
		"recover-commit":
			quit(_recover(repository_root, report_path, "COMPLETE_COMMIT", Fixture.TARGET_OWNER, 5))
		"seed-precommit":
			_seed(repository_root, false)
			quit(PRECOMMIT_CRASH_EXIT)
		"recover-abort":
			quit(_recover(repository_root, report_path, "ABORT_UNDECIDED", Fixture.SOURCE_OWNER, 4))
		"seed-claim":
			quit(_seed_claim(repository_root))
		"claim":
			quit(_claim(repository_root, report_path, owner_id, ready_file, go_file))
		_:
			quit(2)


func _seed_claim(repository_root: String) -> int:
	var coordinator := Coordinator.new()
	if not bool(coordinator.configure(repository_root, 120, 40).get("success", false)):
		return 21
	var initialized: Dictionary = coordinator.initialize(
		"matter-handoff-checkpoint/process-claim", [Fixture.initial_lease()], 10
	)
	return 0 if bool(initialized.get("success", false)) else 22


func _claim(repository_root: String, report_path: String, owner_id: String, ready_file: String, go_file: String) -> int:
	var coordinator := Coordinator.new()
	if not bool(coordinator.configure(repository_root, 120, 40).get("success", false)):
		return 31
	var restored: Dictionary = coordinator.restore_latest()
	if not bool(restored.get("success", false)):
		return 32
	var source: Dictionary = coordinator.lease(Fixture.REGION_ID)
	if not _write_report(ready_file, {"ready": true, "owner_id": owner_id}):
		return 33
	var started: int = Time.get_ticks_msec()
	while not FileAccess.file_exists(go_file):
		if Time.get_ticks_msec() - started > 15000:
			return 34
		OS.delay_msec(10)
	var result: Dictionary = coordinator.claim_expired_lease(
		Fixture.REGION_ID, owner_id, String(source["checksum"]),
		"transition/process-claim-%s" % owner_id.get_file(), 130
	)
	var success: bool = bool(result.get("success", false))
	var lease: Dictionary = Dictionary(result.get("details", {}).get("lease", {})) if success else {}
	var report: Dictionary = {
		"schema": "planet_simulator.mw9_claim_race_report.v1",
		"claim_success": success,
		"error": String(result.get("error_code", "")),
		"owner_id": String(lease.get("owner_id", owner_id)),
		"authority_epoch": int(lease.get("authority_epoch", 0)),
		"lease_revision": int(lease.get("lease_revision", 0)),
		"checkpoint_generation": int(coordinator.checkpoint().get("generation", 0)),
	}
	return 0 if _write_report(report_path, report) else 35


func _seed(repository_root: String, commit_decision: bool) -> void:
	var coordinator := Coordinator.new()
	if not bool(coordinator.configure(repository_root, 120, 40).get("success", false)):
		quit(3)
		return
	if not bool(coordinator.initialize("matter-handoff-checkpoint/process", [Fixture.initial_lease()], 10).get("success", false)):
		quit(4)
		return
	var lease: Dictionary = coordinator.lease(Fixture.REGION_ID)
	var transfer_id: String = "matter-transfer/process-commit" if commit_decision else "matter-transfer/process-abort"
	if not bool(coordinator.begin_handoff(
		transfer_id, Fixture.REGION_ID, Fixture.SOURCE_OWNER, Fixture.TARGET_OWNER,
		4, lease["fencing_token"], "transition/process-begin", 20
	).get("success", false)):
		quit(5)
		return
	if not bool(coordinator.record_package(
		transfer_id, Fixture.package_transport(phase_label(commit_decision)),
		Fixture.package_checksum(phase_label(commit_decision)), Fixture.summary_manifest(),
		"transition/process-package", 21
	).get("success", false)):
		quit(6)
		return
	if not bool(coordinator.mark_target_prepared(
		transfer_id, Fixture.target_state_hash(phase_label(commit_decision)),
		"transition/process-prepared", 22
	).get("success", false)):
		quit(7)
		return
	if commit_decision and not bool(coordinator.decide_commit(
		transfer_id, "transition/process-commit-decision", 23
	).get("success", false)):
		quit(8)


func _recover(repository_root: String, report_path: String, expected_action: String, expected_owner: String, expected_epoch: int) -> int:
	var coordinator := Coordinator.new()
	var configured: Dictionary = coordinator.configure(repository_root, 120, 40)
	if not bool(configured.get("success", false)):
		return 11
	var restored: Dictionary = coordinator.restore_latest()
	if not bool(restored.get("success", false)):
		return 12
	var recovered: Dictionary = coordinator.recover_incomplete("recovery/mw9-process", 30)
	if not bool(recovered.get("success", false)):
		return 13
	var actions: Array = recovered["details"]["actions"]
	var lease: Dictionary = coordinator.lease(Fixture.REGION_ID)
	var record: Dictionary = {}
	for raw_record in coordinator.checkpoint()["handoff_records"]:
		record = raw_record
	var passed: bool = actions.size() == 1 \
		and String(actions[0]["action"]) == expected_action \
		and String(lease["owner_id"]) == expected_owner \
		and int(lease["authority_epoch"]) == expected_epoch \
		and String(lease["status"]) == "ACTIVE" \
		and String(record["phase"]) in [Record.PHASE_COMMITTED, Record.PHASE_ABORTED]
	var report: Dictionary = {
		"schema": "planet_simulator.mw9_process_report.v1",
		"passed": passed,
		"expected_action": expected_action,
		"actual_action": String(actions[0]["action"]) if actions.size() == 1 else "",
		"owner_id": String(lease.get("owner_id", "")),
		"authority_epoch": int(lease.get("authority_epoch", 0)),
		"lease_revision": int(lease.get("lease_revision", 0)),
		"fencing_token_checksum": String(lease.get("fencing_token", {}).get("checksum", "")),
		"checkpoint_generation": int(coordinator.checkpoint().get("generation", 0)),
		"record_phase": String(record.get("phase", "")),
		"record_decision": String(record.get("decision", "")),
		"package_checksum": String(record.get("package_checksum", "")),
		"summary_manifest_checksum": String(record.get("summary_manifest", {}).get("checksum", "")),
	}
	if not _write_report(report_path, report):
		return 14
	return 0 if passed else 15


func phase_label(commit_decision: bool) -> String:
	return "process-commit" if commit_decision else "process-abort"


func _options() -> Dictionary:
	var result: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
		result[parts[0]] = parts[1]
	return result


func _write_report(path: String, report: Dictionary) -> bool:
	if path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t", false, true))
	file.flush()
	var error: int = file.get_error()
	file.close()
	return error == OK
