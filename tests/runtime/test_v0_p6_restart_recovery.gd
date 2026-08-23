extends SceneTree

## P6.8 L0 stage proof: server restart reconstructs the persistent shared outpost.
##
## Formalizes the restart/recovery pattern proven in P6.7 as a first-class
## stage exit. One canonical file, one persistence owner, TWO full
## save -> crash -> restore cycles:
##   1. build outpost state via THREE players and many operation kinds;
##   2. save via the single persistence owner (atomic write);
##   3. simulate server crash: destroy EVERY in-memory object (null refs);
##   4. restore: fresh outpost + fresh stack; persistence owner load rebuilds
##      the state, ledger snapshot restore rebuilds exactly-once memory;
##   5. assert checksum identical, ledger exactly-once preserved (a duplicated
##      container item would be visible if replay memory were lost), identity
##      bindings re-established for the SAME logical players/entities;
##   6. repeat the cycle to prove the restart loop is idempotent, including a
##      stale ".tmp" leftover from a crashed write being absorbed safely.

const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const AdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const RouteScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const OwnerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")

const BASE_DIR := "user://p6_restart_recovery"
const CANONICAL_PATH := BASE_DIR + "/canonical_outpost.json"
const DOMAIN_ID := "p6-domain/outpost-world-state"
const WORLD_SEED := 4242

const PLAYERS: Array = [
	["player/alice", "entity/alice-main"],
	["player/bob", "entity/bob-main"],
	["player/carol", "entity/carol-main"],
]

var assertions := 0
var failures: Array[String] = []


class OutpostHandler:
	extends RefCounted

	var outpost = null

	func execute_command(command: Dictionary) -> Dictionary:
		var delta: Dictionary = command.get("delta", {})
		var applied: bool = outpost.apply_delta(delta)
		return {"applied": applied, "error_code": String(outpost.get_report()["last_error_code"])}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.8-restart-recovery][FAIL] %s" % message)


## One fresh server boot: empty outpost + full P6 stack + ledger snapshot
## restore (the crash-recovery handoff) + identity re-binding of the SAME
## logical players to NEW sessions. Returns every live object so the caller
## can destroy them all when simulating the next crash.
func _boot_generation(generation: int, ledger_snapshot: Dictionary) -> Dictionary:
	var outpost = StateScript.new()
	if generation == 1:
		outpost.set_world_seed(WORLD_SEED)
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(256)
	if not ledger_snapshot.is_empty():
		var restored: Dictionary = ledger.restore(ledger_snapshot)
		_assert(bool(restored.get("success", false)), "gen %d ledger restore failed" % generation)
	var admission = AdmissionScript.new()
	admission.configure(registry, ledger)
	var adapter = AdapterScript.new()
	adapter.configure(registry, ledger)
	var handler = OutpostHandler.new()
	handler.outpost = outpost
	var route = RouteScript.new()
	route.configure(registry, ledger, admission, adapter, handler)
	for player_row in PLAYERS:
		var logical := String(player_row[0])
		var entity := String(player_row[1])
		var session := "client-session/%s-gen%d" % [logical.get_file(), generation]
		var bound: Dictionary = registry.bind(session, logical, entity)
		_assert(bool(bound.get("success", false)), "gen %d bind failed for %s" % [generation, logical])
	return {
		"outpost": outpost,
		"registry": registry,
		"ledger": ledger,
		"route": route,
		"session_for": func(logical_player_id: String) -> String:
			return "client-session/%s-gen%d" % [logical_player_id.get_file(), generation],
	}


func _command(kind: String, delta: Dictionary) -> Dictionary:
	return {"domain_id": DOMAIN_ID, "command_kind": kind, "delta": delta}


func _place(pos: Array, block_type: String) -> Dictionary:
	return _command("PLACE_BLOCK", {"op": "place_block", "pos": pos, "block_type": block_type})


