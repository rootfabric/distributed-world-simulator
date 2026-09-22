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


class MatterDecisionEpochAdapter8:
	extends RefCounted
	var source = null
	var matter_region_epoch := 1

	func configure(source_view, region_epoch: int = 1) -> Dictionary:
		if source != null or source_view == null or not source_view.has_method("snapshot") or not source_view.has_method("authorize_write") or region_epoch < 1:
			return {"success": false, "error_code": "MVP8_MATTER_DECISION_ADAPTER_INVALID", "details": {}}
		source = source_view
		matter_region_epoch = region_epoch
		return {"success": true, "error_code": "", "details": {"matter_region_epoch": matter_region_epoch, "canonical_state_owned": false}}

	func snapshot() -> Dictionary:
		return source.snapshot() if source != null else {}

	func authorize_write(authority_id: String, region_epoch: int) -> Dictionary:
		if source == null or region_epoch != matter_region_epoch:
			return {"success": false, "error_code": "MVP8_MATTER_REGION_EPOCH_MISMATCH", "details": {}}
		var current: Dictionary = source.snapshot()
		if current.is_empty() or current.get("state") != "ACTIVE" or String(current.get("active_authority_id", "")) != authority_id:
			return {"success": false, "error_code": "SM1_AUTHORITY_TRANSFER_WRITE_FENCED", "details": {"matter_region_epoch": matter_region_epoch}}
		var sm1_epoch := int(current.get("authority_epoch", 0))
		var authorized: Dictionary = source.authorize_write(authority_id, sm1_epoch)
		if not bool(authorized.get("success", false)):
			return authorized
		var details: Dictionary = Dictionary(authorized.get("details", {})).duplicate(true)
		details["matter_region_epoch"] = matter_region_epoch
		details["sm1_authority_epoch"] = sm1_epoch
		details["canonical_state_owned"] = false
		return {"success": true, "error_code": "", "details": details}


var _repository8 = null
var _adapter8 = null
var _outbox8 = null
var _recovery8 = null
var _sessions8: Dictionary = {}
var _generation8 := 0
var _recovered8 := false
var _checkpoint_receipt8: Dictionary = {}
var _construction_root8 := ""
var _construction_cut_file8 := ""
var _matter_decisions8: Dictionary = {}
var _recovery_decision_bootstrap8 := false
var _recovery_setup_ready8 := false
var _recovery_gameplay_ready8 := false
var _recovery_construction_ready8 := false


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
	_matter_decisions8.clear()
	for actor in ["a", "b"]:
		var adapter = MatterDecisionEpochAdapter8.new()
		var adapter_ready: Dictionary = adapter.configure(decisions[actor], 1)
		if not bool(adapter_ready.get("success", false)):
			return adapter_ready
		_matter_decisions8[actor] = adapter
	_shared_dig4 = create_shared_dig()
	var configured: Dictionary = _shared_dig4.configure(service, _matter_decisions8, _sessions8)
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
	configured = _adapter8.configure_matter7(_shared_dig4, _matter_decisions8, _sessions8, root)
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
		return _restore_gameplay_state8()
	return Protocol.success({"recovered": _recovered8, "generation": _generation8})


func _restore_gameplay_state8() -> Dictionary:
	if authority != "authority/a" or _recovery8 == null or _adapter8 == null:
		return Protocol.failure("MVP8_RECOVERY_RUNTIME_NOT_CONFIGURED")
	if _recovered8:
		return Protocol.success({"replay": true, "recovered": true, "generation": _generation8})
	_generation8 = int(cfg.get("mvp8_generation", 1))
	var restored: Dictionary = _recovery8.require_minimum_generation7(_generation8)
	if not bool(restored.get("success", false)):
		return restored
	restored = _recovery8.recover_latest()
	if not bool(restored.get("success", false)):
		return restored
	_recovered8 = true
	_checkpoint_receipt8 = Dictionary(restored.get("details", {}).get("checkpoint", {})).duplicate(true)
	_shared_dig4 = _adapter8.get_shared_matter7()
	return Protocol.success({"recovered": true, "generation": _generation8})


func initialize_owner() -> Dictionary:
	var recovering := bool(cfg.get("mvp8_recovery", false))
	var expected_epochs: Dictionary = Dictionary(cfg.get(
		"mvp8_player_ownership_epochs",
		cfg.get("mvp8_authority_epochs", {"a": 1, "b": 1})
	)).duplicate(true)
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
	# Recovery restores the canonical Service tick before fresh transport
	# admission. Rebase only the scheduler cursor to that exact tick; resetting
	# it to zero would make the first post-restart tick non-monotonic.
	var initial_clock_tick := int(service.get_report().get("server_tick", 0))
	var clock_ready: Dictionary = clock.configure(60, 8, initial_clock_tick)
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


