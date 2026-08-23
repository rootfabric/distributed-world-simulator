extends SceneTree

## P6.10 L0 stage proof: systematic fault/race matrix for the persistent
## shared outpost stack (P6.1-P6.9 composed end to end).
##
## Six fault scenarios, each following setup -> fault injection -> invariant
## assertions (no corruption, no duplicates, no lost data):
##   1. reconnect during active writes: mid-write transport change -> rebind;
##   2. simultaneous same-block placement: exactly-one deterministic winner,
##      loser consumed with a clean POSITION_OCCUPIED rejection;
##   3. shadow rejection during an active session: every shadow write surface
##      fails closed with SHADOW_CANNOT_WRITE, canonical file untouched;
##   4. ledger replay under concurrent sessions for one logical player:
##      stale session dead, live session deduplicates through the ledger;
##   5. persistence during active writes: interleaved saves stay consistent,
##      no partial write, final load matches final checksum;
##   6. restart during pending operations: both crash windows (before/after
##      the handler) recover exactly once through ledger snapshot restore.

const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const AdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const RouteScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const OwnerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const ShadowScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")

const BASE_DIR := "user://p6_fault_race_matrix"
const S3_PATH := BASE_DIR + "/s3_canonical.json"
const S5_PATH := BASE_DIR + "/s5_canonical.json"
const S6_PATH := BASE_DIR + "/s6_canonical.json"
const DOMAIN_ID := "p6-domain/outpost-world-state"
const WORLD_SEED := 9010

const ALICE := "player/alice"
const BOB := "player/bob"

var assertions := 0
var failures: Array[String] = []


class CountingHandler:
	extends RefCounted

	var outpost = null
	var executions: int = 0

	func execute_command(command: Dictionary) -> Dictionary:
		executions = int(executions) + 1
		var delta: Dictionary = command.get("delta", {})
		var applied: bool = outpost.apply_delta(delta)
		return {"applied": applied, "error_code": String(outpost.get_report()["last_error_code"])}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.10-fault-race-matrix][FAIL] %s" % message)


func _assert_bool(result: Dictionary, message: String) -> bool:
	if not bool(result.get("success", false)):
		_assert(false, message)
		return false
	return true


## Route-level success AND the handler actually applied the mutation.
func _assert_applied(outcome: Dictionary, message: String) -> void:
	if _assert_bool(outcome, message):
		var details: Dictionary = outcome["details"]
		_assert(String(details["result"]) == "EXECUTED", "%s (result=%s)" % [message, String(details.get("result", ""))])
		_assert(bool(details["outcome"]["applied"]), "%s (handler did not apply)" % message)


func _assert_replayed(outcome: Dictionary, message: String) -> void:
	if _assert_bool(outcome, message):
		_assert(String(outcome["details"]["result"]) == "ALREADY_APPLIED", "%s (result=%s)" % [message, String(outcome["details"].get("result", ""))])


func _assert_rejected(outcome: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(outcome.get("success", false)) and String(outcome.get("error_code", "")) == error_code,
			"%s (got %s)" % [message, String(outcome.get("error_code", "<success>"))])


## One fresh server boot: empty outpost + full P6 admission/routing stack.
func _boot_stack() -> Dictionary:
	var outpost = StateScript.new()
	outpost.set_world_seed(WORLD_SEED)
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(256)
	var admission = AdmissionScript.new()
	admission.configure(registry, ledger)
	var adapter = AdapterScript.new()
	adapter.configure(registry, ledger)
	var handler = CountingHandler.new()
	handler.outpost = outpost
	var route = RouteScript.new()
	route.configure(registry, ledger, admission, adapter, handler)
	return {
		"outpost": outpost,
		"registry": registry,
		"ledger": ledger,
		"admission": admission,
		"route": route,
		"handler": handler,
	}


func _bind(stack: Dictionary, session: String, logical: String, entity: String) -> void:
	var bound: Dictionary = stack["registry"].bind(session, logical, entity)
	_assert(bool(bound.get("success", false)), "bind failed: %s -> %s" % [session, logical])


func _command(kind: String, delta: Dictionary) -> Dictionary:
	return {"domain_id": DOMAIN_ID, "command_kind": kind, "delta": delta}


