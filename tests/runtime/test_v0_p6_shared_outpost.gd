extends SceneTree

## P6.7 L0 integration: persistent SHARED outpost.
##
## Two identity-registry players share ONE canonical outpost state through the
## full P6 stack (identity registry -> gateway command route -> admission
## -> operation ledger -> outpost state). The single persistence owner saves
## and restores the canonical outpost across a simulated server restart.

const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const AdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const RouteScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const OwnerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")

const BASE_DIR := "user://p6_shared_outpost_it"
const DOMAIN_ID := "p6-domain/outpost-world-state"

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
		print("[p6.7-shared-outpost-it][FAIL] %s" % message)


func _build_stack(p_outpost) -> Dictionary:
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(256)
	var admission = AdmissionScript.new()
	admission.configure(registry, ledger)
	var adapter = AdapterScript.new()
	adapter.configure(registry, ledger)
	var handler = OutpostHandler.new()
	handler.outpost = p_outpost
	var route = RouteScript.new()
	route.configure(registry, ledger, admission, adapter, handler)
	return {"registry": registry, "ledger": ledger, "route": route}


func _place_command(pos: Array, block_type: String) -> Dictionary:
	return {
		"domain_id": DOMAIN_ID,
		"command_kind": "PLACE_BLOCK",
		"delta": {"op": "place_block", "pos": pos, "block_type": block_type},
	}


