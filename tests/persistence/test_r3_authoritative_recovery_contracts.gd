extends SceneTree

const AuthorityScript = preload("res://scripts/network/session/n1_remote_item_authority.gd")
const ReplayScript = preload("res://scripts/network/session/network_reconnect_replay_service.gd")
const RepositoryScript = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const CoordinatorScript = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")
const CheckpointScript = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const MovePayloadScript = preload("res://scripts/network/contracts/item_move_to_container_payload.gd")
const ResumeScript = preload("res://scripts/network/contracts/network_session_resume_envelope.gd")

var assertions: int = 0
var failures: Array[String] = []
var root_path: String = ""


func _init() -> void:
	root_path = ProjectSettings.globalize_path("user://r3-authoritative-contracts-%d" % Time.get_ticks_usec())
	_remove_tree(root_path)
	_test_checkpoint_and_repository()
	_test_recovery_and_replay()
	_test_restore_failure_is_transactional()
	_test_progression_fences()
	_test_pending_and_corruption()
	_test_legacy_diagnostic()
	_remove_tree(root_path)
	_finish()


func _test_checkpoint_and_repository() -> void:
	var fixture: Dictionary = _build_fixture("operation/r3/contracts/1", false)
	_assert(bool(fixture.get("success", false)), "Could not build baseline R3 fixture")
	if not bool(fixture.get("success", false)):
		return
	var repository = RepositoryScript.new()
	_assert_ok(repository.configure(root_path.path_join("checkpoint")), "Repository configure failed")
	var coordinator = CoordinatorScript.new()
	_assert_ok(coordinator.configure(repository, fixture.authority, fixture.replay), "Coordinator configure failed")
	var created: Dictionary = coordinator.create_checkpoint("checkpoint/r3/contracts/1", 1, 0, "")
	_assert_ok(created, "Baseline checkpoint creation failed")
	var checkpoint: Dictionary = created["details"]["checkpoint"]
	_assert_ok(CheckpointScript.validate(checkpoint), "Baseline checkpoint validation failed")
	_assert(String(checkpoint["checksum"]) == CheckpointScript.compute_checksum(checkpoint), "Checkpoint checksum is unstable")
	_assert(int(checkpoint["state_revision"]) == 12, "Baseline revision changed")
	_assert(int(checkpoint["server_tick"]) == 500, "Baseline tick changed")
	_assert_ok(repository.save_atomic(checkpoint), "Baseline checkpoint save failed")
	var loaded: Dictionary = repository.load_committed()
	_assert_ok(loaded, "Baseline checkpoint load failed")
	_assert(String(loaded["details"]["source"]) == "ACTIVE", "Baseline source is not ACTIVE")
	_assert(String(loaded["details"]["checkpoint"]["checksum"]) == String(checkpoint["checksum"]), "Loaded baseline checksum changed")
	var runtime_value: Dictionary = checkpoint.duplicate(true)
	runtime_value["authority_state"] = {"node": Node.new()}
	_assert_error(CheckpointScript.validate(runtime_value), "AUTHORITATIVE_CHECKPOINT_NOT_JSON_SAFE", "Runtime object checkpoint accepted")
	runtime_value["authority_state"]["node"].free()
	var unknown: Dictionary = checkpoint.duplicate(true)
	unknown["unexpected"] = true
	_assert(not bool(CheckpointScript.validate(unknown).get("success", false)), "Unexpected checkpoint field accepted")
	var damaged: Dictionary = checkpoint.duplicate(true)
	damaged["server_tick"] = 501
	_assert_error(CheckpointScript.validate(damaged), "AUTHORITATIVE_TICK_MISMATCH", "Damaged checkpoint metadata accepted")