func _place(pos: Array, block_type: String) -> Dictionary:
	return _command("PLACE_BLOCK", {"op": "place_block", "pos": pos, "block_type": block_type})


func _destroy_stack(stack: Dictionary) -> void:
	# Server process death: NO live object survives the crash.
	stack["outpost"] = null
	stack["registry"] = null
	stack["ledger"] = null
	stack["admission"] = null
	stack["route"] = null
	stack["handler"] = null
	stack.clear()


## ============================================================================
## Scenario 1: reconnect during active writes
## ============================================================================
func _scenario_reconnect_during_writes() -> void:
	var stack := _boot_stack()
	var registry = stack["registry"]
	var route = stack["route"]
	var outpost = stack["outpost"]
	var handler = stack["handler"]
	var s_old := "client-session/alice-s1-old"
	var s_new := "client-session/alice-s1-new"
	_bind(stack, s_old, ALICE, "entity/alice-main")
	for row in [["op/s1-1", _place([1, 0, 1], "stone")], ["op/s1-2", _place([2, 0, 2], "wood")], ["op/s1-3", _place([3, 0, 3], "brick")]]:
		var cmd: Dictionary = row[1]
		_assert_applied(route.route_command(s_old, String(row[0]), cmd), "s1 pre-disconnect op %s not applied" % String(row[0]))
	_assert(outpost.block_count() == 3, "s1 pre-disconnect block count wrong")
	# FAULT: the client comes back on a FRESH session id before the server has
	# processed the transport change -> clean rejection, no corruption.
	_assert_rejected(route.route_command(s_new, "op/s1-2", _place([2, 0, 2], "wood")), "UNKNOWN_SESSION", "s1 early new-session route not rejected")
	_assert(outpost.block_count() == 3, "s1 early rejected route corrupted state")
	# reconnect via rebind: logical identity preserved verbatim
	var rebind: Dictionary = registry.rebind_on_transport_change(s_old, s_new)
	if _assert_bool(rebind, "s1 rebind failed"):
		_assert(String(rebind["details"]["preserved_logical_player_id"]) == ALICE, "s1 rebind lost logical identity")
	# no lost writes: every pre-disconnect write is still canonical truth
	for pos_key in ["1,0,1", "2,0,2", "3,0,3"]:
		_assert(outpost.has_block(pos_key), "s1 lost block %s across reconnect" % pos_key)
	# no duplicates: client retry of op/s1-2 after reconnect deduplicates
	_assert_replayed(route.route_command(s_new, "op/s1-2", _place([2, 0, 2], "wood")), "s1 post-reconnect replay not deduplicated")
	_assert(outpost.block_count() == 3, "s1 replay duplicated a block")
	# writes continue on the new session without loss
	_assert_applied(route.route_command(s_new, "op/s1-4", _place([4, 0, 4], "glass")), "s1 post-reconnect write not applied")
	_assert(outpost.block_count() == 4, "s1 final block count wrong")
	# the stale session is dead: clean rejection, no state change
	_assert_rejected(route.route_command(s_old, "op/s1-5", _place([5, 0, 5], "stone")), "UNKNOWN_SESSION", "s1 stale session still routed")
	_assert(outpost.block_count() == 4, "s1 stale route mutated state")
	_assert(int(handler.executions) == 4, "s1 handler execution count wrong: %d" % int(handler.executions))
	_destroy_stack(stack)


