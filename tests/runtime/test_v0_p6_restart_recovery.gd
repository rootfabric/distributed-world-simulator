extends SceneTree

## P6 R3 rewrite of the P6.8 restart/recovery gate (delegation level).
##
## What this file proves:
##   - the ONLY thing that crosses the boot boundary is authoritative
##     checkpoint BYTES written by the real AuthoritativeRecoveryRepository
##     through the real AuthoritativeRecoveryCoordinator;
##   - generation B rebuilds canonical sources, the canonical replay owner and
##     the read-only P6 projection exclusively from those bytes;
##   - checkpointed OperationIds are exactly-once after recovery because the
##     CANONICAL replay owner rejects them, not because P6 carried memory;
##   - work committed after the last checkpoint re-lands idempotently at the
##     canonical boundary (no duplicate world effects);
##   - PENDING reservations are NOT durable truth: a fresh boot has a fresh
##     admission guard and an uncheckpointed intent simply executes once.
##
## What this file deliberately does NOT claim:
##   - a literal OS-process kill/restart boundary. That evidence is bound to
##     the existing M6 process recovery runner (test_m6_dedicated_recovery_
##     processes.gd pattern) and stays an explicit, separate gate.

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

var base_dir := "res://artifacts/test-results/p6-r3-restart-recovery-%d" % OS.get_process_id()

var assertions := 0
var failures: Array[String] = []


## Canonical owners fixture (M4 Item Graph / P4 Construction / P5 stand-in).
class CanonicalSourcesOwner extends RefCounted:
	var construction := {"schema": "fixture.construction.v1", "revision": 0, "blocks": {}}
	var item_graph := {"schema": "fixture.item_graph.v1", "revision": 0, "containers": {}}
	var gameplay := {"schema": "fixture.gameplay.v1", "revision": 0, "players": {}, "tick": 0}
	var resource_mining := {"schema": "fixture.resource.v1", "revision": 0}

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


## Authority fixture exporting the accepted authoritative recovery shape.
class CanonicalAuthorityFixture extends RefCounted:
	const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
	const AUTHORITY_OWNER_ID := "authority/p6-r3/canonical-fixture"
	const LOGICAL_SESSION_ID := "session/p6-r3/restart-recovery"

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
		print("[p6.8-restart-recovery-r3][FAIL] %s" % message)


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
	return {"registry": registry, "ledger": ledger, "admission": admission, "route": route, "handler": handler}


func _projection_checksum(authority: CanonicalAuthorityFixture) -> String:
	var projection = ProjectionScript.new()
	var configured: Dictionary = projection.configure_from_canonical_sources(authority.owner.export_sources())
	if not bool(configured.get("success", false)):
		return ""
	return projection.compute_checksum()


