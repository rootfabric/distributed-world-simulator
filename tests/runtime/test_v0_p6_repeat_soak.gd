extends SceneTree

## P6.11 L0 stage proof: compressed repeat + soak for the persistent shared
## outpost stack (P6.1-P6.9 composed end to end).
##
## Part 1 - FIVE clean end-to-end repeats. Each iteration is a full lifecycle:
##   build outpost (unique operation ids per iteration) -> save via the single
##   persistence owner -> crash (destroy every in-memory object) -> restore
##   (ledger snapshot + file load) -> checksum match -> exactly-once replay
##   probes. The restart loop must be idempotent across all five generations.
##
## Part 2 - COMPRESSED SOAK. N=200 rapid operations (place/break/move/container)
## across 2 players, then save -> crash -> load -> checksum match -> zero
## corruption, zero duplicates, zero lost operations (the loaded state is
## compared against an independently maintained model of every operation).
## This is the compressed in-process stand-in for the 30-minute manual soak:
## it exercises the same durability invariants (exactly-once ledger, atomic
## save, fail-closed load, deterministic checksum) without wall-clock time.

const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const AdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const RouteScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const OwnerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")

const BASE_DIR := "user://p6_repeat_soak"
const SOAK_PATH := BASE_DIR + "/soak_canonical.json"
const DOMAIN_ID := "p6-domain/outpost-world-state"
const WORLD_SEED := 11011
const REPEATS := 5
const SOAK_OP_COUNT := 200

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
		print("[p6.11-repeat-soak][FAIL] %s" % message)


func _assert_bool(result: Dictionary, message: String) -> bool:
	if not bool(result.get("success", false)):
		_assert(false, message)
		return false
	return true


func _assert_applied(outcome: Dictionary, message: String) -> void:
	if _assert_bool(outcome, message):
		var details: Dictionary = outcome["details"]
		_assert(String(details["result"]) == "EXECUTED", "%s (result=%s)" % [message, String(details.get("result", ""))])
		_assert(bool(details["outcome"]["applied"]), "%s (handler did not apply)" % message)


func _assert_replayed(outcome: Dictionary, message: String) -> void:
	if _assert_bool(outcome, message):
		_assert(String(outcome["details"]["result"]) == "ALREADY_APPLIED", "%s (result=%s)" % [message, String(outcome["details"].get("result", ""))])


func _boot_stack() -> Dictionary:
	var outpost = StateScript.new()
	outpost.set_world_seed(WORLD_SEED)
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(512)
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
	stack["outpost"] = null
	stack["registry"] = null
	stack["ledger"] = null
	stack["route"] = null
	stack["handler"] = null
	stack.clear()