## ============================================================================
## Scenario 2: simultaneous same-block placement (deterministic winner)
## ============================================================================
func _scenario_same_block_race() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var outpost = stack["outpost"]
	var handler = stack["handler"]
	var s_alice := "client-session/alice-s2"
	var s_bob := "client-session/bob-s2"
	_bind(stack, s_alice, ALICE, "entity/alice-main")
	_bind(stack, s_bob, BOB, "entity/bob-main")
	var race_pos: Array = [7, 0, 7]
	# FAULT: two players race the same position. Routing order on the single
	# server authority is the deterministic tiebreaker.
	var a: Dictionary = route.route_command(s_alice, "op/race-a", _place(race_pos, "stone"))
	var b: Dictionary = route.route_command(s_bob, "op/race-b", _place(race_pos, "wood"))
	_assert_applied(a, "s2 first placer not applied")
	if _assert_bool(b, "s2 loser route failed"):
		_assert(String(b["details"]["result"]) == "EXECUTED", "s2 loser route not consumed")
		_assert(bool(b["details"]["outcome"]["applied"]) == false, "s2 loser wrongly applied")
		_assert(String(b["details"]["outcome"]["error_code"]) == "POSITION_OCCUPIED", "s2 loser rejection not clean")
	# exactly one block wins the position, deterministically
	_assert(outpost.block_type_at("7,0,7") == "stone", "s2 winner block wrong")
	_assert(outpost.block_count() == 1, "s2 duplicate block at race position")
	# loser retry with the SAME operation id: consumed exactly once, no second execution
	_assert_replayed(route.route_command(s_bob, "op/race-b", _place(race_pos, "wood")), "s2 loser retry not deduplicated")
	_assert(outpost.block_count() == 1, "s2 loser retry mutated state")
	_assert(int(handler.executions) == 2, "s2 handler execution count wrong: %d" % int(handler.executions))
	# the loser can still make progress on a free position
	_assert_applied(route.route_command(s_bob, "op/race-b-2", _place([8, 0, 8], "wood")), "s2 loser follow-up not applied")
	_assert(outpost.block_count() == 2, "s2 final block count wrong")
	_assert(int(stack["ledger"].get_report()["applied_count"]) == 3, "s2 ledger applied count wrong")
	_destroy_stack(stack)


## ============================================================================
## Scenario 3: shadow rejection during an active session
## ============================================================================
func _scenario_shadow_rejection_during_session() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var outpost = stack["outpost"]
	var s_alice := "client-session/alice-s3"
	_bind(stack, s_alice, ALICE, "entity/alice-main")
	var owner = OwnerScript.new()
	_assert_applied(route.route_command(s_alice, "op/s3-1", _place([31, 0, 31], "stone")), "s3 op1 not applied")
	_assert_applied(route.route_command(s_alice, "op/s3-2", _place([32, 0, 32], "wood")), "s3 op2 not applied")
	_assert(owner.save(outpost, S3_PATH), "s3 initial save failed")
	var active_checksum: String = outpost.compute_checksum()
	var shadow = ShadowScript.new()
	var recon: Dictionary = shadow.configure(owner, S3_PATH)
	if _assert_bool(recon, "s3 shadow reconstruction failed"):
		_assert(String(recon["details"]["checksum"]) == active_checksum, "s3 shadow checksum diverged")
	# FAULT: shadow write attempts while the active authority is live
	var w1: Dictionary = shadow.apply_delta({"op": "place_block", "pos": [33, 0, 33], "block_type": "brick"})
	_assert(not bool(w1.get("success", true)) and String(w1.get("error_code", "")) == "SHADOW_CANNOT_WRITE", "s3 shadow apply_delta not rejected")
	var w2: Dictionary = shadow.persist_state(S3_PATH)
	_assert(not bool(w2.get("success", true)) and String(w2.get("error_code", "")) == "SHADOW_CANNOT_WRITE", "s3 shadow persist_state not rejected")
	var w3: Dictionary = shadow.deserialize({"schema": "planet_simulator.p6_outpost_state.v1"})
	_assert(not bool(w3.get("success", true)) and String(w3.get("error_code", "")) == "SHADOW_CANNOT_WRITE", "s3 shadow deserialize not rejected")
	# no corruption: the canonical file still holds the pre-fault truth exactly
	var reloaded: Dictionary = owner.load(S3_PATH)
	if _assert_bool(reloaded, "s3 canonical reload failed after shadow writes"):
		_assert(String(reloaded["details"]["checksum"]) == active_checksum, "s3 canonical file corrupted by shadow writes")
	_assert(not outpost.has_block("33,0,33"), "s3 shadow write leaked into active state")
	_assert(shadow.get_block([33, 0, 33]).get("error_code", "") == "UNKNOWN_BLOCK", "s3 shadow write landed in shadow view")
	# the active authority is unaffected and keeps accepting + persisting work
	_assert_applied(route.route_command(s_alice, "op/s3-4", _place([34, 0, 34], "glass")), "s3 active post-fault write not applied")
	_assert(owner.save(outpost, S3_PATH), "s3 post-fault save failed")
	var final_load: Dictionary = owner.load(S3_PATH)
	if _assert_bool(final_load, "s3 final load failed"):
		_assert(String(final_load["details"]["checksum"]) == outpost.compute_checksum(), "s3 final checksum mismatch")
	_assert(outpost.block_count() == 3, "s3 final block count wrong")
	# shadow reads stay read-only consistent; a defensive copy cannot poison truth
	var copy = shadow.get_state()
	_assert(copy != null, "s3 shadow get_state returned null")
	if copy != null:
		_assert(copy.apply_delta({"op": "place_block", "pos": [35, 0, 35], "block_type": "stone"}), "s3 defensive copy not mutable")
		_assert(shadow.get_block([35, 0, 35]).get("error_code", "") == "UNKNOWN_BLOCK", "s3 copy mutation poisoned shadow truth")
	_assert(String(shadow.get_mode()) == "SHADOW", "s3 shadow mode drifted")
	_destroy_stack(stack)


