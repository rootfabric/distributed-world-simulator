extends SceneTree

const TicketScript = preload("res://scripts/network/contracts/network_resume_ticket.gd")
const ResumeScript = preload("res://scripts/network/contracts/network_session_resume_envelope.gd")
const ResumeResultScript = preload("res://scripts/network/contracts/network_session_resume_result.gd")
const ReplayServiceScript = preload("res://scripts/network/session/network_reconnect_replay_service.gd")
const AuthorityScript = preload("res://scripts/network/session/n1_remote_item_authority.gd")
const CommandScript = preload("res://scripts/network/contracts/network_command_envelope.gd")
const ResultScript = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const MovePayloadScript = preload("res://scripts/network/contracts/item_move_to_container_payload.gd")
const WireScript = preload("res://scripts/network/contracts/network_wire_frame.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_resume_dtos()
	_test_replay_service()
	_test_bounded_windows()
	_test_grant_bound()
	_test_wire_types()
	_finish()


func _test_resume_dtos() -> void:
	var token: String = "a".repeat(64)
	var ticket: Dictionary = TicketScript.create("resume-ticket/test/1", "session/logical/1", "bot-n1", 10, 20, token)
	_assert_ok(TicketScript.validate(ticket), "Valid ticket rejected")
	_assert(String(ticket["checksum"]) == TicketScript.compute_checksum(ticket), "Ticket checksum unstable")
	_mutation_matrix(ticket, TicketScript, ["protocol_version", "issued_tick", "expires_tick"], "ticket")
	var invalid_window: Dictionary = ticket.duplicate(true)
	invalid_window["expires_tick"] = 10
	invalid_window["checksum"] = TicketScript.compute_checksum(invalid_window)
	_assert_error(TicketScript.validate(invalid_window), "INVALID_TICKET_WINDOW", "Invalid ticket window accepted")
	var invalid_token: Dictionary = ticket.duplicate(true)
	invalid_token["resume_token"] = "A".repeat(64)
	invalid_token["checksum"] = TicketScript.compute_checksum(invalid_token)
	_assert_error(TicketScript.validate(invalid_token), "INVALID_RESUME_TOKEN", "Noncanonical token accepted")
	var resume: Dictionary = ResumeScript.create(
		"resume/test/1", ticket, "session/transport/2", "operation/test/1", "b".repeat(64), "c".repeat(64)
	)
	_assert_ok(ResumeScript.validate(resume), "Valid resume rejected")
	_assert(String(resume["checksum"]) == ResumeScript.compute_checksum(resume), "Resume checksum unstable")
	_mutation_matrix(resume, ResumeScript, ["protocol_version"], "resume")
	var runtime_resume: Dictionary = resume.duplicate(true)
	runtime_resume["ticket"] = {"node": Node.new()}
	_assert(not bool(ResumeScript.validate(runtime_resume).get("success", false)), "Runtime object in resume accepted")
	runtime_resume["ticket"]["node"].free()
	var accepted: Dictionary = ResumeResultScript.create(
		"resume/test/1", true, "session/logical/1", "session/transport/2", "operation/test/1", 13, 501, ""
	)
	_assert_ok(ResumeResultScript.validate(accepted), "Valid accepted resume result rejected")
	var rejected: Dictionary = ResumeResultScript.create(
		"resume/test/2", false, "session/logical/1", "session/transport/3", "operation/test/1", 13, 501, "RESUME_DENIED"
	)
	_assert_ok(ResumeResultScript.validate(rejected), "Valid rejected resume result rejected")
	var bad_accepted: Dictionary = accepted.duplicate(true)
	bad_accepted["error_code"] = "NOT_EMPTY"
	bad_accepted["checksum"] = ResumeResultScript.compute_checksum(bad_accepted)
	_assert_error(ResumeResultScript.validate(bad_accepted), "INVALID_ERROR_CODE", "Accepted result with error accepted")
	var bad_rejected: Dictionary = rejected.duplicate(true)
	bad_rejected["error_code"] = ""
	bad_rejected["checksum"] = ResumeResultScript.compute_checksum(bad_rejected)
	_assert_error(ResumeResultScript.validate(bad_rejected), "ERROR_CODE_REQUIRED", "Rejected result without error accepted")


func _test_replay_service() -> void:
	var fixture: Dictionary = _build_completed_fixture("operation/n1/reconnect/contracts")
	_assert(bool(fixture.get("success", false)), "Could not build completed authority fixture")
	if not bool(fixture.get("success", false)): return
	var service = ReplayServiceScript.new()
	_assert_ok(service.configure(4, 8, 64, 256, 2), "Replay service configuration failed")
	_assert_error(service.configure(0, 1, 1, 1, 1), "INVALID_REPLAY_LIMITS", "Invalid replay limits accepted")
	_assert_error(service.configure(4097, 1, 1, 1, 1), "INVALID_REPLAY_LIMITS", "Unbounded ticket limit accepted")
	var issued: Dictionary = service.issue_ticket(fixture.logical_session_id, "bot-n1", 500)
	_assert_ok(issued, "Ticket issue failed")
	var ticket: Dictionary = issued["details"]["ticket"]
	_assert_ok(TicketScript.validate(ticket), "Issued ticket invalid")
	var recorded: Dictionary = service.record_completed_operation(
		fixture.logical_session_id, "bot-n1", fixture.command, fixture.result, fixture.delta,
		fixture.final_snapshot, 501, fixture.base_snapshot
	)
	_assert_ok(recorded, "Completed operation record failed")
	_assert(not bool(recorded["details"].get("replay", true)), "First record marked as replay")
	var repeated_record: Dictionary = service.record_completed_operation(
		fixture.logical_session_id, "bot-n1", fixture.command, fixture.result, fixture.delta,
		fixture.final_snapshot, 501, fixture.base_snapshot
	)
	_assert_ok(repeated_record, "Exact record replay failed")
	_assert(bool(repeated_record["details"].get("replay", false)), "Exact record replay not marked")
	var resume: Dictionary = ResumeScript.create(
		"resume/contracts/1", ticket, "session/transport/contracts/1", String(fixture.command["operation_id"]),
		CommandScript.command_fingerprint(fixture.command), String(fixture.base_snapshot["checksum"])
	)
	var decision: Dictionary = service.evaluate_resume(resume, 501)
	_assert_ok(decision, "Resume evaluation failed")
	var decision_result: Dictionary = decision["details"]["result"]
	_assert_ok(ResumeResultScript.validate(decision_result), "Resume decision result invalid")
	_assert(bool(decision_result["accepted"]), "Valid resume was rejected")
	var replayed: Dictionary = service.serve_replay("session/transport/contracts/1", fixture.command, 501)
	_assert_ok(replayed, "Granted replay failed")
	_assert(String(replayed["details"]["result"]["status"]) == "SUCCEEDED", "Replayed result status changed")
	_assert(String(replayed["details"]["delta"]["checksum"]) == String(fixture.delta["checksum"]), "Replayed delta changed")
	_assert(String(replayed["details"]["final_snapshot"]["checksum"]) == String(fixture.final_snapshot["checksum"]), "Replayed snapshot changed")
	_assert_error(service.serve_replay("session/transport/contracts/1", fixture.command, 501), "REPLAY_GRANT_NOT_FOUND", "Replay grant was reusable")
	var report: Dictionary = fixture.authority.get_report()
	_assert(int(report["mutation_count"]) == 1, "Replay service caused another mutation")
	_assert(int(report["handler_invocation_count"]) == 1, "Replay service invoked domain handler")
	var wrong_fingerprint: Dictionary = resume.duplicate(true)
	wrong_fingerprint["resume_id"] = "resume/contracts/wrong-fingerprint"
	wrong_fingerprint["transport_session_id"] = "session/transport/contracts/2"
	wrong_fingerprint["command_fingerprint"] = "d".repeat(64)
	wrong_fingerprint["checksum"] = ResumeScript.compute_checksum(wrong_fingerprint)
	var wrong_decision: Dictionary = service.evaluate_resume(wrong_fingerprint, 501)
	_assert_ok(wrong_decision, "Fingerprint rejection did not return result")
	_assert(not bool(wrong_decision["details"]["result"]["accepted"]), "Wrong fingerprint accepted")
	_assert(String(wrong_decision["details"]["result"]["error_code"]) == "COMMAND_FINGERPRINT_MISMATCH", "Wrong fingerprint error changed")
	var same_session: Dictionary = resume.duplicate(true)
	same_session["resume_id"] = "resume/contracts/same-session"
	same_session["transport_session_id"] = fixture.logical_session_id
	same_session["checksum"] = ResumeScript.compute_checksum(same_session)
	var same_decision: Dictionary = service.evaluate_resume(same_session, 501)
	_assert(not bool(same_decision["details"]["result"]["accepted"]), "Unrotated transport session accepted")
	_assert(String(same_decision["details"]["result"]["error_code"]) == "TRANSPORT_SESSION_NOT_ROTATED", "Unrotated session error changed")
	var wrong_checksum: Dictionary = resume.duplicate(true)
	wrong_checksum["resume_id"] = "resume/contracts/wrong-snapshot"
	wrong_checksum["transport_session_id"] = "session/transport/contracts/3"
	wrong_checksum["last_snapshot_checksum"] = "e".repeat(64)
	wrong_checksum["checksum"] = ResumeScript.compute_checksum(wrong_checksum)
	var checksum_decision: Dictionary = service.evaluate_resume(wrong_checksum, 501)
	_assert(not bool(checksum_decision["details"]["result"]["accepted"]), "Wrong client snapshot checksum accepted")
	_assert(String(checksum_decision["details"]["result"]["error_code"]) == "LAST_SNAPSHOT_CHECKSUM_MISMATCH", "Snapshot mismatch error changed")
	var second_resume: Dictionary = ResumeScript.create(
		"resume/contracts/2", ticket, "session/transport/contracts/4", String(fixture.command["operation_id"]),
		CommandScript.command_fingerprint(fixture.command), String(fixture.final_snapshot["checksum"])
	)
	_assert(bool(service.evaluate_resume(second_resume, 501)["details"]["result"]["accepted"]), "Second bounded resume rejected")
	var third_resume: Dictionary = ResumeScript.create(
		"resume/contracts/3", ticket, "session/transport/contracts/5", String(fixture.command["operation_id"]),
		CommandScript.command_fingerprint(fixture.command), String(fixture.final_snapshot["checksum"])
	)
	var third_decision: Dictionary = service.evaluate_resume(third_resume, 501)
	_assert(not bool(third_decision["details"]["result"]["accepted"]), "Resume limit was not enforced")
	_assert(String(third_decision["details"]["result"]["error_code"]) == "RESUME_LIMIT_EXCEEDED", "Resume limit error changed")


func _test_bounded_windows() -> void:
	var fixture: Dictionary = _build_completed_fixture("operation/n1/reconnect/bounded/1")
	_assert(bool(fixture.get("success", false)), "Bounded fixture build failed")
	if not bool(fixture.get("success", false)): return
	var service = ReplayServiceScript.new()
	_assert_ok(service.configure(1, 1, 2, 4, 1), "Bounded service configure failed")
	var first_ticket: Dictionary = service.issue_ticket(fixture.logical_session_id, "bot-n1", 500)["details"]["ticket"]
	var second_ticket_result: Dictionary = service.issue_ticket(fixture.logical_session_id, "bot-n1", 501)
	_assert_ok(second_ticket_result, "Second ticket issue failed")
	var cache: Dictionary = service.get_snapshot()
	_assert(int(cache["ticket_count"]) == 1, "Ticket cache exceeded bound")
	_assert(int(cache["ticket_evictions"]) == 1, "Ticket eviction was not counted")
	var missing_resume: Dictionary = ResumeScript.create(
		"resume/bounded/missing", first_ticket, "session/transport/bounded/1", String(fixture.command["operation_id"]),
		CommandScript.command_fingerprint(fixture.command), String(fixture.base_snapshot["checksum"])
	)
	var missing_decision: Dictionary = service.evaluate_resume(missing_resume, 501)
	_assert(String(missing_decision["details"]["result"]["error_code"]) == "RESUME_TICKET_NOT_FOUND", "Evicted ticket remained usable")
	_assert_ok(service.record_completed_operation(
		fixture.logical_session_id, "bot-n1", fixture.command, fixture.result, fixture.delta,
		fixture.final_snapshot, 501, fixture.base_snapshot
	), "First bounded replay record failed")
	var command2: Dictionary = fixture.command.duplicate(true)
	command2["message_id"] = "message/n1/bounded/2"
	command2["operation_id"] = "operation/n1/reconnect/bounded/2"
	var result2: Dictionary = fixture.result.duplicate(true)
	result2["message_id"] = command2["message_id"]
	result2["operation_id"] = command2["operation_id"]
	_assert_ok(ResultScript.validate(result2), "Second result fixture invalid")
	_assert_ok(service.record_completed_operation(
		fixture.logical_session_id, "bot-n1", command2, result2, fixture.delta,
		fixture.final_snapshot, 502, fixture.base_snapshot
	), "Second bounded replay record failed")
	cache = service.get_snapshot()
	_assert(int(cache["record_count"]) == 1, "Replay cache exceeded record bound")
	_assert(int(cache["record_evictions"]) == 1, "Record eviction was not counted")
	var expired_ticket: Dictionary = second_ticket_result["details"]["ticket"]
	var expired_resume: Dictionary = ResumeScript.create(
		"resume/bounded/expired", expired_ticket, "session/transport/bounded/2", command2["operation_id"],
		CommandScript.command_fingerprint(command2), String(fixture.base_snapshot["checksum"])
	)
	var expired_decision: Dictionary = service.evaluate_resume(expired_resume, 510)
	_assert(not bool(expired_decision["details"]["result"]["accepted"]), "Expired ticket accepted")


func _test_grant_bound() -> void:
	var fixture: Dictionary = _build_completed_fixture("operation/n1/reconnect/grant-bound")
	_assert(bool(fixture.get("success", false)), "Grant-bound fixture build failed")
	if not bool(fixture.get("success", false)):
		return
	var service = ReplayServiceScript.new()
	_assert_ok(service.configure(1, 1, 64, 256, 1), "Grant-bound service configure failed")
	_assert_ok(service.record_completed_operation(
		fixture.logical_session_id, "bot-n1", fixture.command, fixture.result, fixture.delta,
		fixture.final_snapshot, 501, fixture.base_snapshot
	), "Grant-bound replay record failed")
	var ticket1_result: Dictionary = service.issue_ticket(fixture.logical_session_id, "bot-n1", 500)
	_assert_ok(ticket1_result, "First grant-bound ticket issue failed")
	var resume1: Dictionary = ResumeScript.create(
		"resume/grant-bound/1", ticket1_result["details"]["ticket"], "session/transport/grant-bound/1",
		String(fixture.command["operation_id"]), CommandScript.command_fingerprint(fixture.command),
		String(fixture.base_snapshot["checksum"])
	)
	_assert(bool(service.evaluate_resume(resume1, 501)["details"]["result"]["accepted"]), "First grant-bound resume rejected")
	var ticket2_result: Dictionary = service.issue_ticket(fixture.logical_session_id, "bot-n1", 501)
	_assert_ok(ticket2_result, "Second grant-bound ticket issue failed")
	var resume2: Dictionary = ResumeScript.create(
		"resume/grant-bound/2", ticket2_result["details"]["ticket"], "session/transport/grant-bound/2",
		String(fixture.command["operation_id"]), CommandScript.command_fingerprint(fixture.command),
		String(fixture.final_snapshot["checksum"])
	)
	_assert(bool(service.evaluate_resume(resume2, 501)["details"]["result"]["accepted"]), "Second grant-bound resume rejected")
	var cache: Dictionary = service.get_snapshot()
	_assert(int(cache["max_grants"]) == 1, "Grant cache bound was not derived")
	_assert(int(cache["grant_count"]) == 1, "Grant cache exceeded bound")
	_assert(int(cache["grant_evictions"]) == 1, "Grant eviction was not counted")
	_assert_error(service.serve_replay("session/transport/grant-bound/1", fixture.command, 501), "REPLAY_GRANT_NOT_FOUND", "Evicted replay grant remained usable")
	_assert_ok(service.serve_replay("session/transport/grant-bound/2", fixture.command, 501), "Newest bounded replay grant failed")


func _test_wire_types() -> void:
	var payload: Dictionary = {"probe": true}
	for message_type in ["RESUME_TICKET", "SESSION_RESUME", "SESSION_RESUME_RESULT"]:
		var frame: Dictionary = WireScript.create("wire/test/%s" % message_type.to_lower(), message_type, payload)
		_assert_ok(WireScript.validate(frame), "Wire rejected N1.3 type %s" % message_type)
		var encoded: Dictionary = WireScript.encode(frame)
		_assert(bool(encoded.get("success", false)), "Wire encode failed for %s" % message_type)
		_assert(bool(WireScript.decode(encoded["packet"]).get("success", false)), "Wire decode failed for %s" % message_type)


func _build_completed_fixture(operation_id: String) -> Dictionary:
	var authority = AuthorityScript.new()
	var setup: Dictionary = authority.setup("sim-n1", 5, 500)
	if not bool(setup.get("success", false)): return {"success": false}
	var logical_session_id: String = "session/logical/contracts"
	if not bool(authority.bind_session(logical_session_id).get("success", false)): return {"success": false}
	var base_snapshot: Dictionary = authority.create_snapshot()
	var inventory: Dictionary = base_snapshot["domain_components"]["inventory"]
	var payload: Dictionary = MovePayloadScript.create(
		logical_session_id, String(base_snapshot["authority_owner_id"]), String(inventory["command_item_id"]),
		String(inventory["source_container_id"]), String(inventory["destination_container_id"]), int(inventory["item_revision"])
	)
	var command: Dictionary = CommandScript.create(
		"message/n1/contracts/1", operation_id, String(base_snapshot["entity_id"]), "item.move_to_container", payload,
		int(base_snapshot["state_revision"]), int(base_snapshot["authority_epoch"]), int(base_snapshot["server_tick"]), 1000
	)
	var result: Dictionary = authority.handle_command(command)
	if String(result.get("status", "")) != "SUCCEEDED": return {"success": false}
	return {
		"success": true,
		"authority": authority,
		"logical_session_id": logical_session_id,
		"base_snapshot": base_snapshot,
		"command": command,
		"result": result,
		"delta": authority.get_delta(operation_id),
		"final_snapshot": authority.get_final_snapshot(operation_id),
	}


func _mutation_matrix(baseline: Dictionary, script, integer_fields: Array[String], label: String) -> void:
	for field in baseline.keys():
		var missing: Dictionary = baseline.duplicate(true)
		missing.erase(field)
		_assert(not bool(script.validate(missing).get("success", false)), "%s missing field accepted: %s" % [label, field])
	var extra: Dictionary = baseline.duplicate(true)
	extra["unexpected"] = true
	_assert_error(script.validate(extra), "UNEXPECTED_FIELD", "%s extra field accepted" % label)
	var corrupted: Dictionary = baseline.duplicate(true)
	corrupted["checksum"] = "f".repeat(64)
	_assert_error(script.validate(corrupted), "CHECKSUM_MISMATCH", "%s checksum corruption accepted" % label)
	for field in integer_fields:
		var wrong: Dictionary = baseline.duplicate(true)
		wrong[field] = "1"
		_assert(not bool(script.validate(wrong).get("success", false)), "%s wrong integer type accepted: %s" % [label, field])


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, expected: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == expected, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N1 reconnect replay contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error(failure)
	print("N1 reconnect replay contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
