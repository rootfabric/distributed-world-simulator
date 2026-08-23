extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"

const ResourceMiningDelta = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_delta.gd"
)
const V0P4EarthOutpostAuthority = preload(
	"res://scripts/construction/mvp/v0_p4_mvp_earth_outpost_authority.gd"
)
const V0P4ConstructionBridge = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd"
)

var _resource_commands := 0
var _resource_rejections := 0
var _resource_deltas_published := 0
var _resource_snapshots_published := 0
var _resource_delta_build_failures := 0
var _resource_resync_requests := 0
var _v0_p4_composition_report: Dictionary = {}
var _v0_p4_legacy_prebind_ignored := false
var _v0_p4_publication_batches := 0
var _v0_p4_item_snapshot_fallbacks := 0
var _v0_p4_construction_snapshot_fallbacks := 0
var _v0_p4_replay_publications_suppressed := 0


func set_construction_bridge(bridge) -> Dictionary:
	# Compatibility quarantine for the legacy SimulatorApp Earth prebind.
	# P4.4 must bind Construction only after the canonical gameplay service has
	# been set up/recovered, so the old fixture bridge is validated but never
	# installed as the live M3 bridge. The real P4 bridge is created below in
	# _setup_v0_p4_live_composition() before transport start.
	if _configured:
		return _failure("M3_CONSTRUCTION_BRIDGE_MUST_BE_SET_BEFORE_SETUP")
	if bridge == null or not bridge.has_method("connect_player") or not bridge.has_method("submit_player_command"):
		return _failure("M3_CONSTRUCTION_BRIDGE_INVALID")
	_v0_p4_legacy_prebind_ignored = true
	return _success({"deferred_to_v0_p4_live_composition": true})


func _setup_v0_p4_live_composition(config: Dictionary) -> Dictionary:
	_v0_p4_composition_report = {
		"enabled": false,
		"bound_before_clients": false,
		"single_item_graph_identity": false,
		"fixture_material_truth_present": false,
	}
	var world_id := String(config.get("world_id", "")).strip_edges().to_lower()
	if world_id != "earth":
		return _success({"v0_p4_construction": _v0_p4_composition_report.duplicate(true)})
	if not bool(config.get("enable_v0_p4_construction", true)):
		return _success({"v0_p4_construction": _v0_p4_composition_report.duplicate(true)})
	if _construction_bridge != null:
		return _failure("V0_P4_CONSTRUCTION_BRIDGE_ALREADY_BOUND")
	if _service == null or not _service.has_method("get_canonical_item_graph_port"):
		return _failure("V0_P4_CANONICAL_GAMEPLAY_SERVICE_REQUIRED")
	var canonical_item_graph = _service.get_canonical_item_graph_port()
	if canonical_item_graph == null:
		return _failure("V0_P4_CANONICAL_ITEM_GRAPH_REQUIRED")
	if (
		not canonical_item_graph.has_method("preflight_server_construction_consume")
		or not canonical_item_graph.has_method("apply_server_construction_consume")
	):
		return _failure("V0_P4_CANONICAL_ITEM_GRAPH_NOT_CONSTRUCTION_CAPABLE")
	var repository_root := String(config.get("construction_repository_root", "")).strip_edges()
	if repository_root.is_empty():
		var persistence_root := String(config.get("persistence_root", "")).strip_edges()
		if not persistence_root.is_empty():
			repository_root = "%s/v0-p4-construction-m0" % persistence_root
		else:
			repository_root = "user://v0-p4-construction/runtime-%d-%d" % [
				OS.get_process_id(),
				get_instance_id(),
			]
	var authority_result: Dictionary = V0P4EarthOutpostAuthority.create_gateway(
		canonical_item_graph,
		_authority_owner_id,
		_authority_epoch,
		repository_root
	)
	if not bool(authority_result.get("success", false)):
		return authority_result
	var details: Dictionary = Dictionary(authority_result.get("details", {}))
	if not bool(details.get("single_item_graph_identity", false)):
		return _failure("V0_P4_CANONICAL_ITEM_GRAPH_IDENTITY_MISMATCH")
	if bool(details.get("fixture_material_truth_present", true)):
		return _failure("V0_P4_FIXTURE_MATERIAL_TRUTH_FORBIDDEN")
	var construction_bridge = V0P4ConstructionBridge.new()
	var bridge_setup: Dictionary = construction_bridge.setup(details.get("gateway"))
	if not bool(bridge_setup.get("success", false)):
		return bridge_setup
	_construction_bridge = construction_bridge
	_v0_p4_composition_report = {
		"enabled": true,
		"bound_before_clients": true,
		"single_item_graph_identity": true,
		"fixture_material_truth_present": false,
		"legacy_prebind_ignored": _v0_p4_legacy_prebind_ignored,
		"repository_root": repository_root,
		"construct_id": String(details.get("construct_id", "")),
		"build_plan_id": String(details.get("build_plan_id", "")),
		"p4_construction_consume_ready": true,
		"resource_mining_bound_to_same_service": (
			_service.has_method("get_resource_mining_port")
			and _service.get_resource_mining_port() != null
		),
	}
	return _success({"v0_p4_construction": _v0_p4_composition_report.duplicate(true)})


