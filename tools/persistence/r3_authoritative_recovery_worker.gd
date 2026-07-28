extends SceneTree

const AuthorityScript = preload("res://scripts/network/session/n1_remote_item_authority.gd")
const ReplayScript = preload("res://scripts/network/session/network_reconnect_replay_service.gd")
const RepositoryScript = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const CoordinatorScript = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")
const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const MovePayloadScript = preload("res://scripts/network/contracts/item_move_to_container_payload.gd")
const ResumeScript = preload("res://scripts/network/contracts/network_session_resume_envelope.gd")
const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const COMMIT_CRASH_EXIT: int = 86
const PENDING_CRASH_EXIT: int = 87


func _initialize() -> void:
	var parsed: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if not bool(parsed.get("success", false)):
		push_error(String(parsed.get("message", "Invalid R3 worker options")))
		quit(2)
		return
	var options: Dictionary = parsed["options"]
	match String(options["phase"]):
		"commit-crash": _run_seed(options, true)
		"pending-crash": _run_seed(options, false)
		"recover-replay": _run_recovery(options, false)
		"recover-reexecute": _run_recovery(options, true)
		_:
			push_error("Unsupported R3 worker phase")
			quit(2)


func _run_seed(options: Dictionary, commit_after_mutation: bool) -> void:
	var authority = AuthorityScript.new()
	var setup: Dictionary = authority.setup("sim-r3", 7, 500)
	if not bool(setup.get("success", false)):
		_fail(options, "AUTHORITY_SETUP_FAILED", setup)
		return
	var logical_session_id: String = "session/logical/r3/process"
	if not bool(authority.bind_session(logical_session_id).get("success", false)):
		_fail(options, "SESSION_BIND_FAILED")
		return
	var replay = ReplayScript.new()
	if not bool(replay.configure(4, 8, 64, 256, 3).get("success", false)):
		_fail(options, "REPLAY_CONFIGURE_FAILED")
		return
	var ticket_result: Dictionary = replay.issue_ticket(logical_session_id, "bot-r3", 500)
	if not bool(ticket_result.get("success", false)):
		_fail(options, "TICKET_ISSUE_FAILED", ticket_result)
		return
	var base_snapshot: Dictionary = authority.create_snapshot()
	var inventory: Dictionary = base_snapshot["domain_components"]["inventory"]
	var operation_id: String = "operation/r3/process/committed" if commit_after_mutation else "operation/r3/process/pending"
	var command: Dictionary = CommandScript.create(
		"message/r3/process/1",
		operation_id,
		String(base_snapshot["entity_id"]),
		"item.move_to_container",
		MovePayloadScript.create(
			logical_session_id,
			String(base_snapshot["authority_owner_id"]),
			String(inventory["command_item_id"]),
			String(inventory["source_container_id"]),
			String(inventory["destination_container_id"]),
			int(inventory["item_revision"])
		),
		int(base_snapshot["state_revision"]),
		int(base_snapshot["authority_epoch"]),
		int(base_snapshot["server_tick"]),
		1000
	)
	var repository = RepositoryScript.new()
	var repository_setup: Dictionary = repository.configure(String(options["repository_root"]))
	if not bool(repository_setup.get("success", false)):
		_fail(options, "REPOSITORY_CONFIGURE_FAILED", repository_setup)
		return
	var coordinator = CoordinatorScript.new()
	if not bool(coordinator.configure(repository, authority, replay).get("success", false)):
		_fail(options, "COORDINATOR_CONFIGURE_FAILED")
		return
	var baseline: Dictionary = coordinator.persist_checkpoint("checkpoint/r3/process/baseline", 1, 0, "")
	if not bool(baseline.get("success", false)):
		_fail(options, "BASELINE_PERSIST_FAILED", baseline)
		return
	var result: Dictionary = authority.handle_command(command)
	if String(result.get("status", "")) != "SUCCEEDED":
		_fail(options, "COMMAND_EXECUTION_FAILED", result)
		return
	var final_snapshot: Dictionary = authority.get_final_snapshot(operation_id)
	var record_result: Dictionary = replay.record_completed_operation(
		logical_session_id,
		"bot-r3",
		command,
		result,
		authority.get_delta(operation_id),
		final_snapshot,
		int(final_snapshot["server_tick"]),
		base_snapshot
	)
	if not bool(record_result.get("success", false)):
		_fail(options, "REPLAY_RECORD_FAILED", record_result)
		return
	var context: Dictionary = {
		"schema": "planet_simulator.r3_process_client_context.v1",
		"operation_id": operation_id,
		"logical_session_id": logical_session_id,
		"command": command,
		"ticket": ticket_result["details"]["ticket"],
		"base_snapshot_checksum": String(base_snapshot["checksum"]),
		"final_snapshot_checksum": String(final_snapshot["checksum"]),
		"expected_generation": 2 if commit_after_mutation else 1,
	}
	var context_write: Dictionary = AtomicJsonScript.write_dictionary(String(options["context_file"]), context)
	if not bool(context_write.get("success", false)):
		_fail(options, "CLIENT_CONTEXT_WRITE_FAILED", context_write)
		return
	var created: Dictionary = coordinator.create_checkpoint(
		"checkpoint/r3/process/committed" if commit_after_mutation else "checkpoint/r3/process/pending",
		2,
		1,
		operation_id
	)
	if not bool(created.get("success", false)):
		_fail(options, "COMMITTED_CHECKPOINT_CREATE_FAILED", created)
		return
	if commit_after_mutation:
		var saved: Dictionary = repository.save_atomic(created["details"]["checkpoint"])
		if not bool(saved.get("success", false)):
			_fail(options, "COMMITTED_CHECKPOINT_SAVE_FAILED", saved)
			return
		print("R3_WORKER_COMMIT_COMPLETE")
		quit(COMMIT_CRASH_EXIT)
	else:
		var prepared: Dictionary = repository.prepare(created["details"]["checkpoint"])
		if not bool(prepared.get("success", false)):
			_fail(options, "PENDING_CHECKPOINT_PREPARE_FAILED", prepared)
			return
		print("R3_WORKER_PENDING_COMPLETE")
		quit(PENDING_CRASH_EXIT)


