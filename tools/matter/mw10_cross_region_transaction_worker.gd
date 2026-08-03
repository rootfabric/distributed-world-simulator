extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Record = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_record.gd")
const AuthorityGate = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_authority_gate.gd")
const Coordinator = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_coordinator.gd")

const COMMIT_CRASH_EXIT := 91
const PRECOMMIT_CRASH_EXIT := 92


class FileRuntime extends RefCounted:
	var root_path := ""

	func _init(value: String) -> void:
		root_path = value
		DirAccess.make_dir_recursive_absolute(root_path)

	func prepare_region(participant: Dictionary, context: Dictionary) -> Dictionary:
		var key: String = _key(String(context["transaction_id"]), String(participant["region_id"]))
		var path: String = root_path.path_join("staged").path_join("%s.json" % key)
		var source: Dictionary = _read_json(path)
		if source.is_empty():
			var previous: Dictionary = participant["previous_source_revision"]
			source = SourceRevision.create(
				"MATTER", String(previous["source_id"]), int(previous["authority_epoch"]),
				int(previous["source_revision"]) + 1,
				MatterUtils.payload_hash([key, "prepared-source"]),
				MatterUtils.payload_hash([key, "prepared-dependency"])
			)
			if source.is_empty() or not _write_json_atomic(path, source):
				return MatterUtils.failure("MW10_PROCESS_PREPARE_WRITE_FAILED")
		return MatterUtils.success({
			"source_revision": source,
			"runtime_state_hash": MatterUtils.payload_hash([key, "prepared-state"]),
		})

	func commit_region(participant: Dictionary, prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
		var key: String = _key(String(context["transaction_id"]), String(participant["region_id"]))
		var committed_path: String = root_path.path_join("committed").path_join("%s.json" % key)
		var source: Dictionary = _read_json(committed_path)
		if source.is_empty():
			var staged_path: String = root_path.path_join("staged").path_join("%s.json" % key)
			if _read_json(staged_path).is_empty():
				return MatterUtils.failure("MW10_PROCESS_COMMIT_STAGE_MISSING")
			source = prepare_receipt["source_revision"].duplicate(true)
			if not _write_json_atomic(committed_path, source):
				return MatterUtils.failure("MW10_PROCESS_COMMIT_WRITE_FAILED")
		return MatterUtils.success({
			"source_revision": source,
			"runtime_state_hash": MatterUtils.payload_hash([key, "committed-state", context["global_commit_hash"]]),
		})

	func rollback_region(participant: Dictionary, _prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
		var key: String = _key(String(context["transaction_id"]), String(participant["region_id"]))
		_remove_file(root_path.path_join("staged").path_join("%s.json" % key))
		_remove_file(root_path.path_join("committed").path_join("%s.json" % key))
		var rollback_path: String = root_path.path_join("rolled-back").path_join("%s.json" % key)
		if not _write_json_atomic(rollback_path, {
			"transaction_id": context["transaction_id"],
			"region_id": participant["region_id"],
			"participant_checksum": participant["checksum"],
		}):
			return MatterUtils.failure("MW10_PROCESS_ROLLBACK_WRITE_FAILED")
		return MatterUtils.success({
			"source_revision": participant["previous_source_revision"],
			"runtime_state_hash": MatterUtils.payload_hash([key, "rolled-back-state"]),
		})

	func publish_invalidation(outbox_record: Dictionary) -> Dictionary:
		var key: String = _safe(String(outbox_record["outbox_id"]))
		var path: String = root_path.path_join("published").path_join("%s.json" % key)
		var existing: Dictionary = _read_json(path)
		if not existing.is_empty():
			if String(existing.get("checksum", "")) != String(outbox_record["checksum"]):
				return MatterUtils.failure("MW10_PROCESS_OUTBOX_ID_CONFLICT")
			return MatterUtils.success({"replay": true})
		if not _write_json_atomic(path, outbox_record):
			return MatterUtils.failure("MW10_PROCESS_OUTBOX_WRITE_FAILED")
		return MatterUtils.success({"replay": false})

	func count_files(directory_name: String) -> int:
		var path: String = root_path.path_join(directory_name)
		var directory := DirAccess.open(path)
		return 0 if directory == null else directory.get_files().size()

	func _key(transaction_id: String, region_id: String) -> String:
		return "%s__%s" % [_safe(transaction_id), _safe(region_id)]

	func _safe(value: String) -> String:
		return value.to_lower().replace("/", "-").replace("_", "-")

	func _write_json_atomic(path: String, value: Dictionary) -> bool:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var pending: String = "%s.%d.pending" % [path, Time.get_ticks_usec()]
		var file := FileAccess.open(pending, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(MatterUtils.canonical_json(value))
		file.flush()
		var error: int = file.get_error()
		file.close()
		if error != OK:
			_remove_file(pending)
			return false
		_remove_file(path)
		if DirAccess.rename_absolute(pending, path) != OK:
			_remove_file(pending)
			return false
		return true

	func _read_json(path: String) -> Dictionary:
		if not FileAccess.file_exists(path):
			return {}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {}
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

	func _remove_file(path: String) -> void:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _init() -> void:
	var options: Dictionary = _options()
	var phase: String = String(options.get("phase", ""))
	var repository_root: String = String(options.get("repository-root", ""))
	var runtime_root: String = String(options.get("runtime-root", ""))
	var report_path: String = String(options.get("report-file", ""))
	var ready_file: String = String(options.get("ready-file", ""))
	var go_file: String = String(options.get("go-file", ""))
	var contender: String = String(options.get("contender", "a"))
	match phase:
		"seed-commit":
			_seed_commit(repository_root, runtime_root)
			quit(COMMIT_CRASH_EXIT)
		"recover-commit":
			quit(_recover(repository_root, runtime_root, report_path, "COMPLETE_COMMIT", "COMMITTED"))
		"seed-precommit":
			_seed_precommit(repository_root, runtime_root)
			quit(PRECOMMIT_CRASH_EXIT)
		"recover-abort":
			quit(_recover(repository_root, runtime_root, report_path, "ABORT_UNDECIDED", "ABORTED"))
		"seed-race":
			quit(_seed_empty(repository_root, runtime_root))
		"begin-race":
			quit(_begin_race(repository_root, runtime_root, report_path, ready_file, go_file, contender))
		_:
			quit(2)


func _seed_empty(repository_root: String, runtime_root: String) -> int:
	var coordinator = _coordinator(repository_root, runtime_root)
	if coordinator == null:
		return 21
	var initialized: Dictionary = coordinator.initialize(Fixture.CHECKPOINT_ID, 20)
	return 0 if bool(initialized.get("success", false)) else 22


func _seed_commit(repository_root: String, runtime_root: String) -> void:
	var coordinator = _coordinator(repository_root, runtime_root)
	if coordinator == null:
		quit(3)
		return
	if not bool(coordinator.initialize(Fixture.CHECKPOINT_ID, 20).get("success", false)):
		quit(4)
		return
	var plan: Dictionary = Fixture.plan_ab("matter-transaction/process-commit", "matter-operation/process-commit")
	if not bool(coordinator.begin_transaction(plan, "transition/process-commit-begin", 30).get("success", false)):
		quit(5)
		return
	if not bool(coordinator.prepare_all(String(plan["transaction_id"]), "transition/process-commit-prepare", 31).get("success", false)):
		quit(6)
		return
	if not bool(coordinator.decide_commit(String(plan["transaction_id"]), "transition/process-commit-decision", 35).get("success", false)):
		quit(7)
		return
	if not bool(coordinator.commit_next(String(plan["transaction_id"]), "transition/process-commit-first", 36).get("success", false)):
		quit(8)


func _seed_precommit(repository_root: String, runtime_root: String) -> void:
	var coordinator = _coordinator(repository_root, runtime_root)
	if coordinator == null:
		quit(3)
		return
	if not bool(coordinator.initialize(Fixture.CHECKPOINT_ID, 20).get("success", false)):
		quit(4)
		return
	var plan: Dictionary = Fixture.plan_ab("matter-transaction/process-abort", "matter-operation/process-abort")
	if not bool(coordinator.begin_transaction(plan, "transition/process-abort-begin", 30).get("success", false)):
		quit(5)
		return
	if not bool(coordinator.prepare_next(String(plan["transaction_id"]), "transition/process-abort-prepare", 31).get("success", false)):
		quit(6)


func _recover(repository_root: String, runtime_root: String, report_path: String, expected_action: String, expected_phase: String) -> int:
	var runtime := FileRuntime.new(runtime_root)
	var coordinator = _coordinator(repository_root, runtime_root, runtime)
	if coordinator == null:
		return 11
	var restored: Dictionary = coordinator.restore_latest()
	if not bool(restored.get("success", false)):
		return 12
	var recovered: Dictionary = coordinator.recover_incomplete("recovery/mw10-process", 50)
	if not bool(recovered.get("success", false)):
		return 13
	var actions: Array = recovered["details"]["actions"]
	var latest_records: Dictionary = {}
	for raw_record in coordinator.checkpoint()["transaction_records"]:
		latest_records[String(raw_record["transaction_id"])] = raw_record
	var record: Dictionary = {}
	for transaction_id in latest_records:
		record = latest_records[transaction_id]
	var passed: bool = actions.size() == 1 \
		and String(actions[0]["action"]) == expected_action \
		and String(record.get("phase", "")) == expected_phase \
		and Array(coordinator.checkpoint()["region_reservations"]).is_empty()
	if expected_phase == "COMMITTED":
		passed = passed and runtime.count_files("committed") == 2 \
			and runtime.count_files("published") == 1 \
			and String(coordinator.operation_result(String(record["operation_id"])).get("outcome", "")) == "COMMITTED"
	else:
		passed = passed and runtime.count_files("committed") == 0 \
			and runtime.count_files("published") == 0 \
			and runtime.count_files("rolled-back") == 1 \
			and String(coordinator.operation_result(String(record["operation_id"])).get("outcome", "")) == "ABORTED"
	var report: Dictionary = {
		"schema": "planet_simulator.mw10_process_report.v1",
		"passed": passed,
		"expected_action": expected_action,
		"actual_action": String(actions[0]["action"]) if actions.size() == 1 else "",
		"record_phase": String(record.get("phase", "")),
		"record_decision": String(record.get("decision", "")),
		"checkpoint_generation": int(coordinator.checkpoint().get("generation", 0)),
		"reservation_count": Array(coordinator.checkpoint().get("region_reservations", [])).size(),
		"committed_file_count": runtime.count_files("committed"),
		"rolled_back_file_count": runtime.count_files("rolled-back"),
		"published_file_count": runtime.count_files("published"),
		"outcome": String(coordinator.operation_result(String(record.get("operation_id", ""))).get("outcome", "")),
	}
	if not _write_report(report_path, report):
		return 14
	return 0 if passed else 15


func _begin_race(
	repository_root: String,
	runtime_root: String,
	report_path: String,
	ready_file: String,
	go_file: String,
	contender: String
) -> int:
	var coordinator = _coordinator(repository_root, runtime_root)
	if coordinator == null:
		return 31
	var restored: Dictionary = coordinator.restore_latest()
	if not bool(restored.get("success", false)):
		return 32
	if not _write_report(ready_file, {"ready": true, "contender": contender}):
		return 33
	var started: int = Time.get_ticks_msec()
	while not FileAccess.file_exists(go_file):
		if Time.get_ticks_msec() - started > 15000:
			return 34
		OS.delay_msec(10)
	var plan: Dictionary = Fixture.plan_ab(
		"matter-transaction/process-race-%s" % contender,
		"matter-operation/process-race-%s" % contender,
		30
	)
	var result: Dictionary = coordinator.begin_transaction(
		plan, "transition/process-race-%s" % contender, 30
	)
	var report: Dictionary = {
		"schema": "planet_simulator.mw10_begin_race_report.v1",
		"begin_success": bool(result.get("success", false)),
		"error": String(result.get("error_code", "")),
		"transaction_id": String(plan["transaction_id"]),
		"checkpoint_generation": int(coordinator.checkpoint().get("generation", 0)),
		"reservation_count": Array(coordinator.checkpoint().get("region_reservations", [])).size(),
	}
	return 0 if _write_report(report_path, report) else 35


func _coordinator(repository_root: String, runtime_root: String, runtime_override = null):
	var gate := AuthorityGate.new()
	if not bool(gate.configure(Fixture.lease_provider()).get("success", false)):
		return null
	var runtime = runtime_override if runtime_override != null else FileRuntime.new(runtime_root)
	var coordinator := Coordinator.new()
	if not bool(coordinator.configure(repository_root, gate, runtime).get("success", false)):
		return null
	return coordinator


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
