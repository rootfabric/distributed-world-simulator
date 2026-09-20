extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_guarded_authority_process.gd"

# MVP8 composes the already accepted MVP6 live authority with MVP7 quiescent
# recovery. No new canonical store is introduced.
const Service8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_gameplay_service.gd")
const SharedMatter8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_shared_dig_authority.gd")
const Adapter8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_matter_gameplay_authority_adapter.gd")
const Recovery8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_recovery_coordinator.gd")
const Repository8 = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Outbox8 = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Restorer8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_cross_authority_construction_restorer.gd")
const Views8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_remote_owner_views.gd")
const Scheduler8 = preload("res://scripts/network/simulation/fixed_tick_scheduler.gd")
const NetworkUtils8 = preload("res://scripts/network/contracts/network_contract_utils.gd")

var _repository8 = null
var _adapter8 = null
var _outbox8 = null
var _recovery8 = null
var _sessions8: Dictionary = {}
var _generation8 := 0
var _recovered8 := false
var _checkpoint8: Dictionary = {}
var _construction_root8 := ""
var _construction_cut_file8 := ""


func create_shared_dig():
	return SharedMatter8.new()


func _write_json8(path: String, value: Dictionary) -> Dictionary:
	if path.strip_edges().is_empty():
		return Protocol.failure("MVP8_OUTPUT_PATH_REQUIRED")
	var directory := path.get_base_dir()
	var made := DirAccess.make_dir_recursive_absolute(directory)
	if made != OK and made != ERR_ALREADY_EXISTS:
		return Protocol.failure("MVP8_OUTPUT_DIRECTORY_FAILED")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return Protocol.failure("MVP8_OUTPUT_OPEN_FAILED")
	file.store_string(JSON.stringify(value, "", true, true) + "\n")
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	return Protocol.success() if okay else Protocol.failure("MVP8_OUTPUT_WRITE_FAILED")


