extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")
const AuthorityGate = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_authority_gate.gd")
const Coordinator = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_coordinator.gd")
const Record = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_record.gd")
const Checkpoint = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_checkpoint.gd")
const PhysicalOutput = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_physical_output.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

var assertions := 0
var failures: Array[String] = []
var roots: Array[String] = []


class Runtime extends RefCounted:
	var calls: Array[String] = []
	var prepared: Dictionary = {}
	var commit_counts: Dictionary = {}
	var omit_physical_region := ""

	func prepare_region(participant: Dictionary, context: Dictionary) -> Dictionary:
		var region_id := String(participant["region_id"])
		var key := "%s|%s" % [context["transaction_id"], region_id]
		calls.append("prepare:%s" % region_id)
		if not prepared.has(key):
			var previous: Dictionary = participant["previous_source_revision"]
			prepared[key] = SourceRevision.create(
				"MATTER",
				String(previous["source_id"]),
				int(previous["authority_epoch"]),
				int(previous["source_revision"]) + 1,
				MatterUtils.payload_hash([key, "prepared-source"]),
				MatterUtils.payload_hash([key, "prepared-dependency"])
			)
		return MatterUtils.success({
			"source_revision": prepared[key],
			"runtime_state_hash": MatterUtils.payload_hash([key, "prepared-state"]),
		})

	func commit_region(participant: Dictionary, prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
		var region_id := String(participant["region_id"])
		var key := "%s|%s" % [context["transaction_id"], region_id]
		calls.append("commit:%s" % region_id)
		commit_counts[region_id] = int(commit_counts.get(region_id, 0)) + 1
		var physical: Dictionary = Fixture.physical_commit_details(participant, prepare_receipt, context)
		if physical.is_empty():
			return MatterUtils.failure("C1_TEST_PHYSICAL_OUTPUT_CREATION_FAILED")
		physical["runtime_state_hash"] = MatterUtils.payload_hash([
			key, "committed-state", context["global_commit_hash"]
		])
		if region_id == omit_physical_region:
			physical.erase("matter_result")
			physical.erase("material_batch")
		return MatterUtils.success(physical)

	func rollback_region(participant: Dictionary, _prepare_receipt: Dictionary, context: Dictionary) -> Dictionary:
		var region_id := String(participant["region_id"])
		var key := "%s|%s" % [context["transaction_id"], region_id]
		calls.append("rollback:%s" % region_id)
		return MatterUtils.success({
			"source_revision": participant["previous_source_revision"],
			"runtime_state_hash": MatterUtils.payload_hash([key, "rolled-back-state"]),
		})

	func publish_invalidation(outbox_record: Dictionary) -> Dictionary:
		calls.append("publish:%s" % String(outbox_record["outbox_id"]))
		return MatterUtils.success({"published": true})


func _init() -> void:
	_test_config_boundary()
	_test_fresh_commit_and_replay()
	_test_partial_commit_restart_recovery()
	_test_missing_physical_output_fails_closed()
	_test_legacy_record_remains_readable()
	_cleanup()
	if failures.is_empty():
		print("MW10 physical output durability: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("MW10 physical output durability: FAIL (%d assertions, %d failures)" % [
			assertions, failures.size()
		])
		quit(1)


func _test_config_boundary() -> void:
	var file := FileAccess.open(
		"res://config/matter/mw10-canonical-physical-output-durability.v1.json",
		FileAccess.READ
	)
	_assert(file != null, "C1 durability config exists")
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	_assert(typeof(parsed) == TYPE_DICTIONARY, "C1 durability config parses")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var config: Dictionary = parsed
	_assert(String(config.get("owner", "")) == "MW10", "C1 owner remains MW10")
	_assert(bool(config.get("durability", {}).get("participant_output_persisted_with_commit_record", false)), "C1 participant output durability declared")
	_assert(bool(config.get("schema_boundaries", {}).get("transaction_record_v1_read_compatibility", false)), "C1 keeps v1 record read compatibility")
	_assert(not bool(config.get("delivery_boundary", {}).get("p7_3_delivery_wired", true)), "C1 does not claim C2 P7.3 wiring")