## Identity bindings preserved across restart: the fresh registry re-binds the
## SAME (logical, entity) pairs; the deterministic binding rows must match the
## pre-crash rows on every durable field, with only the session id renewed.
func _assert_bindings_preserved(pre_crash_bindings: Dictionary, registry, session_for: Callable) -> void:
	for logical_value in pre_crash_bindings.keys():
		var logical := String(logical_value)
		var expected: Dictionary = pre_crash_bindings[logical]
		var resolved: Dictionary = registry.resolve(logical)
		if not _assert_bool(resolved, "post-restart resolve failed for %s" % logical):
			continue
		var row: Dictionary = resolved["details"]["binding"]
		_assert(String(row["logical_player_id"]) == String(expected["logical_player_id"]), "logical id changed for %s" % logical)
		_assert(String(row["player_entity_id"]) == String(expected["player_entity_id"]), "entity binding changed for %s" % logical)
		_assert(String(row["binding_id"]) == String(expected["binding_id"]), "binding_id not deterministically rebuilt for %s" % logical)
		_assert(int(row["binding_revision"]) == int(expected["binding_revision"]), "binding_revision drifted for %s" % logical)
		_assert(String(row["state"]) == String(expected["state"]), "binding state drifted for %s" % logical)
		_assert(String(row["client_session_id"]) == String(session_for.call(logical)), "session not renewed for %s" % logical)


func _assert_bool(result: Dictionary, message: String) -> bool:
	if not bool(result.get("success", false)):
		_assert(false, message)
		return false
	return true


func _destroy_generation(live: Dictionary) -> void:
	# Server process death: NO live object survives the crash.
	live["outpost"] = null
	live["registry"] = null
	live["ledger"] = null
	live["route"] = null
	live["session_for"] = Callable()
	live.clear()