## ============================================================================
## Scenario 4: ledger replay under concurrent sessions for one logical player
## ============================================================================
func _scenario_ledger_concurrent_sessions() -> void:
	var stack := _boot_stack()
	var registry = stack["registry"]
	var route = stack["route"]
	var ledger = stack["ledger"]
	var outpost = stack["outpost"]
	var handler = stack["handler"]
	var s1 := "client-session/alice-s4-a"
	var s2 := "client-session/alice-s4-b"
	_bind(stack, s1, ALICE, "entity/alice-main")
	_assert_applied(route.route_command(s1, "op/s4-x", _place([21, 0, 21], "stone")), "s4 op x not applied")
	# a SECOND live session for the same logical player is fail-closed
	var dup_bind: Dictionary = registry.bind(s2, ALICE, "entity/alice-main")
	_assert(not bool(dup_bind.get("success", true)) and String(dup_bind.get("error_code", "")) == "LOGICAL_PLAYER_ALREADY_LIVE", "s4 duplicate live bind not rejected")
	# the only legal concurrency path: transport change supersedes s1 with s2
	_assert(bool(registry.rebind_on_transport_change(s1, s2).get("success", false)), "s4 rebind failed")
	# ledger keys are (logical, operation): op x replays as applied through s2
	_assert_replayed(route.route_command(s2, "op/s4-x", _place([21, 0, 21], "stone")), "s4 op x replay through new session not deduplicated")
	_assert(int(handler.executions) == 1, "s4 op x executed twice: %d" % int(handler.executions))
	# in-flight duplicate of a NEW op across the transport change: the stale
	# session is dead, the live session executes it exactly once
	_assert_rejected(route.route_command(s1, "op/s4-y", _place([22, 0, 22], "stone")), "UNKNOWN_SESSION", "s4 stale session routed op y")
	_assert_applied(route.route_command(s2, "op/s4-y", _place([22, 0, 22], "stone")), "s4 op y not applied")
	_assert_replayed(route.route_command(s2, "op/s4-y", _place([22, 0, 22], "stone")), "s4 op y duplicate not deduplicated")
	# invariants: no duplicates, no lost data, ledger is the dedup oracle
	_assert(outpost.block_count() == 2, "s4 final block count wrong")
	_assert(outpost.has_block("21,0,21") and outpost.has_block("22,0,22"), "s4 lost a block across sessions")
	_assert(int(handler.executions) == 2, "s4 handler execution count wrong: %d" % int(handler.executions))
	_assert(int(ledger.get_report()["applied_count"]) == 2, "s4 ledger applied count wrong")
	_assert(int(route.get_report()["counters"]["replayed"]) == 2, "s4 route replay counter wrong")
	_destroy_stack(stack)


