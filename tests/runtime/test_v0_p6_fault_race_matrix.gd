extends SceneTree

## P6 R3 rewrite of the P6.10 fault/race matrix.
##
## Six fault scenarios over the R3 boundary (gateway route -> admission
## -> ledger -> canonical owners fixture -> read-only projection -> delegated
## authoritative persistence):
##   1. reconnect during active writes: mid-write transport change -> rebind;
##   2. simultaneous same-block placement: exactly-one deterministic winner,
##      loser consumed with a clean POSITION_OCCUPIED rejection;
##   3. shadow rejection during an active session: every shadow write surface
##      fails closed with SHADOW_CANNOT_WRITE, delegated checkpoint untouched;
##   4. ledger replay under concurrent sessions for one logical player:
##      stale session dead, live session deduplicates through the ledger;
##   5. persistence during active writes: interleaved delegated checkpoints
##      stay atomic (no pending/partial files) and recover byte-stably;
##   6. pending crash windows: PENDING retries are rejected fail-closed and
##      only explicit reconciliation completes an operation.
##
## SCOPE: in-process fault semantics only. Literal process-restart and soak
## evidence stay bound to their separate real-time gates.

const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const ClosureScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const RouteScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const ShadowScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")
const PersistenceAdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const RepositoryScript = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const CoordinatorScript = preload("res://scripts/persistence/authoritative_recovery_coordinator.gd")

const DOMAIN_ID := "p6-domain/outpost-world-state"
const ALICE := "player/alice"
const BOB := "player/bob"

var base_dir := "res://artifacts/test-results/p6-r3-fault-race-%d" % OS.get_process_id()

var assertions := 0
var failures: Array[String] = []


## Canonical owners fixture (M4 Item Graph / P4 Construction / P5 stand-in).
class CanonicalSourcesOwner extends RefCounted:
	var construction := {"schema": "fixture.construction.v1", "revision": 0, "blocks": {}}
	var item_graph := {"schema": "fixture.item_graph.v1", "revision": 0, "containers": {}}
	var gameplay := {"schema": "fixture.gameplay.v1", "revision": 0, "players": {}, "tick": 0}
	var resource_mining := {"schema": "fixture.resource.v1", "revision": 0}
	var position_conflicts := 0

	func apply_player_command(delta: Dictionary) -> Dictionary:
		var op := String(delta.get("op", ""))
		match op:
			"place_block":
				var pos: Array = delta.get("pos", [])
				var pos_key := "%d,%d,%d" % [int(pos[0]), int(pos[1]), int(pos[2])]
				if (construction["blocks"] as Dictionary).has(pos_key):
					position_conflicts += 1
					return {"applied": false, "error_code": "POSITION_OCCUPIED"}
				construction["blocks"][pos_key] = String(delta.get("block_type", ""))
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
			"player_move":
				gameplay["players"][String(delta.get("player_id", ""))] = {"pos": delta.get("pos", []), "rot": float(delta.get("rot", 0.0))}
				gameplay["revision"] = int(gameplay["revision"]) + 1
			"set_tick":
				gameplay["tick"] = int(delta.get("value", 0))
				gameplay["revision"] = int(gameplay["revision"]) + 1
			_:
				return {"applied": false, "error_code": "UNSUPPORTED_CANONICAL_OPERATION"}
		return {"applied": true, "error_code": ""}

	func export_sources() -> Dictionary:
		return {
			"gameplay": gameplay.duplicate(true),
			"item_graph": item_graph.duplicate(true),
			"construction": construction.duplicate(true),
			"resource_mining": resource_mining.duplicate(true),
		}

	func import_sources(sources: Dictionary) -> Dictionary:
		for name in ["gameplay", "item_graph", "construction", "resource_mining"]:
			if not sources.has(name) or typeof(sources[name]) != TYPE_DICTIONARY:
				return {"success": false, "error_code": "INVALID_CANONICAL_SOURCES"}
		gameplay = (sources["gameplay"] as Dictionary).duplicate(true)
		item_graph = (sources["item_graph"] as Dictionary).duplicate(true)
		construction = (sources["construction"] as Dictionary).duplicate(true)
		resource_mining = (sources["resource_mining"] as Dictionary).duplicate(true)
		return {"success": true, "error_code": ""}

	func block_count() -> int:
		return (construction["blocks"] as Dictionary).size()

	func block_type_at(pos_key: String) -> String:
		return String(construction["blocks"].get(pos_key, ""))

	func has_block(pos_key: String) -> bool:
		return (construction["blocks"] as Dictionary).has(pos_key)


