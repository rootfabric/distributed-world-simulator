extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")
const Protocol = preload("res://scripts/research/fabric_bake0/unseen_machine_challenge_protocol_v1.gd")
const Fabric1 = preload("res://scripts/research/fabric_bake0/fabric1_generalized_runtime_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const Bridge = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric1/bridge4_canonical_world_fixture_v1.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_test_small_full_restart_and_history()
	_test_external_authority_and_atomic_restore()
	_finish()

func _test_small_full_restart_and_history() -> void:
	var base := _small_spec(1, [], [])
	_assert(not base.is_empty(), "small generic graph did not build")
	var runtime := Fabric1.new()
	_assert_ok(runtime.start(base, 10), "small valid object did not FULL-fallback")
	_assert(runtime.status().mode == "FULL", "small object did not start FULL")
	_assert_ok(runtime.execute([1.0, 0.0]), "small FULL execution failed")

	var captured := runtime.capture_capsule()
	_assert_ok(captured, "FULL capsule capture failed")
	var capsule: Dictionary = captured.details.capsule
	var corrupted := capsule.duplicate(true)
	corrupted["machine_id"] = "machine/r1-corrupt"
	var retryable := Fabric1.new()
	_assert_error(retryable.restore(base, corrupted), "FABRIC1_CAPSULE_CHECKSUM_INVALID", "corrupt capsule was accepted")
	_assert(retryable.status().mode == "UNINITIALIZED", "failed restore partially initialized runtime")
	_assert_ok(retryable.restore(base, capsule), "valid FULL restore failed after rejected corrupt capsule")
	_assert(retryable.status().mode == "FULL", "FULL restore changed mode")

	var event1 := "event/r1/failure-one"
	var successor1 := _small_spec(2, ["edge/r1/alt-left"], [event1])
	_assert_ok(retryable.apply_canonical_failure(successor1, event1, ["edge/r1/alt-left"], 11), "first failure after FULL restore failed")
	_assert(retryable.status().mode == "FULL", "first consecutive failure left FULL")
	_assert(retryable.status().event_ledger == [event1], "first event ledger wrong")

	var event2 := "event/r1/failure-two"
	var successor2 := _small_spec(3, ["edge/r1/alt-left", "edge/r1/alt-right"], [event1, event2])
	_assert_ok(retryable.apply_canonical_failure(successor2, event2, ["edge/r1/alt-right"], 12), "second consecutive FULL failure required a BAKE")
	_assert(retryable.status().event_ledger == [event1, event2], "second event ledger wrong")
	_assert_ok(retryable.execute([1.0, 0.0]), "post-second-failure FULL execution failed")

	var history_base := _small_spec(4, [], ["event/r1/old"])
	var forged := _small_spec(5, ["edge/r1/alt-left"], ["event/r1/forged", "event/r1/new"])
	_assert_error(Protocol.validate_successor(history_base, forged, "event/r1/new", ["edge/r1/alt-left"]), "B0_7_EVENT_HISTORY_NOT_PRESERVED", "forged replacement event history accepted")
	var honest := _small_spec(5, ["edge/r1/alt-left"], ["event/r1/new", "event/r1/old"])
	_assert_ok(Protocol.validate_successor(history_base, honest, "event/r1/new", ["edge/r1/alt-left"]), "honest event-ledger continuation rejected")

func _test_external_authority_and_atomic_restore() -> void:
	var initial := Fixture.initial_snapshot()
	var matter := Fixture.matter_batch()
	var authority := Adapter.authority_for(initial, matter, Fixture.AUTHORITY_OWNER, Fixture.AUTHORITY_EPOCH)
	var context := Adapter.compile_authoritative(initial, matter, authority, [])
	_assert_ok(context, "real canonical source context failed")
	_assert(context.details.authority.checksum == authority.checksum, "outer authority changed during compile")
	_assert(context.details.source_context.frontier.frontier_hash == context.details.frontier.frontier_hash, "source frontier not threaded into compiler context")
	_assert(context.details.authority.mutable_source_ids == [U.source_key("CONSTRUCTION", Fixture.CONSTRUCT_ID)], "Construction mutability boundary wrong")
	_assert(context.details.authority.readonly_source_ids == [U.source_key("MATTER", matter.batch_id)], "Matter did not remain readonly")

	var runtime := Bridge.new()
	_assert_ok(runtime.start_authoritative(initial, matter, authority, [], 20), "BRIDGE4 authoritative start failed")
	var status := runtime.status()
	_assert(status.fabric1.external_source == true, "FABRIC1 did not mark external source")
	_assert(status.fabric1.source_context.authority.checksum == authority.checksum, "FABRIC1 authority diverged from BRIDGE4")
	_assert(status.fabric1.artifact_source_binding.authority_envelope.checksum == authority.checksum, "BAKE artifact authority diverged from canonical owner")
	_assert(status.fabric1.artifact_source_binding.canonical_source_frontier.frontier_hash == context.details.frontier.frontier_hash, "BAKE artifact frontier diverged from canonical frontier")
	_assert_ok(runtime.execute(initial, matter, [1.0, 0.0], authority), "explicit-authority execution failed")

	var wrong_authority := Adapter.authority_for(initial, matter, "server/r1-wrong-owner", Fixture.AUTHORITY_EPOCH + 1)
	var wrong_exec := runtime.execute(initial, matter, [1.0, 0.0], wrong_authority)
	_assert(not bool(wrong_exec.get("success", false)), "changed owner/epoch remained executable")

	var proposal := runtime.observe_load(initial, matter, Fixture.TARGET_BOND_ID, 90.0, 21, authority)
	_assert_ok(proposal, "FULL refinement proposal failed")
	_assert(runtime.status().mode == "FULL", "proposal did not enter FULL")
	var cap_result := runtime.capture_capsule()
	_assert_ok(cap_result, "pending FULL bridge capsule capture failed")
	var capsule: Dictionary = cap_result.details.capsule

	var bad_capsule := capsule.duplicate(true)
	bad_capsule["authority_checksum"] = "0".repeat(64)
	bad_capsule["checksum"] = U.compute_checksum(bad_capsule)
	var atomic := Bridge.new()
	_assert_error(atomic.restore(initial, matter, bad_capsule, authority, []), "BRIDGE4_CAPSULE_STALE", "forged authority capsule accepted")
	_assert(atomic.status().mode == "UNINITIALIZED", "failed BRIDGE4 restore partially initialized runtime")
	_assert_ok(atomic.restore(initial, matter, capsule, authority, []), "valid pending FULL restore failed after rejected capsule")
	_assert(atomic.status().mode == "FULL" and not atomic.status().pending_proposal.is_empty(), "pending FULL proposal did not survive restore")

	var wrong_restore := Bridge.new().restore(initial, matter, capsule, wrong_authority, [])
	_assert_error(wrong_restore, "BRIDGE4_CAPSULE_STALE", "capsule self-attested stale authority")

	var created := Fixture.create_store(initial)
	_assert_ok(created.result, "canonical store creation failed")
	var desired := Fixture.damaged_snapshot(initial)
	_assert_ok(Fixture.apply_damage(created.store, initial, desired).result, "external canonical damage commit failed")
	var authoritative_after: Dictionary = created.store.get_snapshot(Fixture.CONSTRUCT_ID)
	var event := "event/r1/external-failure"
	_assert_ok(atomic.observe_canonical_successor(authoritative_after, matter, event, 22, authority), "canonical successor after FULL restore failed")
	_assert(atomic.status().event_ledger == [event], "external event ledger wrong after restore continuation")
	_assert(atomic.status().canonical_writes == 0, "repair runtime gained canonical write authority")

func _small_spec(revision: int, disabled: Array, events: Array) -> Dictionary:
	var edges: Array = [
		_edge("edge/r1/in-a", "port/r1/a", "node/r1/0", 1.0),
		_edge("edge/r1/main-left", "node/r1/0", "node/r1/1", 1.2),
		_edge("edge/r1/main-right", "node/r1/1", "port/r1/b", 1.1),
		_edge("edge/r1/alt-in", "port/r1/a", "node/r1/2", 0.7),
		_edge("edge/r1/alt-left", "node/r1/0", "node/r1/2", 0.4),
		_edge("edge/r1/alt-right", "node/r1/2", "node/r1/1", 0.5),
	]
	for edge in edges:
		if disabled.has(String(edge.edge_id)):
			edge.active = false
	return Graph.create("machine/r1-small-full", revision, ["port/r1/a", "port/r1/b"], ["node/r1/0", "node/r1/1", "node/r1/2"], edges, events)

func _edge(id: String, a: String, b: String, conductance: float) -> Dictionary:
	return {"edge_id": id, "node_a": a, "node_b": b, "conductance": conductance, "active": true}

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	var hash := U.canonical_hash({"assertions": assertions, "failures": failures})
	if failures.is_empty():
		print("FABRIC-REPAIR-R1 INTEGRITY: PASS (%d assertions)" % assertions)
		print("FABRIC_REPAIR_R1_INTEGRITY_HASH=%s" % hash)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FABRIC-REPAIR-R1 INTEGRITY: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