## ============================================================================
## Scenario 5: persistence during active writes
## ============================================================================
func _scenario_persistence_during_writes() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var outpost = stack["outpost"]
	var owner = OwnerScript.new()
	var s_alice := "client-session/alice-s5"
	_bind(stack, s_alice, ALICE, "entity/alice-main")
	# writes stream in while saves interleave with them
	_assert_applied(route.route_command(s_alice, "op/s5-1", _place([41, 0, 41], "stone")), "s5 op1 not applied")
	_assert_applied(route.route_command(s_alice, "op/s5-2", _place([42, 0, 42], "wood")), "s5 op2 not applied")
	_assert(owner.save(outpost, S5_PATH), "s5 mid-stream save failed")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(S5_PATH + ".tmp")), "s5 mid-stream save left tmp behind")
	# a load racing the active session sees a COMPLETE consistent prefix
	var mid: Dictionary = owner.load(S5_PATH)
	if _assert_bool(mid, "s5 mid-stream load failed (partial write?)"):
		_assert(String(mid["details"]["checksum"]) == outpost.compute_checksum(), "s5 mid-stream snapshot diverged from live state")
		_assert(mid["details"]["state"].block_count() == 2, "s5 mid-stream snapshot lost blocks")
	# more writes land while the file is already on disk
	_assert_applied(route.route_command(s_alice, "op/s5-3", _place([43, 0, 43], "brick")), "s5 op3 not applied")
	_assert_applied(route.route_command(s_alice, "op/s5-4", _command("CONTAINER_CREATE", {"op": "container_create", "container_id": "s5-crate"})), "s5 op4 not applied")
	_assert_applied(route.route_command(s_alice, "op/s5-5", _command("CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": "s5-crate", "item": "pickaxe"})), "s5 op5 not applied")
	_assert_applied(route.route_command(s_alice, "op/s5-6", _command("PLAYER_MOVE", {"op": "player_move", "player_id": ALICE, "pos": [9, 0, 9], "rot": 2.5})), "s5 op6 not applied")
	_assert_applied(route.route_command(s_alice, "op/s5-7", _command("SET_TICK", {"op": "set_tick", "value": 55})), "s5 op7 not applied")
	var final_checksum: String = outpost.compute_checksum()
	_assert(owner.save(outpost, S5_PATH), "s5 final save failed")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(S5_PATH + ".tmp")), "s5 final save left tmp behind")
	# CRASH: destroy everything, then restore
	_destroy_stack(stack)
	var stack2 := _boot_stack()
	var outpost2 = stack2["outpost"]
	var loaded: Dictionary = owner.load(S5_PATH)
	if _assert_bool(loaded, "s5 restore load failed"):
		var restored = loaded["details"]["state"]
		_assert(restored.compute_checksum() == final_checksum, "s5 restored checksum mismatch")
		_assert(outpost2.deserialize(restored.serialize()), "s5 adoption failed")
		_assert(outpost2.compute_checksum() == final_checksum, "s5 adopted outpost diverged")
		_assert(outpost2.block_count() == 3, "s5 restored block count wrong")
		_assert(outpost2.container_items("s5-crate") == ["pickaxe"], "s5 restored container wrong")
		_assert(outpost2.player_position(ALICE)["pos"] == [9, 0, 9], "s5 restored position wrong")
		_assert(int(outpost2.get_report()["tick"]) == 55, "s5 restored tick wrong")
	_destroy_stack(stack2)