func _test_recovery_and_replay() -> void:
	var fixture: Dictionary = _build_fixture("operation/r3/recovery/1", true)
	_assert(bool(fixture.get("success", false)), "Could not build committed R3 fixture")
	if not bool(fixture.get("success", false)):
		return
	var repository_root: String = root_path.path_join("recovery")
	var repository = RepositoryScript.new()
	_assert_ok(repository.configure(repository_root), "Recovery repository configure failed")
	var coordinator = CoordinatorScript.new()
	_assert_ok(coordinator.configure(repository, fixture.authority, fixture.replay), "Recovery coordinator configure failed")
	_assert_ok(coordinator.persist_checkpoint("checkpoint/r3/recovery/1", 1, 0, fixture.operation_id), "Committed checkpoint save failed")
	var restored_authority = AuthorityScript.new()
	var restored_replay = ReplayScript.new()
	var restored_coordinator = CoordinatorScript.new()
	_assert_ok(restored_coordinator.configure(repository, restored_authority, restored_replay), "Restored coordinator configure failed")
	var recovered: Dictionary = restored_coordinator.recover_latest()
	_assert_ok(recovered, "Committed recovery failed")
	var before: Dictionary = restored_authority.get_report()
	_assert(int(before["mutation_count"]) == 1, "Recovered mutation count changed")
	_assert(int(before["handler_invocation_count"]) == 1, "Recovered handler count changed")
	_assert(int(before["operation_ledger_count"]) == 1, "Recovered ledger count changed")
	_assert(bool(before["destination_contains_item"]), "Recovered item is not in destination")
	var replay_command: Dictionary = fixture.command.duplicate(true)
	replay_command["message_id"] = "message/r3/recovery/replay"
	var replayed_result: Dictionary = restored_authority.handle_command(replay_command)
	_assert(String(replayed_result.get("status", "")) == "SUCCEEDED", "Recovered command replay did not succeed")
	_assert(String(replayed_result.get("payload", {}).get("result_snapshot_checksum", "")) == fixture.final_checksum, "Recovered command replay checksum changed")
	var after: Dictionary = restored_authority.get_report()
	_assert(int(after["mutation_count"]) == 1, "Recovered command mutated domain twice")
	_assert(int(after["handler_invocation_count"]) == 1, "Recovered command invoked handler twice")
	_assert(int(after["operation_ledger_count"]) == 1, "Recovered command duplicated ledger record")
	_assert(int(after["aggregate_revision"]) == 13, "Recovered revision changed after replay")
	_assert(int(after["server_tick"]) == 501, "Recovered tick changed after replay")
	var resumed: Dictionary = ResumeScript.create(
		"resume/r3/recovery/1",
		fixture.ticket,
		"session/transport/r3/recovery/2",
		fixture.operation_id,
		CommandScript.command_fingerprint(fixture.command),
		fixture.base_checksum
	)
	var decision: Dictionary = restored_replay.evaluate_resume(resumed, 501)
	_assert_ok(decision, "Recovered replay resume evaluation failed")
	_assert(bool(decision["details"]["result"]["accepted"]), "Recovered replay ticket was rejected")
	var served: Dictionary = restored_replay.serve_replay("session/transport/r3/recovery/2", replay_command, 501)
	_assert_ok(served, "Recovered replay record could not be served")
	_assert(String(served["details"]["final_snapshot"]["checksum"]) == fixture.final_checksum, "Recovered replay final snapshot changed")
	_assert_error(restored_replay.serve_replay("session/transport/r3/recovery/2", replay_command, 501), "REPLAY_GRANT_NOT_FOUND", "Recovered replay grant was reusable")


func _test_restore_failure_is_transactional() -> void:
	var authority = AuthorityScript.new()
	_assert_ok(authority.setup("sim-r3-transactional", 9, 700), "Transactional authority setup failed")
	_assert_ok(authority.bind_session("session/logical/r3/transactional"), "Transactional session bind failed")
	var before_snapshot: Dictionary = authority.create_snapshot()
	var before_report: Dictionary = authority.get_report()
	var damaged: Dictionary = authority.export_recovery_state()
	var entities: Array = damaged["domain_state"]["world_entities"]["entities"]
	_assert(entities.size() == 1, "Transactional recovery fixture entity missing")
	if entities.size() != 1:
		return
	entities[0]["physics_state"]["sleeping"] = not bool(entities[0]["physics_state"].get("sleeping", false))
	var restore_result: Dictionary = authority.restore_recovery_state(damaged)
	_assert_error(restore_result, "RECOVERED_SNAPSHOT_CHECKSUM_MISMATCH", "Mismatched staged snapshot was accepted")
	var after_snapshot: Dictionary = authority.create_snapshot()
	var after_report: Dictionary = authority.get_report()
	_assert(String(after_snapshot.get("checksum", "")) == String(before_snapshot.get("checksum", "")), "Failed recovery changed live snapshot")
	_assert(int(after_report.get("aggregate_revision", -1)) == int(before_report.get("aggregate_revision", -2)), "Failed recovery changed live revision")
	_assert(int(after_report.get("server_tick", -1)) == int(before_report.get("server_tick", -2)), "Failed recovery changed live tick")
	_assert(int(after_report.get("mutation_count", -1)) == int(before_report.get("mutation_count", -2)), "Failed recovery changed live mutation count")