func _read_json8(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return Dictionary(parsed) if parsed is Dictionary else {}


func _setup_recovery8(recovering: bool) -> Dictionary:
	if authority != "authority/a":
		return Protocol.success()
	var root := String(cfg.get("mvp8_root", "")).strip_edges()
	if root.is_empty():
		return Protocol.failure("MVP8_RECOVERY_ROOT_REQUIRED")
	_sessions8 = {"a": Protocol.session(cfg, "a"), "b": Protocol.session(cfg, "b")}
	_shared_dig4 = create_shared_dig()
	var configured: Dictionary = _shared_dig4.configure(service, decisions, _sessions8)
	if not bool(configured.get("success", false)):
		return configured
	_repository8 = Repository8.new()
	configured = _repository8.configure(root.path_join("gameplay"))
	if not bool(configured.get("success", false)):
		return configured
	_adapter8 = Adapter8.new()
	configured = _adapter8.setup(service, "session/mvp8/live-world")
	if not bool(configured.get("success", false)):
		return configured
	configured = _adapter8.configure_matter7(_shared_dig4, decisions, _sessions8, root)
	if not bool(configured.get("success", false)):
		return configured
	_outbox8 = Outbox8.new()
	configured = _outbox8.setup(service)
	if not bool(configured.get("success", false)):
		return configured
	_recovery8 = Recovery8.new()
	configured = _recovery8.configure(_repository8, _adapter8, _outbox8)
	if not bool(configured.get("success", false)):
		return configured
	if recovering:
		_generation8 = int(cfg.get("mvp8_generation", 1))
		configured = _recovery8.require_minimum_generation7(_generation8)
		if not bool(configured.get("success", false)):
			return configured
		configured = _recovery8.recover_latest()
		if not bool(configured.get("success", false)):
			return configured
		_recovered8 = true
		_checkpoint8 = Dictionary(configured.get("details", {}).get("checkpoint", {})).duplicate(true)
		_shared_dig4 = _adapter8.get_shared_matter7()
	return Protocol.success({"recovered": _recovered8, "generation": _generation8})


func initialize_owner() -> Dictionary:
	var recovering := bool(cfg.get("mvp8_recovery", false))
	var expected_epochs: Dictionary = Dictionary(cfg.get("mvp8_authority_epochs", {"a": 1, "b": 1})).duplicate(true)
	service = Service8.new()
	var setup: Dictionary = service.setup(authority, 1, 0, {
		"profile": Service8.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/mvp8/" + authority,
		"fixed_tick_authority": true,
		"mvp6_fixture_owner": authority == "authority/a",
		"mvp6_spatial_validation": true,
	})
	if not bool(setup.get("success", false)):
		return setup

	if authority == "authority/a":
		var recovery_ready := _setup_recovery8(recovering)
		if not bool(recovery_ready.get("success", false)):
			return recovery_ready
		for actor in ["a", "b"]:
			var joined: Dictionary = service.join(actor, Protocol.session(cfg, actor), "operation/mvp8/" + String(cfg["run_id"]) + "/join/" + actor)
			if not bool(joined.get("success", false)):
				return joined
			if int(service.get_player(actor).get("ownership_epoch", 0)) != int(expected_epochs.get(actor, 1)):
				return Protocol.failure("MVP8_RECOVERED_OWNERSHIP_EPOCH_MISMATCH:" + actor)

	initial_snapshot = service.create_snapshot()
	initial_graph = service.create_canonical_item_graph_snapshot()
	live_port = service.get_live_player_transfer_port()
	if live_port == null:
		return Protocol.failure("MVP8_NATIVE_LIVE_PORT_MISSING")
	var other := "authority/b" if authority == "authority/a" else "authority/a"
	source_view = Views8.SourceReceiptView.new()
	source_view.config = cfg.duplicate(true)
	source_view.source_authority = other
	source_view.source_key = String(cfg["internal_keys"][other])
	var peer_setup: Dictionary = live_port.register_peer(other, source_view)
	if not bool(peer_setup.get("success", false)):
		return peer_setup
	for actor in ["a", "b"]:
		var bound: Dictionary = live_port.bind_player(actor, Protocol.session(cfg, actor), int(expected_epochs.get(actor, 1)), decisions[actor])
		if not bool(bound.get("success", false)):
			return bound
	clock = Scheduler8.new()
	var clock_ready: Dictionary = clock.configure(60, 8, 0)
	if not bool(clock_ready.get("success", false)):
		return clock_ready

	_construction_root8 = String(cfg.get("mvp8_construction_root", "")).strip_edges()
	_construction_cut_file8 = String(cfg.get("mvp8_construction_cut_file", "")).strip_edges()
	if authority == "authority/a" and (_construction_root8.is_empty() or _construction_cut_file8.is_empty()):
		return Protocol.failure("MVP8_CONSTRUCTION_PERSISTENCE_PATH_REQUIRED")
	if authority == "authority/a" and recovering:
		var restored := _restore_construction8()
		if not bool(restored.get("success", false)):
			return restored
	return Protocol.success()


func _ensure_construction6() -> Dictionary:
	if authority != "authority/a":
		return Protocol.failure("MVP6_CONSTRUCTION_CANONICAL_OWNER_REQUIRED")
	if not _construction6.is_empty():
		return Protocol.success(_public6({"replay": true}))
	if _construction_root8.is_empty():
		return Protocol.failure("MVP8_CONSTRUCTION_ROOT_REQUIRED")
	var ore_ready := _ensure_ore6(SeamFactory.FINAL_PART_COUNT)
	if not bool(ore_ready.get("success", false)):
		return ore_ready
	var decision_a: Dictionary = decisions["a"].snapshot()
	if String(decision_a.get("active_authority_id", "")) != "authority/a":
		return Protocol.failure("MVP6_CONSTRUCTION_PLAYER_A_NOT_RETURNED")
	var created: Dictionary = SeamFactory.create(_graph6(), "authority/a", 1, _construction_root8)
	if not bool(created.get("success", false)):
		return created
	_construction6 = Dictionary(created.get("details", {}))
	_bridge6 = SeamBridge.new()
	var bridge_ready: Dictionary = _bridge6.setup(_construction6["gateway"])
	if not bool(bridge_ready.get("success", false)):
		return bridge_ready
	for actor in ["a", "b"]:
		var connected: Dictionary = _bridge6.connect_player(actor, int(decisions[actor].snapshot().get("authority_epoch", 0)))
		if not bool(connected.get("success", false)):
			return connected
		_sessions6[actor] = _bridge6.get_player_session(actor)
	var bind_a: Dictionary = _construction6["endpoint_a"].bind_authenticated_player("a", _sessions6["a"])
	if not bool(bind_a.get("success", false)):
		return bind_a
	var bind_b: Dictionary = _construction6["endpoint_b"].bind_authenticated_player("a", _sessions6["a"])
	if not bool(bind_b.get("success", false)):
		return bind_b
	var base_command := _build_command6(0, 0, "build-base-100")
	var base_checked: Dictionary = SeamCommand.validate(base_command)
	if not bool(base_checked.get("success", false)):
		return base_checked
	var base_result: Dictionary = _construction6["endpoint_a"].submit(base_command)
	if not bool(base_result.get("success", false)):
		return base_result
	var base_snapshot := _snapshot6()
	if Array(base_snapshot.get("parts", [])).size() != SeamFactory.BASE_PART_COUNT:
		return Protocol.failure("MVP6_LIVE_BASE_PART_COUNT_INVALID")
	var registered: Dictionary = SeamFactory.register_active_construct(_construction6)
	if not bool(registered.get("success", false)):
		return registered
	_phase6 = "BASE"
	return Protocol.success(_public6({"ore_after_base": _ore6(_graph6().create_snapshot(), "a")}))


func _restore_construction8() -> Dictionary:
	var cut := _read_json8(_construction_cut_file8)
	if cut.get("schema") != "distributed_world_simulator.mvp8_construction_cut.v1":
		return Protocol.failure("MVP8_CONSTRUCTION_CUT_REQUIRED")
	var graph = _graph6()
	var graph_snapshot: Dictionary = graph.create_snapshot()
	if String(graph_snapshot.get("checksum", "")) != String(cut.get("item_graph_checksum", "")):
		return Protocol.failure("MVP8_CONSTRUCTION_ITEM_GRAPH_MISMATCH")
	var restored: Dictionary = Restorer8.restore(
		graph,
		String(graph_snapshot.get("authority_owner_id", "authority/a")),
		int(graph_snapshot.get("authority_epoch", 1)),
		String(cut.get("repository_root", ""))
	)
	if not bool(restored.get("success", false)):
		return restored
	var detail: Dictionary = restored.get("details", {})
	var loaded: Dictionary = detail["authoritative_adapter"].load_state(Dictionary(cut.get("durable_construction", {})))
	if not bool(loaded.get("success", false)):
		return loaded
	loaded = detail["cluster"].load_state(Dictionary(cut.get("durable_cluster", {})))
	if not bool(loaded.get("success", false)):
		return loaded
	var replica = detail["cluster"].get_replica(SeamFactory.CONSTRUCT_ID, SeamFactory.SERVER_B)
	if replica == null:
		return Protocol.failure("MVP8_RECOVERED_CONSTRUCTION_REPLICA_REQUIRED")
	var replica_state: Dictionary = replica.get_state()
	var state_bundle: Dictionary = replica_state.get("state_bundle", {})
	if state_bundle.is_empty():
		return Protocol.failure("MVP8_RECOVERED_CONSTRUCTION_STATE_BUNDLE_REQUIRED")
	loaded = detail["transfer_backend"].import_construct_state(state_bundle)
	if not bool(loaded.get("success", false)):
		return loaded
	var expected: Dictionary = cut.get("snapshot", {})
	var actual: Dictionary = detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID)
	if NetworkUtils8.canonical_json(actual) != NetworkUtils8.canonical_json(expected):
		return Protocol.failure("MVP8_RECOVERED_CONSTRUCTION_SNAPSHOT_MISMATCH")
	_construction6 = detail
	_bridge6 = SeamBridge.new()
	loaded = _bridge6.setup(_construction6["gateway"])
	if not bool(loaded.get("success", false)):
		return loaded
	_sessions6.clear()
	for actor in ["a", "b"]:
		loaded = _bridge6.connect_player(actor, int(decisions[actor].snapshot().get("authority_epoch", 0)))
		if not bool(loaded.get("success", false)):
			return loaded
		_sessions6[actor] = _bridge6.get_player_session(actor)
	loaded = _construction6["endpoint_a"].bind_authenticated_player("a", _sessions6["a"])
	if not bool(loaded.get("success", false)):
		return loaded
	loaded = _construction6["endpoint_b"].bind_authenticated_player("a", _sessions6["a"])
	if not bool(loaded.get("success", false)):
		return loaded
	_phase6 = "REMOVED"
	_replays6 = {"ADD": true, "REMOVE": true}
	return Protocol.success({"checksum": String(actual.get("checksum", "")), "part_count": Array(actual.get("parts", [])).size()})