func _setup_network_condition_simulator(config: Dictionary) -> Dictionary:
	# P4.4 reuses the existing M3 setup seam that already runs after M6 recovery
	# and before Boundary.start_server(). This keeps Construction bound to the
	# recovered canonical M4 owner without changing the generic P2 runtime.
	var composition: Dictionary = _setup_v0_p4_live_composition(config)
	if not bool(composition.get("success", false)):
		return composition
	return super._setup_network_condition_simulator(config)


func get_v0_p4_composition_report() -> Dictionary:
	return _v0_p4_composition_report.duplicate(true)


func _handle_message(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var message_type := String(payload.get("type", ""))
	if message_type == "RESOURCE_COMMAND" or message_type == "RESOURCE_RESYNC_REQUEST":
		if not _is_peer_compatible(peer_id, session_id):
			_reject_pre_handshake_message(peer_id, payload)
			return
		if message_type == "RESOURCE_COMMAND":
			_handle_resource_command(peer_id, session_id, payload)
		else:
			_handle_resource_resync_request(peer_id, session_id, payload)
		return

	super._handle_message(peer_id, session_id, payload)
	# JOIN_ACK already carries gameplay and Item Graph state. Publish the P3
	# resource snapshot on the same reliable RESYNC stream immediately after a
	# successful join so old P2 message ordering remains untouched.
	if (
		message_type == "JOIN"
		and _peer_to_player.has(peer_id)
		and String(_peer_to_session.get(peer_id, "")) == session_id
	):
		_send_resource_snapshot(peer_id, "PLAYER_JOINED")


func _handle_construction_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", _failure("STALE_TRANSPORT_SESSION"))
		return
	if _construction_bridge == null:
		_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", _failure("M3_CONSTRUCTION_NOT_ENABLED"))
		return
	var command_value = payload.get("command", {})
	if not command_value is Dictionary:
		_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", _failure("CONSTRUCTION_COMMAND_REQUIRED"))
		return
	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var before_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	var submitted: Dictionary = _construction_bridge.submit_player_command(logical_id, Dictionary(command_value))
	if not bool(submitted.get("success", false)):
		_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", submitted)
		_rejections += 1
		return

	var gateway_result: Dictionary = Dictionary(submitted.get("details", {}).get("result", {}))
	var replay := bool(gateway_result.get("replay", false))
	if replay:
		_send_result(peer_id, operation_id, "CONSTRUCTION_COMMAND", submitted)
		_v0_p4_replay_publications_suppressed += 1
		_write_report("READY", false)
		return

	# The cross-domain commit has succeeded at this point. From here onward all
	# failures are replication failures and must recover with authoritative
	# snapshots; they must never turn the committed build into a rejection.
	var after_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	var item_delta: Dictionary = {}
	var item_snapshot_fallback_required := false
	var item_delta_result: Dictionary = CanonicalItemGraphDelta.create(
		before_item_snapshot,
		after_item_snapshot
	)
	if not bool(item_delta_result.get("success", false)):
		item_snapshot_fallback_required = true
		_item_graph_delta_build_failures += 1
		_v0_p4_item_snapshot_fallbacks += 1
		_last_error_code = "V0_P4_CONSTRUCTION_ITEM_DELTA_BUILD_FAILED"
	else:
		item_delta = Dictionary(item_delta_result.get("details", {}).get("delta", {})).duplicate(true)

	var submitted_details: Dictionary = Dictionary(submitted.get("details", {}))
	var event_packet: Dictionary = Dictionary(submitted_details.get("event_packet", {})).duplicate(true)
	var construction_snapshot: Dictionary = Dictionary(submitted_details.get("snapshot_packet", {})).duplicate(true)
	var construction_snapshot_fallback_required := bool(
		submitted_details.get("event_fallback_required", false)
	) or event_packet.is_empty()
	if construction_snapshot_fallback_required:
		_v0_p4_construction_snapshot_fallbacks += 1
		_last_error_code = "V0_P4_CONSTRUCTION_EVENT_BUILD_FAILED"

	var result_sent := _send_result(
		peer_id,
		operation_id,
		"CONSTRUCTION_COMMAND",
		submitted,
		{} if item_snapshot_fallback_required else item_delta
	)
	if item_snapshot_fallback_required:
		_broadcast_item_snapshot("V0_P4_CONSTRUCTION_ITEM_DELTA_FALLBACK")
	else:
		_broadcast_item_delta(item_delta, peer_id, "construction.build")

	if construction_snapshot_fallback_required:
		if construction_snapshot.is_empty() and _construction_bridge.has_method("get_snapshot_packet"):
			construction_snapshot = _construction_bridge.get_snapshot_packet()
		_broadcast_v0_p4_construction_snapshot(
			construction_snapshot,
			"V0_P4_CONSTRUCTION_EVENT_FALLBACK"
		)
	else:
		_broadcast_v0_p4_construction_event(event_packet)

	_v0_p4_publication_batches += 1
	_capture_two_connected_checksum()
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _broadcast_v0_p4_construction_event(event_packet: Dictionary) -> void:
	if event_packet.is_empty():
		return
	for peer_id_value in _peer_to_player.keys():
		if _send_on_channel(
			String(peer_id_value),
			"CONSTRUCTION_EVENT",
			event_packet,
			RealtimeChannelPolicy.RESYNC,
			"RELIABLE_ORDERED"
		):
			_broadcasts += 1
			_construction_events_published += 1


func _broadcast_v0_p4_construction_snapshot(snapshot_packet: Dictionary, reason: String) -> void:
	if snapshot_packet.is_empty():
		_last_error_code = "V0_P4_CONSTRUCTION_SNAPSHOT_FALLBACK_MISSING"
		return
	var payload := snapshot_packet.duplicate(true)
	payload["reason"] = reason
	for peer_id_value in _peer_to_player.keys():
		if _send_on_channel(
			String(peer_id_value),
			"CONSTRUCTION_SNAPSHOT",
			payload,
			RealtimeChannelPolicy.RESYNC,
			"RELIABLE_ORDERED"
		):
			_broadcasts += 1
			_construction_snapshots_published += 1


func _handle_resource_command(peer_id: String, session_id: String, payload: Dictionary) -> void:
	_resource_commands += 1
	var operation_id := String(payload.get("operation_id", "")).strip_edges()
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		_send_result(peer_id, operation_id, "resource.mine", _failure("STALE_TRANSPORT_SESSION"))
		_resource_rejections += 1
		return
	if not _is_canonical_operation_id(operation_id):
		_reject_uncommitted_command(
			peer_id,
			operation_id,
			"resource.mine",
			"OPERATION_ID_REQUIRED" if operation_id.is_empty() else "INVALID_OPERATION_ID"
		)
		_resource_rejections += 1
		return
	var command_payload_value = payload.get("payload", {})
	if not command_payload_value is Dictionary:
		_reject_uncommitted_command(
			peer_id,
			operation_id,
			"resource.mine",
			"INVALID_RESOURCE_COMMAND"
		)
		_resource_rejections += 1
		return
	if _service == null or not _service.has_method("handle_resource_mine"):
		_send_result(peer_id, operation_id, "resource.mine", _failure("RESOURCE_MINING_NOT_READY"))
		_resource_rejections += 1
		return

	var logical_id := String(_peer_to_player.get(peer_id, ""))
	var before_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
	var before_resource_snapshot: Dictionary = _service.create_resource_mining_snapshot()
	var result: Dictionary = _service.handle_resource_mine(
		logical_id,
		session_id,
		int(payload.get("ownership_epoch", 0)),
		operation_id,
		Dictionary(command_payload_value)
	)
	if not _persist_command_result(operation_id, "resource.mine", logical_id, result):
		_send_result(peer_id, operation_id, "resource.mine", _failure("M6_DURABLE_COMMIT_FAILED"))
		return

	var item_delta: Dictionary = {}
	var item_fallback_required := false
	var resource_delta: Dictionary = {}
	var resource_fallback_required := false
	if bool(result.get("success", false)) and not _is_replay_result(result):
		var after_item_snapshot: Dictionary = _service.create_canonical_item_graph_snapshot()
		var item_delta_result: Dictionary = CanonicalItemGraphDelta.create(
			before_item_snapshot,
			after_item_snapshot
		)
		if not bool(item_delta_result.get("success", false)):
			item_fallback_required = true
			_item_graph_delta_build_failures += 1
			_last_error_code = "ITEM_GRAPH_DELTA_BUILD_FAILED"
		else:
			item_delta = Dictionary(item_delta_result.get("details", {}).get("delta", {})).duplicate(true)

		var after_resource_snapshot: Dictionary = _service.create_resource_mining_snapshot()
		var resource_delta_result: Dictionary = ResourceMiningDelta.create(
			before_resource_snapshot,
			after_resource_snapshot
		)
		if not bool(resource_delta_result.get("success", false)):
			resource_fallback_required = true
			_resource_delta_build_failures += 1
			_last_error_code = "RESOURCE_DELTA_BUILD_FAILED"
		else:
			resource_delta = Dictionary(
				resource_delta_result.get("details", {}).get("delta", {})
			).duplicate(true)

	var result_sent := _send_result(peer_id, operation_id, "resource.mine", result, item_delta)
	if bool(result.get("success", false)):
		if not _is_replay_result(result):
			if item_fallback_required:
				_broadcast_item_snapshot("RESOURCE_MINE_ITEM_DELTA_FALLBACK")
			else:
				_broadcast_item_delta(item_delta, peer_id, "resource.mine")
			if resource_fallback_required:
				_broadcast_resource_snapshot("RESOURCE_DELTA_BUILD_FALLBACK")
			else:
				_broadcast_resource_delta(resource_delta)
			_broadcast_snapshot("RESOURCE_MINED", RealtimeChannelPolicy.RESYNC, "RELIABLE_ORDERED")
			_capture_two_connected_checksum()
	else:
		_rejections += 1
		_resource_rejections += 1
	if result_sent:
		_mark_operation_delivered(operation_id)
	_write_report("READY", false)


func _handle_resource_resync_request(
	peer_id: String,
	session_id: String,
	_payload: Dictionary
) -> void:
	if not _peer_to_player.has(peer_id) or String(_peer_to_session.get(peer_id, "")) != session_id:
		return
	_resource_resync_requests += 1
	_send_resource_snapshot(peer_id, "EXPLICIT_RESYNC")


func _send_resource_snapshot(peer_id: String, reason: String) -> bool:
	if _service == null or not _service.has_method("create_resource_mining_snapshot"):
		return false
	var snapshot: Dictionary = _service.create_resource_mining_snapshot()
	if snapshot.is_empty():
		return false
	var sent := _send_on_channel(
		peer_id,
		"RESOURCE_SNAPSHOT",
		{"reason": reason, "snapshot": snapshot},
		RealtimeChannelPolicy.RESYNC,
		"RELIABLE_ORDERED"
	)
	if sent:
		_resource_snapshots_published += 1
	return sent


func _broadcast_resource_snapshot(reason: String) -> void:
	for peer_id_value in _peer_to_player.keys():
		if _send_resource_snapshot(String(peer_id_value), reason):
			_broadcasts += 1


func _broadcast_resource_delta(delta: Dictionary) -> void:
	if delta.is_empty():
		return
	for peer_id_value in _peer_to_player.keys():
		if _send_on_channel(
			String(peer_id_value),
			"RESOURCE_DELTA",
			{"delta": delta},
			RealtimeChannelPolicy.ITEM,
			"RELIABLE_ORDERED"
		):
			_broadcasts += 1
			_resource_deltas_published += 1


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["v0_p3_resource_mining"] = {
		"resource_commands": _resource_commands,
		"resource_rejections": _resource_rejections,
		"resource_deltas_published": _resource_deltas_published,
		"resource_snapshots_published": _resource_snapshots_published,
		"resource_delta_build_failures": _resource_delta_build_failures,
		"resource_resync_requests": _resource_resync_requests,
		"snapshot": (
			_service.create_resource_mining_snapshot()
			if _service != null and _service.has_method("create_resource_mining_snapshot")
			else {}
		),
	}
	report["v0_p4_live_composition"] = _v0_p4_composition_report.duplicate(true)
	report["v0_p4_post_commit_publication"] = {
		"publication_batches": _v0_p4_publication_batches,
		"item_snapshot_fallbacks": _v0_p4_item_snapshot_fallbacks,
		"construction_snapshot_fallbacks": _v0_p4_construction_snapshot_fallbacks,
		"replay_publications_suppressed": _v0_p4_replay_publications_suppressed,
	}
	return report