## Authority fixture exporting the accepted authoritative recovery shape.
class CanonicalAuthorityFixture extends RefCounted:
	const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
	const AUTHORITY_OWNER_ID := "authority/p6-r3/canonical-fixture"
	const LOGICAL_SESSION_ID := "session/p6-r3/fault-race"

	var owner: CanonicalSourcesOwner
	var authority_epoch := 1
	var state_revision := 0
	var server_tick := 0

	func _init(p_owner: CanonicalSourcesOwner) -> void:
		owner = p_owner

	func export_recovery_state() -> Dictionary:
		var snapshot: Dictionary = EntitySnapshot.create(
			"snapshot/p6-r3/%08d" % state_revision,
			"entity/p6-r3/outpost-world",
			"planet_simulator.canonical_world",
			state_revision,
			AUTHORITY_OWNER_ID,
			authority_epoch,
			server_tick,
			_spatial_ref(),
			{"region_id": "region/p6-r3"},
			{},
			{"p6_canonical_sources": owner.export_sources()}
		)
		if snapshot.is_empty():
			return {}
		return {
			"schema": "p6-r3.fixture.canonical_authority.v1",
			"authority_owner_id": AUTHORITY_OWNER_ID,
			"authority_epoch": authority_epoch,
			"server_tick": server_tick,
			"session_id": LOGICAL_SESSION_ID,
			"current_snapshot": snapshot,
		}

	func restore_recovery_state(value: Dictionary) -> Dictionary:
		var snapshot_value: Variant = value.get("current_snapshot", null)
		if not snapshot_value is Dictionary:
			return {"success": false, "error_code": "INVALID_RECOVERY_STATE"}
		var components_value: Variant = (snapshot_value as Dictionary).get("domain_components", null)
		if not components_value is Dictionary:
			return {"success": false, "error_code": "INVALID_RECOVERY_STATE"}
		var sources_value: Variant = (components_value as Dictionary).get("p6_canonical_sources", null)
		if not sources_value is Dictionary:
			return {"success": false, "error_code": "INVALID_RECOVERY_STATE"}
		var imported: Dictionary = owner.import_sources(Dictionary(sources_value))
		if not bool(imported.get("success", false)):
			return imported
		authority_epoch = int((snapshot_value as Dictionary).get("authority_epoch", 1))
		state_revision = int((snapshot_value as Dictionary).get("state_revision", 0))
		server_tick = int((snapshot_value as Dictionary).get("server_tick", 0))
		return {
			"success": true,
			"error_code": "",
			"details": {"state_revision": state_revision, "server_tick": server_tick, "restored": true},
		}

	func advance() -> void:
		state_revision += 1
		server_tick += 1

	func _spatial_ref() -> Dictionary:
		return {
			"schema": EntitySnapshot.SPATIAL_REF_SCHEMA,
			"universe_id": "planet-simulator",
			"instance_id": "p6-r3",
			"space_id": "networked-gameplay",
			"frame_id": "frame/p6-r3",
			"position_m": [0.0, 0.0, 0.0],
			"rotation_xyzw": [0.0, 0.0, 0.0, 1.0],
			"linear_velocity_mps": [0.0, 0.0, 0.0],
			"angular_velocity_rps": [0.0, 0.0, 0.0],
			"sample_time_s": float(server_tick),
		}


