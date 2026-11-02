extends SceneTree

# R4.2 P1-A: real M6 authoritative checkpoint worker and deterministic
# fake-failure matrix. This test does NOT alter production M3 durable commands.
const Proof = preload("res://scripts/persistence/m6_async_durable_command_proof.gd")
const Gate = preload("res://scripts/persistence/m6_pending_durable_ack_gate.gd")
const Writer = preload("res://scripts/persistence/async_checkpoint_writer.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Outbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")

const PEER_A := "peer/net-smooth/p1a/a"
const SESSION_A := "transport-session/net-smooth/p1a/a1"
const PLAYER_A := "a"
const OP_A := "operation/net-smooth/p1a/a/move1"

class FakeWriter:
	extends RefCounted
	var busy := false
	var reject_submit := false
	var job: Dictionary = {}
	var completed: Dictionary = {}

	func is_busy() -> bool:
		return busy

	func submit(authority_state: Dictionary, replay_state: Dictionary,
				checkpoint_id: String, generation: int, previous_generation: int,
				operation_id: String = "") -> Dictionary:
		if busy or reject_submit:
			return {"success": false, "error_code": "FAKE_WRITER_BUSY", "details": {}}
		busy = true
		job = {"authority": authority_state.duplicate(true),
			"replay": replay_state.duplicate(true), "checkpoint_id": checkpoint_id,
			"generation": generation, "previous_generation": previous_generation,
			"operation_id": operation_id}
		return {"success": true, "error_code": "", "details": {"generation": generation}}

	func finish(success: bool = true) -> Dictionary:
		var outcome := {
			"success": success,
			"error_code": "" if success else "SIMULATED_DISK_IO_ERROR",
			"details": {"generation": int(job.get("generation", -1)),
				"checkpoint_id": String(job.get("checkpoint_id", "")),
				"operation_id": String(job.get("operation_id", ""))},
		}
		completed = outcome
		return outcome

	func poll_completed() -> Dictionary:
		if completed.is_empty():
			return {}
		var result: Dictionary = completed.duplicate(true)
		completed.clear()
		busy = false
		return result


