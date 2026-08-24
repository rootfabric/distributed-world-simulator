extends SceneTree

## P6 R3 LITERAL thirty-minute two-client soak (real time, no acceleration).
##
## Repair-map finding P6-R-007 retracted the R2 simulated soak claim. This
## gate replaces it with a literal wall-clock run:
##   - TWO concurrent client sessions (alice, bob) drive continuous routed
##     command traffic through the full P6 admission boundary for AT LEAST
##     30 minutes of real time;
##   - delegated authoritative checkpoints persist every 60 seconds through
##     the REAL AuthoritativeRecoveryCoordinator/Repository;
##   - client sessions periodically reconnect (fresh identity binds);
##   - after the window, generation B recovers from persisted bytes ONLY and
##     must show: identical canonical truth, committed-record count equal to
##     the executed-operation count (exactly-once), and deduped resubmits.
##
## SCOPE NOTICE: this is a composition-level two-client soak through the P6
## gateway admission boundary. It does NOT claim network-process-level
## graphical client soaking (that remains the accepted M3/M7 harness domain)
## and it does NOT claim any crash-window behaviour beyond what
## test_v0_p6_real_process_restart.gd already proves.

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
const SOAK_DURATION_MS := 30 * 60 * 1000
const ELAPSED_EPSILON_MS := 250
const CHECKPOINT_INTERVAL_MS := 60 * 1000
const RECONNECT_INTERVAL_MS := 7 * 60 * 1000
const OP_PERIOD_MS := 400
const LEDGER_CAPACITY := 65536
const MIN_EXECUTED_OPS := 1200

var assertions := 0
var failures: Array[String] = []
var items_executed := 0
var handler_rejected := 0
# SMOKE MODE: explicit short-window logic validation only. It can never emit
# the literal REAL_TIME stage marker, so it cannot fabricate the WO predicate.
var smoke_mode := false


func _user_arg(name: String) -> String:
	for raw in OS.get_cmdline_user_args():
		var argument := String(raw)
		if argument.begins_with("--%s=" % name):
			return argument.substr(name.length() + 3)
	return ""


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-soak][FAIL] %s" % message)


func _place(operation_id: String, pos: Array, block_type: String) -> Dictionary:
	return {
		"domain_id": DOMAIN_ID,
		"command_kind": "PLACE_BLOCK",
		"operation_id": operation_id,
		"delta": {"op": "place_block", "pos": pos, "block_type": block_type},
	}


func _item(operation_id: String, item: String) -> Dictionary:
	return {
		"domain_id": DOMAIN_ID,
		"command_kind": "CONTAINER_ADD_ITEM",
		"operation_id": operation_id,
		"delta": {"op": "container_add_item", "container_id": "soak-crate", "item": item},
	}


func _build_stack(authority, replay) -> Dictionary:
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(LEDGER_CAPACITY)
	var admission = AdmissionScript.new()
	var closure = ClosureScript.new()
	admission.configure(registry, ledger)
	closure.configure(registry, ledger)
	var handler = Fixtures.CanonicalCommandHandler.new()
	handler.authority = authority
	handler.replay = replay
	var route = RouteScript.new()
	route.configure(registry, ledger, admission, closure, handler)
	return {
		"registry": registry, "ledger": ledger, "admission": admission,
		"closure": closure, "route": route, "handler": handler,
	}


func _projection_checksum(authority) -> String:
	var projection = ProjectionScript.new()
	var configured: Dictionary = projection.configure_from_canonical_sources(authority.owner.export_sources())
	if not bool(configured.get("success", false)):
		return ""
	return projection.compute_checksum()