## Canonical replay owner fixture (M6 durable replay outbox stand-in).
class CanonicalReplayFixture extends RefCounted:
	const SCHEMA := "p6-r3.fixture.replay.v1"

	var records := {}

	func commit_operation(operation_id: String, command_type: String) -> void:
		records[operation_id] = {"command_type": command_type, "state": "COMMITTED"}

	func has(operation_id: String) -> bool:
		return records.has(operation_id)

	func to_dict() -> Dictionary:
		return {"schema": SCHEMA, "records": records.duplicate(true)}

	func load_dict(value: Dictionary, _current_tick: int = -1) -> Dictionary:
		if String(value.get("schema", "")) != SCHEMA:
			return {"success": false, "error_code": "INVALID_REPLAY_STATE"}
		var loaded_value: Variant = value.get("records", null)
		if not loaded_value is Dictionary:
			return {"success": false, "error_code": "INVALID_REPLAY_STATE"}
		records = Dictionary(loaded_value).duplicate(true)
		return {"success": true, "error_code": "", "details": {"records": (records as Dictionary).size()}}


class CanonicalCommandHandler extends RefCounted:
	var authority: CanonicalAuthorityFixture
	var replay: CanonicalReplayFixture
	var executions := 0

	func execute_command(command: Dictionary) -> Dictionary:
		executions += 1
		var operation_id := String(command.get("operation_id", ""))
		if replay.has(operation_id):
			return {"applied": false, "error_code": "ALREADY_COMMITTED_AT_CANONICAL_OWNER"}
		var outcome: Dictionary = authority.owner.apply_player_command(Dictionary(command.get("delta", {})))
		if bool(outcome.get("applied", false)):
			replay.commit_operation(operation_id, String(command.get("command_kind", "")))
			authority.advance()
		return outcome


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.10-fault-race-r3][FAIL] %s" % message)


func _assert_rejected(outcome: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(outcome.get("success", false)) and String(outcome.get("error_code", "")) == error_code,
			"%s (got %s)" % [message, String(outcome.get("error_code", "<success>"))])


func _command(operation_id: String, kind: String, delta: Dictionary) -> Dictionary:
	return {"domain_id": DOMAIN_ID, "command_kind": kind, "operation_id": operation_id, "delta": delta}


func _place(operation_id: String, pos: Array, block_type: String) -> Dictionary:
	return _command(operation_id, "PLACE_BLOCK", {"op": "place_block", "pos": pos, "block_type": block_type})


## One fresh boot: canonical owners + replay owner + full P6 admission stack.
func _boot_stack() -> Dictionary:
	var authority = CanonicalAuthorityFixture.new(CanonicalSourcesOwner.new())
	var replay = CanonicalReplayFixture.new()
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(256)
	var admission = AdmissionScript.new()
	var closure = ClosureScript.new()
	admission.configure(registry, ledger)
	closure.configure(registry, ledger)
	var handler = CanonicalCommandHandler.new()
	handler.authority = authority
	handler.replay = replay
	var route = RouteScript.new()
	route.configure(registry, ledger, admission, closure, handler)
	return {
		"authority": authority, "replay": replay, "registry": registry,
		"ledger": ledger, "admission": admission, "route": route, "handler": handler,
	}


func _bind(stack: Dictionary, session: String, logical: String, entity: String) -> void:
	var bound: Dictionary = stack["registry"].bind(session, logical, entity)
	_assert(bool(bound.get("success", false)), "bind failed: %s -> %s" % [session, logical])