func _test_fresh_commit_and_replay() -> void:
	var runtime := Runtime.new()
	var coordinator = _new_coordinator(_root("fresh"), runtime)
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, 20), "fresh initialize")
	var plan := Fixture.plan_ab("matter-transaction/c1-fresh", "matter-operation/c1-fresh")
	var committed: Dictionary = coordinator.execute_transaction(plan, "transition/c1-fresh", 30)
	_assert_ok(committed, "fresh execute")
	var output: Dictionary = Dictionary(committed["details"].get("physical_output", {}))
	_assert_ok(PhysicalOutput.validate(output), "fresh physical output")
	_assert(Array(output["participant_outputs"]).size() == 2, "fresh output participant count")
	_assert(absf(float(output["total_mass_kg"]) - 10.0) <= 0.000001, "fresh output total mass")
	var terminal: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	_assert(String(terminal.get("schema", "")) == Record.SCHEMA, "fresh record uses v2 schema")
	_assert(Array(terminal.get("participant_physical_outputs", [])).size() == 2, "fresh record persists participant outputs")
	_assert(Dictionary(terminal.get("physical_output", {})) == output, "fresh record persists terminal envelope")
	_assert_ok(Checkpoint.validate(coordinator.checkpoint()), "fresh checkpoint validates")
	var calls_before := runtime.calls.size()
	var replay: Dictionary = coordinator.execute_transaction(plan, "transition/c1-fresh-replay", 100)
	_assert_ok(replay, "fresh replay")
	_assert(bool(replay["details"].get("replay", false)), "fresh replay flag")
	_assert(Dictionary(replay["details"].get("physical_output", {})) == output, "fresh replay returns same physical envelope")
	_assert(runtime.calls.size() == calls_before, "fresh replay does not invoke runtime")


func _test_partial_commit_restart_recovery() -> void:
	var root := _root("recovery")
	var runtime := Runtime.new()
	var first = _new_coordinator(root, runtime)
	_assert_ok(first.initialize(Fixture.CHECKPOINT_ID, 20), "recovery initialize")
	var plan := Fixture.plan_ab("matter-transaction/c1-recovery", "matter-operation/c1-recovery")
	_assert_ok(first.begin_transaction(plan, "transition/c1-recovery-begin", 30), "recovery begin")
	_assert_ok(first.prepare_all(String(plan["transaction_id"]), "transition/c1-recovery-prepare", 31), "recovery prepare")
	_assert_ok(first.decide_commit(String(plan["transaction_id"]), "transition/c1-recovery-decision", 40), "recovery decision")
	_assert_ok(first.commit_next(String(plan["transaction_id"]), "transition/c1-recovery-a", 41), "recovery first commit")
	var partial: Dictionary = first.latest_record(String(plan["transaction_id"]))
	_assert(String(partial["phase"]) == Record.PHASE_COMMITTING, "partial phase")
	_assert(Array(partial["participant_physical_outputs"]).size() == 1, "partial physical output persisted")
	_assert(Dictionary(partial["physical_output"]).is_empty(), "partial terminal envelope absent")
	var a_checksum := String(partial["participant_physical_outputs"][0]["checksum"])
	_assert(int(runtime.commit_counts.get(Fixture.REGION_A, 0)) == 1, "A committed exactly once before restart")

	var restored = _new_coordinator(root, runtime)
	_assert_ok(restored.restore_latest(), "recovery restore")
	var loaded: Dictionary = restored.latest_record(String(plan["transaction_id"]))
	_assert(String(loaded["participant_physical_outputs"][0]["checksum"]) == a_checksum, "restart preserves A physical output checksum")
	var recovered: Dictionary = restored.recover_incomplete("recovery/c1-physical", 50)
	_assert_ok(recovered, "recovery complete")
	var terminal: Dictionary = restored.latest_record(String(plan["transaction_id"]))
	_assert(String(terminal["phase"]) == Record.PHASE_COMMITTED, "recovery terminal phase")
	_assert(Array(terminal["participant_physical_outputs"]).size() == 2, "recovery retains both participant outputs")
	_assert(String(terminal["participant_physical_outputs"][0]["checksum"]) == a_checksum, "recovery does not replace A physical output")
	_assert_ok(PhysicalOutput.validate(Dictionary(terminal["physical_output"])), "recovery terminal physical output")
	_assert(int(runtime.commit_counts.get(Fixture.REGION_A, 0)) == 1, "recovery does not recommit A")
	_assert(int(runtime.commit_counts.get(Fixture.REGION_B, 0)) == 1, "recovery commits B exactly once")
	_assert(Dictionary(restored.physical_output(String(plan["operation_id"]))) == Dictionary(terminal["physical_output"]), "recovery lookup returns durable envelope")
	_assert_ok(Checkpoint.validate(restored.checkpoint()), "recovery checkpoint validates")