func _init() -> void:
	var root := ProjectSettings.globalize_path(base_dir)
	_remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	var persistence_root := root.path_join("persistence")

	# ================= GENERATION A =================
	var authority = CanonicalAuthorityFixture.new(CanonicalSourcesOwner.new())
	var replay = CanonicalReplayFixture.new()
	var repository = RepositoryScript.new()
	_assert(bool(repository.configure(persistence_root).get("success", false)), "repository configure failed")
	var coordinator = CoordinatorScript.new()
	_assert(bool(coordinator.configure(repository, authority, replay).get("success", false)), "coordinator configure failed")
	var p6_owner = PersistenceAdapterScript.new()
	_assert(bool(p6_owner.configure(coordinator).get("success", false)), "P6 adapter configure failed")

	var stack: Dictionary = _build_stack(authority, replay)
	var registry = stack["registry"]
	var route = stack["route"]
	var admission = stack["admission"]
	var ledger = stack["ledger"]
	for player_row in [["client-session/alice-a", "player/alice", "entity/alice-a"], ["client-session/bob-a", "player/bob", "entity/bob-a"], ["client-session/carol-a", "player/carol", "entity/carol-a"]]:
		_assert(bool(registry.bind(String(player_row[0]), String(player_row[1]), String(player_row[2])).get("success", false)), "generation A bind failed: %s" % String(player_row[1]))

	# durable committed work by three players across several command kinds
	for command_row in [
		["operation/p6.8-d1", "client-session/alice-a", _place("operation/p6.8-d1", [1, 0, 1], "stone")],
		["operation/p6.8-d2", "client-session/bob-a", _place("operation/p6.8-d2", [2, 0, 2], "wood")],
		["operation/p6.8-d3", "client-session/carol-a", {
			"domain_id": DOMAIN_ID, "command_kind": "CONTAINER_CREATE", "operation_id": "operation/p6.8-d3",
			"delta": {"op": "container_create", "container_id": "crate-1"},
		}],
		["operation/p6.8-d4", "client-session/alice-a", {
			"domain_id": DOMAIN_ID, "command_kind": "CONTAINER_ADD_ITEM", "operation_id": "operation/p6.8-d4",
			"delta": {"op": "container_add_item", "container_id": "crate-1", "item": "pickaxe"},
		}],
	]:
		var routed: Dictionary = route.route_command(String(command_row[1]), String(command_row[0]), command_row[2])
		_assert(bool(routed.get("success", false)) and String(routed["details"]["result"]) == "EXECUTED", "generation A durable op failed: %s" % String(command_row[0]))
	_assert(authority.owner.block_count() == 2, "generation A block count wrong")
	var durable_checkpoint: Dictionary = p6_owner.persist_checkpoint("checkpoint/p6-r3/restart/001", 1, 0, "operation/p6.8-d4")
	_assert(bool(durable_checkpoint.get("success", false)), "generation A checkpoint failed")
	var checkpointed_projection_checksum := _projection_checksum(authority)
	_assert(checkpointed_projection_checksum.length() == 64, "generation A projection checksum missing")

	# --- crash window A: admission reserved PENDING, handler never ran ---
	var window_a: Dictionary = admission.admit("player/alice", "operation/p6.8-wa", DOMAIN_ID, _place("operation/p6.8-wa", [5, 0, 5], "glass"))
	_assert(bool(window_a.get("success", false)), "window A admission failed")
	_assert(ledger.is_pending("player/alice", "operation/p6.8-wa"), "window A reservation missing")

	# --- crash window B: canonical effect landed + replay committed AFTER the
	# last checkpoint (not yet durable) ---
	var window_b: Dictionary = admission.admit("player/bob", "operation/p6.8-wb", DOMAIN_ID, _place("operation/p6.8-wb", [6, 0, 6], "brick"))
	_assert(bool(window_b.get("success", false)), "window B admission failed")
	var window_b_outcome: Dictionary = (stack["handler"] as CanonicalCommandHandler).execute_command(_place("operation/p6.8-wb", [6, 0, 6], "brick"))
	_assert(bool(window_b_outcome.get("applied", false)), "window B canonical effect failed")
	# no admission.complete(): completion was lost with the process

	# CRASH: every live object dies; only checkpoint bytes remain on disk.
	stack = {}
	registry = null
	route = null
	admission = null
	ledger = null
	authority = null
	replay = null
	coordinator = null
	p6_owner = null

	# ================= GENERATION B =================
	var authority_b = CanonicalAuthorityFixture.new(CanonicalSourcesOwner.new())
	var replay_b = CanonicalReplayFixture.new()
	var repository_b = RepositoryScript.new()
	repository_b.configure(persistence_root)
	var coordinator_b = CoordinatorScript.new()
	coordinator_b.configure(repository_b, authority_b, replay_b)
	var p6_owner_b = PersistenceAdapterScript.new()
	p6_owner_b.configure(coordinator_b)
	var recovered: Dictionary = p6_owner_b.recover_latest()
	_assert(bool(recovered.get("success", false)), "generation B recovery from bytes failed")
	if not bool(recovered.get("success", false)):
		_remove_tree(root)
		_finish()
		return

	# canonical truth rebuilt exactly from the checkpointed bytes
	_assert(authority_b.owner.block_count() == 2, "recovery changed checkpointed block count")
	_assert(authority_b.owner.block_type_at("1,0,1") == "stone" and authority_b.owner.block_type_at("2,0,2") == "wood", "recovery lost checkpointed blocks")
	_assert(_projection_checksum(authority_b) == checkpointed_projection_checksum, "projection diverged across the boot boundary")
	_assert(replay_b.has("operation/p6.8-d1") and replay_b.has("operation/p6.8-d4"), "checkpointed replay records lost")
	_assert(not replay_b.has("operation/p6.8-wa") and not replay_b.has("operation/p6.8-wb"), "uncheckpointed work leaked into durable replay truth")

	# PENDING is NOT durable: the fresh admission guard starts empty.
	var stack_b: Dictionary = _build_stack(authority_b, replay_b)
	var registry_b = stack_b["registry"]
	var route_b = stack_b["route"]
	var ledger_b = stack_b["ledger"]
	_assert(not ledger_b.is_pending("player/alice", "operation/p6.8-wa"), "PENDING survived as durable truth")
	_assert(bool(registry_b.bind("client-session/alice-b", "player/alice", "entity/alice-b").get("success", false)), "alice generation B bind failed")

	# checkpointed operation replay: exactly-once at the CANONICAL owner.
	var replay_d1: Dictionary = route_b.route_command("client-session/alice-b", "operation/p6.8-d1", _place("operation/p6.8-d1", [1, 0, 1], "stone"))
	_assert(bool(replay_d1.get("success", false)), "checkpointed replay route failed")
	if bool(replay_d1.get("success", false)):
		var outcome_d1: Dictionary = replay_d1["details"]["outcome"]
		_assert(String(outcome_d1.get("error_code", "")) == "ALREADY_COMMITTED_AT_CANONICAL_OWNER", "checkpointed replay not rejected by canonical owner")
	_assert(authority_b.owner.block_count() == 2, "checkpointed replay duplicated a canonical block")

	# window A intent: never committed anywhere -> executes exactly once now.
	var window_a_replay: Dictionary = route_b.route_command("client-session/alice-b", "operation/p6.8-wa", _place("operation/p6.8-wa", [5, 0, 5], "glass"))
	_assert(bool(window_a_replay.get("success", false)) and String(window_a_replay["details"]["result"]) == "EXECUTED", "window A intent did not execute after recovery")
	_assert(authority_b.owner.block_type_at("5,0,5") == "glass", "window A block missing")
	# replaying it again is exactly-once through BOTH guards now.
	var window_a_again: Dictionary = route_b.route_command("client-session/alice-b", "operation/p6.8-wa", _place("operation/p6.8-wa", [5, 0, 5], "glass"))
	_assert(bool(window_a_again.get("success", false)) and String(window_a_again["details"]["result"]) == "ALREADY_APPLIED", "window A replay not deduplicated after execution")

	# window B intent: the in-flight effect was lost with the process; the
	# canonical boundary re-lands it idempotently (no duplicate world effect).
	var window_b_replay: Dictionary = route_b.route_command("client-session/alice-b", "operation/p6.8-wb", _place("operation/p6.8-wb", [6, 0, 6], "brick"))
	_assert(bool(window_b_replay.get("success", false)), "window B re-submission failed")
	if bool(window_b_replay.get("success", false)):
		var outcome_wb: Dictionary = window_b_replay["details"]["outcome"]
		_assert(not bool(outcome_wb.get("applied", true)) or String(outcome_wb.get("error_code", "")) == "", "window B re-submission duplicated the world effect")
	_assert(authority_b.owner.block_count() == 4, "post-recovery block count wrong")
	_assert((authority_b.owner.export_sources()["item_graph"]["containers"] as Dictionary).has("crate-1"), "checkpointed container lost")
	_assert(((authority_b.owner.export_sources()["item_graph"]["containers"] as Dictionary)["crate-1"] as Array).has("pickaxe"), "checkpointed container item lost")

	# pin the recovered generation with a new checkpoint: from here on the
	# window-B operation is durable exactly-once as well.
	var pinned: Dictionary = p6_owner_b.persist_checkpoint("checkpoint/p6-r3/restart/002", 2, 1, "operation/p6.8-wa")
	_assert(bool(pinned.get("success", false)), "generation B checkpoint failed")

	var authority_c = CanonicalAuthorityFixture.new(CanonicalSourcesOwner.new())
	var replay_c = CanonicalReplayFixture.new()
	var repository_c = RepositoryScript.new()
	repository_c.configure(persistence_root)
	var coordinator_c = CoordinatorScript.new()
	coordinator_c.configure(repository_c, authority_c, replay_c)
	var p6_owner_c = PersistenceAdapterScript.new()
	p6_owner_c.configure(coordinator_c)
	var recovered_c: Dictionary = p6_owner_c.recover_latest()
	_assert(bool(recovered_c.get("success", false)), "generation C recovery failed")
	_assert(int(recovered_c["details"]["checkpoint"]["generation"]) == 2, "generation C did not see the pinned checkpoint")
	_assert(authority_c.owner.block_count() == 4, "generation C lost pinned blocks")
	_assert(replay_c.has("operation/p6.8-wa"), "pinned replay record missing")

	# private-write fence footprint: only authoritative files exist.
	_assert(_only_authoritative_files(persistence_root), "persistence root contains non-authoritative files")

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
		print("[p6.8-restart-recovery-r3] all %d assertions passed" % assertions)
		print("[p6.8-restart-recovery-r3][stage] DELEGATED_RECOVERY_EXACTLY_ONCE_PASS")
		print("[p6.8-restart-recovery-r3][scope] in-process delegated durability only; the literal OS-process restart gate stays bound to the existing M6 process recovery runner and is NOT claimed here")
		quit(0)
	else:
		print("[p6.8-restart-recovery-r3] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
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