## ============================================================================
## Part 1: five clean end-to-end repeats
## ============================================================================
func _run_repeat(iteration: int, file_path: String) -> void:
	var tag := "repeat%d" % iteration
	var stack := _boot_stack()
	var route = stack["route"]
	var outpost = stack["outpost"]
	var ledger = stack["ledger"]
	var handler = stack["handler"]
	var session := "client-session/alice-%s" % tag
	_bind(stack, session, ALICE, "entity/alice-main")
	# BUILD: every iteration uses its own unique operation ids
	var build_ops: Array = [
		["op/%s-place-1" % tag, _place([iteration, 0, 1], "stone")],
		["op/%s-place-2" % tag, _place([iteration, 0, 2], "wood")],
		["op/%s-crate" % tag, _command("CONTAINER_CREATE", {"op": "container_create", "container_id": "crate-%s" % tag})],
		["op/%s-item" % tag, _command("CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": "crate-%s" % tag, "item": "hammer-%s" % tag})],
		["op/%s-move" % tag, _command("PLAYER_MOVE", {"op": "player_move", "player_id": ALICE, "pos": [iteration, 5, 5], "rot": 0.5 * iteration})],
		["op/%s-tick" % tag, _command("SET_TICK", {"op": "set_tick", "value": 10 * iteration})],
	]
	for row in build_ops:
		var cmd: Dictionary = row[1]
		_assert_applied(route.route_command(session, String(row[0]), cmd), "%s build op %s not applied" % [tag, String(row[0])])
	var built_checksum: String = outpost.compute_checksum()
	var ledger_snap: Dictionary = ledger.snapshot()
	var executions_before: int = int(handler.executions)
	# SAVE
	var owner = OwnerScript.new()
	_assert(owner.save(outpost, file_path), "%s save failed" % tag)
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(file_path + ".tmp")), "%s save left tmp behind" % tag)
	# CRASH
	_destroy_stack(stack)
	_assert(stack.is_empty(), "%s crash left live references" % tag)
	# RESTORE
	var stack2 := _boot_stack()
	var route2 = stack2["route"]
	var ledger2 = stack2["ledger"]
	var outpost2 = stack2["outpost"]
	var handler2 = stack2["handler"]
	var session2 := "client-session/alice-%s-gen2" % tag
	_bind(stack2, session2, ALICE, "entity/alice-main")
	var restored_ledger: Dictionary = ledger2.restore(ledger_snap)
	_assert(_assert_bool(restored_ledger, "%s ledger restore failed" % tag) and int(restored_ledger["details"]["applied"]) == build_ops.size(), "%s ledger applied restore wrong" % tag)
	var loaded: Dictionary = owner.load(file_path)
	if _assert_bool(loaded, "%s load failed" % tag):
		var restored = loaded["details"]["state"]
		# CHECKSUM MATCH across the full cycle
		_assert(restored.compute_checksum() == built_checksum, "%s restored checksum mismatch" % tag)
		_assert(outpost2.deserialize(restored.serialize()), "%s adoption failed" % tag)
		_assert(outpost2.compute_checksum() == built_checksum, "%s adopted outpost diverged" % tag)
		_assert(outpost2.block_count() == 2 and outpost2.container_items("crate-%s" % tag) == ["hammer-%s" % tag], "%s restored payload wrong" % tag)
		_assert(outpost2.player_position(ALICE)["pos"] == [iteration, 5, 5], "%s restored position wrong" % tag)
		_assert(int(outpost2.get_report()["tick"]) == 10 * iteration, "%s restored tick wrong" % tag)
	# EXACTLY ONCE: every operation of this iteration replays as applied, and
	# a duplicated container add would be visible if replay memory were lost
	for row in build_ops:
		var cmd: Dictionary = row[1]
		_assert_replayed(route2.route_command(session2, String(row[0]), cmd), "%s replay of %s not deduplicated" % [tag, String(row[0])])
	_assert(outpost2.container_items("crate-%s" % tag) == ["hammer-%s" % tag], "%s replay duplicated container item" % tag)
	_assert(outpost2.block_count() == 2, "%s replay duplicated a block" % tag)
	_assert(int(handler2.executions) == 0, "%s replay reached the handler (%d times)" % [tag, int(handler2.executions)])
	_assert(executions_before == build_ops.size(), "%s build execution count wrong" % tag)
	_destroy_stack(stack2)