var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fake_writer_contract()
	_test_fail_closed_matrix()
	_test_real_worker_repository()
	for reason in failures:
		push_error(reason)
	print("NET_SMOOTH1_R42_P1A_ASYNC_PROOF: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_fake_writer_contract() -> void:
	var writer = FakeWriter.new()
	var gate = Gate.new()
	check(_ok(gate.configure(10)), "fake case: gate generation 10")
	var proof = Proof.new()
	check(_ok(proof.configure(writer, gate)), "proof configured on shared fake writer")

	# Simulate an already in-flight *periodic* checkpoint from the same writer.
	var prior: Dictionary = writer.submit(
		{"server_tick": 8}, {"replay": true}, "checkpoint/m6/dedicated/11", 11, 10)
	check(_ok(prior), "previous periodic checkpoint is in flight")
	var deferred: Dictionary = proof.reserve_mutation(
		"op/a", PEER_A, SESSION_A, PLAYER_A, 1, "ITEM")
	check(not _ok(deferred) and deferred.get("error_code", "") == "P1A_WAIT_PRIOR_PERIODIC",
		"periodic writer prevents any new mutation")
	check(proof.get_report().get("phase", "") == "IDLE",
		"no pre-mutation reservation while periodic writer busy")
	writer.finish()
	var consumed: Dictionary = writer.poll_completed()
	check(_ok(proof.observe_periodic_completion(consumed)), "only completed periodic generation is observed")
	check(int(gate.get_report().get("generation", -1)) == 11, "gate consumes generation 11 once")
	check(_ok(proof.reserve_mutation("op/a", PEER_A, SESSION_A, PLAYER_A, 1, "ITEM")),
		"next command reserved before applying mutation")
	check(not _ok(proof.reserve_mutation("op/b", PEER_A, SESSION_A, PLAYER_A, 1, "ITEM")),
		"serial reservation fences conflicting second command")
	var result := {"success": true, "data": {"material_units": 3}}
	var authority := {"server_tick": 9, "current_snapshot": {"checksum": "frozen"}}
	var replay := {"operation": "op/a", "durable": true}
	check(_ok(proof.submit_frozen("op/a", result, authority, replay)),
		"detached checkpoint submitted for generation 12")
	check(writer.job.get("generation", 0) == 12
		and writer.job.get("previous_generation", 0) == 11,
		"exact generation and previous generation submitted")
	result["data"]["material_units"] = 987
	authority["server_tick"] = 1000
	replay["operation"] = "corrupted-caller"
	check(int(writer.job["authority"]["server_tick"]) == 9
		and String(writer.job["replay"]["operation"]) == "op/a",
		"writer owns independently detached values")
	check(proof.peek_publication(PEER_A, SESSION_A, PLAYER_A, 1).is_empty(),
		"no successful result visible before commit")
	var pending: Dictionary = proof.poll_command_completion()
	check(_ok(pending) and bool(pending.get("details", {}).get("pending", false)),
		"normal poll is non-blocking while writer in flight")
	writer.finish()
	var committed: Dictionary = proof.poll_command_completion()
	check(_ok(committed) and bool(committed.get("details", {}).get("committed", false)),
		"worker completion advances ACK escrow")
	check(int(gate.get_report().get("generation", -1)) == 12,
		"generation advances exactly on matching commit")
	check(proof.peek_publication(PEER_A, SESSION_A, PLAYER_A, 2).is_empty(),
		"stale ownership epoch has no publication")
	check(proof.peek_publication("peer/other", SESSION_A, PLAYER_A, 1).is_empty(),
		"other peer has no publication")
	var ack: Dictionary = proof.peek_publication(PEER_A, SESSION_A, PLAYER_A, 1)
	check(_ok(ack) and int(ack.get("details", {}).get("result", {}).get("data", {}).get("material_units", -1)) == 3,
		"frozen committed outcome, not mutated caller result, published")
	ack["details"]["result"]["data"]["material_units"] = 999
	check(int(proof.peek_publication(PEER_A, SESSION_A, PLAYER_A, 1).get("details", {}).get("result", {}).get("data", {}).get("material_units", -1)) == 3,
		"ACK cannot mutate escrow by reference")
	check(not _ok(proof.mark_enqueued("op/a", "peer/other", SESSION_A, PLAYER_A, 1, true)),
		"wrong-session ACK delivery strictly refused")
	check(_ok(proof.mark_enqueued("op/a", PEER_A, SESSION_A, PLAYER_A, 1, true)),
		"ACK delivery only after actual successful enqueue")
	check(proof.get_report().get("phase", "") == "IDLE" and gate.get_report().get("ready_count", -1) == 0,
		"delivered escrow removed and next generation released")

	check(_ok(proof.reserve_mutation("op/b", PEER_A, SESSION_A, PLAYER_A, 1, "ITEM")),
		"next operation admitted after ACK delivery")
	check(_ok(proof.submit_frozen("op/b", {"success": true},
		{"server_tick": 10}, {"replay": true})), "next generation staged")
	check(_ok(proof.discard_stale_session(PEER_A, SESSION_A)),
		"transport disconnect quarantines in-flight ACK")
	check(proof.peek_publication(PEER_A, SESSION_A, PLAYER_A, 1).is_empty(),
		"stale session cannot receive in-flight result")
	writer.finish()
	var stale_outcome: Dictionary = proof.poll_command_completion()
	check(_ok(stale_outcome) and not bool(stale_outcome.get("details", {}).get("ack_eligible", true)),
		"durable completion survives disconnect but does not release stale ACK")
	check(proof.get_report().get("phase", "") == "IDLE"
		and int(gate.get_report().get("generation", -1)) == 13,
		"disconnected command still increments canonical generation")


func _test_fail_closed_matrix() -> void:
	# Submission failed AFTER reservation/mutation: never retry blindly.
	var writer = FakeWriter.new()
	var gate = Gate.new()
	check(_ok(gate.configure(21)), "submit-failure gate configured")
	var proof = Proof.new()
	check(_ok(proof.configure(writer, gate)), "submit-failure proof configured")
	check(_ok(proof.reserve_mutation("op/f", PEER_A, SESSION_A, PLAYER_A, 1, "ITEM")),
		"failure test mutation reserved")
	writer.reject_submit = true
	check(not _ok(proof.submit_frozen("op/f", {"success": true},
		{"server_tick": 22}, {"replay": true})), "rejected submit is never treated as committed")
	check(proof.get_report()["fatal"] and bool(gate.get_report()["fatal"]),
		"submission error makes owner+ACK gate fail closed")
	check(proof.peek_publication(PEER_A, SESSION_A, PLAYER_A, 1).is_empty(),
		"failed submission never emits ACK")

	for failure_class in ["IO_FAILURE", "WRONG_GENERATION", "WRONG_OPERATION", "WRONG_CHECKPOINT"]:
		var fault_writer = FakeWriter.new()
		var fault_gate = Gate.new()
		check(_ok(fault_gate.configure(51)), "fault gate configured " + failure_class)
		var actor = Proof.new()
		check(_ok(actor.configure(fault_writer, fault_gate)), "fault owner configured " + failure_class)
		check(_ok(actor.reserve_mutation("op/fault", PEER_A, SESSION_A, PLAYER_A, 1, "ITEM")),
			"fault operation reserved " + failure_class)
		check(_ok(actor.submit_frozen("op/fault", {"success": true},
			{"server_tick": 52}, {"replay": true})), "fault operation staged " + failure_class)
		var completion: Dictionary = fault_writer.finish(failure_class != "IO_FAILURE")
		if failure_class == "WRONG_GENERATION":
			completion["details"]["generation"] = 53
		elif failure_class == "WRONG_OPERATION":
			completion["details"]["operation_id"] = "op/forged"
		elif failure_class == "WRONG_CHECKPOINT":
			completion["details"]["checkpoint_id"] = "checkpoint/forged/52"
		check(not _ok(actor.accept_command_completion(completion)),
			"commit failure / tamper rejected " + failure_class)
		check(actor.get_report()["fatal"] and actor.peek_publication(
			PEER_A, SESSION_A, PLAYER_A, 1).is_empty(),
			"no ACK or further mutation after mismatch " + failure_class)

	var enqueue_writer = FakeWriter.new()
	var enqueue_gate = Gate.new()
	check(_ok(enqueue_gate.configure(67)), "enqueue-failure gate configured")
	var enqueue_actor = Proof.new()
	check(_ok(enqueue_actor.configure(enqueue_writer, enqueue_gate)), "enqueue-failure owner configured")
	check(_ok(enqueue_actor.reserve_mutation("op/failedsend",
		PEER_A, SESSION_A, PLAYER_A, 1, "ITEM")), "failed-send command reserved")
	check(_ok(enqueue_actor.submit_frozen("op/failedsend",
		{"success": true}, {"server_tick": 68}, {"replay": true})),
		"failed-send command submitted")
	enqueue_writer.finish()
	check(_ok(enqueue_actor.poll_command_completion()), "failed-send command actually committed")
	check(_ok(enqueue_actor.mark_enqueued("op/failedsend", PEER_A,
		SESSION_A, PLAYER_A, 1, false)), "failed reliable enqueue quarantines ACK")
	check(enqueue_actor.get_report()["phase"] == "IDLE"
		and int(enqueue_gate.get_report().get("generation", -1)) == 68,
		"failed enqueue never rolls back committed outcome")
	check(_ok(enqueue_actor.reserve_mutation("op/next", PEER_A,
		SESSION_A, PLAYER_A, 1, "ITEM")), "failed enqueue does not deadlock next operation")


func _test_real_worker_repository() -> void:
	# Actual M6 adapter/outbox/atomic repository + existing single writer.
	# Blocking wait_completed() is allowed ONLY in this standalone test.
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r42-p1a-proof-%d" % Time.get_ticks_usec())
	var service = Service.new()
	check(_ok(service.setup("simulation/net-smooth-p1a", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET", "region_id": "region/net-smooth/p1a"
	})), "real game service configured")
	check(_ok(service.join(PLAYER_A, SESSION_A,
		"operation/net-smooth/p1a/a/join1")), "real A joined")
	var adapter = Adapter.new()
	check(_ok(adapter.setup(service)), "real M6 adapter configured")
	var outbox = Outbox.new()
	check(_ok(outbox.setup(service)), "real M6 replay-outbox configured")
	var writer = Writer.new()
	check(_ok(writer.setup(root_path)), "real single checkpoint writer started")
	var authority: Dictionary = adapter.export_recovery_state()
	var replay: Dictionary = outbox.to_dict()
	check(_ok(writer.submit(authority, replay,
		"checkpoint/m6/dedicated/1", 1, 0)), "baseline atomic checkpoint submitted")
	var first: Dictionary = writer.wait_completed()
	check(_ok(first), "real base checkpoint persisted and verified")
	var repository = Repository.new()
	check(_ok(repository.configure(root_path)), "real independent repository reader")
	check(int(repository.load_committed().get("details", {}).get("checkpoint", {}).get("generation", -1)) == 1,
		"committed generation 1 recovered from disk")
	var gate = Gate.new()
	check(_ok(gate.configure(1)), "real gate generation 1")
	var actor = Proof.new()
	check(_ok(actor.configure(writer, gate)), "real proof shares same writer")
	check(_ok(writer.submit(adapter.export_recovery_state(), outbox.to_dict(),
		"checkpoint/m6/dedicated/2", 2, 1)), "prior periodic checkpoint staged")
	check(not _ok(actor.reserve_mutation(OP_A, PEER_A, SESSION_A, PLAYER_A, 1, "MOVE")),
		"real periodic busy prevents next mutation")
	var periodic: Dictionary = writer.wait_completed()
	check(_ok(actor.observe_periodic_completion(periodic)), "real periodic worker completion observed")
	check(int(gate.get_report().get("generation", -1)) == 2, "real periodic generation advanced")
	check(_ok(actor.reserve_mutation(OP_A, PEER_A, SESSION_A, PLAYER_A, 1, "MOVE")),
		"real durable command reserved before move")
	var moved: Dictionary = service.move_player(PLAYER_A, SESSION_A, 1, 1, 0.1, 0.0, OP_A)
	check(_ok(moved), "real canonical movement applied exactly once")
	check(_ok(outbox.stage_committed(OP_A, "MOVE", {
		"logical_player_id": PLAYER_A, "result": moved.duplicate(true),
		"success": true})), "M6 replay outbox staged before detached checkpoint")
	var captured_authority: Dictionary = adapter.export_recovery_state()
	var captured_replay: Dictionary = outbox.to_dict()
	var reference: Dictionary = Checkpoint.create(
		"checkpoint/m6/dedicated/3", 3, 2,
		captured_authority, captured_replay, OP_A,
		int(captured_authority.get("server_tick", 0)))
	check(_ok(Checkpoint.validate(reference)), "expected real detached checkpoint validates")
	check(_ok(actor.submit_frozen(OP_A, moved,
		captured_authority, captured_replay)), "real durable command submitted async")
	check(actor.peek_publication(PEER_A, SESSION_A, PLAYER_A, 1).is_empty(),
		"real worker has not made early success observable")
	captured_authority["session_id"] = "tampered/live/after-submit"
	captured_replay.clear()
	var committed: Dictionary = writer.wait_completed()
	check(_ok(actor.accept_command_completion(committed)),
		"real worker atomic save releases escrow")
	var disk: Dictionary = repository.load_committed()
	check(_ok(disk), "exact committed checkpoint readable after completion")
	check(int(disk.get("details", {}).get("checkpoint", {}).get("generation", -1)) == 3,
		"real generation exactly 3")
	check(String(disk.get("details", {}).get("checkpoint", {}).get("checksum", "")) == String(reference.get("checksum", "!")),
		"real immutable detached snapshot equals pre-submit expected SHA")
	check(not actor.peek_publication(PEER_A, SESSION_A, PLAYER_A, 1).is_empty(),
		"only disk-committed result can now be emitted")
	check(_ok(actor.mark_enqueued(OP_A, PEER_A, SESSION_A, PLAYER_A, 1, true)),
		"real ACK escrow delivers after durable commit")
	var before_revision := int(service.get_report().get("revision", -1))
	var retried: Dictionary = service.move_player(PLAYER_A, SESSION_A, 1, 1, 0.1, 0.0, OP_A)
	check(_ok(retried) and (bool(retried.get("replay", false))
		or bool(retried.get("details", {}).get("replay", false))),
		"old operation_id follows canonical service replay")
	check(int(service.get_report().get("revision", -1)) == before_revision,
		"replay does not apply same movement again")
	check(_ok(writer.stop()) or writer.stop().is_empty(),
		"real single writer stops after completed command")
	service.shutdown()


func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