func _mvp8_add(cycle: int) -> Dictionary:
	if _phase6 != "REMOVED":
		return Protocol.failure("MVP8_BUILD_ADD_PHASE_INVALID")
	var sequence := 20 + cycle * 2
	var inner := _build_command6(sequence, 1, "mvp8-add-east-leaf-%d" % cycle)
	var checked: Dictionary = SeamCommand.validate(inner)
	if not bool(checked.get("success", false)):
		return checked
	var route := DistributedCommand.create(
		"authority-route/mvp8/live/add-east-%d" % cycle,
		SeamFactory.SERVER_B, SeamFactory.SERVER_A, sequence, inner,
		{"entry": "east", "operation": "ADD", "cycle": cycle}
	)
	var applied: Dictionary = _construction6["cluster"].submit(SeamFactory.SERVER_B, route)
	if not bool(applied.get("success", false)):
		return applied
	_phase6 = "ADDED"
	_route_receipts6.append({"intent": "MVP8_ADD", "cycle": cycle, "entry_process": "authority/b", "writer_process": "authority/a"})
	return Protocol.success(_public6({"gateway_result": applied.get("gateway_result", {}), "cycle": cycle}))


func _mvp8_remove(cycle: int) -> Dictionary:
	if _phase6 != "ADDED":
		return Protocol.failure("MVP8_BUILD_REMOVE_PHASE_INVALID")
	var permissions = _construction6["gateway"].get_permission_store()
	var grant := SeamGrant.create(
		"permission/mvp8/live/damage/%d" % cycle,
		String(_sessions6["a"].get("client_id", "")),
		SeamFactory.CONSTRUCT_ID,
		[SeamGrant.ACTION_DAMAGE, SeamGrant.ACTION_READ],
		int(permissions.get_epoch())
	)
	var published: Dictionary = permissions.publish(grant)
	if not bool(published.get("success", false)):
		return published
	var added := _snapshot6()
	var salvage_transform := Transform3D(Basis.IDENTITY, Vector3(float(SeamFactory.ADD_PART_INDEX) - 49.5, 0.5, 0.0))
	var request := DamageRequest.create(
		"damage/mvp8/live/remove-east-leaf/%d" % cycle,
		SeamFactory.CONSTRUCT_ID,
		String(added.get("checksum", "")),
		SeamFactory.part_id(0),
		[SeamFactory.bond_id(SeamFactory.ADD_PART_INDEX - 1)],
		[], {}, [],
		SalvagePolicy.create(2, ItemRelations.world(salvage_transform), false)
	)
	var valid_request: Dictionary = DamageRequest.validate(request)
	if not bool(valid_request.get("success", false)):
		return valid_request
	var bundle: Dictionary = _bridge6.get_snapshot_packet().get("state_bundle", {})
	var sequence := 21 + cycle * 2
	var inner := SeamCommand.create(
		"multiplayer-command/mvp8/live/remove-east-leaf/%d" % cycle,
		String(_sessions6["a"].get("client_id", "")),
		String(_sessions6["a"].get("session_id", "")),
		int(_sessions6["a"].get("session_epoch", 0)),
		sequence,
		SeamGrant.ACTION_DAMAGE,
		SeamFactory.CONSTRUCT_ID,
		String(added.get("checksum", "")),
		int(bundle.get("server_generation", 0)),
		int(permissions.get_epoch()),
		{
			"plan_id": "plan/mvp8/live/remove-east-leaf/%d" % cycle,
			"operation_id": "operation/mvp8/live/remove-east-leaf/%d" % cycle,
			"request": request,
			"failure_mode": "",
		}
	)
	var checked: Dictionary = SeamCommand.validate(inner)
	if not bool(checked.get("success", false)):
		return checked
	var route := DistributedCommand.create(
		"authority-route/mvp8/live/remove-east-%d" % cycle,
		SeamFactory.SERVER_B, SeamFactory.SERVER_A, sequence, inner,
		{"entry": "east", "operation": "REMOVE", "cycle": cycle}
	)
	var applied: Dictionary = _construction6["cluster"].submit(SeamFactory.SERVER_B, route)
	if not bool(applied.get("success", false)):
		return applied
	_phase6 = "REMOVED"
	_route_receipts6.append({"intent": "MVP8_REMOVE", "cycle": cycle, "entry_process": "authority/b", "writer_process": "authority/a"})
	return Protocol.success(_public6({"gateway_result": applied.get("gateway_result", {}), "cycle": cycle}))


