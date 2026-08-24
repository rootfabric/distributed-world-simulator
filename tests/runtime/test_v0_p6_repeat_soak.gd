extends SceneTree

## P6 R3 rewrite of the P6.11 repeat/soak file.
##
## What this file proves on the R3 boundary:
##   - a mixed 200-operation stream across two players lands exactly once on
##     the canonical owners fixture through the full P6 admission route;
##   - a FULL replay of every operation id afterwards mutates nothing: the
##     handler is never re-invoked and the canonical sources do not move;
##   - the bounded admission ledger fails CLOSED at capacity: new work is
##     rejected with LEDGER_CAPACITY_EXCEEDED and no OperationId is forgotten
##     to make room (the oldest operations still replay as ALREADY_APPLIED).
##
## What this file deliberately does NOT claim:
##   - the literal 30-minute two-client soak predicate. That evidence must be
##     produced by a real-time two-client run and stays a separate gate; this
##     in-process loop is a repeat/idempotence regression, not soak evidence.

const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const ClosureScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const RouteScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")

const DOMAIN_ID := "p6-domain/outpost-world-state"
const ALICE := "player/alice"
const BOB := "player/bob"
const LEDGER_CAP := 200

var assertions := 0
var failures: Array[String] = []


## Canonical owners fixture (M4 Item Graph / P4 Construction / P5 stand-in).
class CanonicalSourcesOwner extends RefCounted:
	var construction := {"schema": "fixture.construction.v1", "revision": 0, "blocks": {}}
	var item_graph := {"schema": "fixture.item_graph.v1", "revision": 0, "containers": {}}
	var gameplay := {"schema": "fixture.gameplay.v1", "revision": 0, "players": {}, "tick": 0}
	var resource_mining := {"schema": "fixture.resource.v1", "revision": 0}
	var mutations := 0

	func apply_player_command(delta: Dictionary) -> Dictionary:
		var op := String(delta.get("op", ""))
		match op:
			"place_block":
				var pos: Array = delta.get("pos", [])
				var pos_key := "%d,%d,%d" % [int(pos[0]), int(pos[1]), int(pos[2])]
				if (construction["blocks"] as Dictionary).has(pos_key):
					return {"applied": false, "error_code": "POSITION_OCCUPIED"}
				construction["blocks"][pos_key] = String(delta.get("block_type", ""))
				construction["revision"] = int(construction["revision"]) + 1
			"break_block":
				var break_pos: Array = delta.get("pos", [])
				var break_key := "%d,%d,%d" % [int(break_pos[0]), int(break_pos[1]), int(break_pos[2])]
				if not (construction["blocks"] as Dictionary).has(break_key):
					return {"applied": false, "error_code": "UNKNOWN_BLOCK"}
				(construction["blocks"] as Dictionary).erase(break_key)
				construction["revision"] = int(construction["revision"]) + 1
			"container_create":
				item_graph["containers"][String(delta.get("container_id", ""))] = []
				item_graph["revision"] = int(item_graph["revision"]) + 1
			"container_add_item":
				var container_id := String(delta.get("container_id", ""))
				if not (item_graph["containers"] as Dictionary).has(container_id):
					return {"applied": false, "error_code": "UNKNOWN_CONTAINER"}
				item_graph["containers"][container_id].append(String(delta.get("item", "")))
				item_graph["revision"] = int(item_graph["revision"]) + 1
			"container_remove_item":
				var remove_container := String(delta.get("container_id", ""))
				if not (item_graph["containers"] as Dictionary).has(remove_container):
					return {"applied": false, "error_code": "UNKNOWN_CONTAINER"}
				var item := String(delta.get("item", ""))
				if not (item_graph["containers"][remove_container] as Array).has(item):
					return {"applied": false, "error_code": "UNKNOWN_ITEM"}
				(item_graph["containers"][remove_container] as Array).erase(item)
				item_graph["revision"] = int(item_graph["revision"]) + 1
			"player_move":
				gameplay["players"][String(delta.get("player_id", ""))] = {"pos": delta.get("pos", []), "rot": float(delta.get("rot", 0.0))}
				gameplay["revision"] = int(gameplay["revision"]) + 1
			"set_tick":
				gameplay["tick"] = int(delta.get("value", 0))
				gameplay["revision"] = int(gameplay["revision"]) + 1
			_:
				return {"applied": false, "error_code": "UNSUPPORTED_CANONICAL_OPERATION"}
		mutations += 1
		return {"applied": true, "error_code": ""}

	func export_sources() -> Dictionary:
		return {
			"gameplay": gameplay.duplicate(true),
			"item_graph": item_graph.duplicate(true),
			"construction": construction.duplicate(true),
			"resource_mining": resource_mining.duplicate(true),
		}

	func block_count() -> int:
		return (construction["blocks"] as Dictionary).size()

	func container_items(container_id: String) -> Array:
		return (item_graph["containers"].get(container_id, []) as Array).duplicate()

	func player_position(player_id: String) -> Dictionary:
		return (gameplay["players"].get(player_id, {}) as Dictionary).duplicate()

	func tick() -> int:
		return int(gameplay["tick"])