func _run_recovery(options: Dictionary, reexecute: bool) -> void:
	var context_result: Dictionary = AtomicJsonScript.read_dictionary(String(options["context_file"]))
	if not bool(context_result.get("success", false)):
		_fail(options, "CLIENT_CONTEXT_READ_FAILED", context_result)
		return
	var context: Dictionary = context_result["value"]
	var repository = RepositoryScript.new()
	var repository_setup: Dictionary = repository.configure(String(options["repository_root"]))
	if not bool(repository_setup.get("success", false)):
		_fail(options, "REPOSITORY_CONFIGURE_FAILED", repository_setup)
		return
	var authority = AuthorityScript.new()
	var replay = ReplayScript.new()
	var coordinator = CoordinatorScript.new()
	if not bool(coordinator.configure(repository, authority, replay).get("success", false)):
		_fail(options, "COORDINATOR_CONFIGURE_FAILED")
		return
	var recovered: Dictionary = coordinator.recover_latest()
	if not bool(recovered.get("success", false)):
		_fail(options, "RECOVERY_FAILED", recovered)
		return
	var checkpoint: Dictionary = recovered["details"]["checkpoint"]
	var command: Dictionary = Dictionary(context["command"]).duplicate(true)
	command["message_id"] = "message/r3/process/recovered"
	var before: Dictionary = authority.get_report()
	var result: Dictionary = authority.handle_command(command)
	var after: Dictionary = authority.get_report()
	var replay_accepted: bool = false
	var replay_served: bool = false
	var replay_checksum: String = ""
	if not reexecute:
		var resume: Dictionary = ResumeScript.create(
			"resume/r3/process/recovered",
			context["ticket"],
			"session/transport/r3/process/recovered",
			String(context["operation_id"]),
			CommandScript.command_fingerprint(command),
			String(context["base_snapshot_checksum"])
		)
		var decision: Dictionary = replay.evaluate_resume(resume, int(checkpoint["server_tick"]))
		replay_accepted = bool(decision.get("success", false)) and bool(decision.get("details", {}).get("result", {}).get("accepted", false))
		if replay_accepted:
			var served: Dictionary = replay.serve_replay("session/transport/r3/process/recovered", command, int(checkpoint["server_tick"]))
			replay_served = bool(served.get("success", false))
			if replay_served:
				replay_checksum = String(served["details"]["final_snapshot"]["checksum"])
	var report: Dictionary = {
		"schema": "planet_simulator.r3_authoritative_recovery_process_report.v1",
		"passed": (
			String(result.get("status", "")) == "SUCCEEDED"
			and int(after["mutation_count"]) == 1
			and int(after["handler_invocation_count"]) == 1
			and int(after["operation_ledger_count"]) == 1
			and String(after["snapshot_checksum"]) == String(context["final_snapshot_checksum"])
			and (reexecute or (replay_accepted and replay_served and replay_checksum == String(context["final_snapshot_checksum"])))
		),
		"mode": "REEXECUTE" if reexecute else "REPLAY",
		"repository_source": String(recovered["details"].get("source", "")),
		"checkpoint_generation": int(checkpoint["generation"]),
		"expected_generation": int(context["expected_generation"]),
		"pending_file_count": recovered["details"].get("pending_files", []).size(),
		"before_mutation_count": int(before["mutation_count"]),
		"before_handler_invocation_count": int(before["handler_invocation_count"]),
		"after_mutation_count": int(after["mutation_count"]),
		"after_handler_invocation_count": int(after["handler_invocation_count"]),
		"operation_ledger_count": int(after["operation_ledger_count"]),
		"aggregate_revision": int(after["aggregate_revision"]),
		"server_tick": int(after["server_tick"]),
		"final_snapshot_checksum": String(after["snapshot_checksum"]),
		"expected_snapshot_checksum": String(context["final_snapshot_checksum"]),
		"replay_accepted": replay_accepted,
		"replay_served": replay_served,
		"replay_snapshot_checksum": replay_checksum,
		"result_status": String(result.get("status", "")),
	}
	var report_write: Dictionary = AtomicJsonScript.write_dictionary(String(options["result_file"]), report)
	if not bool(report_write.get("success", false)):
		push_error("R3 report write failed: %s" % report_write)
		quit(2)
		return
	print("R3_AUTHORITATIVE_RECOVERY_RESULT %s" % JSON.stringify({"passed": report["passed"], "mode": report["mode"], "generation": report["checkpoint_generation"]}))
	quit(0 if bool(report["passed"]) else 1)