## ============================================================================
## Scenario 1: reconnect during active writes
## ============================================================================
func _scenario_reconnect_during_writes() -> void:
	var stack := _boot_stack()
	var registry = stack["registry"]
	var route = stack["route"]
	var authority = stack["authority"]
	var handler = stack["handler"]
	var s_old := "client-session/alice-s1-old"
	var s_new := "client-session/alice-s1-new"
	_bind(stack, s_old, ALICE, "entity/alice-main")
	for row in [["op/s1-1", _place("op/s1-1", [1, 0, 1], "stone")], ["op/s1-2", _place("op/s1-2", [2, 0, 2], "wood")], ["op/s1-3", _place("op/s1-3", [3, 0, 3], "brick")]]:
		var routed: Dictionary = route.route_command(s_old, String(row[0]), row[1])
		_assert(bool(routed.get("success", false)) and String(routed["details"]["result"]) == "EXECUTED" and bool(routed["details"]["outcome"]["applied"]), "s1 pre-disconnect op %s not applied" % String(row[0]))
	_assert(authority.owner.block_count() == 3, "s1 pre-disconnect block count wrong")
	_assert_rejected(route.route_command(s_new, "op/s1-2", _place("op/s1-2", [2, 0, 2], "wood")), "UNKNOWN_SESSION", "s1 early new-session route not rejected")
	_assert(authority.owner.block_count() == 3, "s1 early rejected route corrupted state")
	var rebind: Dictionary = registry.rebind_on_transport_change(s_old, s_new)
	_assert(bool(rebind.get("success", false)) and String(rebind["details"]["preserved_logical_player_id"]) == ALICE, "s1 rebind lost logical identity")
	for pos_key in ["1,0,1", "2,0,2", "3,0,3"]:
		_assert(authority.owner.has_block(pos_key), "s1 lost block %s across reconnect" % pos_key)
	var replayed: Dictionary = route.route_command(s_new, "op/s1-2", _place("op/s1-2", [2, 0, 2], "wood"))
	_assert(bool(replayed.get("success", false)) and String(replayed["details"]["result"]) == "ALREADY_APPLIED", "s1 post-reconnect replay not deduplicated")
	_assert(authority.owner.block_count() == 3, "s1 replay duplicated a block")
	var continued: Dictionary = route.route_command(s_new, "op/s1-4", _place("op/s1-4", [4, 0, 4], "glass"))
	_assert(bool(continued.get("success", false)) and String(continued["details"]["result"]) == "EXECUTED", "s1 post-reconnect write not applied")
	_assert(authority.owner.block_count() == 4, "s1 final block count wrong")
	_assert_rejected(route.route_command(s_old, "op/s1-5", _place("op/s1-5", [5, 0, 5], "stone")), "UNKNOWN_SESSION", "s1 stale session still routed")
	_assert(authority.owner.block_count() == 4, "s1 stale route mutated state")
	_assert(handler.executions == 4, "s1 handler execution count wrong: %d" % handler.executions)


## ============================================================================
## Scenario 2: simultaneous same-block placement (deterministic winner)
## ============================================================================
func _scenario_same_block_race() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var authority = stack["authority"]
	var handler = stack["handler"]
	var ledger = stack["ledger"]
	var s_alice := "client-session/alice-s2"
	var s_bob := "client-session/bob-s2"
	_bind(stack, s_alice, ALICE, "entity/alice-main")
	_bind(stack, s_bob, BOB, "entity/bob-main")
	var race_pos: Array = [7, 0, 7]
	var a: Dictionary = route.route_command(s_alice, "op/race-a", _place("op/race-a", race_pos, "stone"))
	_assert(bool(a.get("success", false)) and String(a["details"]["result"]) == "EXECUTED" and bool(a["details"]["outcome"]["applied"]), "s2 first placer not applied")
	var b: Dictionary = route.route_command(s_bob, "op/race-b", _place("op/race-b", race_pos, "wood"))
	_assert(bool(b.get("success", false)) and String(b["details"]["result"]) == "EXECUTED", "s2 loser route not consumed")
	if bool(b.get("success", false)):
		_assert(not bool(b["details"]["outcome"]["applied"]), "s2 loser wrongly applied")
		_assert(String(b["details"]["outcome"]["error_code"]) == "POSITION_OCCUPIED", "s2 loser rejection not clean")
	_assert(authority.owner.block_type_at("7,0,7") == "stone", "s2 winner block wrong")
	_assert(authority.owner.block_count() == 1, "s2 duplicate block at race position")
	var loser_retry: Dictionary = route.route_command(s_bob, "op/race-b", _place("op/race-b", race_pos, "wood"))
	_assert(bool(loser_retry.get("success", false)) and String(loser_retry["details"]["result"]) == "ALREADY_APPLIED", "s2 loser retry not deduplicated")
	_assert(authority.owner.block_count() == 1, "s2 loser retry mutated state")
	_assert(handler.executions == 2, "s2 handler execution count wrong: %d" % handler.executions)
	var follow_up: Dictionary = route.route_command(s_bob, "op/race-b-2", _place("op/race-b-2", [8, 0, 8], "wood"))
	_assert(bool(follow_up.get("success", false)) and String(follow_up["details"]["result"]) == "EXECUTED", "s2 loser follow-up not applied")
	_assert(authority.owner.block_count() == 2, "s2 final block count wrong")
	_assert(int(ledger.get_report()["applied_count"]) == 3, "s2 ledger applied count wrong")