func _init() -> void:
	# SMOKE MODE: `-- --soak-smoke-seconds=90` runs the identical logic over a
	# short window with compressed intervals. It validates mechanics only and
	# emits V0_P6_SOAK_SMOKE_ONLY_NO_REAL_TIME_CLAIM; it can never produce the
	# literal WO predicate marker.
	var smoke_seconds := _user_arg("soak-smoke-seconds")
	smoke_mode = not smoke_seconds.is_empty()
	var duration_ms := SOAK_DURATION_MS
	var checkpoint_every_ms := CHECKPOINT_INTERVAL_MS
	var reconnect_every_ms := RECONNECT_INTERVAL_MS
	var min_executed_ops := MIN_EXECUTED_OPS
	if smoke_mode:
		duration_ms = maxi(1, int(smoke_seconds.to_float() * 1000.0))
		checkpoint_every_ms = 5000
		reconnect_every_ms = 8000
		min_executed_ops = 10
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("v0-p6-r3-literal-soak")

	var authority = Fixtures.CanonicalAuthorityFixture.new(Fixtures.CanonicalSourcesOwner.new())
	var replay = Fixtures.CanonicalReplayFixture.new()
	var stack := _build_stack(authority, replay)
	var registry = stack["registry"]
	var ledger = stack["ledger"]
	var route = stack["route"]

	var persistence_root := ProjectSettings.globalize_path(
		"res://artifacts/test-results/p6-r3-soak-persistence-%d" % OS.get_process_id())
	var repository = RepositoryScript.new()
	_assert(bool(repository.configure(persistence_root).get("success", false)), "repository configured")
	var coordinator = CoordinatorScript.new()
	_assert(bool(coordinator.configure(repository, authority, replay).get("success", false)), "coordinator configured")
	var p6_owner = PersistenceAdapterScript.new()
	_assert(bool(p6_owner.configure(coordinator).get("success", false)), "p6 persistence adapter configured")

	_assert(bool(registry.bind("client-session/alice-0", "player/alice", "entity/alice-a").get("success", false)), "alice initial bind")
	_assert(bool(registry.bind("client-session/bob-0", "player/bob", "entity/bob-0").get("success", false)), "bob initial bind")

	# shared container for the item-op mix
	_assert(bool(route.route_command("client-session/alice-0", "operation/p6-soak/crate-create", {
		"domain_id": DOMAIN_ID,
		"command_kind": "CONTAINER_CREATE",
		"operation_id": "operation/p6-soak/crate-create",
		"delta": {"op": "container_create", "container_id": "soak-crate"},
	}).get("success", false)), "soak crate created")

	var players := [
		{"name": "alice", "session_index": 0, "next_due_ms": 0, "counter": 0,
			"executed": 0, "last_op": ""},
		{"name": "bob", "session_index": 0, "next_due_ms": OP_PERIOD_MS / 2, "counter": 500000,
			"executed": 0, "last_op": ""},
	]

	var started_ms := Time.get_ticks_msec()
	var next_checkpoint_ms := started_ms + checkpoint_every_ms
	var checkpoint_count := 0
	var reconnects_done := {"alice": 0, "bob": 0}

	while Time.get_ticks_msec() - started_ms < duration_ms:
		var now_ms := Time.get_ticks_msec()

		# periodic delegated durability (generation strictly increments)
		if now_ms >= next_checkpoint_ms:
			checkpoint_count += 1
			var last_op_for_checkpoint := String(players[1]["last_op"])
			if last_op_for_checkpoint.is_empty():
				last_op_for_checkpoint = "operation/p6-soak/crate-create"
			var persisted: Dictionary = p6_owner.persist_checkpoint(
				"checkpoint/p6-r3/soak/%03d" % checkpoint_count,
				checkpoint_count, checkpoint_count - 1, last_op_for_checkpoint)
			_assert(bool(persisted.get("success", false)), "periodic checkpoint %d persisted" % checkpoint_count)
			next_checkpoint_ms += checkpoint_every_ms

		# periodic session reconnects (staggered: alice at even windows, bob odd).
		# A LIVE logical player must move via rebind_on_transport_change(old->new):
		# a plain bind() of a second session fails closed with
		# LOGICAL_PLAYER_ALREADY_LIVE by design.
		for pi in players.size():
			var p: Dictionary = players[pi]
			var window := int((now_ms - started_ms) / float(reconnect_every_ms))
			if window > int(p["session_index"]) and window % 2 == pi:
				var old_session := "client-session/%s-%d" % [String(p["name"]), int(p["session_index"])]
				var new_session := "client-session/%s-%d" % [String(p["name"]), window]
				var rebound: Dictionary = registry.rebind_on_transport_change(old_session, new_session)
				if bool(rebound.get("success", false)):
					p["session_index"] = window
					reconnects_done[String(p["name"])] = int(reconnects_done[String(p["name"])]) + 1
				else:
					# retry on a later loop iteration with the same target window;
					# do NOT advance session_index on failure
					p["next_due_ms"] = mini(int(p["next_due_ms"]) + OP_PERIOD_MS * 4, now_ms + OP_PERIOD_MS * 4)
					_assert(false, "%s reconnect rebind #%d failed (%s)" % [
						String(p["name"]), window, String(rebound.get("error_code", "?"))])

		# continuous two-client command traffic
		for pi in players.size():
			var p: Dictionary = players[pi]
			if now_ms < int(p["next_due_ms"]):
				continue
			p["next_due_ms"] = now_ms + OP_PERIOD_MS + rng.randi_range(-80, 80)
			var counter := int(p["counter"])
			p["counter"] = counter + 1
			var session := "client-session/%s-%d" % [String(p["name"]), int(p["session_index"])]
			var op_id := "operation/p6-soak/%s/%06d" % [String(p["name"]), counter]
			var command: Dictionary
			if counter % 10 == 9:
				command = _item(op_id, "log-%06d" % counter)
			else:
				var x := counter % 48
				var y := (counter / 48) % 12
				var z := pi * 24 + (counter / 576) % 24
				command = _place(op_id, [x, y, z], ["stone", "wood", "brick", "glass"][counter % 4])
			var routed: Dictionary = route.route_command(session, op_id, command)
			# route contract: success=true carries result EXECUTED|ALREADY_APPLIED;
			# a handler-level rejection lives in details.outcome.applied=false while
			# the route still reports EXECUTED (the OperationId is consumed).
			if bool(routed.get("success", false)):
				var result := String(routed.get("details", {}).get("result", ""))
				if result == "EXECUTED":
					if bool(routed.get("details", {}).get("outcome", {}).get("applied", false)):
						p["executed"] = int(p["executed"]) + 1
						p["last_op"] = op_id
						if counter % 10 == 9:
							items_executed += 1
					else:
						handler_rejected += 1
				else:
					_assert(false, "%s got ALREADY_APPLIED for a fresh id %s" % [String(p["name"]), op_id])
			else:
				_assert(false, "%s route failed (%s) for %s" % [
					String(p["name"]), String(routed.get("error_code", "?")), op_id])

		OS.delay_msec(20)

	var elapsed_ms := Time.get_ticks_msec() - started_ms
	print("[p6-r3-soak] window closed: elapsed=%d ms (%.2f min), checkpoints=%d, reconnects=%s" % [
		elapsed_ms, elapsed_ms / 60000.0, checkpoint_count, str(reconnects_done)])

	# --- literal real-time requirements (skipped floor checks in SMOKE mode) ---
	if not smoke_mode:
		_assert(elapsed_ms >= SOAK_DURATION_MS - ELAPSED_EPSILON_MS, "soak ran at least 30 real-time minutes")
		_assert(checkpoint_count >= 28, "periodic checkpoints covered the whole window")
	var total_executed := int(players[0]["executed"]) + int(players[1]["executed"])
	if not smoke_mode:
		_assert(total_executed >= min_executed_ops, "continuous traffic volume reached (%d executed)" % total_executed)
	else:
		print("[p6-r3-soak][SMOKE] traffic executed=%d (floor skipped)" % total_executed)

	# --- canonical truth consistency at the end of generation A ---
	var final_checksum := _projection_checksum(authority)
	_assert(final_checksum.length() == 64, "final projection checksum computed")
	var final_blocks := (authority.owner.export_sources()["construction"]["blocks"] as Dictionary).size()
	var committed_records := (replay.records as Dictionary).size()
	# +1 accounts for operation/p6-soak/crate-create committed before traffic
	_assert(committed_records == total_executed + 1, "committed replay records == executed ops + crate (%d == %d)" % [committed_records, total_executed + 1])

	# --- final durable boundary ---
	var final_persisted: Dictionary = p6_owner.persist_checkpoint("checkpoint/p6-r3/soak/final", checkpoint_count + 1, checkpoint_count, String(players[0]["last_op"]))
	_assert(bool(final_persisted.get("success", false)), "final checkpoint persisted")

	# --- generation B: recover from bytes ONLY and verify ---
	var authority_b = Fixtures.CanonicalAuthorityFixture.new(Fixtures.CanonicalSourcesOwner.new())
	var replay_b = Fixtures.CanonicalReplayFixture.new()
	var repository_b = RepositoryScript.new()
	repository_b.configure(persistence_root)
	var coordinator_b = CoordinatorScript.new()
	coordinator_b.configure(repository_b, authority_b, replay_b)
	var p6_owner_b = PersistenceAdapterScript.new()
	p6_owner_b.configure(coordinator_b)
	var recovered: Dictionary = p6_owner_b.recover_latest()
	_assert(bool(recovered.get("success", false)), "generation B recovered from bytes")
	if bool(recovered.get("success", false)):
		_assert(int(authority_b.owner.block_count()) == final_blocks, "recovered block count == end-of-soak truth")
		_assert(_projection_checksum(authority_b) == final_checksum, "recovered projection checksum == end-of-soak truth")
		_assert((replay_b.records as Dictionary).size() == committed_records, "recovered replay records == committed records")
		var containers: Dictionary = authority_b.owner.export_sources()["item_graph"]["containers"]
		_assert((containers.get("soak-crate", []) as Array).size() == items_executed, "soak crate items survived")
		# resampled dedup across the process/delegation boundary: exact original
		# first alice command (counter=1 -> pos [1,0,0], block wood)
		var stack_b := _build_stack(authority_b, replay_b)
		_assert(bool(stack_b["registry"].bind(
			"client-session/alice-b", "player/alice", "entity/alice-a").get("success", false)),
			"generation B alice bind for dedup probe")
		var first_op := "operation/p6-soak/alice/000001"
		var dup: Dictionary = stack_b["route"].route_command(
			"client-session/alice-b", first_op,
			_place(first_op, [1, 0, 0], "wood"))
		# route-level EXECUTED means admitted+handled; the canonical
		# exactly-once verdict lives in outcome.applied/outcome.error_code
		var dup_outcome: Dictionary = Dictionary(dup.get("details", {}).get("outcome", {}))
		_assert(bool(dup.get("success", false)), "dedup probe routed")
		_assert(not bool(dup_outcome.get("applied", true)), "resubmitted soaked op not re-applied after recovery")
		_assert(String(dup_outcome.get("error_code", "")) == "ALREADY_COMMITTED_AT_CANONICAL_OWNER",
			"dedup probe rejected by canonical owner (got %s)" % String(dup_outcome.get("error_code", "?")))
		_assert(int(authority_b.owner.block_count()) == final_blocks, "dedup probe created no duplicate block")

	print("[p6-r3-soak] totals: applied=%d handler_rejected=%d committed=%d blocks=%d crate_items=%d" % [
		total_executed, handler_rejected, committed_records, final_blocks,
		(authority.owner.export_sources()["item_graph"]["containers"].get("soak-crate", []) as Array).size()])

	if failures.is_empty():
		print("[p6-r3-soak] all %d assertions passed (literal %.2f real-time minutes, two concurrent client sessions)" % [assertions, elapsed_ms / 60000.0])
		if smoke_mode:
			print("[p6-r3-soak][stage] V0_P6_SOAK_SMOKE_ONLY_NO_REAL_TIME_CLAIM")
			print("[p6-r3-soak][scope] SMOKE MODE — mechanics validation only; NOT a soak predicate")
		else:
			print("[p6-r3-soak][stage] V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS_REAL_TIME")
			print("[p6-r3-soak][scope] composition-level two-session soak; network-process graphical soak remains the accepted M3/M7 harness domain")
		quit(0)
	else:
		print("[p6-r3-soak] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		for failure in failures:
			print("[p6-r3-soak][FAIL] %s" % failure)
		quit(1)
