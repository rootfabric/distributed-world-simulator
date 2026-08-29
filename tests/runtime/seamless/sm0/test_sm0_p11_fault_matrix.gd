extends SceneTree

const Model = preload("res://scripts/runtime/seamless/sm0/sm0_p11_simultaneous_crossing_model.gd")

var _assertions := 0
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var model = Model.new()
	_check_success(model.setup(7), "setup")

	_check_success(model.seed_aggregate("player/p11/one", "logical/p11/one", "PLAYER", "authority/sm0/a", 1), "seed p1")
	_check_success(model.seed_aggregate("player/p11/two", "logical/p11/two", "PLAYER", "authority/sm0/b", 1), "seed p2")
	_check_error(model.seed_aggregate("player/p11/duplicate", "logical/p11/one", "PLAYER", "authority/sm0/c", 1), "SM0_P11_IDENTITY_DUPLICATE", "duplicate identity rejected")

	# Simultaneous crossing pair: P1 A->B while P2 B->A.
	_check_success(model.begin_transfer("p11/swap/p1", "player/p11/one", "authority/sm0/a", "authority/sm0/b", 1, 7), "prepare p1")
	_check_success(model.begin_transfer("p11/swap/p2", "player/p11/two", "authority/sm0/b", "authority/sm0/a", 1, 7), "prepare p2")
	_check(bool(model.snapshot("player/p11/one").get("frozen", false)), "p1 frozen")
	_check(bool(model.snapshot("player/p11/two").get("frozen", false)), "p2 frozen")
	_check_error(model.interact("p11/frozen/use", "player/p11/one", "authority/sm0/a", 1), "SM0_P11_INTERACTION_SOURCE_FROZEN", "frozen source rejects interaction")
	_check_success(model.commit_transfer("p11/swap/p2"), "commit p2 first")
	_check_success(model.commit_transfer("p11/swap/p1"), "commit p1 second")
	_check_equal(String(model.snapshot("player/p11/one").get("owner_authority_id", "")), "authority/sm0/b", "p1 owner B")
	_check_equal(String(model.snapshot("player/p11/two").get("owner_authority_id", "")), "authority/sm0/a", "p2 owner A")
	_check_equal(int(model.snapshot("player/p11/one").get("authority_epoch", 0)), 2, "p1 epoch 2")
	_check_equal(int(model.snapshot("player/p11/two").get("authority_epoch", 0)), 2, "p2 epoch 2")
	_check_equal(String(model.snapshot("player/p11/one").get("identity_id", "")), "logical/p11/one", "p1 identity stable")
	_check_equal(String(model.snapshot("player/p11/two").get("identity_id", "")), "logical/p11/two", "p2 identity stable")
	_check_equal(model.active_writer_count("player/p11/one"), 1, "p1 one writer")
	_check_equal(model.active_writer_count("player/p11/two"), 1, "p2 one writer")

	# Exact duplicate commit behaves as idempotent fast-commit replay.
	var replay := model.commit_transfer("p11/swap/p1")
	_check_success(replay, "duplicate commit replay")
	_check(bool(Dictionary(replay.get("details", {})).get("replay", false)), "duplicate commit marked replay")
	_check_equal(int(model.snapshot("player/p11/one").get("authority_epoch", 0)), 2, "duplicate commit does not advance epoch")
	_check_error(model.begin_transfer("p11/swap/p1", "player/p11/two", "authority/sm0/a", "authority/sm0/c", 2, 7), "SM0_P11_OPERATION_REUSE_CONFLICT", "operation id conflict fails closed")

	# Stale owner and stale topology cannot mutate or initiate transfer.
	_check_error(model.interact("p11/stale-owner/use", "player/p11/one", "authority/sm0/a", 1), "SM0_P11_INTERACTION_NOT_OWNER", "stale ghost interaction rejected")
	_check_success(model.set_topology_revision(8), "topology advances")
	_check_error(model.begin_transfer("p11/stale-topology", "player/p11/one", "authority/sm0/b", "authority/sm0/c", 2, 7), "SM0_P11_STALE_TOPOLOGY_REVISION", "stale topology rejected")
	_check(not bool(model.snapshot("player/p11/one").get("frozen", false)), "stale topology leaves source unfrozen")

	# Target unavailability must not create ownership or freeze unrelated aggregate.
	_check_success(model.set_authority_available("authority/sm0/c", false), "C unavailable")
	_check_error(model.begin_transfer("p11/unavailable-target", "player/p11/one", "authority/sm0/b", "authority/sm0/c", 2, 8), "SM0_P11_TARGET_UNAVAILABLE", "unavailable target rejected")
	_check_equal(String(model.snapshot("player/p11/one").get("owner_authority_id", "")), "authority/sm0/b", "unavailable target cannot acquire ownership")
	_check_success(model.interact("p11/unrelated/use", "player/p11/two", "authority/sm0/a", 2), "unrelated authority continues")
	_check_success(model.set_authority_available("authority/sm0/c", true), "C restored")

	# Injected target commit failure rolls back source and replays deterministically.
	_check_success(model.seed_aggregate("item/p11/rollback", "item-id/p11/rollback", "ITEM", "authority/sm0/c", 1), "seed rollback item")
	_check_success(model.begin_transfer("p11/rollback/1", "item/p11/rollback", "authority/sm0/c", "authority/sm0/b", 1, 8), "prepare rollback")
	var failed_commit := model.commit_transfer("p11/rollback/1", true)
	_check_error(failed_commit, "SM0_P11_INJECTED_TARGET_COMMIT_FAILURE", "injected failure")
	_check_equal(String(model.snapshot("item/p11/rollback").get("owner_authority_id", "")), "authority/sm0/c", "rollback owner restored")
	_check_equal(int(model.snapshot("item/p11/rollback").get("authority_epoch", 0)), 1, "rollback epoch unchanged")
	_check(not bool(model.snapshot("item/p11/rollback").get("frozen", false)), "rollback unfreezes source")
	var failed_replay := model.commit_transfer("p11/rollback/1", true)
	_check_error(failed_replay, "SM0_P11_INJECTED_TARGET_COMMIT_FAILURE", "failed operation replay deterministic")
	_check(bool(Dictionary(failed_replay.get("details", {})).get("replay", false)), "failed replay marked replay")

	# Foreign replicas remain presentation-only.
	var projection := model.project_foreign("authority/sm0/a", "item/p11/rollback")
	_check_success(projection, "foreign projection")
	var projection_details: Dictionary = Dictionary(projection.get("details", {}))
	_check(bool(projection_details.get("read_only", false)), "foreign projection read-only")
	_check(not bool(projection_details.get("canonical_write_allowed", true)), "foreign projection cannot write canonical")
	_check_error(model.attempt_projection_mutation(projection_details), "SM0_P11_FOREIGN_REPLICA_READ_ONLY", "foreign mutation rejected")

	# Second simultaneous route shape: A->B while B->C.
	_check_success(model.seed_aggregate("player/p11/three", "logical/p11/three", "PLAYER", "authority/sm0/a", 1), "seed p3")
	_check_success(model.seed_aggregate("player/p11/four", "logical/p11/four", "PLAYER", "authority/sm0/b", 1), "seed p4")
	_check_success(model.begin_transfer("p11/fanout/p3", "player/p11/three", "authority/sm0/a", "authority/sm0/b", 1, 8), "prepare p3 A-B")
	_check_success(model.begin_transfer("p11/fanout/p4", "player/p11/four", "authority/sm0/b", "authority/sm0/c", 1, 8), "prepare p4 B-C")
	_check_success(model.commit_transfer("p11/fanout/p4"), "commit p4")
	_check_success(model.commit_transfer("p11/fanout/p3"), "commit p3")
	_check_equal(String(model.snapshot("player/p11/three").get("owner_authority_id", "")), "authority/sm0/b", "p3 owner B")
	_check_equal(String(model.snapshot("player/p11/four").get("owner_authority_id", "")), "authority/sm0/c", "p4 owner C")
	_check_equal(model.active_writer_count("player/p11/three"), 1, "p3 one writer")
	_check_equal(model.active_writer_count("player/p11/four"), 1, "p4 one writer")
	_check_equal(model.pending_count(), 0, "no transfer leak")

	# Projection fabric fault matrix: delayed/reordered deltas and source dropout are isolated.
	_check_success(model.accept_projection("authority/sm0/a", 1, 1, "checksum-a1", "entity/p11/a"), "accept A1")
	_check_success(model.accept_projection("authority/sm0/b", 1, 1, "checksum-b1", "entity/p11/b"), "accept B1")
	_check_success(model.accept_projection("authority/sm0/c", 1, 1, "checksum-c1", "entity/p11/c"), "accept C1")
	_check_success(model.accept_projection("authority/sm0/a", 1, 3, "checksum-a3", "entity/p11/a"), "accept A3")
	_check_error(model.accept_projection("authority/sm0/a", 1, 2, "checksum-a2", "entity/p11/a"), "SM0_P11_PROJECTION_SEQUENCE_STALE", "delayed A2 rejected")
	_check_error(model.accept_projection("authority/sm0/a", 1, 3, "mutated-a3", "entity/p11/a"), "SM0_P11_PROJECTION_SAME_SEQUENCE_MUTATION", "same-sequence mutation rejected")
	_check_success(model.mark_projection_unavailable("authority/sm0/a", 1), "A projection source disconnect")
	var composed := model.compose_projection_view()
	_check_success(composed, "compose after A dropout")
	var details: Dictionary = Dictionary(composed.get("details", {}))
	_check(Array(details.get("degraded_sources", [])).has("authority/sm0/a"), "A only is degraded")
	_check(_has_projection(Array(details.get("entities", [])), "entity/p11/b"), "B survives A dropout")
	_check(_has_projection(Array(details.get("entities", [])), "entity/p11/c"), "C survives A dropout")
	_check(not _has_projection(Array(details.get("entities", [])), "entity/p11/a"), "A dynamic removed on dropout")
	_check(not bool(details.get("canonical_state_generated", true)), "projection loss cannot synthesize canonical state")

	_finish()

func _has_projection(values: Array, entity_id: String) -> bool:
	for raw in values:
		if raw is Dictionary and String(Dictionary(raw).get("entity_id", "")) == entity_id:
			return true
	return false

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), "%s expected success, got %s" % [label, String(result.get("error_code", ""))])

func _check_error(result: Dictionary, error_code: String, label: String) -> void:
	_check(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s expected %s, got %s" % [label, error_code, String(result.get("error_code", ""))])

func _check_equal(actual, expected, label: String) -> void:
	_check(actual == expected, "%s expected %s got %s" % [label, str(expected), str(actual)])

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)

func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			push_error("P11 assertion failed: %s" % failure)
		print("SM0 P11 deterministic fault matrix: FAIL (%d assertions / %d failures)" % [_assertions, _failures.size()])
		quit(1)
		return
	print("SM0 P11 deterministic fault matrix: PASS (%d assertions)" % _assertions)
	quit(0)