func _init() -> void:
	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))
	var owner = OwnerScript.new()

	# ================= GENERATION 1: build shared work =======================
	var gen1: Dictionary = _boot_generation(1, {})
	var outpost1 = gen1["outpost"]
	var route1 = gen1["route"]
	var ledger1 = gen1["ledger"]

	var ops := {
		"alice_place": route1.route_command("client-session/alice-gen1", "operation/g1-alice-1", _place([1, 0, 1], "stone")),
		"bob_place": route1.route_command("client-session/bob-gen1", "operation/g1-bob-1", _place([2, 0, 2], "wood")),
		"carol_crate": route1.route_command("client-session/carol-gen1", "operation/g1-carol-1", _command("CONTAINER_CREATE", {"op": "container_create", "container_id": "crate-1"})),
		"carol_axe": route1.route_command("client-session/carol-gen1", "operation/g1-carol-2", _command("CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": "crate-1", "item": "axe"})),
		"alice_move": route1.route_command("client-session/alice-gen1", "operation/g1-alice-2", _command("PLAYER_MOVE", {"op": "player_move", "player_id": "player/alice", "pos": [5, 0, 5], "rot": 1.5})),
		"bob_tick": route1.route_command("client-session/bob-gen1", "operation/g1-bob-2", _command("SET_TICK", {"op": "set_tick", "value": 100})),
	}
	for op_name in ops.keys():
		var outcome: Dictionary = ops[op_name]
		_assert(bool(outcome.get("success", false)) and String(outcome["details"]["result"]) == "EXECUTED", "gen1 op %s not executed" % String(op_name))
	_assert(outpost1.block_count() == 2, "gen1 block count wrong")
	_assert(outpost1.container_items("crate-1") == ["axe"], "gen1 container items wrong")
	_assert(int(outpost1.get_report()["tick"]) == 100, "gen1 tick wrong")
	# exactly-once sanity before any crash
	var pre_replay: Dictionary = route1.route_command("client-session/carol-gen1", "operation/g1-carol-2", _command("CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": "crate-1", "item": "axe"}))
	_assert(bool(pre_replay.get("success", false)) and String(pre_replay["details"]["result"]) == "ALREADY_APPLIED", "gen1 replay not deduplicated")
	_assert(outpost1.container_items("crate-1") == ["axe"], "gen1 replay duplicated item")

	var pre_crash_bindings := {}
	for player_row in PLAYERS:
		var logical := String(player_row[0])
		var resolved: Dictionary = gen1["registry"].resolve(logical)
		if _assert_bool(resolved, "gen1 resolve failed for %s" % logical):
			pre_crash_bindings[logical] = resolved["details"]["binding"]

	var checksum_g1: String = outpost1.compute_checksum()
	var ledger_snap_g1: Dictionary = ledger1.snapshot()
	_assert(owner.save(outpost1, CANONICAL_PATH), "gen1 save failed: %s" % owner.get_report()["last_error_code"])
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(CANONICAL_PATH + ".tmp")), "gen1 save left tmp file behind")

	# ================= CRASH 1: destroy EVERYTHING ===========================
	_destroy_generation(gen1)
	_assert(gen1.is_empty(), "crash 1 left live references")

	# ================= RESTORE 1 (generation 2) ==============================
	var gen2: Dictionary = _boot_generation(2, ledger_snap_g1)
	var outpost2 = gen2["outpost"]
	var route2 = gen2["route"]
	var ledger2 = gen2["ledger"]
	var loaded1: Dictionary = owner.load(CANONICAL_PATH)
	if _assert_bool(loaded1, "gen2 load failed: %s" % owner.get_report()["last_error_code"]):
		var restored1 = loaded1["details"]["state"]
		_assert(restored1.compute_checksum() == checksum_g1, "gen2 restored checksum mismatch")
		_assert(outpost2.deserialize(restored1.serialize()), "gen2 adoption failed")
		_assert(outpost2.compute_checksum() == checksum_g1, "gen2 adopted outpost diverged")
		_assert(outpost2.block_count() == 2, "gen2 lost blocks")
		_assert(outpost2.container_items("crate-1") == ["axe"], "gen2 lost container items")
		_assert(outpost2.has_player("player/alice") and outpost2.player_position("player/alice")["pos"] == [5, 0, 5], "gen2 lost player position")
	_assert(int(ledger2.get_report()["applied_count"]) == 6, "gen2 ledger applied count wrong")
	# exactly-once across the restart: the duplicated-item replay is the sharpest probe
	var post_replay: Dictionary = route2.route_command("client-session/carol-gen2", "operation/g1-carol-2", _command("CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": "crate-1", "item": "axe"}))
	_assert(bool(post_replay.get("success", false)) and String(post_replay["details"]["result"]) == "ALREADY_APPLIED", "gen2 replay not deduplicated after restart")
	_assert(outpost2.container_items("crate-1") == ["axe"], "gen2 replay duplicated item after restart")
	var post_replay2: Dictionary = route2.route_command("client-session/alice-gen2", "operation/g1-alice-1", _place([1, 0, 1], "stone"))
	_assert(bool(post_replay2.get("success", false)) and String(post_replay2["details"]["result"]) == "ALREADY_APPLIED", "gen2 alice replay not deduplicated")
	# identity bindings preserved: same logical players/entities re-established
	_assert_bindings_preserved(pre_crash_bindings, gen2["registry"], gen2["session_for"])
	# the restored world keeps accepting new work
	var gen2_op: Dictionary = route2.route_command("client-session/bob-gen2", "operation/g2-bob-1", _place([3, 0, 3], "brick"))
	_assert(bool(gen2_op.get("success", false)) and String(gen2_op["details"]["result"]) == "EXECUTED", "gen2 new op not executed")
	_assert(outpost2.block_count() == 3, "gen2 block count after new op wrong")

	var checksum_g2: String = outpost2.compute_checksum()
	var ledger_snap_g2: Dictionary = ledger2.snapshot()
	# crash-mid-write leftover: a stale ".tmp" must be absorbed by the next atomic save
	var tmp_path: String = ProjectSettings.globalize_path(CANONICAL_PATH + ".tmp")
	var junk := FileAccess.open(tmp_path, FileAccess.WRITE)
	junk.store_string("{\"torn\":true}")
	junk.flush()
	junk.close()
	_assert(owner.save(outpost2, CANONICAL_PATH), "gen2 save failed: %s" % owner.get_report()["last_error_code"])
	_assert(not FileAccess.file_exists(tmp_path), "gen2 save left stale tmp behind")

	# ================= CRASH 2 + RESTORE 2 (generation 3) ====================
	_destroy_generation(gen2)
	_assert(gen2.is_empty(), "crash 2 left live references")

	var gen3: Dictionary = _boot_generation(3, ledger_snap_g2)
	var outpost3 = gen3["outpost"]
	var route3 = gen3["route"]
	var ledger3 = gen3["ledger"]
	var loaded2: Dictionary = owner.load(CANONICAL_PATH)
	if _assert_bool(loaded2, "gen3 load failed: %s" % owner.get_report()["last_error_code"]):
		var restored2 = loaded2["details"]["state"]
		_assert(restored2.compute_checksum() == checksum_g2, "gen3 restored checksum mismatch")
		_assert(outpost3.deserialize(restored2.serialize()), "gen3 adoption failed")
		_assert(outpost3.compute_checksum() == checksum_g2, "gen3 adopted outpost diverged")
		_assert(outpost3.block_count() == 3, "gen3 lost blocks")
		_assert(int(outpost3.get_report()["tick"]) == 100, "gen3 lost tick")
	# deep exactly-once: a GENERATION-1 operation still replays as applied
	var deep_replay: Dictionary = route3.route_command("client-session/carol-gen3", "operation/g1-carol-2", _command("CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": "crate-1", "item": "axe"}))
	_assert(bool(deep_replay.get("success", false)) and String(deep_replay["details"]["result"]) == "ALREADY_APPLIED", "gen3 deep replay not deduplicated")
	_assert(outpost3.container_items("crate-1") == ["axe"], "gen3 deep replay duplicated item")
	var deep_replay2: Dictionary = route3.route_command("client-session/bob-gen3", "operation/g2-bob-1", _place([3, 0, 3], "brick"))
	_assert(bool(deep_replay2.get("success", false)) and String(deep_replay2["details"]["result"]) == "ALREADY_APPLIED", "gen3 g2 replay not deduplicated")
	_assert_bindings_preserved(pre_crash_bindings, gen3["registry"], gen3["session_for"])
	var gen3_op: Dictionary = route3.route_command("client-session/alice-gen3", "operation/g3-alice-1", _place([4, 0, 4], "glass"))
	_assert(bool(gen3_op.get("success", false)) and String(gen3_op["details"]["result"]) == "EXECUTED", "gen3 new op not executed")
	_assert(outpost3.block_count() == 4, "gen3 block count after new op wrong")

	# ================= IDEMPOTENCE: double save, double load =================
	var checksum_g3: String = outpost3.compute_checksum()
	_assert(owner.save(outpost3, CANONICAL_PATH), "gen3 save A failed")
	_assert(owner.save(outpost3, CANONICAL_PATH), "gen3 save B failed")
	var reload_a: Dictionary = owner.load(CANONICAL_PATH)
	var reload_b: Dictionary = owner.load(CANONICAL_PATH)
	if _assert_bool(reload_a, "gen3 reload A failed") and _assert_bool(reload_b, "gen3 reload B failed"):
		_assert(reload_a["details"]["state"].compute_checksum() == checksum_g3, "reload A checksum mismatch")
		_assert(reload_b["details"]["state"].compute_checksum() == checksum_g3, "reload B checksum mismatch")
		_assert(String(reload_a["details"]["checksum"]) == String(reload_b["details"]["checksum"]), "double load diverged")

	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))

	if failures.is_empty():
		print("[p6.8-restart-recovery] all %d assertions passed" % assertions)
		print("[p6.8-restart-recovery][stage] RESTART_RECOVERY_PASS")
		quit(0)
	else:
		print("[p6.8-restart-recovery] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
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