## Canonical replay owner fixture (M6 durable replay outbox stand-in).
class CanonicalReplayFixture extends RefCounted:
	var records := {}

	func commit_operation(operation_id: String, _command_type: String) -> void:
		records[operation_id] = true

	func has(operation_id: String) -> bool:
		return records.has(operation_id)


class CanonicalCommandHandler extends RefCounted:
	var owner: CanonicalSourcesOwner
	var replay: CanonicalReplayFixture
	var executions := 0

	func execute_command(command: Dictionary) -> Dictionary:
		executions += 1
		var operation_id := String(command.get("operation_id", ""))
		if replay.has(operation_id):
			return {"applied": false, "error_code": "ALREADY_COMMITTED_AT_CANONICAL_OWNER"}
		var outcome: Dictionary = owner.apply_player_command(Dictionary(command.get("delta", {})))
		if bool(outcome.get("applied", false)):
			replay.commit_operation(operation_id, String(command.get("command_kind", "")))
		return outcome


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.11-repeat-r3][FAIL] %s" % message)


func _command(operation_id: String, kind: String, delta: Dictionary) -> Dictionary:
	return {"domain_id": DOMAIN_ID, "command_kind": kind, "operation_id": operation_id, "delta": delta}


func _place(operation_id: String, pos: Array, block_type: String) -> Dictionary:
	return _command(operation_id, "PLACE_BLOCK", {"op": "place_block", "pos": pos, "block_type": block_type})


func _build_stack() -> Dictionary:
	var owner = CanonicalSourcesOwner.new()
	var replay = CanonicalReplayFixture.new()
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(LEDGER_CAP)
	var admission = AdmissionScript.new()
	var closure = ClosureScript.new()
	admission.configure(registry, ledger)
	closure.configure(registry, ledger)
	var handler = CanonicalCommandHandler.new()
	handler.owner = owner
	handler.replay = replay
	var route = RouteScript.new()
	route.configure(registry, ledger, admission, closure, handler)
	return {"owner": owner, "replay": replay, "registry": registry, "ledger": ledger, "route": route, "handler": handler}