func _test_progression_fences() -> void:
	var fixture: Dictionary = _build_fixture("operation/r3/progression/1", false)
	_assert(bool(fixture.get("success", false)), "Could not build progression fixture")
	if not bool(fixture.get("success", false)):
		return
	var repository = RepositoryScript.new()
	_assert_ok(repository.configure(root_path.path_join("progression")), "Progression repository configure failed")
	var coordinator = CoordinatorScript.new()
	_assert_ok(coordinator.configure(repository, fixture.authority, fixture.replay), "Progression coordinator configure failed")
	var first: Dictionary = coordinator.create_checkpoint("checkpoint/r3/progression/1", 1, 0, "")["details"]["checkpoint"]
	_assert_ok(repository.save_atomic(first), "Progression baseline save failed")
	var same_generation: Dictionary = first.duplicate(true)
	same_generation["checkpoint_id"] = "checkpoint/r3/progression/same"
	same_generation["checksum"] = CheckpointScript.compute_checksum(same_generation)
	_assert_error(repository.save_atomic(same_generation), "AUTHORITATIVE_GENERATION_ROLLBACK", "Same generation checkpoint accepted")
	var epoch_rollback: Dictionary = first.duplicate(true)
	epoch_rollback["checkpoint_id"] = "checkpoint/r3/progression/epoch"
	epoch_rollback["generation"] = 2
	epoch_rollback["previous_generation"] = 1
	epoch_rollback["authority_epoch"] = int(first["authority_epoch"]) - 1
	epoch_rollback["authority_state"]["authority_epoch"] = epoch_rollback["authority_epoch"]
	epoch_rollback["authority_state"]["current_snapshot"]["authority_epoch"] = epoch_rollback["authority_epoch"]
	epoch_rollback["authority_state"]["current_snapshot"]["checksum"] = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd").compute_checksum(epoch_rollback["authority_state"]["current_snapshot"])
	epoch_rollback["checksum"] = CheckpointScript.compute_checksum(epoch_rollback)
	_assert_error(repository.save_atomic(epoch_rollback), "AUTHORITATIVE_EPOCH_ROLLBACK", "Authority epoch rollback accepted")
	var tick_rollback: Dictionary = first.duplicate(true)
	tick_rollback["checkpoint_id"] = "checkpoint/r3/progression/tick"
	tick_rollback["generation"] = 2
	tick_rollback["previous_generation"] = 1
	tick_rollback["server_tick"] = 499
	tick_rollback["committed_at_tick"] = 499
	tick_rollback["authority_state"]["server_tick"] = 499
	tick_rollback["authority_state"]["domain_state"]["server_tick"] = 499
	tick_rollback["authority_state"]["current_snapshot"]["server_tick"] = 499
	tick_rollback["authority_state"]["current_snapshot"]["checksum"] = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd").compute_checksum(tick_rollback["authority_state"]["current_snapshot"])
	tick_rollback["checksum"] = CheckpointScript.compute_checksum(tick_rollback)
	_assert_error(repository.save_atomic(tick_rollback), "AUTHORITATIVE_TICK_ROLLBACK", "Server tick rollback accepted")


