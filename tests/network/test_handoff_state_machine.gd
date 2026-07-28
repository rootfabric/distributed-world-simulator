extends SceneTree

const TicketScript = preload("res://scripts/network/contracts/handoff_ticket.gd")
const ResultScript = preload("res://scripts/network/contracts/handoff_result.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const MachineScript = preload("res://scripts/network/handoff/handoff_state_machine.gd")
const SessionScript = preload("res://scripts/network/handoff/world_entity_handoff_session.gd")
const AggregateScript = preload("res://scripts/simulation/entities/world_entity_aggregate.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")

var failures: Array[String] = []
var assertions: int = 0


class FakeAggregate:
	extends RefCounted

	func to_snapshot() -> Dictionary:
		return {}

	func setup_from_snapshot(_value: Dictionary) -> bool:
		return true

	func transfer_authority(_owner: String, _epoch: int) -> Dictionary:
		return {"success": true}


func _init() -> void:
	var ticket: Dictionary = _ticket()
	_assert_ok(TicketScript.validate(ticket), "Valid handoff ticket rejected")
	_assert(not TicketScript.ticket_hash(ticket).is_empty(), "Ticket hash is empty")
	var same_node: Dictionary = ticket.duplicate(true)
	same_node["target_node_id"] = "sim-a"
	_assert_code(TicketScript.validate(same_node), "SAME_AUTHORITY_NODE", "Same-node handoff accepted")
	var stale_target_epoch: Dictionary = ticket.duplicate(true)
	stale_target_epoch["target_authority_epoch"] = 4
	_assert_code(TicketScript.validate(stale_target_epoch), "INVALID_AUTHORITY_EPOCH", "Non-increasing target epoch accepted")
	var incomplete_snapshot: Dictionary = ticket.duplicate(true)
	incomplete_snapshot["snapshot_id"] = "snapshot/incomplete"
	_assert_code(TicketScript.validate(incomplete_snapshot), "INCOMPLETE_SNAPSHOT_REFERENCE", "Incomplete snapshot reference accepted")
	var invalid_abort_ticket: Dictionary = ticket.duplicate(true)
	invalid_abort_ticket["state"] = "ABORTED"
	invalid_abort_ticket["transition_revision"] = 1
	_assert_code(TicketScript.validate(invalid_abort_ticket), "HANDOFF_REASON_REQUIRED", "Aborted ticket without reason accepted")
	var invalid_abort_result: Dictionary = ResultScript.create("handoff/invalid", "entity/item/probe", "ABORTED", "", "sim-a", "sim-b", "sim-a", 4, 20, 110, {})
	_assert_code(ResultScript.validate(invalid_abort_result), "EMPTY_FIELD", "Aborted result without error code accepted")

	var machine = MachineScript.new()
	_assert_ok(machine.setup(ticket), "State machine setup failed")
	_assert_code(machine.transition("PREPARING", {"tick": "101"}), "INVALID_TRANSITION_TICK_TYPE", "String transition tick accepted")
	_assert_code(machine.transition("PREPARING", {"tick": 101, "expected_transition_revision": "0"}), "INVALID_TRANSITION_REVISION_TYPE", "String transition revision accepted")
	_assert_code(machine.transition("PREPARING", {"tick": 101, "snapshot_id": "snapshot/not-allowed"}), "UNEXPECTED_TRANSITION_CONTEXT", "Unexpected transition context accepted")
	_assert_code(machine.transition("FROZEN", {"tick": 101}), "ILLEGAL_HANDOFF_TRANSITION", "Illegal transition accepted")
	_assert_ok(machine.transition("PREPARING", {"tick": 101}), "REQUESTED -> PREPARING failed")
	_assert_code(machine.transition("PREPARING", {"tick": 102, "expected_transition_revision": 0}), "TRANSITION_REVISION_CONFLICT", "Stale transition revision accepted")
	_assert_code(machine.transition("FROZEN", {"tick": 100}), "INVALID_TRANSITION_TICK", "Backward transition tick accepted")
	_assert_ok(machine.transition("FROZEN", {"tick": 102}), "PREPARING -> FROZEN failed")
	_assert_code(machine.transition("SNAPSHOT_READY", {"tick": 103}), "INVALID_SNAPSHOT_REFERENCE_TYPE", "Snapshot-ready without snapshot accepted")
	var snapshot_hash: String = "handoff-snapshot".sha256_text()
	_assert_ok(machine.transition("SNAPSHOT_READY", {"tick": 103, "snapshot_id": "snapshot/handoff/1", "snapshot_hash": snapshot_hash}), "FROZEN -> SNAPSHOT_READY failed")
	_assert_ok(machine.transition("TARGET_PREPARED", {"tick": 104}), "SNAPSHOT_READY -> TARGET_PREPARED failed")
	var prepared: Dictionary = machine.prepare_transition("COMMITTED", {"tick": 105})
	_assert_ok(prepared, "Commit preflight failed")
	var tampered_prepared: Dictionary = prepared.duplicate(true)
	tampered_prepared["candidate"] = prepared["candidate"].duplicate(true)
	tampered_prepared["candidate"]["entity_id"] = "entity/forged"
	_assert_code(machine.commit_prepared(tampered_prepared), "PREPARED_CANDIDATE_MISMATCH", "Tampered prepared transition accepted")
	var forged_prepared: Dictionary = tampered_prepared.duplicate(true)
	forged_prepared["candidate_hash"] = TicketScript.ticket_hash(forged_prepared["candidate"])
	forged_prepared["prepared_token"] = UtilsScript.payload_hash({
		"source_ticket_hash": String(forged_prepared["source_ticket_hash"]),
		"candidate_hash": String(forged_prepared["candidate_hash"]),
		"tick": int(forged_prepared["tick"]),
	})
	_assert_code(machine.commit_prepared(forged_prepared), "PREPARED_IDENTITY_MUTATION", "Identity-mutating prepared transition accepted")
	var tampered_tick: Dictionary = prepared.duplicate(true)
	tampered_tick["tick"] = 99
	_assert_code(machine.commit_prepared(tampered_tick), "PREPARED_TOKEN_MISMATCH", "Prepared tick tampering accepted")
	var commit: Dictionary = machine.commit_prepared(prepared)
	_assert_ok(commit, "Prepared commit failed")
	_assert(String(machine.ticket["state"]) == "COMMITTED", "Machine did not enter COMMITTED")
	_assert(TicketScript.is_terminal(machine.ticket), "COMMITTED ticket not terminal")
	var replay: Dictionary = machine.transition("COMMITTED", {"tick": 106})
	_assert_ok(replay, "Idempotent commit replay failed")
	_assert(bool(replay.get("replay", false)) and not bool(replay.get("changed", true)), "Commit replay mutated ticket")
	_assert_code(machine.transition("ABORTED", {"tick": 107}), "HANDOFF_TERMINAL", "Terminal handoff left COMMITTED")
	_assert(machine.transition_history.size() == 6, "Unexpected transition history size")
	var committed_result: Dictionary = machine.create_result(106, 22)
	_assert_ok(ResultScript.validate(committed_result), "Committed handoff result invalid")
	_assert(String(committed_result["authority_owner_id"]) == "sim-b", "Committed result owner is not target")

	var abort_machine = MachineScript.new()
	_assert_ok(abort_machine.setup(_ticket()), "Abort machine setup failed")
	_assert_ok(abort_machine.transition("PREPARING", {"tick": 101}), "Abort path prepare failed")
	_assert_ok(abort_machine.transition("ABORTED", {"tick": 102, "reason": "target_unavailable"}), "Abort transition failed")
	_assert(String(abort_machine.ticket["reason"]) == "target_unavailable", "Abort reason lost")
	_assert_code(abort_machine.transition("PREPARING", {"tick": 103}), "HANDOFF_TERMINAL", "Aborted ticket resumed")
	var abort_result: Dictionary = abort_machine.create_result(103, 20)
	_assert_ok(ResultScript.validate(abort_result), "Aborted handoff result invalid")
	_assert(String(abort_result["authority_owner_id"]) == "sim-a", "Abort changed authority owner")

	var expire_machine = MachineScript.new()
	_assert_ok(expire_machine.setup(_ticket()), "Expire machine setup failed")
	_assert_code(expire_machine.expire(199), "HANDOFF_NOT_EXPIRED", "Ticket expired too early")
	_assert_ok(expire_machine.expire(200), "Ticket did not expire at expiry tick")
	_assert(String(expire_machine.ticket["state"]) == "EXPIRED", "Expired ticket state incorrect")

	var unsupported_session = SessionScript.new()
	_assert_code(unsupported_session.setup(FakeAggregate.new(), _ticket()), "UNSUPPORTED_AGGREGATE_TYPE", "Arbitrary aggregate implementation accepted")

	var aggregate = AggregateScript.new()
	_assert(aggregate.setup(
		"entity/item/probe",
		"item/probe",
		SpatialRefScript.create("body/moon/fixed", Vector3(10, 20, 30)),
		{
			"entity_type": "world_item",
			"physics_state": {"mass_kg": 2.0},
			"domain_components": {"item": {"definition_id": "survey_beacon"}},
			"authority_owner_id": "sim-a",
			"authority_epoch": 4,
			"state_revision": 20,
			"lifecycle_state": "ACTIVE",
		}
	), "Aggregate setup failed")
	var session_ticket: Dictionary = TicketScript.create(
		"handoff/aggregate/1", aggregate.entity_id, "sim-a", "sim-b", 4, 5,
		aggregate.state_revision, "region/moon/b", 100, 200
	)
	var session = SessionScript.new()
	_assert_ok(session.setup(aggregate, session_ticket), "Handoff session setup failed")
	_assert_ok(session.transition("PREPARING", {"tick": 101}), "Session prepare failed")
	_assert_ok(session.transition("FROZEN", {"tick": 102}), "Session freeze failed")
	_assert_ok(session.transition("SNAPSHOT_READY", {"tick": 103, "snapshot_id": "snapshot/aggregate/1", "snapshot_hash": snapshot_hash}), "Session snapshot-ready failed")
	_assert_ok(session.transition("TARGET_PREPARED", {"tick": 104}), "Session target prepare failed")
	var revision_before_commit: int = aggregate.state_revision
	var session_commit: Dictionary = session.transition("COMMITTED", {"tick": 105})
	_assert_ok(session_commit, "Session commit failed")
	_assert(aggregate.authority_owner_id == "sim-b", "Aggregate authority owner not transferred")
	_assert(aggregate.authority_epoch == 5, "Aggregate authority epoch not transferred")
	_assert(aggregate.state_revision == revision_before_commit + 1, "Aggregate revision did not advance exactly once")
	var revision_after_commit: int = aggregate.state_revision
	_assert_ok(session.transition("COMMITTED", {"tick": 106}), "Session commit replay failed")
	_assert(aggregate.state_revision == revision_after_commit, "Commit replay changed aggregate revision")
	var result: Dictionary = session.create_result(106)
	_assert_ok(ResultScript.validate(result), "Session result invalid")
	_assert(int(result["state_revision"]) == aggregate.state_revision, "Session result revision mismatch")

	var stale_aggregate = AggregateScript.new()
	_assert(stale_aggregate.setup_from_snapshot(aggregate.to_snapshot()), "Stale aggregate clone failed")
	var stale_ticket: Dictionary = TicketScript.create(
		"handoff/stale/1", stale_aggregate.entity_id, "sim-b", "sim-c", 5, 6,
		stale_aggregate.state_revision - 1, "region/moon/c", 100, 200
	)
	var stale_session = SessionScript.new()
	_assert_code(stale_session.setup(stale_aggregate, stale_ticket), "REVISION_CONFLICT", "Stale handoff session accepted")

	var abort_aggregate = AggregateScript.new()
	_assert(abort_aggregate.setup_from_snapshot(aggregate.to_snapshot()), "Abort aggregate clone failed")
	var abort_ticket: Dictionary = TicketScript.create(
		"handoff/abort/2", abort_aggregate.entity_id, "sim-b", "sim-c", 5, 6,
		abort_aggregate.state_revision, "region/moon/c", 100, 200
	)
	var aggregate_abort_session = SessionScript.new()
	_assert_ok(aggregate_abort_session.setup(abort_aggregate, abort_ticket), "Aggregate abort session setup failed")
	_assert_ok(aggregate_abort_session.transition("ABORTED", {"tick": 101, "reason": "operator_cancel"}), "Aggregate abort failed")
	_assert(abort_aggregate.authority_owner_id == "sim-b" and abort_aggregate.authority_epoch == 5, "Abort mutated aggregate authority")

	_finish()


func _ticket() -> Dictionary:
	return TicketScript.create(
		"handoff/1", "entity/item/probe", "sim-a", "sim-b",
		4, 5, 20, "region/moon/b", 100, 200
	)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_code(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N0 handoff state machine: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 handoff state machine: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