func _init() -> void:
	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))
	var canonical_path := BASE_DIR + "/canonical_outpost.json"

	# --- shared stack: two registry players, ONE outpost state ---
	var outpost = StateScript.new()
	outpost.set_world_seed(1337)
	var stack: Dictionary = _build_stack(outpost)
	var registry = stack["registry"]
	var ledger = stack["ledger"]
	var route = stack["route"]
	var alice_bind: Dictionary = registry.bind("client-session/alice-1", "player/alice", "entity/alice-1")
	var bob_bind: Dictionary = registry.bind("client-session/bob-1", "player/bob", "entity/bob-1")
	_assert(bool(alice_bind.get("success", false)), "alice bind failed")
	_assert(bool(bob_bind.get("success", false)), "bob bind failed")

	# --- 1. both players place blocks; shared state reflects BOTH ---
	var alice_op: Dictionary = route.route_command("client-session/alice-1", "operation/p6.7-a1", _place_command([1, 1, 1], "stone"))
	_assert(bool(alice_op.get("success", false)) and String(alice_op["details"]["result"]) == "EXECUTED", "alice place not executed: %s" % JSON.stringify(alice_op))
	var bob_op: Dictionary = route.route_command("client-session/bob-1", "operation/p6.7-b1", _place_command([2, 0, 0], "wood"))
	_assert(bool(bob_op.get("success", false)) and String(bob_op["details"]["result"]) == "EXECUTED", "bob place not executed")
	_assert(outpost.block_count() == 2, "shared state does not reflect both players")
	_assert(String(outpost.block_type_at("1,1,1")) == "stone" and String(outpost.block_type_at("2,0,0")) == "wood", "block authorship lost")
	# exactly-once: replaying alice's operation changes nothing
	var replay_op: Dictionary = route.route_command("client-session/alice-1", "operation/p6.7-a1", _place_command([1, 1, 1], "stone"))
	_assert(bool(replay_op.get("success", false)) and String(replay_op["details"]["result"]) == "ALREADY_APPLIED", "replay not deduplicated")
	_assert(outpost.block_count() == 2, "replay mutated shared state")

	# --- 2. save -> fresh outpost -> load -> checksum matches ---
	var owner = OwnerScript.new()
	var pre_save_checksum: String = outpost.compute_checksum()
	_assert(owner.save(outpost, canonical_path), "owner save failed: %s" % owner.get_report()["last_error_code"])
	var loaded: Dictionary = owner.load(canonical_path)
	if not bool(loaded.get("success", false)):
		_assert(false, "owner load failed: %s" % owner.get_report()["last_error_code"])
	else:
		var restored = loaded["details"]["state"]
		_assert(restored.compute_checksum() == pre_save_checksum, "restored checksum mismatch")

	# --- 3. alice reconnects on a NEW session via identity rebind ---
	var rebind: Dictionary = registry.rebind_on_transport_change("client-session/alice-1", "client-session/alice-2")
	_assert(bool(rebind.get("success", false)) and String(rebind["details"]["preserved_logical_player_id"]) == "player/alice", "alice rebind failed")
	var alice_op2: Dictionary = route.route_command("client-session/alice-2", "operation/p6.7-a2", _place_command([3, 3, 3], "glass"))
	_assert(bool(alice_op2.get("success", false)) and String(alice_op2["details"]["result"]) == "EXECUTED", "post-rebind place not executed")
	_assert(outpost.block_count() == 3, "post-rebind contribution missing")
	_assert(String(outpost.block_type_at("1,1,1")) == "stone", "pre-reconnect contribution lost")
	# ledger continuity: alice's PRE-reconnect op replays as already applied via the NEW session
	var cross_replay: Dictionary = route.route_command("client-session/alice-2", "operation/p6.7-a1", _place_command([1, 1, 1], "stone"))
	_assert(bool(cross_replay.get("success", false)) and String(cross_replay["details"]["result"]) == "ALREADY_APPLIED", "ledger not keyed by logical identity")

	# --- 4. restart simulation: save -> destroy ALL -> load -> identical ---
	var pre_restart_checksum: String = outpost.compute_checksum()
	var ledger_snap: Dictionary = ledger.snapshot()
	_assert(owner.save(outpost, canonical_path), "restart save failed")
	# destroy everything (server process death): no live object survives
	outpost = null
	stack = {}
	registry = null
	ledger = null
	route = null
	# fresh boot: empty outpost, fresh registry/ledger (ledger restored from snapshot)
	var outpost2 = StateScript.new()
	_assert(outpost2.block_count() == 0, "fresh outpost not empty")
	var stack2: Dictionary = _build_stack(outpost2)
	var registry2 = stack2["registry"]
	var ledger2 = stack2["ledger"]
	var route2 = stack2["route"]
	_assert(bool(ledger2.restore(ledger_snap).get("success", false)), "ledger snapshot restore failed")
	_assert(registry2.bind("client-session/alice-3", "player/alice", "entity/alice-2").get("success", false), "alice post-restart bind failed")
	_assert(registry2.bind("client-session/bob-2", "player/bob", "entity/bob-2").get("success", false), "bob post-restart bind failed")
	var loaded2: Dictionary = owner.load(canonical_path)
	if not bool(loaded2.get("success", false)):
		_assert(false, "restart load failed: %s" % owner.get_report()["last_error_code"])
	else:
		var restored2 = loaded2["details"]["state"]
		_assert(restored2.compute_checksum() == pre_restart_checksum, "restart state not identical")
		# canonical outpost is adopted by the fresh server
		outpost2.deserialize(restored2.serialize())
		_assert(outpost2.compute_checksum() == pre_restart_checksum, "adopted outpost diverged")
		_assert(outpost2.block_count() == 3, "restart lost shared blocks")
	# exactly-once survives restart: bob's pre-restart op replays via new session
	var post_restart_replay: Dictionary = route2.route_command("client-session/bob-2", "operation/p6.7-b1", _place_command([2, 0, 0], "wood"))
	_assert(bool(post_restart_replay.get("success", false)) and String(post_restart_replay["details"]["result"]) == "ALREADY_APPLIED", "post-restart replay not deduplicated")
	# and the shared world keeps accepting new work after restart
	var post_restart_op: Dictionary = route2.route_command("client-session/bob-2", "operation/p6.7-b2", _place_command([4, 4, 4], "brick"))
	_assert(bool(post_restart_op.get("success", false)) and String(post_restart_op["details"]["result"]) == "EXECUTED", "post-restart place not executed")
	_assert(outpost2.block_count() == 4, "post-restart state growth wrong")

	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))

	if failures.is_empty():
		print("[p6.7-shared-outpost-it] all %d assertions passed" % assertions)
		print("[p6.7-shared-outpost-it][stage] SHARED_OUTPOST_PASS")
		quit(0)
	else:
		print("[p6.7-shared-outpost-it] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
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
