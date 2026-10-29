extends SceneTree

# NET-SMOOTH1 R4.2-P1-B R1: independent fail-closed falsifier for the P1-A
# reviewer finding (periodic completion during an unfinished command).
# Deliberately does not run any network or enable production async commands.
const Proof = preload("res://scripts/persistence/m6_async_durable_command_proof.gd")
const Gate = preload("res://scripts/persistence/m6_pending_durable_ack_gate.gd")

const PEER := "peer/p1b/a"
const SESSION := "transport-session/p1b/a/1"
const PLAYER := "a"

class DeterministicWriter:
	extends RefCounted
	var busy := false
	var payload: Dictionary = {}
	func is_busy() -> bool:
		return busy
	func submit(authority_state: Dictionary, replay_state: Dictionary,
		checkpoint_id: String, generation: int, previous_generation: int,
		operation_id: String = "") -> Dictionary:
		if busy:
			return {"success": false, "error_code": "WRITER_BUSY", "details": {}}
		busy = true
		payload = {"authority": authority_state.duplicate(true),
			"replay": replay_state.duplicate(true), "generation": generation,
			"previous_generation": previous_generation,
			"checkpoint_id": checkpoint_id, "operation_id": operation_id}
		return {"success": true, "error_code": "", "details": {"generation": generation}}
	func poll_completed() -> Dictionary:
		return {}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_periodic_while_applying_fails_closed()
	_test_periodic_while_commit_pending_fails_closed()
	_test_periodic_sequence_exact_once()
	_test_no_early_publication_for_blocked_writer()
	for failure in failures:
		push_error(failure)
	print("NET_SMOOTH1_R42_P1B_PERIODIC: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _new_owner(generation: int) -> Dictionary:
	var gate = Gate.new()
	check(_ok(gate.configure(generation)), "ACK gate configured")
	var writer = DeterministicWriter.new()
	var proof = Proof.new()
	check(_ok(proof.configure(writer, gate)), "writer owner configured")
	return {"proof": proof, "gate": gate, "writer": writer}

func _success_periodic(generation: int) -> Dictionary:
	return {"success": true, "error_code": "", "details": {
		"generation": generation, "operation_id": "",
		"checkpoint_id": "checkpoint/m6/dedicated/%d" % generation}}

func _test_periodic_while_applying_fails_closed() -> void:
	var state: Dictionary = _new_owner(50)
	var proof = state["proof"]
	var gate = state["gate"]
	check(_ok(proof.reserve_mutation("operation/p1b/one", PEER, SESSION, PLAYER, 1, "ITEM")),
		"command reserves before authoritative mutation")
	check(not _ok(proof.observe_periodic_completion(_success_periodic(51))),
		"periodic completion during APPLYING rejected")
	check(String(proof.get_report().get("fatal_code", "")) ==
		"P1B_PERIODIC_COMPLETION_OUT_OF_PHASE", "exact out-of-phase error recorded")
	check(bool(gate.get_report().get("fatal", false)), "ACK gate also fail closed")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"no early publication on mismatched completion")
	check(not _ok(proof.reserve_mutation("operation/p1b/two", PEER, SESSION, PLAYER, 1, "ITEM")),
		"fatal state rejects further command")

func _test_periodic_while_commit_pending_fails_closed() -> void:
	var state: Dictionary = _new_owner(80)
	var proof = state["proof"]
	var gate = state["gate"]
	check(_ok(proof.reserve_mutation("operation/p1b/three", PEER, SESSION, PLAYER, 1, "ITEM")),
		"commit command reserved")
	check(_ok(proof.submit_frozen("operation/p1b/three", {"success": true},
		{"server_tick": 7}, {"replay": true})), "frozen command submitted")
	check(not _ok(proof.observe_periodic_completion(_success_periodic(81))),
		"periodic completion while command IO pending rejected, not silently discarded")
	check(bool(gate.get_report().get("fatal", false)), "pending generation locked after error")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"no ACK after confusing periodic with a command")
	check(int(gate.get_report().get("generation", -1)) == 80,
		"generation cannot advance on forged completion")

func _test_periodic_sequence_exact_once() -> void:
	var state: Dictionary = _new_owner(120)
	var proof = state["proof"]
	var gate = state["gate"]
	check(_ok(proof.observe_periodic_completion(_success_periodic(121))),
		"quiescent periodic generation accepted once")
	check(int(gate.get_report().get("generation", -1)) == 121,
		"accepted prior generation observed by ACK gate")
	check(not _ok(proof.observe_periodic_completion(_success_periodic(121))),
		"replayed identical periodic generation rejected")
	check(bool(gate.get_report().get("fatal", false)),
		"duplicate periodic completion fails closed to prevent generation drift")
	check(not _ok(proof.reserve_mutation("operation/p1b/after-duplicate",
		PEER, SESSION, PLAYER, 1, "ITEM")), "no mutation after lost generation ordering")

func _test_no_early_publication_for_blocked_writer() -> void:
	var state: Dictionary = _new_owner(202)
	var proof = state["proof"]
	var writer = state["writer"]
	writer.busy = true
	var reply: Dictionary = proof.reserve_mutation("operation/p1b/wait",
		PEER, SESSION, PLAYER, 1, "ITEM")
	check(not _ok(reply) and String(reply.get("error_code", "")) ==
		"P1A_WAIT_PRIOR_PERIODIC", "busy periodic worker backpressures BEFORE mutation")
	check(proof.get_report().get("phase", "") == "IDLE",
		"rejected pre-reservation never applies or prepares uncommitted outcome")
	check(proof.peek_publication(PEER, SESSION, PLAYER, 1).is_empty(),
		"busy writer cannot expose a successful ACK")

func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))

func check(good: bool, label: String) -> void:
	assertions += 1
	if not good:
		failures.append(label)