func _next_construction_sequence8() -> int:
	if _construction6.is_empty() or _bridge6 == null or not _sessions6.has("a"):
		return -1
	var session_id := String(_sessions6["a"].get("session_id", ""))
	if session_id.is_empty():
		return -1
	var session: Dictionary = _construction6["gateway"].get_session_store().get_session(session_id)
	return int(session.get("next_sequence", -1))


func has_part8(snapshot: Dictionary, part_id: String) -> bool:
	for raw in snapshot.get("parts", []):
		if raw is Dictionary and String(raw.get("part_id", "")) == part_id:
			return true
	return false


func _mvp8_add(cycle: int) -> Dictionary:
	if _phase6 != "REMOVED":
		return Protocol.failure("MVP8_BUILD_ADD_PHASE_INVALID")
	var removed := _snapshot6()
	var repair_plan_value = removed.get("compiled_facets", {}).get("damage_repair_plan", {})
	if not repair_plan_value is Dictionary or Dictionary(repair_plan_value).is_empty():
		return Protocol.failure("MVP8_CANONICAL_REPAIR_PLAN_REQUIRED")
	var repair_plan: Dictionary = Dictionary(repair_plan_value).duplicate(true)
	var permissions = _construction6["gateway"].get_permission_store()
	var grant := SeamGrant.create(
		"permission/mvp8/live/repair/%d" % cycle,
		String(_sessions6["a"].get("client_id", "")),
		SeamFactory.CONSTRUCT_ID,
		[SeamGrant.ACTION_READ, SeamGrant.ACTION_REPAIR],
		int(permissions.get_epoch())
	)
	var published: Dictionary = permissions.publish(grant)
	if not bool(published.get("success", false)):
		return published
	var sequence := _next_construction_sequence8()
	if sequence < 0:
		return Protocol.failure("MVP8_CONSTRUCTION_SEQUENCE_REQUIRED")
	var bundle: Dictionary = _bridge6.get_snapshot_packet().get("state_bundle", {})
	var inner := SeamCommand.create(
		"multiplayer-command/mvp8/live/repair-east-leaf/%d" % cycle,
		String(_sessions6["a"].get("client_id", "")),
		String(_sessions6["a"].get("session_id", "")),
		int(_sessions6["a"].get("session_epoch", 0)),
		sequence,
		SeamGrant.ACTION_REPAIR,
		SeamFactory.CONSTRUCT_ID,
		String(removed.get("checksum", "")),
		int(bundle.get("server_generation", 0)),
		int(permissions.get_epoch()),
		{
			"plan_id": "plan/mvp8/live/repair-east-leaf/%d" % cycle,
			"operation_id": "operation/mvp8/live/repair-east-leaf/%d" % cycle,
			"repair_plan": repair_plan,
			"failure_mode": "",
		}
	)
	var checked: Dictionary = SeamCommand.validate(inner)
	if not bool(checked.get("success", false)):
		return checked
	var record: Dictionary = _construction6["cluster"].get_registry().get_record(SeamFactory.CONSTRUCT_ID)
	var construction_epoch := int(record.get("authority_epoch", 0))
	if construction_epoch < 1:
		return Protocol.failure("MVP8_CONSTRUCTION_AUTHORITY_RECORD_REQUIRED")
	var route := DistributedCommand.create(
		"authority-route/mvp8/live/repair-east-%d" % cycle,
		SeamFactory.SERVER_B, SeamFactory.SERVER_A, construction_epoch, inner,
		{"entry": "east", "operation": "ADD", "canonical_action": "DAMAGE_REPAIR", "cycle": cycle}
	)
	var applied: Dictionary = _construction6["cluster"].submit(SeamFactory.SERVER_B, route)
	if not bool(applied.get("success", false)):
		return applied
	var restored := _snapshot6()
	if Array(restored.get("parts", [])).size() != SeamFactory.FINAL_PART_COUNT or not has_part8(restored, SeamFactory.part_id(SeamFactory.ADD_PART_INDEX)):
		return Protocol.failure("MVP8_REPAIR_ADD_DID_NOT_RESTORE_LEAF")
	_phase6 = "ADDED"
	_route_receipts6.append({
		"intent": "MVP8_ADD",
		"canonical_action": "DAMAGE_REPAIR",
		"cycle": cycle,
		"entry_process": "authority/b",
		"writer_process": "authority/a",
		"part_count": Array(restored.get("parts", [])).size(),
	})
	return Protocol.success(_public6({
		"gateway_result": applied.get("gateway_result", {}),
		"cycle": cycle,
		"canonical_action": "DAMAGE_REPAIR",
		"reused_part_identity": SeamFactory.part_id(SeamFactory.ADD_PART_INDEX),
	}))

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
	var sequence := _next_construction_sequence8()
	if sequence < 0:
		return Protocol.failure("MVP8_CONSTRUCTION_SEQUENCE_REQUIRED")
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
	var record: Dictionary = _construction6["cluster"].get_registry().get_record(SeamFactory.CONSTRUCT_ID)
	var construction_epoch := int(record.get("authority_epoch", 0))
	if construction_epoch < 1:
		return Protocol.failure("MVP8_CONSTRUCTION_AUTHORITY_RECORD_REQUIRED")
	var route := DistributedCommand.create(
		"authority-route/mvp8/live/remove-east-%d" % cycle,
		SeamFactory.SERVER_B, SeamFactory.SERVER_A, construction_epoch, inner,
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
	if not _checkpoint_receipt8.is_empty():
		return Protocol.success({"replay": true, "checkpoint": _checkpoint_receipt8.duplicate(true)})
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
	# The Service7 cut is sealed now. Stop fixed-clock/input advancement but keep
	# the process alive for read-only REPORT/SYNC until the gateway acknowledges
	# the planned restart and sends STOP.
	clock = null
	held_inputs.clear()
	pending_fixed_wire.clear()
	pending_fixed_sequence = 0
	_checkpoint_receipt8 = {
		"generation": generation,
		"checkpoint_checksum": String(saved.get("details", {}).get("checkpoint", {}).get("checksum", "")),
		"gameplay_checksum": String(service.export_durable_state().get("checksum", "")),
		"item_graph_checksum": String(graph_state.get("snapshot", {}).get("checksum", "")),
		"construction_checksum": String(snapshot.get("checksum", "")),
		"matter": _shared_dig4.report(),
		"players": players,
	}
	return Protocol.success({"checkpoint": _checkpoint_receipt8.duplicate(true)})


func _bounds8() -> Dictionary:
	var replay: Dictionary = service.export_replay_state() if service != null else {}
	var pending: int = _outbox8.get_pending_records().size() if _outbox8 != null else 0
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


func _bootstrap_recovery_decisions8(body: Dictionary) -> Dictionary:
	if _recovery_decision_bootstrap8:
		return Protocol.success({"replay": true})
	var incoming = body.get("decisions", {})
	if not incoming is Dictionary:
		return Protocol.failure("MVP3_AUTHENTICATED_DECISIONS_REQUIRED")
	var bootstrap := {}
	for actor in ["a", "b"]:
		var current_value = Dictionary(incoming).get(actor, {})
		if not current_value is Dictionary:
			return Protocol.failure("MVP3_AUTHENTICATED_DECISIONS_REQUIRED")
		var current: Dictionary = Dictionary(current_value).duplicate(true)
		var player_value = current.get("player_snapshot", {})
		if not player_value is Dictionary:
			return Protocol.failure("MVP3_DECISION_IDENTITY_INVALID")
		bootstrap[actor] = {
			"state": "ACTIVE",
			"active_authority_id": "authority/a",
			"authority_epoch": 1,
			"player_snapshot": Dictionary(player_value).duplicate(true),
			"transfer": {},
		}
	var baseline := ingest_decisions({"decisions": bootstrap, "completed": {}})
	if not bool(baseline.get("success", false)):
		return baseline
	var current_ingest := ingest_decisions(body)
	if not bool(current_ingest.get("success", false)):
		return current_ingest
	_recovery_decision_bootstrap8 = true
	return Protocol.success()


func _compact_recovery_ack8(kind: String, result: Dictionary) -> Dictionary:
	if not bool(result.get("success", false)):
		return result
	return Protocol.success({
		"kind": kind,
		"authority_id": authority,
		"authority_process_id": OS.get_process_id(),
		"recovery_stage": kind,
	})


func _recovery_setup_stage8(body: Dictionary) -> Dictionary:
	if authority != "authority/a" or service != null or _recovery_setup_ready8:
		return Protocol.failure("MVP8_RECOVERY_SETUP_STAGE_INVALID")
	var boot := _bootstrap_recovery_decisions8(body)
	if not bool(boot.get("success", false)):
		return boot
	service = Service8.new()
	var setup: Dictionary = service.setup(authority, 1, 0, {
		"profile": Service8.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/mvp8/" + authority,
		"fixed_tick_authority": true,
		"mvp6_fixture_owner": true,
		"mvp6_spatial_validation": true,
	})
	if not bool(setup.get("success", false)):
		return setup
	setup = _setup_recovery8(false)
	if not bool(setup.get("success", false)):
		return setup
	_construction_root8 = String(cfg.get("mvp8_construction_root", "")).strip_edges()
	_construction_cut_file8 = String(cfg.get("mvp8_construction_cut_file", "")).strip_edges()
	if _construction_root8.is_empty() or _construction_cut_file8.is_empty():
		return Protocol.failure("MVP8_CONSTRUCTION_PERSISTENCE_PATH_REQUIRED")
	_recovery_setup_ready8 = true
	return _compact_recovery_ack8("MVP8_RECOVERY_SETUP", Protocol.success())


func _recovery_gameplay_stage8() -> Dictionary:
	if authority != "authority/a" or not _recovery_setup_ready8 or _recovery_gameplay_ready8:
		return Protocol.failure("MVP8_RECOVERY_GAMEPLAY_STAGE_INVALID")
	var restored := _restore_gameplay_state8()
	if not bool(restored.get("success", false)):
		return restored
	var expected_epochs: Dictionary = Dictionary(cfg.get(
		"mvp8_player_ownership_epochs",
		cfg.get("mvp8_authority_epochs", {"a": 1, "b": 1})
	)).duplicate(true)
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
	source_view = Views8.SourceReceiptView.new()
	source_view.config = cfg.duplicate(true)
	source_view.source_authority = "authority/b"
	source_view.source_key = String(cfg["internal_keys"]["authority/b"])
	var peer_setup: Dictionary = live_port.register_peer("authority/b", source_view)
	if not bool(peer_setup.get("success", false)):
		return peer_setup
	for actor in ["a", "b"]:
		var bound: Dictionary = live_port.bind_player(actor, Protocol.session(cfg, actor), int(expected_epochs.get(actor, 1)), decisions[actor])
		if not bool(bound.get("success", false)):
			return bound
	clock = Scheduler8.new()
	var clock_ready: Dictionary = clock.configure(60, 8, int(service.get_report().get("server_tick", 0)))
	if not bool(clock_ready.get("success", false)):
		return clock_ready
	_recovery_gameplay_ready8 = true
	return _compact_recovery_ack8("MVP8_RECOVERY_GAMEPLAY", Protocol.success())


func _recovery_construction_stage8() -> Dictionary:
	if authority != "authority/a" or not _recovery_gameplay_ready8 or _recovery_construction_ready8:
		return Protocol.failure("MVP8_RECOVERY_CONSTRUCTION_STAGE_INVALID")
	var restored := _restore_construction8()
	if not bool(restored.get("success", false)):
		return restored
	_recovery_construction_ready8 = true
	return _compact_recovery_ack8("MVP8_RECOVERY_CONSTRUCTION", Protocol.success())


func _recovery_init8(body: Dictionary) -> Dictionary:
	# Compatibility path for direct tests. The production MVP8 gateway uses the
	# staged recovery handshake below so ENet servicing resumes between restore
	# participants.
	var boot := _bootstrap_recovery_decisions8(body)
	if not bool(boot.get("success", false)):
		return boot
	var result := initialize_owner()
	return native_envelope("INIT", "", result)


func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if bool(cfg.get("mvp8_recovery", false)):
		if kind == "MVP8_RECOVERY_SETUP":
			return _recovery_setup_stage8(body)
		if kind == "MVP8_RECOVERY_GAMEPLAY":
			return _recovery_gameplay_stage8()
		if kind == "MVP8_RECOVERY_CONSTRUCTION":
			return _recovery_construction_stage8()
		if kind == "INIT":
			return _recovery_init8(body)
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
			# Actor-scoped Item Graph ownership follows the accepted SM1 player
			# transfer. Execute only on the authority that currently has the
			# canonical player record; a stale/non-owner authority fails closed.
			var player: Dictionary = service.get_player(actor)
			if player.is_empty():
				result = Protocol.failure("MVP8_ITEM_ACTIVE_OWNER_REQUIRED")
			else:
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
		"checkpoint": _checkpoint_receipt8.duplicate(true),
		"bounds": _bounds8(),
		"construction_root": _construction_root8,
		"canonical_state_owned": authority == "authority/a",
		"recovery_decision_bootstrap": _recovery_decision_bootstrap8,
		"recovery_stages": {
			"setup": _recovery_setup_ready8,
			"gameplay": _recovery_gameplay_ready8,
			"construction": _recovery_construction_ready8,
		},
		"mvp8_predicate_verified": false,
	}
	return value