## ============================================================================
## Scenario 3: shadow rejection during an active session
## ============================================================================
func _scenario_shadow_rejection_during_session() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var authority = stack["authority"]
	var s_alice := "client-session/alice-s3"
	_bind(stack, s_alice, ALICE, "entity/alice-main")
	var repository = RepositoryScript.new()
	_assert(bool(repository.configure(_persistence_root("s3")).get("success", false)), "s3 repository configure failed")
	var coordinator = CoordinatorScript.new()
	_assert(bool(coordinator.configure(repository, authority, stack["replay"]).get("success", false)), "s3 coordinator configure failed")
	var p6_owner = PersistenceAdapterScript.new()
	_assert(bool(p6_owner.configure(coordinator).get("success", false)), "s3 adapter configure failed")
	var op1: Dictionary = route.route_command(s_alice, "op/s3-1", _place("op/s3-1", [31, 0, 31], "stone"))
	var op2: Dictionary = route.route_command(s_alice, "op/s3-2", _place("op/s3-2", [32, 0, 32], "wood"))
	_assert(bool(op1.get("success", false)) and bool(op2.get("success", false)), "s3 setup writes failed")
	_assert(bool(p6_owner.persist_checkpoint("checkpoint/p6-r3/fault/s3/001", 1, 0, "op/s3-2").get("success", false)), "s3 initial checkpoint failed")

	# shadow reconstructs the CURRENT canonical projection read-only
	var projection = ProjectionScript.new()
	_assert(bool(projection.configure_from_canonical_sources(authority.owner.export_sources()).get("success", false)), "s3 projection configure failed")
	var active_checksum: String = projection.compute_checksum()
	var shadow = ShadowScript.new()
	var recon: Dictionary = shadow.configure(projection)
	_assert(bool(recon.get("success", false)) and String(recon["details"]["checksum"]) == active_checksum, "s3 shadow reconstruction diverged")
	_assert(String(shadow.get_mode()) == "SHADOW", "s3 shadow mode drifted")
	# FAULT: shadow write attempts while the active authority is live
	_assert_rejected(shadow.apply_delta({"op": "place_block", "pos": [33, 0, 33], "block_type": "brick"}), "SHADOW_CANNOT_WRITE", "s3 shadow apply_delta not rejected")
	_assert_rejected(shadow.persist_state(), "SHADOW_CANNOT_WRITE", "s3 shadow persist_state not rejected")
	_assert_rejected(shadow.deserialize({"schema": "planet_simulator.p6_outpost_state.v1"}), "SHADOW_CANNOT_WRITE", "s3 shadow deserialize not rejected")
	_assert_rejected(shadow.promote_to_active(), "SHADOW_PROMOTION_REQUIRES_CANONICAL_AUTHORITY_TRANSFER", "s3 shadow self-promotion not rejected")
	_assert(not authority.owner.has_block("33,0,33"), "s3 shadow write leaked into canonical sources")
	# no corruption: the delegated checkpoint still holds the pre-fault truth
	_assert(bool(p6_owner.recover_latest().get("success", false)), "s3 delegated recovery after shadow writes failed")
	_assert(authority.owner.block_count() == 2, "s3 canonical truth mutated by shadow writes")
	# the active authority keeps accepting + persisting work
	var post_fault: Dictionary = route.route_command(s_alice, "op/s3-4", _place("op/s3-4", [34, 0, 34], "glass"))
	_assert(bool(post_fault.get("success", false)) and String(post_fault["details"]["result"]) == "EXECUTED", "s3 active post-fault write not applied")
	_assert(bool(p6_owner.persist_checkpoint("checkpoint/p6-r3/fault/s3/002", 2, 1, "op/s3-4").get("success", false)), "s3 post-fault checkpoint failed")
	_assert(bool(p6_owner.recover_latest().get("success", false)), "s3 final recovery failed")
	_assert(authority.owner.block_count() == 3, "s3 final block count wrong")
	# a defensive shadow copy cannot poison truth
	var copy: Variant = shadow.get_projection()
	_assert(copy != null, "s3 shadow get_projection returned null")
	if copy != null:
		_assert(not bool(copy.apply_delta({"op": "place_block", "pos": [35, 0, 35], "block_type": "stone"})), "s3 defensive copy became a canonical writer")
	_assert(not authority.owner.has_block("35,0,35"), "s3 copy mutation poisoned canonical truth")
	_assert(repository.list_pending_files().is_empty(), "s3 repository left a pending file behind")