func _checkpoint8() -> Dictionary:
	if authority != "authority/a" or _adapter8 == null or _recovery8 == null or _construction6.is_empty() or _phase6 != "REMOVED":
		return Protocol.failure("MVP8_QUIESCENT_CHECKPOINT_NOT_READY")
	if not _checkpoint8.is_empty():
		return Protocol.success({"replay": true, "checkpoint": _checkpoint8.duplicate(true)})
	var generation := 1
	var prepared: Dictionary = _adapter8.prepare_checkpoint7(generation)
	if not bool(prepared.get("success", false)):
		return prepared
	var saved: Dictionary = _recovery8.persist_checkpoint("checkpoint/mvp8/live/1", generation, 0, "")
	if not bool(saved.get("success", false)):
		return saved
	var graph = _graph6()
	var graph_state: Dictionary = graph.export_durable_state()
	var snapshot := _snapshot6()
	var cut := {
		"schema": "distributed_world_simulator.mvp8_construction_cut.v1",
		"repository_root": _construction_root8,
		"durable_items": graph_state,
		"durable_construction": _construction6["authoritative_adapter"].export_state(),
		"durable_cluster": _construction6["cluster"].export_state(),
		"snapshot": snapshot,
		"authority_record": _construction6["cluster"].get_registry().get_record(SeamFactory.CONSTRUCT_ID),
		"item_graph_checksum": String(graph_state.get("snapshot", {}).get("checksum", "")),
		"construction_checksum": String(snapshot.get("checksum", "")),
	}
	var written := _write_json8(_construction_cut_file8, cut)
	if not bool(written.get("success", false)):
		return written
	var players := {}
	for actor in ["a", "b"]:
		var player: Dictionary = service.get_player(actor)
		players[actor] = {
			"last_input_sequence": int(player.get("last_input_sequence", 0)),
			"ownership_epoch": int(player.get("ownership_epoch", 0)),
			"position": Dictionary(player.get("position", {})).duplicate(true),
		}
	_checkpoint8 = {
		"generation": generation,
		"checkpoint_checksum": String(saved.get("details", {}).get("checkpoint", {}).get("checksum", "")),
		"gameplay_checksum": String(service.export_durable_state().get("checksum", "")),
		"item_graph_checksum": String(graph_state.get("snapshot", {}).get("checksum", "")),
		"construction_checksum": String(snapshot.get("checksum", "")),
		"matter": _shared_dig4.report(),
		"players": players,
	}
	return Protocol.success({"checkpoint": _checkpoint8.duplicate(true)})


