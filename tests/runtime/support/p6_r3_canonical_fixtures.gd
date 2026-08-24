extends RefCounted

## P6 R3 shared canonical-owner fixtures for process-boundary tests.
##
## These fixtures stand in for the accepted canonical owners (M4 Item Graph,
## P4 Construction, P5 gameplay, M6 durable replay outbox) and export/import
## the EXACT authoritative recovery contract those owners use. They create no
## new persistence owner, no new save format and no second truth: durability
## itself always flows through the real AuthoritativeRecoveryCoordinator and
## AuthoritativeRecoveryRepository.


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

	func has_block(pos_key: String) -> bool:
		return (construction["blocks"] as Dictionary).has(pos_key)


class CanonicalAuthorityFixture extends RefCounted:
	const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
	const AUTHORITY_OWNER_ID := "authority/p6-r3/canonical-fixture"
	const LOGICAL_SESSION_ID := "session/p6-r3/process-restart"

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


## Build a full P6 admission stack (registry -> ledger -> admission -> closure
## -> route -> handler) over the given authority/replay fixtures.
static func build_stack(registry_script, ledger_script, admission_script, closure_script, route_script, authority: CanonicalAuthorityFixture, replay: CanonicalReplayFixture) -> Dictionary:
	var registry = registry_script.new()
	var ledger = ledger_script.new()
	ledger.configure(256)
	var admission = admission_script.new()
	var closure = closure_script.new()
	admission.configure(registry, ledger)
	closure.configure(registry, ledger)
	var handler = CanonicalCommandHandler.new()
	handler.authority = authority
	handler.replay = replay
	var route = route_script.new()
	route.configure(registry, ledger, admission, closure, handler)
	return {
		"registry": registry, "ledger": ledger, "admission": admission,
		"closure": closure, "route": route, "handler": handler,
	}