func _parse_options(args) -> Dictionary:
	var options: Dictionary = {"phase": "", "repository_root": "", "context_file": "", "result_file": ""}
	for raw in args:
		var argument: String = String(raw)
		if not argument.begins_with("--") or not argument.contains("="):
			return {"success": false, "message": "Invalid option: %s" % argument}
		var position: int = argument.find("=")
		var key: String = argument.substr(2, position - 2)
		var value: String = argument.substr(position + 1)
		match key:
			"phase": options["phase"] = value
			"repository-root": options["repository_root"] = value
			"context-file": options["context_file"] = value
			"result-file": options["result_file"] = value
			_: return {"success": false, "message": "Unknown option: --%s" % key}
	for key in options.keys():
		if String(options[key]).strip_edges().is_empty() and not (key == "result_file" and String(options["phase"]) in ["commit-crash", "pending-crash"]):
			return {"success": false, "message": "%s is required" % key}
	return {"success": true, "options": options}


func _fail(options: Dictionary, error_code: String, details: Dictionary = {}) -> void:
	var report: Dictionary = {"schema": "planet_simulator.r3_authoritative_recovery_process_report.v1", "passed": false, "error_code": error_code, "details": details}
	if not String(options.get("result_file", "")).is_empty():
		AtomicJsonScript.write_dictionary(String(options["result_file"]), report)
	push_error("R3 worker failed: %s %s" % [error_code, details])
	quit(2)