## ============================================================================
## Part 2: compressed soak - 200 rapid operations across 2 players
## ============================================================================
## Emits exactly SOAK_OP_COUNT operations, all of which must succeed, while
## maintaining an independent expected-state model. Operation mix:
##   110 place (65 alice + 45 bob), 25 break, 8 container_create,
##   21 container_add_item, 1 container_remove_item, 25 player_move,
##   10 set_tick  = 200
func _run_soak() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var outpost = stack["outpost"]
	var ledger = stack["ledger"]
	var handler = stack["handler"]
	var s_alice := "client-session/soak-alice"
	var s_bob := "client-session/soak-bob"
	_bind(stack, s_alice, ALICE, "entity/alice-main")
	_bind(stack, s_bob, BOB, "entity/bob-main")
	var expected_blocks: Dictionary = {}
	var expected_containers: Dictionary = {}
	var expected_positions: Dictionary = {}
	var expected_tick := 0
	var op_count := 0
	var executed_ops: Array = []

	# --- 110 placements at unique positions ---------------------------------
	for i in range(65):
		var pos_key := StateScript.position_key(i, 0, 0)
		var op_id := "op/soak-a-place-%03d" % i
		_assert_applied(route.route_command(s_alice, op_id, _place([i, 0, 0], "stone")), "soak op %s not applied" % op_id)
		expected_blocks[pos_key] = "stone"
		op_count += 1
		executed_ops.append(op_id)
	for i in range(45):
		var pos_key := StateScript.position_key(i, 1, 0)
		var op_id := "op/soak-b-place-%03d" % i
		_assert_applied(route.route_command(s_bob, op_id, _place([i, 1, 0], "wood")), "soak op %s not applied" % op_id)
		expected_blocks[pos_key] = "wood"
		op_count += 1
		executed_ops.append(op_id)
	# --- 25 breaks of existing blocks ---------------------------------------
	for i in range(15):
		var pos_key := StateScript.position_key(i, 0, 0)
		var op_id := "op/soak-a-break-%03d" % i
		_assert_applied(route.route_command(s_alice, op_id, _command("BREAK_BLOCK", {"op": "break_block", "pos": [i, 0, 0]})), "soak op %s not applied" % op_id)
		expected_blocks.erase(pos_key)
		op_count += 1
		executed_ops.append(op_id)
	for i in range(10):
		var pos_key := StateScript.position_key(i, 1, 0)
		var op_id := "op/soak-b-break-%03d" % i
		_assert_applied(route.route_command(s_bob, op_id, _command("BREAK_BLOCK", {"op": "break_block", "pos": [i, 1, 0]})), "soak op %s not applied" % op_id)
		expected_blocks.erase(pos_key)
		op_count += 1
		executed_ops.append(op_id)
	# --- 8 containers + 21 items + 1 removal --------------------------------
	for c in range(5):
		var container_id := "soak-crate-a-%d" % c
		var op_id := "op/soak-a-crate-%d" % c
		_assert_applied(route.route_command(s_alice, op_id, _command("CONTAINER_CREATE", {"op": "container_create", "container_id": container_id})), "soak op %s not applied" % op_id)
		expected_containers[container_id] = {"items": []}
		op_count += 1
		executed_ops.append(op_id)
		for item_index in range(3):
			var item_op := "op/soak-a-item-%d-%d" % [c, item_index]
			var item := "tool-a-%d-%d" % [c, item_index]
			_assert_applied(route.route_command(s_alice, item_op, _command("CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": container_id, "item": item})), "soak op %s not applied" % item_op)
			(expected_containers[container_id] as Dictionary)["items"].append(item)
			op_count += 1
			executed_ops.append(item_op)
	for c in range(3):
		var container_id := "soak-crate-b-%d" % c
		var op_id := "op/soak-b-crate-%d" % c
		_assert_applied(route.route_command(s_bob, op_id, _command("CONTAINER_CREATE", {"op": "container_create", "container_id": container_id})), "soak op %s not applied" % op_id)
		expected_containers[container_id] = {"items": []}
		op_count += 1
		executed_ops.append(op_id)
		for item_index in range(2):
			var item_op := "op/soak-b-item-%d-%d" % [c, item_index]
			var item := "tool-b-%d-%d" % [c, item_index]
			_assert_applied(route.route_command(s_bob, item_op, _command("CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": container_id, "item": item})), "soak op %s not applied" % item_op)
			(expected_containers[container_id] as Dictionary)["items"].append(item)
			op_count += 1
			executed_ops.append(item_op)
	var removed_item := "tool-b-0-0"
	_assert_applied(route.route_command(s_bob, "op/soak-b-remove-item", _command("CONTAINER_REMOVE_ITEM", {"op": "container_remove_item", "container_id": "soak-crate-b-0", "item": removed_item})), "soak remove-item op not applied")
	(expected_containers["soak-crate-b-0"] as Dictionary)["items"].erase(removed_item)
	op_count += 1
	executed_ops.append("op/soak-b-remove-item")
	# --- 25 player moves -----------------------------------------------------
	for m in range(20):
		var op_id := "op/soak-a-move-%02d" % m
		var pos: Array = [m, 7, 7]
		_assert_applied(route.route_command(s_alice, op_id, _command("PLAYER_MOVE", {"op": "player_move", "player_id": ALICE, "pos": pos, "rot": 0.25 * m})), "soak op %s not applied" % op_id)
		expected_positions[ALICE] = {"pos": pos, "rot": 0.25 * m}
		op_count += 1
		executed_ops.append(op_id)
	for m in range(5):
		var op_id := "op/soak-b-move-%02d" % m
		var pos: Array = [m, 8, 8]
		_assert_applied(route.route_command(s_bob, op_id, _command("PLAYER_MOVE", {"op": "player_move", "player_id": BOB, "pos": pos, "rot": 1.5 * m})), "soak op %s not applied" % op_id)
		expected_positions[BOB] = {"pos": pos, "rot": 1.5 * m}
		op_count += 1
		executed_ops.append(op_id)
	# --- 10 ticks ------------------------------------------------------------
	for t in range(10):
		var op_id := "op/soak-tick-%02d" % t
		expected_tick = t + 1
		_assert_applied(route.route_command(s_alice, op_id, _command("SET_TICK", {"op": "set_tick", "value": expected_tick})), "soak op %s not applied" % op_id)
		op_count += 1
		executed_ops.append(op_id)

	# soak size guard: exactly N=200 rapid operations were issued
	_assert(op_count == SOAK_OP_COUNT, "soak op count wrong: %d != %d" % [op_count, SOAK_OP_COUNT])
	_assert(int(handler.executions) == SOAK_OP_COUNT, "soak handler executions wrong: %d" % int(handler.executions))
	_assert(int(ledger.get_report()["applied_count"]) == SOAK_OP_COUNT, "soak ledger applied count wrong")
	_assert(int(route.get_report()["counters"]["replayed"]) == 0, "soak had unexpected replays")
	_assert(executed_ops.size() == SOAK_OP_COUNT, "soak op id list wrong")
	# zero duplicates: every issued operation id is unique
	var unique_ops: Dictionary = {}
	for op_id in executed_ops:
		unique_ops[op_id] = true
	_assert(unique_ops.size() == SOAK_OP_COUNT, "soak operation ids not unique")

	var soak_checksum: String = outpost.compute_checksum()
	var ledger_snap: Dictionary = ledger.snapshot()
	var owner = OwnerScript.new()
	_assert(owner.save(outpost, SOAK_PATH), "soak save failed")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(SOAK_PATH + ".tmp")), "soak save left tmp behind")
	# CRASH + RESTORE
	_destroy_stack(stack)
	var stack2 := _boot_stack()
	var ledger2 = stack2["ledger"]
	var outpost2 = stack2["outpost"]
	var s_alice2 := "client-session/soak-alice-gen2"
	var s_bob2 := "client-session/soak-bob-gen2"
	_bind(stack2, s_alice2, ALICE, "entity/alice-main")
	_bind(stack2, s_bob2, BOB, "entity/bob-main")
	var restored_ledger: Dictionary = ledger2.restore(ledger_snap)
	_assert(_assert_bool(restored_ledger, "soak ledger restore failed") and int(restored_ledger["details"]["applied"]) == SOAK_OP_COUNT, "soak ledger applied restore wrong")
	var loaded: Dictionary = owner.load(SOAK_PATH)
	if _assert_bool(loaded, "soak load failed (corruption?)"):
		var restored = loaded["details"]["state"]
		# zero corruption: checksum identical across save -> crash -> load
		_assert(restored.compute_checksum() == soak_checksum, "soak restored checksum mismatch")
		_assert(outpost2.deserialize(restored.serialize()), "soak adoption failed")
		_assert(outpost2.compute_checksum() == soak_checksum, "soak adopted outpost diverged")
		# zero lost operations: loaded state equals the independent model exactly
		_assert(outpost2.blocks == expected_blocks, "soak blocks diverge from model (%d vs %d)" % [outpost2.blocks.size(), expected_blocks.size()])
		_assert(outpost2.containers == expected_containers, "soak containers diverge from model")
		_assert(outpost2.player_positions == expected_positions, "soak positions diverge from model")
		_assert(int(outpost2.tick) == expected_tick, "soak tick diverges from model")
		_assert(outpost2.block_count() == 85, "soak final block count wrong")  # 110 placed - 25 broken
	# zero duplicates after restart: sampled replays dedupe (each through its
	# own player's re-bound session — the ledger keys on logical identity),
	# and the state checksum is unchanged afterwards
	var probe_cmd: Dictionary = _command("SET_TICK", {"op": "set_tick", "value": expected_tick})
	_assert_replayed(route_probe(stack2, s_alice2, "op/soak-a-place-000", probe_cmd), "soak replay probe a-place-000 not deduplicated")
	_assert_replayed(route_probe(stack2, s_bob2, "op/soak-b-crate-2", probe_cmd), "soak replay probe b-crate-2 not deduplicated")
	_assert_replayed(route_probe(stack2, s_alice2, "op/soak-tick-09", probe_cmd), "soak replay probe tick-09 not deduplicated")
	_assert(outpost2.compute_checksum() == soak_checksum, "soak replay probes mutated state")
	_assert(int(ledger2.get_report()["pending_count"]) == 0, "soak pending residue")
	print("[p6.11-repeat-soak] compressed soak: %d ops / 2 players in-process (stand-in for the 30-minute manual soak)" % SOAK_OP_COUNT)
	_destroy_stack(stack2)


## Replay probe helper: routes a replayed operation id through the live route.
func route_probe(stack: Dictionary, session: String, op_id: String, cmd: Dictionary) -> Dictionary:
	return stack["route"].route_command(session, op_id, cmd)


func _init() -> void:
	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))
	for iteration in range(1, REPEATS + 1):
		_run_repeat(iteration, BASE_DIR + "/repeat_%d_canonical.json" % iteration)
	_run_soak()
	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))
	if failures.is_empty():
		print("[p6.11-repeat-soak] all %d assertions passed (%d repeats + %d-op soak)" % [assertions, REPEATS, SOAK_OP_COUNT])
		print("[p6.11-repeat-soak][stage] REPEAT_SOAK_PASS")
		quit(0)
	else:
		print("[p6.11-repeat-soak] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
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