func _test_pending_and_corruption() -> void:
	var fixture: Dictionary = _build_fixture("operation/r3/pending/1", false)
	_assert(bool(fixture.get("success", false)), "Could not build pending fixture")
	if not bool(fixture.get("success", false)):
		return
	var repository = RepositoryScript.new()
	_assert_ok(repository.configure(root_path.path_join("pending")), "Pending repository configure failed")
	var coordinator = CoordinatorScript.new()
	_assert_ok(coordinator.configure(repository, fixture.authority, fixture.replay), "Pending coordinator configure failed")
	var baseline: Dictionary = coordinator.create_checkpoint("checkpoint/r3/pending/1", 1, 0, "")["details"]["checkpoint"]
	_assert_ok(repository.save_atomic(baseline), "Pending baseline save failed")
	var candidate: Dictionary = baseline.duplicate(true)
	candidate["checkpoint_id"] = "checkpoint/r3/pending/2"
	candidate["generation"] = 2
	candidate["previous_generation"] = 1
	candidate["checksum"] = CheckpointScript.compute_checksum(candidate)
	var prepared: Dictionary = repository.prepare(candidate)
	_assert_ok(prepared, "Pending checkpoint prepare failed")
	_assert(repository.list_pending_files().size() == 1, "Pending checkpoint not listed")
	var loaded: Dictionary = repository.load_committed()
	_assert_ok(loaded, "Committed baseline failed with orphan pending file")
	_assert(int(loaded["details"]["checkpoint"]["generation"]) == 1, "Uncommitted pending checkpoint became active")
	_assert(loaded["details"]["pending_files"].size() == 1, "Pending diagnostic missing")
	_assert_ok(repository.cleanup_pending_files(), "Pending cleanup failed")
	_assert(repository.list_pending_files().is_empty(), "Pending cleanup left files")
	var active_path: String = repository.active_path
	var file := FileAccess.open(active_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	_assert_error(repository.load_committed(), "AUTHORITATIVE_CHECKPOINT_CORRUPTED", "Corrupted active checkpoint was accepted")


func _test_legacy_diagnostic() -> void:
	var legacy_root: String = root_path.path_join("legacy")
	DirAccess.make_dir_recursive_absolute(legacy_root)
	var legacy := FileAccess.open(legacy_root.path_join("world.json"), FileAccess.WRITE)
	legacy.store_string("{\"schema\":\"lunar.world.v1\"}")
	legacy.close()
	var repository = RepositoryScript.new()
	_assert_ok(repository.configure(legacy_root), "Legacy repository configure failed")
	var result: Dictionary = repository.load_committed()
	_assert_error(result, "LEGACY_WORLD_STATE_REQUIRES_MIGRATION", "Legacy world state did not produce migration diagnostic")
	_assert(String(result["details"].get("legacy_path", "")).ends_with("world.json"), "Legacy diagnostic path missing")


func _build_fixture(operation_id: String, execute: bool) -> Dictionary:
	var authority = AuthorityScript.new()
	if not bool(authority.setup("sim-r3", 7, 500).get("success", false)):
		return {"success": false}
	var logical_session_id: String = "session/logical/r3"
	if not bool(authority.bind_session(logical_session_id).get("success", false)):
		return {"success": false}
	var replay = ReplayScript.new()
	if not bool(replay.configure(4, 8, 64, 256, 3).get("success", false)):
		return {"success": false}
	var ticket_result: Dictionary = replay.issue_ticket(logical_session_id, "bot-r3", 500)
	if not bool(ticket_result.get("success", false)):
		return {"success": false}
	var base_snapshot: Dictionary = authority.create_snapshot()
	var inventory: Dictionary = base_snapshot["domain_components"]["inventory"]
	var payload: Dictionary = MovePayloadScript.create(
		logical_session_id,
		String(base_snapshot["authority_owner_id"]),
		String(inventory["command_item_id"]),
		String(inventory["source_container_id"]),
		String(inventory["destination_container_id"]),
		int(inventory["item_revision"])
	)
	var command: Dictionary = CommandScript.create(
		"message/r3/command/1",
		operation_id,
		String(base_snapshot["entity_id"]),
		"item.move_to_container",
		payload,
		int(base_snapshot["state_revision"]),
		int(base_snapshot["authority_epoch"]),
		int(base_snapshot["server_tick"]),
		1000
	)
	var result: Dictionary = {}
	var final_snapshot: Dictionary = base_snapshot
	if execute:
		result = authority.handle_command(command)
		if String(result.get("status", "")) != "SUCCEEDED":
			return {"success": false}
		final_snapshot = authority.get_final_snapshot(operation_id)
		var recorded: Dictionary = replay.record_completed_operation(
			logical_session_id,
			"bot-r3",
			command,
			result,
			authority.get_delta(operation_id),
			final_snapshot,
			int(final_snapshot["server_tick"]),
			base_snapshot
		)
		if not bool(recorded.get("success", false)):
			return {"success": false}
	return {
		"success": true,
		"authority": authority,
		"replay": replay,
		"command": command,
		"ticket": ticket_result["details"]["ticket"],
		"operation_id": operation_id,
		"base_checksum": String(base_snapshot["checksum"]),
		"final_checksum": String(final_snapshot["checksum"]),
	}


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	if failures.is_empty():
		print("R3.1 authoritative recovery contracts: PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("R3.1 authoritative recovery contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
		quit(1)
