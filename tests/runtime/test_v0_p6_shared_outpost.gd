extends SceneTree

## P6 R3 rewrite of the P6.7 shared-outpost integration.
##
## Two identity-registry players share ONE canonical world through the full P6
## admission boundary (identity registry -> gateway command route -> admission
## -> operation ledger) with mutations landing on a CANONICAL OWNERS fixture
## that stands in for the accepted M4 Item Graph / P4 Construction / P5
## gameplay surfaces. P6OutpostState is only a read-only projection rebuilt
## from those canonical sources after every commit.
##
## Durability is DELEGATED: the real AuthoritativeRecoveryCoordinator and the
## real AuthoritativeRecoveryRepository provide checkpoint bytes; the P6
## persistence adapter only forwards to them. Exactly-once after delegated
## recovery is enforced by the canonical replay owner, never by P6 memory.
##
## SCOPE NOTICE: this is an in-process composition proof. The literal
## OS-process restart gate is bound to the existing M6 process recovery
## runner and is intentionally NOT claimed by this file.

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

var base_dir := "res://artifacts/test-results/p6-r3-shared-outpost-%d" % OS.get_process_id()

var assertions := 0
var failures: Array[String] = []


## Canonical owners fixture: stands in for the accepted M4 Item Graph, P4
## Construction and P5 gameplay public surfaces for this composition test.
class CanonicalSourcesOwner extends RefCounted:
	var construction := {"schema": "fixture.construction.v1", "revision": 0, "blocks": {}}
	var item_graph := {"schema": "fixture.item_graph.v1", "revision": 0, "containers": {}}
	var gameplay := {"schema": "fixture.gameplay.v1", "revision": 0, "players": {}, "tick": 0}
	var resource_mining := {"schema": "fixture.resource.v1", "revision": 0}
	var mutations := 0
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
				_bump(construction)
			"container_create":
				item_graph["containers"][String(delta.get("container_id", ""))] = []
				_bump(item_graph)
			"container_add_item":
				var container_id := String(delta.get("container_id", ""))
				if not (item_graph["containers"] as Dictionary).has(container_id):
					return {"applied": false, "error_code": "UNKNOWN_CONTAINER"}
				item_graph["containers"][container_id].append(String(delta.get("item", "")))
				_bump(item_graph)
			"player_move":
				gameplay["players"][String(delta.get("player_id", ""))] = {
					"pos": delta.get("pos", []),
					"rot": float(delta.get("rot", 0.0)),
				}
				_bump(gameplay)
			"set_tick":
				gameplay["tick"] = int(delta.get("value", 0))
				_bump(gameplay)
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

	func import_sources(sources: Dictionary) -> Dictionary:
		var required: Array[String] = ["gameplay", "item_graph", "construction", "resource_mining"]
		for name in required:
			if not sources.has(name) or typeof(sources[name]) != TYPE_DICTIONARY:
				return {"success": false, "error_code": "INVALID_CANONICAL_SOURCES"}
		gameplay = (sources["gameplay"] as Dictionary).duplicate(true)
		item_graph = (sources["item_graph"] as Dictionary).duplicate(true)
		construction = (sources["construction"] as Dictionary).duplicate(true)
		resource_mining = (sources["resource_mining"] as Dictionary).duplicate(true)
		return {"success": true, "error_code": ""}

	func block_type_at(pos_key: String) -> String:
		return String(construction["blocks"].get(pos_key, ""))

	func block_count() -> int:
		return (construction["blocks"] as Dictionary).size()

	func _bump(source: Dictionary) -> void:
		source["revision"] = int(source["revision"]) + 1


## Authority fixture over the canonical sources: exports/imports recovery
## state shaped exactly like the accepted authoritative checkpoint contract.
class CanonicalAuthorityFixture extends RefCounted:
	const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
	const AUTHORITY_OWNER_ID := "authority/p6-r3/canonical-fixture"
	const LOGICAL_SESSION_ID := "session/p6-r3/shared-outpost"

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


## Canonical replay owner fixture: the exactly-once oracle for committed
## operations (stand-in for the M6 durable replay outbox semantics).
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


