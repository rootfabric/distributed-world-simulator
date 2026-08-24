extends SceneTree

## P6 R3 process worker: one OS process per boot generation.
##
## seed phase:
##   - builds the P6 composition over canonical-owner fixtures;
##   - routes durable operations and persists an authoritative checkpoint via
##     the REAL coordinator/repository into --persistence-root;
##   - leaves crash windows behind (a PENDING reservation and an uncheckpointed
##     committed effect);
##   - writes the seed facts JSON and then IDLES UNTIL KILLED by the parent
##     test: the process dies as a hard crash, never a graceful shutdown.
##
## recover phase:
##   - a FRESH process with NO shared memory: recovers canonical sources, the
##     replay owner and the read-only projection exclusively from the persisted
##     checkpoint bytes;
##   - replays a checkpointed OperationId (must be rejected exactly-once at the
##     canonical boundary), executes the lost intents exactly once, and writes
##     the recovered facts JSON.
##
## The ONLY channel between generations is the authoritative checkpoint file.

const Fixtures = preload("res://tests/runtime/support/p6_r3_canonical_fixtures.gd")
const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const ClosureScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const RouteScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const PersistenceAdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const RepositoryScript = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const CoordinatorScript = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")

const DOMAIN_ID := "p6-domain/outpost-world-state"
const IDLE_TIMEOUT_MS := 120000
const POLL_MS := 100

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-worker][FAIL] %s" % message)


func _arg(name: String) -> String:
	for raw in OS.get_cmdline_user_args():
		var argument := String(raw)
		if argument.begins_with("--%s=" % name):
			return argument.substr(name.length() + 3)
	return ""