## ============================================================================
## Scenario 4: ledger replay under concurrent sessions for one logical player
## ============================================================================
func _scenario_ledger_concurrent_sessions() -> void:
	var stack := _boot_stack()
	var registry = stack["registry"]
	var route = stack["route"]
	var ledger = stack["ledger"]
	var authority = stack["authority"]
	var handler = stack["handler"]
	var s1 := "client-session/alice-s4-a"
	var s2 := "client-session/alice-s4-b"
	_bind(stack, s1, ALICE, "entity/alice-main")
	var op_x: Dictionary = route.route_command(s1, "op/s4-x", _place("op/s4-x", [21, 0, 21], "stone"))
	_assert(bool(op_x.get("success", false)) and String(op_x["details"]["result"]) == "EXECUTED", "s4 op x not applied")
	var dup_bind: Dictionary = registry.bind(s2, ALICE, "entity/alice-main")
	_assert(not bool(dup_bind.get("success", true)) and String(dup_bind.get("error_code", "")) == "LOGICAL_PLAYER_ALREADY_LIVE", "s4 duplicate live bind not rejected")
	_assert(bool(registry.rebind_on_transport_change(s1, s2).get("success", false)), "s4 rebind failed")
	var replay_x: Dictionary = route.route_command(s2, "op/s4-x", _place("op/s4-x", [21, 0, 21], "stone"))
	_assert(bool(replay_x.get("success", false)) and String(replay_x["details"]["result"]) == "ALREADY_APPLIED", "s4 op x replay through new session not deduplicated")
	_assert(handler.executions == 1, "s4 op x executed twice: %d" % handler.executions)
	_assert_rejected(route.route_command(s1, "op/s4-y", _place("op/s4-y", [22, 0, 22], "stone")), "UNKNOWN_SESSION", "s4 stale session routed op y")
	var op_y: Dictionary = route.route_command(s2, "op/s4-y", _place("op/s4-y", [22, 0, 22], "stone"))
	_assert(bool(op_y.get("success", false)) and String(op_y["details"]["result"]) == "EXECUTED", "s4 op y not applied")
	var dup_y: Dictionary = route.route_command(s2, "op/s4-y", _place("op/s4-y", [22, 0, 22], "stone"))
	_assert(bool(dup_y.get("success", false)) and String(dup_y["details"]["result"]) == "ALREADY_APPLIED", "s4 op y duplicate not deduplicated")
	_assert(authority.owner.block_count() == 2, "s4 final block count wrong")
	_assert(authority.owner.has_block("21,0,21") and authority.owner.has_block("22,0,22"), "s4 lost a block across sessions")
	_assert(handler.executions == 2, "s4 handler execution count wrong: %d" % handler.executions)
	_assert(int(ledger.get_report()["applied_count"]) == 2, "s4 ledger applied count wrong")
	_assert(int(route.get_report()["counters"]["replayed"]) == 2, "s4 route replay counter wrong")