## Route handler: the only place canonical mutations happen. The handler
## consults the canonical replay owner BEFORE mutating, so a replayed
## OperationId is rejected exactly once at the canonical boundary even when
## the P6 admission ledger is completely fresh.
class CanonicalCommandHandler extends RefCounted:
	var authority: CanonicalAuthorityFixture
	var replay: CanonicalReplayFixture
	var executions := 0
	var replay_rejections := 0

	func execute_command(command: Dictionary) -> Dictionary:
		executions += 1
		var operation_id := String(command.get("operation_id", ""))
		if replay.has(operation_id):
			replay_rejections += 1
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
		print("[p6.7-shared-outpost-r3][FAIL] %s" % message)


func _place(operation_id: String, pos: Array, block_type: String) -> Dictionary:
	return {
		"domain_id": DOMAIN_ID,
		"command_kind": "PLACE_BLOCK",
		"operation_id": operation_id,
		"delta": {"op": "place_block", "pos": pos, "block_type": block_type},
	}


func _build_stack(authority: CanonicalAuthorityFixture, replay: CanonicalReplayFixture) -> Dictionary:
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
	return {"registry": registry, "ledger": ledger, "route": route, "handler": handler}


func _projection_from(authority: CanonicalAuthorityFixture) -> Variant:
	var projection = ProjectionScript.new()
	var configured: Dictionary = projection.configure_from_canonical_sources(authority.owner.export_sources())
	if not bool(configured.get("success", false)):
		return null
	return projection