func _bounds8() -> Dictionary:
	var replay := service.export_replay_state() if service != null else {}
	var pending := _outbox8.get_pending_records().size() if _outbox8 != null else 0
	var terminal := 0
	if not _construction6.is_empty():
		terminal = Array(_construction6["gateway"].export_state().get("terminal_commands", [])).size()
	var graph: Dictionary = _graph6().create_snapshot() if _graph6() != null else {}
	var ids: Dictionary = {}
	var duplicate := false
	for raw in graph.get("items", []):
		var row: Dictionary = raw
		var item_id := String(row.get("item_id", ""))
		if ids.has(item_id):
			duplicate = true
		ids[item_id] = true
	return {
		"replay_json_bytes": JSON.stringify(replay).to_utf8_buffer().size(),
		"durable_replay_pending": pending,
		"construction_terminal_commands": terminal,
		"matter_stream_sequence": int(_shared_dig4.report().get("stream_sequence", 0)) if _shared_dig4 != null else 0,
		"item_count": Array(graph.get("items", [])).size(),
		"unique_item_count": ids.size(),
		"duplicate_item_identity": duplicate,
		"construction_id": SeamFactory.CONSTRUCT_ID if not _construction6.is_empty() else "",
	}


func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP8_"):
		return super.handle_rpc(body)
	if closing_ms > 0:
		return Protocol.failure("MVP8_AUTHORITY_STOPPING")
	var ingested: Dictionary = ingest_decisions(body)
	if not bool(ingested.get("success", false)):
		return ingested
	var actor := String(body.get("actor", ""))
	if actor not in ["a", "b"] or String(body.get("session", "")) != Protocol.session(cfg, actor):
		return Protocol.failure("MVP8_NATIVE_PEER_BINDING_INVALID")
	var result: Dictionary
	match kind:
		"MVP8_ITEM":
			if authority != "authority/a":
				result = Protocol.failure("MVP8_ITEM_CANONICAL_OWNER_REQUIRED")
			else:
				var player: Dictionary = service.get_player(actor)
				result = service.handle_canonical_item_command(
					actor,
					Protocol.session(cfg, actor),
					int(player.get("ownership_epoch", 0)),
					String(body.get("operation_id", "")),
					String(body.get("command_kind", "")),
					Dictionary(body.get("payload", {}))
				)
		"MVP8_BUILD_APPLY":
			if authority != "authority/a":
				result = Protocol.failure("MVP8_BUILD_CANONICAL_OWNER_REQUIRED")
			else:
				var intent := String(body.get("intent", ""))
				var cycle := int(body.get("cycle", 0))
				var attested := _route_attestation6(body.get("route_attestation", {}), intent)
				if not bool(attested.get("success", false)):
					result = attested
				elif intent == "ADD":
					result = _mvp8_add(cycle)
				elif intent == "REMOVE":
					result = _mvp8_remove(cycle)
				else:
					result = Protocol.failure("MVP8_BUILD_INTENT_INVALID")
		"MVP8_CHECKPOINT":
			result = _checkpoint8()
		"MVP8_BOUNDS":
			result = Protocol.success(_bounds8())
		_:
			result = Protocol.failure("MVP8_UNKNOWN_NATIVE_COMMAND")
	return native_envelope(kind, actor, result)


func report(passed: bool, phase: String) -> Dictionary:
	var value: Dictionary = super.report(passed, phase)
	value["mvp8"] = {
		"recovered": _recovered8,
		"generation": _generation8,
		"checkpoint": _checkpoint8.duplicate(true),
		"bounds": _bounds8(),
		"construction_root": _construction_root8,
		"canonical_state_owned": authority == "authority/a",
		"mvp8_predicate_verified": false,
	}
	return value