## ============================================================================
## Scenario 5: persistence during active writes
## ============================================================================
func _scenario_persistence_during_writes() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var authority = stack["authority"]
	var repository = RepositoryScript.new()
	_assert(bool(repository.configure(_persistence_root("s5")).get("success", false)), "s5 repository configure failed")
	var coordinator = CoordinatorScript.new()
	_assert(bool(coordinator.configure(repository, authority, stack["replay"]).get("success", false)), "s5 coordinator configure failed")
	var p6_owner = PersistenceAdapterScript.new()
	_assert(bool(p6_owner.configure(coordinator).get("success", false)), "s5 adapter configure failed")
	var s_alice := "client-session/alice-s5"
	_bind(stack, s_alice, ALICE, "entity/alice-main")
	# writes stream in while delegated checkpoints interleave with them
	for row in [
		["op/s5-1", _place("op/s5-1", [41, 0, 41], "stone")],
		["op/s5-2", _place("op/s5-2", [42, 0, 42], "wood")],
	]:
		var routed: Dictionary = route.route_command(s_alice, String(row[0]), row[1])
		_assert(bool(routed.get("success", false)) and String(routed["details"]["result"]) == "EXECUTED", "s5 op %s not applied" % String(row[0]))
	_assert(bool(p6_owner.persist_checkpoint("checkpoint/p6-r3/fault/s5/001", 1, 0, "op/s5-2").get("success", false)), "s5 mid-stream checkpoint failed")
	_assert(repository.list_pending_files().is_empty(), "s5 mid-stream checkpoint left a pending file behind")
	# a load racing the active session sees a COMPLETE consistent prefix
	_assert(bool(p6_owner.recover_latest().get("success", false)), "s5 mid-stream recovery failed (partial write?)")
	_assert(authority.owner.block_count() == 2, "s5 mid-stream recovery diverged from live state")
	# more writes land while the bytes are already on disk
	for row in [
		["op/s5-3", _place("op/s5-3", [43, 0, 43], "brick")],
		["op/s5-4", _command("op/s5-4", "CONTAINER_CREATE", {"op": "container_create", "container_id": "s5-crate"})],
		["op/s5-5", _command("op/s5-5", "CONTAINER_ADD_ITEM", {"op": "container_add_item", "container_id": "s5-crate", "item": "pickaxe"})],
		["op/s5-6", _command("op/s5-6", "PLAYER_MOVE", {"op": "player_move", "player_id": ALICE, "pos": [9, 0, 9], "rot": 2.5})],
		["op/s5-7", _command("op/s5-7", "SET_TICK", {"op": "set_tick", "value": 55})],
	]:
		var routed: Dictionary = route.route_command(s_alice, String(row[0]), row[1])
		_assert(bool(routed.get("success", false)) and String(routed["details"]["result"]) == "EXECUTED", "s5 op %s not applied" % String(row[0]))
	_assert(bool(p6_owner.persist_checkpoint("checkpoint/p6-r3/fault/s5/002", 2, 1, "op/s5-7").get("success", false)), "s5 final checkpoint failed")
	_assert(repository.list_pending_files().is_empty(), "s5 final checkpoint left a pending file behind")
	# restore into a completely fresh boot: bytes only
	var boot_b := _boot_stack()
	var authority_b = boot_b["authority"]
	var replay_b = boot_b["replay"]
	var repository_b = RepositoryScript.new()
	repository_b.configure(_persistence_root("s5"))
	var coordinator_b = CoordinatorScript.new()
	coordinator_b.configure(repository_b, authority_b, replay_b)
	var p6_owner_b = PersistenceAdapterScript.new()
	p6_owner_b.configure(coordinator_b)
	var loaded: Dictionary = p6_owner_b.recover_latest()
	_assert(bool(loaded.get("success", false)), "s5 restore recovery failed")
	if bool(loaded.get("success", false)):
		_assert(int(loaded["details"]["checkpoint"]["generation"]) == 2, "s5 restored generation mismatch")
	_assert(authority_b.owner.block_count() == 3, "s5 restored block count wrong")
	_assert((authority_b.owner.export_sources()["item_graph"]["containers"] as Dictionary).has("s5-crate"), "s5 restored container missing")
	_assert(((authority_b.owner.export_sources()["item_graph"]["containers"] as Dictionary)["s5-crate"] as Array).has("pickaxe"), "s5 restored container item missing")
	_assert((authority_b.owner.export_sources()["gameplay"]["players"] as Dictionary).has(ALICE), "s5 restored player missing")
	_assert(int(authority_b.owner.export_sources()["gameplay"]["tick"]) == 55, "s5 restored tick wrong")
	_assert(replay_b.has("op/s5-7") and replay_b.has("op/s5-1"), "s5 restored replay records missing")