func _test_missing_physical_output_fails_closed() -> void:
	var runtime := Runtime.new()
	runtime.omit_physical_region = Fixture.REGION_A
	var coordinator = _new_coordinator(_root("missing"), runtime)
	_assert_ok(coordinator.initialize(Fixture.CHECKPOINT_ID, 20), "missing initialize")
	var plan := Fixture.plan_ab("matter-transaction/c1-missing", "matter-operation/c1-missing")
	_assert_ok(coordinator.begin_transaction(plan, "transition/c1-missing-begin", 30), "missing begin")
	_assert_ok(coordinator.prepare_all(String(plan["transaction_id"]), "transition/c1-missing-prepare", 31), "missing prepare")
	_assert_ok(coordinator.decide_commit(String(plan["transaction_id"]), "transition/c1-missing-decision", 40), "missing decision")
	var failed: Dictionary = coordinator.commit_next(String(plan["transaction_id"]), "transition/c1-missing-commit", 41)
	_assert(not bool(failed.get("success", false)), "missing physical output rejects")
	_assert(String(failed.get("error_code", "")) == "MATTER_CROSS_REGION_COMMIT_PHYSICAL_OUTPUT_INVALID", "missing physical output error")
	var latest: Dictionary = coordinator.latest_record(String(plan["transaction_id"]))
	_assert(String(latest["phase"]) == Record.PHASE_COMMIT_DECIDED, "missing output does not advance durable phase")
	_assert(Array(latest["commit_receipts"]).is_empty(), "missing output does not persist commit receipt")
	_assert(Array(latest["participant_physical_outputs"]).is_empty(), "missing output does not persist physical output")


func _test_legacy_record_remains_readable() -> void:
	var plan := Fixture.plan_ab("matter-transaction/c1-legacy", "matter-operation/c1-legacy")
	var current: Dictionary = Record.create_begin(plan, "transition/c1-legacy", 30)
	_assert(not current.is_empty(), "v2 begin created")
	var legacy: Dictionary = current.duplicate(true)
	legacy["schema"] = Record.LEGACY_SCHEMA
	legacy.erase("participant_physical_outputs")
	legacy.erase("physical_output")
	legacy["checksum"] = MatterUtils.compute_checksum(legacy)
	_assert_ok(Record.validate(legacy), "legacy v1 record validates")
	var advanced: Dictionary = Record.advance(legacy, Record.PHASE_ABORT_DECIDED, "transition/c1-legacy-abort", 31)
	_assert(not advanced.is_empty(), "legacy v1 record advances into v2 journal")
	_assert(String(advanced.get("schema", "")) == Record.SCHEMA, "legacy advance upgrades to v2")


func _new_coordinator(root: String, runtime: Runtime):
	var gate := AuthorityGate.new()
	_assert_ok(gate.configure(Fixture.lease_provider()), "authority gate configure")
	var coordinator := Coordinator.new()
	_assert_ok(coordinator.configure(root, gate, runtime), "coordinator configure")
	return coordinator


func _root(label: String) -> String:
	var path := ProjectSettings.globalize_path("user://mw10-c1-%s-%d" % [label, Time.get_ticks_usec()])
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	roots.append(path)
	return path


func _cleanup() -> void:
	for root in roots:
		_remove_tree(root)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, String(result.get("error_code", ""))])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