## ============================================================================
## Scenario 6: restart during pending operations (crash windows)
## ============================================================================
func _scenario_pending_crash_recovery() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var admission = stack["admission"]
	var ledger = stack["ledger"]
	var outpost = stack["outpost"]
	var owner = OwnerScript.new()
	var s_a := "client-session/alice-s6-gen-a"
	_bind(stack, s_a, ALICE, "entity/alice-main")
	# one fully completed op: durable before the crash
	_assert_applied(route.route_command(s_a, "op/s6-1", _place([51, 0, 51], "stone")), "s6 op1 not applied")
	_assert(owner.save(outpost, S6_PATH), "s6 pre-crash save failed")
	var file_checksum: String = outpost.compute_checksum()
	# crash window A: admission admitted (PENDING recorded), handler never ran
	var admit_a: Dictionary = admission.admit(ALICE, "op/s6-2", DOMAIN_ID, _place([52, 0, 52], "wood"))
	_assert(bool(admit_a.get("success", false)) and String(admit_a.get("error_code", "x")) == "", "s6 pending admission A failed")
	# crash window B: handler effect landed in memory, completion never recorded
	var admit_b: Dictionary = admission.admit(ALICE, "op/s6-3", DOMAIN_ID, _place([53, 0, 53], "brick"))
	_assert(bool(admit_b.get("success", false)) and String(admit_b.get("error_code", "x")) == "", "s6 pending admission B failed")
	_assert(outpost.apply_delta({"op": "place_block", "pos": [53, 0, 53], "block_type": "brick"}), "s6 window B handler effect failed")
	var ledger_snap: Dictionary = ledger.snapshot()
	_assert(int(ledger.get_report()["pending_count"]) == 2, "s6 pre-crash pending count wrong")
	# CRASH: every in-memory object dies; only the file + ledger snapshot survive
	_destroy_stack(stack)
	# RESTORE: fresh stack, ledger memory rebuilt from the snapshot
	var stack2 := _boot_stack()
	var route2 = stack2["route"]
	var ledger2 = stack2["ledger"]
	var outpost2 = stack2["outpost"]
	var s_b := "client-session/alice-s6-gen-b"
	_bind(stack2, s_b, ALICE, "entity/alice-main")
	var restored: Dictionary = ledger2.restore(ledger_snap)
	if _assert_bool(restored, "s6 ledger restore failed"):
		_assert(int(restored["details"]["pending"]) == 2, "s6 restored pending count wrong")
	var loaded: Dictionary = owner.load(S6_PATH)
	if _assert_bool(loaded, "s6 restore load failed"):
		_assert(String(loaded["details"]["checksum"]) == file_checksum, "s6 durable checksum mismatch")
		_assert(outpost2.deserialize(loaded["details"]["state"].serialize()), "s6 adoption failed")
	# RECOVERY: re-drive both pending intents through the route with their
	# original operation ids -> each handler effect lands EXACTLY ONCE on the
	# restored durable state (window A applies fresh; window B's lost in-memory
	# effect re-applies; the ledger makes both idempotent from here on).
	var cmd_a: Dictionary = _place([52, 0, 52], "wood")
	var cmd_b: Dictionary = _place([53, 0, 53], "brick")
	_assert_applied(route2.route_command(s_b, "op/s6-2", cmd_a), "s6 recovery op2 not applied exactly once")
	_assert_applied(route2.route_command(s_b, "op/s6-3", cmd_b), "s6 recovery op3 not applied exactly once")
	# exactly-once after recovery: duplicate submissions replay, never re-execute
	_assert_replayed(route2.route_command(s_b, "op/s6-2", cmd_a), "s6 post-recovery op2 replay not deduplicated")
	_assert_replayed(route2.route_command(s_b, "op/s6-3", cmd_b), "s6 post-recovery op3 replay not deduplicated")
	_assert(outpost2.block_count() == 3, "s6 final block count wrong (duplicate or lost recovery write)")
	_assert(outpost2.block_type_at("52,0,52") == "wood" and outpost2.block_type_at("53,0,53") == "brick", "s6 recovered blocks wrong")
	# no pending residue; completing an unknown key stays fail-closed
	_assert(int(ledger2.get_report()["pending_count"]) == 0, "s6 pending residue after recovery")
	_assert(int(ledger2.get_report()["applied_count"]) == 3, "s6 final applied count wrong")
	_assert(not bool(ledger2.complete_pending(ALICE, "op/s6-unknown").get("success", true)), "s6 unknown completion not rejected")
	_destroy_stack(stack2)


func _init() -> void:
	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))
	_scenario_reconnect_during_writes()
	_scenario_same_block_race()
	_scenario_shadow_rejection_during_session()
	_scenario_ledger_concurrent_sessions()
	_scenario_persistence_during_writes()
	_scenario_pending_crash_recovery()
	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))
	if failures.is_empty():
		print("[p6.10-fault-race-matrix] all %d assertions passed across 6 fault scenarios" % assertions)
		print("[p6.10-fault-race-matrix][stage] FAULT_RACE_MATRIX_PASS")
		quit(0)
	else:
		print("[p6.10-fault-race-matrix] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)


func _dir_recursive_delete(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_dir_recursive_delete(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