func _init() -> void:
	var stack: Dictionary = _build_stack()
	var registry = stack["registry"]
	var route = stack["route"]
	var ledger = stack["ledger"]
	var owner = stack["owner"]
	var handler = stack["handler"]
	var s_alice := "client-session/repeat-alice"
	var s_bob := "client-session/repeat-bob"
	_assert(bool(registry.bind(s_alice, ALICE, "entity/alice-main").get("success", false)), "alice bind failed")
	_assert(bool(registry.bind(s_bob, BOB, "entity/bob-main").get("success", false)), "bob bind failed")

	var expected_blocks := {}
	var expected_containers := {}
	var expected_tick := 0
	var executed: Array = []

	# --- 110 placements ------------------------------------------------------
	for i in range(65):
		var operation_id := "op/repeat-a-place-%03d" % i
		var routed: Dictionary = route.route_command(s_alice, operation_id, _place(operation_id, [i, 0, 0], "stone"))
		_assert(bool(routed.get("success", false)) and String(routed["details"]["result"]) == "EXECUTED", "op %s not executed" % operation_id)
		expected_blocks["%d,0,0" % i] = "stone"
		executed.append(operation_id)
	for i in range(45):
		var operation_id := "op/repeat-b-place-%03d" % i
		var routed: Dictionary = route.route_command(s_bob, operation_id, _place(operation_id, [i, 1, 0], "wood"))
		_assert(bool(routed.get("success", false)) and String(routed["details"]["result"]) == "EXECUTED", "op %s not executed" % operation_id)
		expected_blocks["%d,1,0" % i] = "wood"
		executed.append(operation_id)
	# --- 25 breaks -----------------------------------------------------------
	for i in range(15):
		var operation_id := "op/repeat-a-break-%03d" % i
		var routed: Dictionary = route.route_command(s_alice, operation_id, _command(operation_id, "BREAK_BLOCK", {"op": "break_block", "pos": [i, 0, 0]}))
		_assert(bool(routed.get("success", false)) and String(routed["details"]["result"]) == "EXECUTED", "op %s not executed" % operation_id)
		expected_blocks.erase("%d,0,0" % i)
		executed.append(operation_id)
	for i in range(10):
		var operation_id := "op/repeat-b-break-%03d" % i
		var routed: Dictionary = route.route_command(s_bob, operation_id, _command(operation_id, "BREAK_BLOCK", {"op": "break_block", "pos": [i, 1, 0]}))
		_assert(bool(routed.get("success", false)) and String(routed["details"]["result"]) == "EXECUTED", "op %s not executed" % operation_id)
		expected_blocks.erase("%d,1,0" % i)
		executed.append(operation_id)
	# --- 8 containers + 21 items + 1 removal ---------------------------------
	for c in range(5):
		var container_id := "repeat-crate-a-%d" % c
		var create_id := "op/repeat-a-crate-%d" % c
		var created: Dictionary = route.route_command(s_alice, create_id, _command(create_id, "CONTAINER_CREATE", {"op": "container_create", "container_id": container_id}))
		_assert(bool(created.get("success", false)) and String(created["details"]["result"]) == "EXECUTED", "op %s not executed" % create_id)
		expected_containers[container_id] = []
		executed.append(create_id)
		for item_index in range(3):
			var item_op := "op/repeat-a-item-%d-%d" % [c, item_index]
			var item := "tool-a-%d-%d" % [c, item_index]
			var added: Dictionary = route.route_command(s_alice, item_op, _command(item_op, "CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": container_id, "item": item}))
			_assert(bool(added.get("success", false)) and String(added["details"]["result"]) == "EXECUTED", "op %s not executed" % item_op)
			(expected_containers[container_id] as Array).append(item)
			executed.append(item_op)
	for c in range(3):
		var container_id := "repeat-crate-b-%d" % c
		var create_id := "op/repeat-b-crate-%d" % c
		var created: Dictionary = route.route_command(s_bob, create_id, _command(create_id, "CONTAINER_CREATE", {"op": "container_create", "container_id": container_id}))
		_assert(bool(created.get("success", false)) and String(created["details"]["result"]) == "EXECUTED", "op %s not executed" % create_id)
		expected_containers[container_id] = []
		executed.append(create_id)
		for item_index in range(2):
			var item_op := "op/repeat-b-item-%d-%d" % [c, item_index]
			var item := "tool-b-%d-%d" % [c, item_index]
			var added: Dictionary = route.route_command(s_bob, item_op, _command(item_op, "CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": container_id, "item": item}))
			_assert(bool(added.get("success", false)) and String(added["details"]["result"]) == "EXECUTED", "op %s not executed" % item_op)
			(expected_containers[container_id] as Array).append(item)
			executed.append(item_op)
	var removed_item := "tool-b-0-0"
	var remove_id := "op/repeat-b-remove-item"
	var removed_op: Dictionary = route.route_command(s_bob, remove_id, _command(remove_id, "CONTAINER_REMOVE_ITEM", {"op": "container_remove_item", "container_id": "repeat-crate-b-0", "item": removed_item}))
	_assert(bool(removed_op.get("success", false)) and String(removed_op["details"]["result"]) == "EXECUTED", "op %s not executed" % remove_id)
	(expected_containers["repeat-crate-b-0"] as Array).erase(removed_item)
	executed.append(remove_id)
	# --- 25 player moves + 10 ticks -------------------------------------------
	for m in range(20):
		var operation_id := "op/repeat-a-move-%02d" % m
		var position: Array = [m, 7, 7]
		var moved: Dictionary = route.route_command(s_alice, operation_id, _command(operation_id, "PLAYER_MOVE", {"op": "player_move", "player_id": ALICE, "pos": position, "rot": 0.25 * m}))
		_assert(bool(moved.get("success", false)) and String(moved["details"]["result"]) == "EXECUTED", "op %s not executed" % operation_id)
		executed.append(operation_id)
	for m in range(5):
		var operation_id := "op/repeat-b-move-%02d" % m
		var position: Array = [m, 8, 8]
		var moved: Dictionary = route.route_command(s_bob, operation_id, _command(operation_id, "PLAYER_MOVE", {"op": "player_move", "player_id": BOB, "pos": position, "rot": 1.5 * m}))
		_assert(bool(moved.get("success", false)) and String(moved["details"]["result"]) == "EXECUTED", "op %s not executed" % operation_id)
		executed.append(operation_id)
	for t in range(10):
		var operation_id := "op/repeat-tick-%02d" % t
		expected_tick = t + 1
		var ticked: Dictionary = route.route_command(s_alice, operation_id, _command(operation_id, "SET_TICK", {"op": "set_tick", "value": expected_tick}))
		_assert(bool(ticked.get("success", false)) and String(ticked["details"]["result"]) == "EXECUTED", "op %s not executed" % operation_id)
		executed.append(operation_id)

	_assert(executed.size() == LEDGER_CAP, "operation mix filled the ledger cap exactly: %d" % executed.size())
	_assert(owner.block_count() == expected_blocks.size(), "canonical block count diverged from the model")
	for pos_key in expected_blocks.keys():
		_assert(String(owner.export_sources()["construction"]["blocks"].get(String(pos_key), "")) == String(expected_blocks[pos_key]), "block %s diverged" % String(pos_key))
	for container_id in expected_containers.keys():
		_assert(owner.container_items(String(container_id)) == expected_containers[container_id], "container %s diverged" % String(container_id))
	_assert(owner.player_position(ALICE)["pos"] == [19, 7, 7], "alice final position diverged")
	_assert(owner.player_position(BOB)["pos"] == [4, 8, 8], "bob final position diverged")
	_assert(owner.tick() == expected_tick, "final tick diverged")
	var executions_after_stream: int = handler.executions

	# --- capacity: new work fails CLOSED; nothing is forgotten ---------------
	var overflow: Dictionary = route.route_command(s_alice, "op/repeat-overflow", _place("op/repeat-overflow", [99, 9, 9], "glass"))
	_assert(not bool(overflow.get("success", false)) and String(overflow.get("error_code", "")) == "LEDGER_CAPACITY_EXCEEDED", "capacity overflow was admitted")
	_assert(int(ledger.get_report()["counters"]["retired"]) == 0, "an OperationId was retired to make room")
	_assert(int(ledger.get_report()["applied_count"]) == LEDGER_CAP, "capacity rejection changed the applied set")

	# --- FULL replay: every executed operation id mutates nothing ------------
	for row in executed:
		var replayed: Dictionary = route.route_command("client-session/repeat-alice" if String(row).find("-a-") != -1 or String(row).find("-tick-") != -1 else "client-session/repeat-bob", String(row), _replay_command_for(String(row)))
		_assert(bool(replayed.get("success", false)) and String(replayed["details"]["result"]) == "ALREADY_APPLIED", "replay of %s not deduplicated" % String(row))
	_assert(handler.executions == executions_after_stream, "replay pass re-invoked the handler")
	_assert(owner.block_count() == expected_blocks.size(), "replay pass mutated canonical blocks")
	_assert(owner.tick() == expected_tick, "replay pass mutated the tick")
	_assert(owner.container_items("repeat-crate-b-0") == expected_containers["repeat-crate-b-0"], "replay pass mutated containers")
	_assert(int(route.get_report()["counters"]["replayed"]) == executed.size(), "route replay counter mismatch")

	_finish()


func _replay_command_for(operation_id: String) -> Dictionary:
	# The replay content is intentionally DIFFERENT from the original payload:
	# deduplication must be keyed by identity, not by payload equality.
	return _place(operation_id, [77, 7, 7], "obsidian")


func _finish() -> void:
	if failures.is_empty():
		print("[p6.11-repeat-r3] all %d assertions passed (%d-op stream + full replay + capacity fence)" % [assertions, LEDGER_CAP])
		print("[p6.11-repeat-r3][stage] REPEAT_IDEMPOTENCE_PASS")
		print("[p6.11-repeat-r3][scope] the literal 30-minute two-client soak predicate is NOT claimed here; it requires a separate real-time two-client run")
		quit(0)
	else:
		print("[p6.11-repeat-r3] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