func _init() -> void:
	var root := ProjectSettings.globalize_path(base_dir)
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)

	# --- canonical world + delegated persistence wiring (REAL coordinator/repository) ---
	var authority = CanonicalAuthorityFixture.new(CanonicalSourcesOwner.new())
	var replay = CanonicalReplayFixture.new()
	var repository = RepositoryScript.new()
	var repo_configured: Dictionary = repository.configure(root.path_join("persistence"))
	_assert(bool(repo_configured.get("success", false)), "canonical repository configure failed")
	var coordinator = CoordinatorScript.new()
	var coordinator_configured: Dictionary = coordinator.configure(repository, authority, replay)
	_assert(bool(coordinator_configured.get("success", false)), "recovery coordinator configure failed")
	var p6_owner = PersistenceAdapterScript.new()
	var adapter_configured: Dictionary = p6_owner.configure(coordinator)
	_assert(bool(adapter_configured.get("success", false)), "P6 persistence adapter configure failed")

	# --- shared stack: two registry players, ONE canonical world ---
	var stack: Dictionary = _build_stack(authority, replay)
	var registry = stack["registry"]
	var ledger = stack["ledger"]
	var route = stack["route"]
	var handler = stack["handler"]
	var alice_bind: Dictionary = registry.bind("client-session/alice-1", "player/alice", "entity/alice-1")
	var bob_bind: Dictionary = registry.bind("client-session/bob-1", "player/bob", "entity/bob-1")
	_assert(bool(alice_bind.get("success", false)), "alice bind failed")
	_assert(bool(bob_bind.get("success", false)), "bob bind failed")

	# --- 1. both players mutate; canonical sources reflect BOTH ---
	var alice_op: Dictionary = route.route_command("client-session/alice-1", "operation/p6.7-a1", _place("operation/p6.7-a1", [1, 1, 1], "stone"))
	_assert(bool(alice_op.get("success", false)) and String(alice_op["details"]["result"]) == "EXECUTED", "alice place not executed: %s" % JSON.stringify(alice_op))
	var bob_op: Dictionary = route.route_command("client-session/bob-1", "operation/p6.7-b1", _place("operation/p6.7-b1", [2, 0, 0], "wood"))
	_assert(bool(bob_op.get("success", false)) and String(bob_op["details"]["result"]) == "EXECUTED", "bob place not executed")
	_assert(authority.owner.block_count() == 2, "canonical sources do not reflect both players")
	_assert(authority.owner.block_type_at("1,1,1") == "stone" and authority.owner.block_type_at("2,0,0") == "wood", "block authorship lost")
	var projection: Variant = _projection_from(authority)
	_assert(projection != null, "projection rebuild from canonical sources failed")
	var pre_projection_checksum: String = projection.compute_checksum() if projection != null else ""

	# exactly-once: replaying alice's operation changes nothing
	var replay_op: Dictionary = route.route_command("client-session/alice-1", "operation/p6.7-a1", _place("operation/p6.7-a1", [1, 1, 1], "stone"))
	_assert(bool(replay_op.get("success", false)) and String(replay_op["details"]["result"]) == "ALREADY_APPLIED", "replay not deduplicated")
	_assert(authority.owner.block_count() == 2, "replay mutated canonical sources")
	_assert(handler.executions == 2, "replay reached the handler again")

	# --- 2. delegated persistence through the REAL coordinator/repository ---
	var persisted: Dictionary = p6_owner.persist_checkpoint("checkpoint/p6-r3/shared/001", 1, 0, "operation/p6.7-b1")
	_assert(bool(persisted.get("success", false)), "delegated checkpoint persist failed: %s" % String(p6_owner.get_report()["last_error_code"]))
	_assert(int(p6_owner.get_report()["persists"]) == 1, "adapter persist counter wrong")
	_assert(repository.list_pending_files().is_empty(), "repository left a pending (partial) file behind")
	var recovered: Dictionary = p6_owner.recover_latest()
	_assert(bool(recovered.get("success", false)), "delegated recovery failed: %s" % String(p6_owner.get_report()["last_error_code"]))
	if bool(recovered.get("success", false)):
		var checkpoint: Dictionary = recovered["details"]["checkpoint"]
		_assert(int(checkpoint["generation"]) == 1, "recovered generation mismatch")
		_assert(String(checkpoint["committed_operation_id"]) == "operation/p6.7-b1", "recovered committed operation mismatch")
		_assert(authority.owner.block_count() == 2, "recovery changed canonical block count")
		var recovered_projection: Variant = _projection_from(authority)
		_assert(recovered_projection != null, "projection rebuild after recovery failed")
		if recovered_projection != null:
			_assert(recovered_projection.compute_checksum() == pre_projection_checksum, "projection diverged across delegated recovery")

	# --- 3. alice reconnects on a NEW session via identity rebind ---
	var rebind: Dictionary = registry.rebind_on_transport_change("client-session/alice-1", "client-session/alice-2")
	_assert(bool(rebind.get("success", false)) and String(rebind["details"]["preserved_logical_player_id"]) == "player/alice", "alice rebind failed")
	var alice_op2: Dictionary = route.route_command("client-session/alice-2", "operation/p6.7-a2", _place("operation/p6.7-a2", [3, 3, 3], "glass"))
	_assert(bool(alice_op2.get("success", false)) and String(alice_op2["details"]["result"]) == "EXECUTED", "post-rebind place not executed")
	_assert(authority.owner.block_count() == 3, "post-rebind contribution missing")
	_assert(authority.owner.block_type_at("1,1,1") == "stone", "pre-reconnect contribution lost")
	var cross_replay: Dictionary = route.route_command("client-session/alice-2", "operation/p6.7-a1", _place("operation/p6.7-a1", [1, 1, 1], "stone"))
	_assert(bool(cross_replay.get("success", false)) and String(cross_replay["details"]["result"]) == "ALREADY_APPLIED", "ledger not keyed by logical identity")

	# --- 4. fresh boot from persisted bytes ONLY (no live object survives) ---
	var persisted2: Dictionary = p6_owner.persist_checkpoint("checkpoint/p6-r3/shared/002", 2, 1, "operation/p6.7-a2")
	_assert(bool(persisted2.get("success", false)), "second delegated persist failed")
	# destroy every live object: only repository bytes survive
	stack = {}
	registry = null
	ledger = null
	route = null
	handler = null
	authority = null
	replay = null
	coordinator = null
	p6_owner = null
	projection = null

	# generation B: everything rebuilt from the persisted checkpoint bytes
	var authority_b = CanonicalAuthorityFixture.new(CanonicalSourcesOwner.new())
	var replay_b = CanonicalReplayFixture.new()
	var repository_b = RepositoryScript.new()
	repository_b.configure(root.path_join("persistence"))
	var coordinator_b = CoordinatorScript.new()
	coordinator_b.configure(repository_b, authority_b, replay_b)
	var p6_owner_b = PersistenceAdapterScript.new()
	p6_owner_b.configure(coordinator_b)
	var recovered_b: Dictionary = p6_owner_b.recover_latest()
	_assert(bool(recovered_b.get("success", false)), "generation B recovery from bytes failed")
	if not bool(recovered_b.get("success", false)):
		_remove_tree(root)
		_finish()
		return
	var generation_b_checkpoint: Dictionary = recovered_b["details"]["checkpoint"]
	_assert(int(generation_b_checkpoint["generation"]) == 2, "generation B did not recover the latest checkpoint")
	_assert(authority_b.owner.block_count() == 3, "generation B canonical sources lost blocks")
	_assert(authority_b.owner.block_type_at("3,3,3") == "glass", "generation B lost the newest contribution")
	_assert(replay_b.has("operation/p6.7-a1") and replay_b.has("operation/p6.7-b1") and replay_b.has("operation/p6.7-a2"), "generation B replay owner lost committed operations")
	var projection_b: Variant = _projection_from(authority_b)
	_assert(projection_b != null, "generation B projection rebuild failed")
	if projection_b != null:
		_assert(String(projection_b.compute_checksum()).length() == 64, "generation B projection checksum missing")

	var stack_b: Dictionary = _build_stack(authority_b, replay_b)
	var route_b = stack_b["route"]
	var handler_b = stack_b["handler"]
	var registry_b = stack_b["registry"]
	_assert(bool(registry_b.bind("client-session/bob-2", "player/bob", "entity/bob-2").get("success", false)), "bob post-restart bind failed")

	# exactly-once across the boot boundary: bob's pre-restart committed op is
	# rejected by the CANONICAL replay owner, not by P6 admission memory.
	var bob_replayed: Dictionary = route_b.route_command("client-session/bob-2", "operation/p6.7-b1", _place("operation/p6.7-b1", [2, 0, 0], "wood"))
	_assert(bool(bob_replayed.get("success", false)), "committed replay route failed at canonical owner")
	if bool(bob_replayed.get("success", false)):
		var outcome_b: Dictionary = bob_replayed["details"]["outcome"]
		_assert(not bool(outcome_b.get("applied", true)), "committed replay mutated canonical sources again")
		_assert(String(outcome_b.get("error_code", "")) == "ALREADY_COMMITTED_AT_CANONICAL_OWNER", "committed replay rejection mismatch")
	_assert(authority_b.owner.block_count() == 3, "committed replay duplicated a canonical mutation")
	_assert(handler_b.executions == 1, "committed replay reached handler unexpectedly often")

	# the recovered world keeps accepting NEW work
	var bob_new: Dictionary = route_b.route_command("client-session/bob-2", "operation/p6.7-b2", _place("operation/p6.7-b2", [4, 4, 4], "brick"))
	_assert(bool(bob_new.get("success", false)) and String(bob_new["details"]["result"]) == "EXECUTED", "post-recovery place not executed")
	_assert(authority_b.owner.block_count() == 4, "post-recovery state growth wrong")

	# P6 private-write fence over this flow's footprint: the persistence root
	# holds ONLY authoritative-repository files.
	_assert(_only_authoritative_files(root.path_join("persistence")), "persistence root contains non-authoritative files")

	_remove_tree(root)
	_finish()


func _only_authoritative_files(directory: String) -> bool:
	var dir := DirAccess.open(directory)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and not entry.begins_with("authoritative-checkpoint"):
			dir.list_dir_end()
			return false
		entry = dir.get_next()
	dir.list_dir_end()
	return true


func _finish() -> void:
	if failures.is_empty():
		print("[p6.7-shared-outpost-r3] all %d assertions passed" % assertions)
		print("[p6.7-shared-outpost-r3][stage] SHARED_OUTPOST_CANONICAL_COMPOSITION_PASS")
		print("[p6.7-shared-outpost-r3][scope] literal OS-process restart evidence is NOT claimed here; it is bound to the existing M6 process recovery runner")
		quit(0)
	else:
		print("[p6.7-shared-outpost-r3] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
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