## ============================================================================
## Scenario 6: pending crash windows (fail-closed admission semantics)
## ============================================================================
func _scenario_pending_windows() -> void:
	var stack := _boot_stack()
	var route = stack["route"]
	var admission = stack["admission"]
	var ledger = stack["ledger"]
	var authority = stack["authority"]
	var handler = stack["handler"]
	var s_a := "client-session/alice-s6-a"
	_bind(stack, s_a, ALICE, "entity/alice-main")
	_assert(authority.owner.block_count() == 0, "s6 unexpected initial state")
	# window A: admission reserved PENDING, handler never ran
	var admit_a: Dictionary = admission.admit(ALICE, "op/s6-2", DOMAIN_ID, _place("op/s6-2", [52, 0, 52], "wood"))
	_assert(bool(admit_a.get("success", false)), "s6 window A admission failed")
	_assert(ledger.is_pending(ALICE, "op/s6-2"), "s6 window A reservation missing")
	# a retry of the SAME operation id must be rejected before the handler
	_assert_rejected(route.route_command(s_a, "op/s6-2", _place("op/s6-2", [52, 0, 52], "wood")), "OPERATION_PENDING", "s6 window A retry not rejected fail-closed")
	_assert(handler.executions == 0, "s6 window A retry reached the handler")
	_assert(not authority.owner.has_block("52,0,52"), "s6 window A mutated canonical sources")
	# window B: handler executed, completion never recorded
	var admit_b: Dictionary = admission.admit(ALICE, "op/s6-3", DOMAIN_ID, _place("op/s6-3", [53, 0, 53], "brick"))
	_assert(bool(admit_b.get("success", false)), "s6 window B admission failed")
	var window_b_outcome: Dictionary = handler.execute_command(_place("op/s6-3", [53, 0, 53], "brick"))
	_assert(bool(window_b_outcome.get("applied", false)), "s6 window B canonical effect failed")
	_assert(authority.owner.has_block("53,0,53"), "s6 window B block missing")
	_assert(ledger.is_pending(ALICE, "op/s6-3"), "s6 window B reservation missing")
	_assert_rejected(route.route_command(s_a, "op/s6-3", _place("op/s6-3", [53, 0, 53], "brick")), "OPERATION_PENDING", "s6 window B retry not rejected fail-closed")
	_assert(handler.executions == 1, "s6 window B retry reached the handler again")
	# explicit reconciliation is the ONLY completion path
	_assert(bool(admission.complete(ALICE, "op/s6-3").get("success", false)), "s6 explicit completion of op/s6-3 failed")
	_assert(ledger.is_applied(ALICE, "op/s6-3"), "s6 completion did not land in the ledger")
	_assert(bool(admission.complete(ALICE, "op/s6-2").get("success", false)), "s6 explicit completion of op/s6-2 failed")
	_assert(int(ledger.get_report()["pending_count"]) == 0, "s6 pending residue after reconciliation")
	_assert(int(ledger.get_report()["applied_count"]) == 2, "s6 applied count wrong")
	# unknown completion stays fail-closed
	_assert(not bool(ledger.complete_pending(ALICE, "op/s6-unknown").get("success", true)), "s6 unknown completion not rejected")
	_assert(authority.owner.block_count() == 1, "s6 final block count wrong")


var _scenario_roots: Dictionary = {}

func _persistence_root(scenario: String) -> String:
	if not _scenario_roots.has(scenario):
		var path: String = ProjectSettings.globalize_path(base_dir).path_join(scenario).path_join("persistence")
		_remove_tree(ProjectSettings.globalize_path(base_dir).path_join(scenario))
		DirAccess.make_dir_recursive_absolute(path)
		_scenario_roots[scenario] = path
	return String(_scenario_roots[scenario])


func _init() -> void:
	var root := ProjectSettings.globalize_path(base_dir)
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	_scenario_reconnect_during_writes()
	_scenario_same_block_race()
	_scenario_shadow_rejection_during_session()
	_scenario_ledger_concurrent_sessions()
	_scenario_persistence_during_writes()
	_scenario_pending_windows()
	_remove_tree(root)
	if failures.is_empty():
		print("[p6.10-fault-race-r3] all %d assertions passed across 6 fault scenarios" % assertions)
		print("[p6.10-fault-race-r3][stage] FAULT_RACE_MATRIX_PASS")
		quit(0)
	else:
		print("[p6.10-fault-race-r3] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
