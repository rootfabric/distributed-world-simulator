extends SceneTree

const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const Machine = preload("res://scripts/network/handoff/handoff_state_machine.gd")

const STATES: Array[String] = [
	"REQUESTED", "PREPARING", "FROZEN", "SNAPSHOT_READY",
	"TARGET_PREPARED", "COMMITTED", "ABORTED", "EXPIRED",
]
const TERMINAL: Array[String] = ["COMMITTED", "ABORTED", "EXPIRED"]
const ALLOWED: Dictionary = {
	"REQUESTED": ["PREPARING", "ABORTED", "EXPIRED"],
	"PREPARING": ["FROZEN", "ABORTED", "EXPIRED"],
	"FROZEN": ["SNAPSHOT_READY", "ABORTED", "EXPIRED"],
	"SNAPSHOT_READY": ["TARGET_PREPARED", "ABORTED", "EXPIRED"],
	"TARGET_PREPARED": ["COMMITTED", "ABORTED", "EXPIRED"],
	"COMMITTED": [],
	"ABORTED": [],
	"EXPIRED": [],
}

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	for source_state in STATES:
		for target_state in STATES:
			var machine = Machine.new()
			var source_ticket: Dictionary = _ticket_in_state(source_state)
			_assert_ok(machine.setup(source_ticket), "Setup failed for %s" % source_state)
			var revision_before: int = int(machine.ticket["transition_revision"])
			var history_before: int = machine.transition_history.size()
			var result: Dictionary = machine.transition(target_state, _context_for(target_state))
			if target_state == source_state:
				_assert_ok(result, "Same-state replay failed: %s" % source_state)
				_assert(bool(result.get("replay", false)), "Same-state transition was not replay: %s" % source_state)
				_assert(int(machine.ticket["transition_revision"]) == revision_before, "Replay changed revision: %s" % source_state)
				_assert(machine.transition_history.size() == history_before, "Replay changed history: %s" % source_state)
			elif TERMINAL.has(source_state):
				_assert_code(result, "HANDOFF_TERMINAL", "Terminal state escaped: %s -> %s" % [source_state, target_state])
				_assert(int(machine.ticket["transition_revision"]) == revision_before, "Rejected terminal transition changed revision")
			elif ALLOWED[source_state].has(target_state):
				_assert_ok(result, "Legal transition failed: %s -> %s" % [source_state, target_state])
				_assert(String(machine.ticket["state"]) == target_state, "Legal transition reached wrong state")
				_assert(int(machine.ticket["transition_revision"]) == revision_before + 1, "Legal transition revision incorrect")
				_assert(machine.transition_history.size() == history_before + 1, "Legal transition history not appended")
			else:
				_assert_code(result, "ILLEGAL_HANDOFF_TRANSITION", "Illegal transition accepted: %s -> %s" % [source_state, target_state])
				_assert(String(machine.ticket["state"]) == source_state, "Rejected transition changed state")
				_assert(int(machine.ticket["transition_revision"]) == revision_before, "Rejected transition changed revision")

	var early_expiry = Machine.new()
	_assert_ok(early_expiry.setup(_ticket_in_state("REQUESTED")), "Early-expiry setup failed")
	_assert_code(
		early_expiry.transition("EXPIRED", {"tick": 199, "reason": "too_early"}),
		"HANDOFF_NOT_EXPIRED",
		"Direct EXPIRED transition bypassed expiry tick"
	)
	_assert(String(early_expiry.ticket["state"]) == "REQUESTED", "Early expiry changed ticket")
	var at_expiry: Dictionary = early_expiry.transition("EXPIRED", {"tick": 200, "reason": "lease_timeout"})
	_assert_ok(at_expiry, "EXPIRED transition failed at expiry tick")

	_finish()


func _ticket_in_state(state: String) -> Dictionary:
	var value: Dictionary = Ticket.create(
		"handoff/matrix/%s" % state.to_lower(), "entity/matrix", "sim-a", "sim-b",
		4, 5, 20, "region/moon/b", 100, 200
	)
	value["state"] = state
	match state:
		"REQUESTED":
			value["transition_revision"] = 0
		"PREPARING":
			value["transition_revision"] = 1
		"FROZEN":
			value["transition_revision"] = 2
		"SNAPSHOT_READY":
			value["transition_revision"] = 3
			_set_snapshot(value)
		"TARGET_PREPARED":
			value["transition_revision"] = 4
			_set_snapshot(value)
		"COMMITTED":
			value["transition_revision"] = 5
			_set_snapshot(value)
		"ABORTED", "EXPIRED":
			value["transition_revision"] = 1
			value["reason"] = state.to_lower()
	return value


func _set_snapshot(value: Dictionary) -> void:
	value["snapshot_id"] = "snapshot/matrix/1"
	value["snapshot_hash"] = "matrix-snapshot".sha256_text()


func _context_for(target_state: String) -> Dictionary:
	if target_state == "SNAPSHOT_READY":
		return {
			"tick": 150,
			"snapshot_id": "snapshot/matrix/next",
			"snapshot_hash": "matrix-next".sha256_text(),
		}
	if target_state == "EXPIRED":
		return {"tick": 200, "reason": "lease_timeout"}
	if target_state == "ABORTED":
		return {"tick": 150, "reason": "matrix_abort"}
	return {"tick": 150}


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
		print("N0 handoff transition matrix: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 handoff transition matrix: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