func _write_result(path: String, payload: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[p6-r3-worker] cannot write result file: %s" % path)
		quit(3)
		return
	file.store_string(JSON.stringify(payload, "\t", false))
	file.close()


func _projection_checksum(authority) -> String:
	var projection = ProjectionScript.new()
	var configured: Dictionary = projection.configure_from_canonical_sources(authority.owner.export_sources())
	if not bool(configured.get("success", false)):
		return ""
	return projection.compute_checksum()


func _place(operation_id: String, pos: Array, block_type: String) -> Dictionary:
	return {
		"domain_id": DOMAIN_ID,
		"command_kind": "PLACE_BLOCK",
		"operation_id": operation_id,
		"delta": {"op": "place_block", "pos": pos, "block_type": block_type},
	}


func _init() -> void:
	var phase := _arg("phase")
	var persistence_root := _arg("persistence-root")
	var result_file := _arg("result-file")
	if phase.is_empty() or persistence_root.is_empty() or result_file.is_empty():
		push_error("[p6-r3-worker] missing --phase/--persistence-root/--result-file")
		quit(2)
		return
	if phase == "seed":
		_run_seed(persistence_root, result_file)
	elif phase == "recover":
		_run_recover(persistence_root, result_file)
	else:
		push_error("[p6-r3-worker] unknown phase: %s" % phase)
		quit(2)


func _run_seed(persistence_root: String, result_file: String) -> void:
	var authority = Fixtures.CanonicalAuthorityFixture.new(Fixtures.CanonicalSourcesOwner.new())
	var replay = Fixtures.CanonicalReplayFixture.new()
	var repository = RepositoryScript.new()
	if not bool(repository.configure(persistence_root).get("success", false)):
		_write_result(result_file, {"state": "FAILED", "error": "REPOSITORY_CONFIGURE"})
		quit(1)
		return
	var coordinator = CoordinatorScript.new()
	if not bool(coordinator.configure(repository, authority, replay).get("success", false)):
		_write_result(result_file, {"state": "FAILED", "error": "COORDINATOR_CONFIGURE"})
		quit(1)
		return
	var p6_owner = PersistenceAdapterScript.new()
	if not bool(p6_owner.configure(coordinator).get("success", false)):
		_write_result(result_file, {"state": "FAILED", "error": "ADAPTER_CONFIGURE"})
		quit(1)
		return
	var stack: Dictionary = Fixtures.build_stack(RegistryScript, LedgerScript, AdmissionScript, ClosureScript, RouteScript, authority, replay)
	var registry = stack["registry"]
	var route = stack["route"]
	var admission = stack["admission"]
	var ledger = stack["ledger"]
	if not bool(registry.bind("client-session/alice-gen-a", "player/alice", "entity/alice-a").get("success", false)):
		_write_result(result_file, {"state": "FAILED", "error": "BIND"})
		quit(1)
		return

	# durable committed work
	for row in [
		["operation/p6-pr/d1", _place("operation/p6-pr/d1", [1, 0, 1], "stone")],
		["operation/p6-pr/d2", _place("operation/p6-pr/d2", [2, 0, 2], "wood")],
		["operation/p6-pr/d3", {"domain_id": DOMAIN_ID, "command_kind": "CONTAINER_CREATE", "operation_id": "operation/p6-pr/d3", "delta": {"op": "container_create", "container_id": "crate-pr"}}],
		["operation/p6-pr/d4", {"domain_id": DOMAIN_ID, "command_kind": "CONTAINER_ADD_ITEM", "operation_id": "operation/p6-pr/d4", "delta": {"op": "container_add_item", "container_id": "crate-pr", "item": "pickaxe"}}],
	]:
		var routed: Dictionary = route.route_command("client-session/alice-gen-a", String(row[0]), row[1])
		if not (bool(routed.get("success", false)) and String(routed.get("details", {}).get("result", "")) == "EXECUTED"):
			_write_result(result_file, {"state": "FAILED", "error": "SEED_OP", "operation": String(row[0])})
			quit(1)
			return

	# THE durable boundary: authoritative checkpoint bytes via the real stack
	var persisted: Dictionary = p6_owner.persist_checkpoint("checkpoint/p6-r3/process/001", 1, 0, "operation/p6-pr/d4")
	if not bool(persisted.get("success", false)):
		_write_result(result_file, {"state": "FAILED", "error": "PERSIST"})
		quit(1)
		return
	var checkpointed_blocks: Dictionary = (authority.owner.export_sources()["construction"]["blocks"] as Dictionary).duplicate(true)
	var checkpointed_checksum := _projection_checksum(authority)

	# crash window A: PENDING reservation, handler never ran, not checkpointed
	var window_a: Dictionary = admission.admit("player/alice", "operation/p6-pr-wa", DOMAIN_ID, _place("operation/p6-pr-wa", [5, 0, 5], "glass"))
	_assert(bool(window_a.get("success", false)) and ledger.is_pending("player/alice", "operation/p6-pr-wa"), "window A reservation failed")

	# crash window B: canonical effect + replay commit AFTER the checkpoint
	var window_b: Dictionary = admission.admit("player/alice", "operation/p6-pr-wb", DOMAIN_ID, _place("operation/p6-pr-wb", [6, 0, 6], "brick"))
	_assert(bool(window_b.get("success", false)), "window B admission failed")
	var window_b_outcome: Dictionary = (stack["handler"] as Fixtures.CanonicalCommandHandler).execute_command(_place("operation/p6-pr-wb", [6, 0, 6], "brick"))
	_assert(bool(window_b_outcome.get("applied", false)), "window B canonical effect failed")

	_write_result(result_file, {
		"state": "PERSISTED",
		"assertions": assertions,
		"failures": failures,
		"checkpointed_block_count": checkpointed_blocks.size(),
		"checkpointed_blocks": checkpointed_blocks,
		"checkpointed_projection_checksum": checkpointed_checksum,
		"checkpointed_replay_ids": ["operation/p6-pr/d1", "operation/p6-pr/d2", "operation/p6-pr/d3", "operation/p6-pr/d4"],
		"window_a_operation": "operation/p6-pr-wa",
		"window_b_operation": "operation/p6-pr-wb",
	})

	# Hard-crash idle: wait until the parent kills this process.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < IDLE_TIMEOUT_MS:
		OS.delay_msec(POLL_MS)
	# kill never arrived: fail the phase instead of exiting gracefully
	_write_result(result_file, {"state": "FAILED", "error": "KILL_NEVER_ARRIVED"})
	quit(1)


func _run_recover(persistence_root: String, result_file: String) -> void:
	var authority = Fixtures.CanonicalAuthorityFixture.new(Fixtures.CanonicalSourcesOwner.new())
	var replay = Fixtures.CanonicalReplayFixture.new()
	var repository = RepositoryScript.new()
	repository.configure(persistence_root)
	var coordinator = CoordinatorScript.new()
	coordinator.configure(repository, authority, replay)
	var p6_owner = PersistenceAdapterScript.new()
	p6_owner.configure(coordinator)

	var recovered: Dictionary = p6_owner.recover_latest()
	if not bool(recovered.get("success", false)):
		_write_result(result_file, {"state": "FAILED", "error": "RECOVER", "detail": String(p6_owner.get_report()["last_error_code"])})
		quit(1)
		return

	var facts: Dictionary = {
		"state": "RECOVERED",
		"checkpoint_generation": int(recovered.get("details", {}).get("checkpoint", {}).get("generation", -1)),
		"recovered_block_count": authority.owner.block_count(),
		"recovered_blocks": (authority.owner.export_sources()["construction"]["blocks"] as Dictionary).duplicate(true),
		"recovered_projection_checksum": _projection_checksum(authority),
		"recovered_replay_ids": (replay.records as Dictionary).keys(),
		"recovered_containers": (authority.owner.export_sources()["item_graph"]["containers"] as Dictionary).duplicate(true),
	}

	# fresh admission stack: PENDING did not survive (it is not durable truth)
	var stack: Dictionary = Fixtures.build_stack(RegistryScript, LedgerScript, AdmissionScript, ClosureScript, RouteScript, authority, replay)
	var registry = stack["registry"]
	var route = stack["route"]
	var ledger = stack["ledger"]
	facts["pending_survived"] = ledger.is_pending("player/alice", "operation/p6-pr-wa")
	if not bool(registry.bind("client-session/alice-gen-b", "player/alice", "entity/alice-b").get("success", false)):
		_write_result(result_file, {"state": "FAILED", "error": "RECOVER_BIND"})
		quit(1)
		return

	# checkpointed OperationId replay -> exactly-once at the canonical owner
	var replay_d1: Dictionary = route.route_command("client-session/alice-gen-b", "operation/p6-pr/d1", _place("operation/p6-pr/d1", [1, 0, 1], "stone"))
	facts["checkpointed_replay_result"] = String(replay_d1.get("details", {}).get("result", "")) if bool(replay_d1.get("success", false)) else "ROUTE_FAILED"
	facts["checkpointed_replay_error_code"] = String(replay_d1.get("details", {}).get("outcome", {}).get("error_code", ""))
	facts["blocks_after_checkpointed_replay"] = authority.owner.block_count()

	# the lost intents execute exactly once on the recovered world
	var window_a: Dictionary = route.route_command("client-session/alice-gen-b", "operation/p6-pr-wa", _place("operation/p6-pr-wa", [5, 0, 5], "glass"))
	facts["window_a_result"] = String(window_a.get("details", {}).get("result", "")) if bool(window_a.get("success", false)) else "ROUTE_FAILED"
	var window_b: Dictionary = route.route_command("client-session/alice-gen-b", "operation/p6-pr-wb", _place("operation/p6-pr-wb", [6, 0, 6], "brick"))
	facts["window_b_result"] = String(window_b.get("details", {}).get("result", "")) if bool(window_b.get("success", false)) else "ROUTE_FAILED"
	# re-submitting the recovered intents must now be deduplicated
	var window_a_again: Dictionary = route.route_command("client-session/alice-gen-b", "operation/p6-pr-wa", _place("operation/p6-pr-wa", [5, 0, 5], "glass"))
	facts["window_a_retry_result"] = String(window_a_again.get("details", {}).get("result", "")) if bool(window_a_again.get("success", false)) else "ROUTE_FAILED"

	facts["final_block_count"] = authority.owner.block_count()
	facts["final_blocks"] = (authority.owner.export_sources()["construction"]["blocks"] as Dictionary).duplicate(true)
	facts["assertions"] = assertions
	facts["failures"] = failures

	_write_result(result_file, facts)
	quit(0 if failures.is_empty() else 1)
