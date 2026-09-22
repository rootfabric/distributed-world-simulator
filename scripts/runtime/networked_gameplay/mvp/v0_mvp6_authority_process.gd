extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_authority_process.gd"

# MVP6 keeps the accepted MVP3-MVP5 process protocol and swaps only the
# concrete gameplay service during bootstrap so native item carrying is part of
# the same authority process. Construction truth exists only on authority/a;
# authority/b is a signed route/replica participant and never owns a store.
const Service6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_gameplay_service.gd")
const Views6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_remote_owner_views.gd")
const Scheduler6 = preload("res://scripts/network/simulation/fixed_tick_scheduler.gd")
const SeamFactory = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_cross_authority_construction_factory.gd")
const SeamBridge = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const SeamCommand = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const SeamGrant = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const DistributedCommand = preload("res://scripts/construction/distributed/construction_distributed_command.gd")
const DamageRequest = preload("res://scripts/construction/damage/construction_damage_request.gd")
const SalvagePolicy = preload("res://scripts/construction/damage/construction_salvage_policy.gd")
const ItemRelations = preload("res://scripts/items/domain/item_relations.gd")

var _construction6: Dictionary = {}
var _bridge6 = null
var _sessions6: Dictionary = {}
var _routes6: Dictionary = {}
var _replica6: Dictionary = {}
var _phase6 := "EMPTY"
var _route_receipts6: Array = []
var _replays6 := {"ADD": false, "REMOVE": false}


func initialize_owner() -> Dictionary:
	# This is the inherited MVP3 initialization sequence with Service6 as the
	# only semantic change. The MVP4/MVP5 source is configured afterwards on the
	# same service exactly as the parent implementation does.
	service = Service6.new()
	var setup: Dictionary = service.setup(authority, 1, 0, {
		"profile": Service6.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/mvp6/" + authority,
		"fixed_tick_authority": true,
		"mvp6_fixture_owner": authority == "authority/a",
		"mvp6_spatial_validation": true,
	})
	if not bool(setup.get("success", false)):
		return setup
	if authority == "authority/a":
		for actor in ["a", "b"]:
			var joined: Dictionary = service.join(actor, Protocol.session(cfg, actor), "operation/mvp6/" + String(cfg["run_id"]) + "/join/" + actor)
			if not bool(joined.get("success", false)):
				return joined
	initial_snapshot = service.create_snapshot()
	initial_graph = service.create_canonical_item_graph_snapshot()
	live_port = service.get_live_player_transfer_port()
	if live_port == null:
		return Protocol.failure("MVP6_NATIVE_LIVE_PORT_MISSING")
	var other := "authority/b" if authority == "authority/a" else "authority/a"
	source_view = Views6.SourceReceiptView.new()
	source_view.config = cfg.duplicate(true)
	source_view.source_authority = other
	source_view.source_key = String(cfg["internal_keys"][other])
	var peer_setup: Dictionary = live_port.register_peer(other, source_view)
	if not bool(peer_setup.get("success", false)):
		return peer_setup
	for actor in ["a", "b"]:
		var bound: Dictionary = live_port.bind_player(actor, Protocol.session(cfg, actor), 1, decisions[actor])
		if not bool(bound.get("success", false)):
			return bound
	clock = Scheduler6.new()
	var clock_ready: Dictionary = clock.configure(60, 8, 0)
	if not bool(clock_ready.get("success", false)):
		return clock_ready
	if authority == "authority/a":
		_shared_dig4 = create_shared_dig()
		var shared_ready: Dictionary = _shared_dig4.configure(service, decisions, {"a": Protocol.session(cfg, "a"), "b": Protocol.session(cfg, "b")})
		if not bool(shared_ready.get("success", false)):
			return shared_ready
	return Protocol.success()


func _graph6():
	return service.get_canonical_item_graph_port() if service != null and service.has_method("get_canonical_item_graph_port") else null


func _ore6(snapshot: Dictionary, actor: String) -> int:
	var total := 0
	for row in snapshot.get("items", []):
		if not row is Dictionary or String(row.get("definition_id", "")) != "item/ore":
			continue
		var owner := String(row.get("player_id", ""))
		var location = row.get("location", {})
		if location is Dictionary:
			owner = String(location.get("player_id", owner))
		if owner == actor:
			total += int(row.get("quantity", 0))
	return total


func _find_item6(snapshot: Dictionary, item_id: String) -> Dictionary:
	for row in snapshot.get("items", []):
		if row is Dictionary and String(row.get("item_id", "")) == item_id:
			return Dictionary(row).duplicate(true)
	return {}


func _stage_ore6() -> Dictionary:
	var graph = _graph6()
	if graph == null:
		return Protocol.failure("MVP6_CANONICAL_ITEM_GRAPH_MISSING")
	var player: Dictionary = service.get_player("a")
	if player.is_empty():
		return Protocol.failure("MVP6_CONSTRUCTION_PLAYER_A_MISSING")
	var snapshot: Dictionary = graph.create_snapshot()
	var inventory: Dictionary = snapshot.get("inventories", {}).get("a", {})
	for raw_id in Array(inventory.get("hotbar", [])).duplicate():
		var item_id := String(raw_id)
		if item_id.is_empty():
			continue
		var item := _find_item6(snapshot, item_id)
		if String(item.get("definition_id", "")) != "item/ore":
			continue
		var moved: Dictionary = service.handle_canonical_item_command(
			"a",
			String(player.get("transport_session_id", "")),
			int(player.get("ownership_epoch", 0)),
			"operation/mvp6/live/stage-" + item_id.sha256_text().left(12),
			"item.transfer",
			{
				"item_id": item_id,
				"quantity": int(item.get("quantity", 0)),
				"target_container_id": "inventory/a",
				"target_slot_index": -1,
			}
		)
		if not bool(moved.get("success", false)):
			return moved
		snapshot = graph.create_snapshot()
	return Protocol.success({"ore": _ore6(graph.create_snapshot(), "a")})


func _ensure_ore6(required: int) -> Dictionary:
	var graph = _graph6()
	if graph == null:
		return Protocol.failure("MVP6_CANONICAL_ITEM_GRAPH_MISSING")
	var before := _ore6(graph.create_snapshot(), "a")
	var staged := _stage_ore6()
	if not bool(staged.get("success", false)):
		return staged
	var after := _ore6(graph.create_snapshot(), "a")
	if before < required or after < required:
		return Protocol.failure("MVP6_CONSTRUCTION_ORE_INSUFFICIENT")
	return Protocol.success({"ore_before": before, "ore_available": after, "required": required, "topup_issued": false})


func _construct_checksum6(bundle: Dictionary) -> String:
	for row in bundle.get("constructs", []):
		if row is Dictionary and String(row.get("construct_id", "")) == SeamFactory.CONSTRUCT_ID:
			return String(row.get("checksum", ""))
	return ""


func _build_command6(sequence: int, stage_index: int, suffix: String) -> Dictionary:
	var session: Dictionary = _sessions6.get("a", {})
	var bundle: Dictionary = _bridge6.get_snapshot_packet().get("state_bundle", {})
	return SeamCommand.create(
		"multiplayer-command/mvp6/live/" + suffix,
		String(session.get("client_id", "")),
		String(session.get("session_id", "")),
		int(session.get("session_epoch", 0)),
		sequence,
		SeamGrant.ACTION_BUILD,
		SeamFactory.CONSTRUCT_ID,
		_construct_checksum6(bundle),
		int(bundle.get("server_generation", 0)),
		int(session.get("permission_epoch", 0)),
		{
			"build_plan_id": SeamFactory.BUILD_PLAN_ID,
			"stage_index": stage_index,
			"operation_id": "operation/mvp6/live/" + suffix,
			"provided_capabilities": ["FASTEN"],
			"options": {},
		}
	)


func _snapshot6() -> Dictionary:
	if _construction6.is_empty():
		return {}
	return Dictionary(_construction6["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID)).duplicate(true)


func _public6(extra: Dictionary = {}) -> Dictionary:
	var snapshot := _snapshot6()
	var value := {
		"phase": _phase6,
		"construction": snapshot,
		"construct_id": SeamFactory.CONSTRUCT_ID,
		"part_count": Array(snapshot.get("parts", [])).size(),
		"bond_count": Array(snapshot.get("bonds", [])).size(),
		"checksum": String(snapshot.get("checksum", "")),
		"build_state": String(snapshot.get("build_state", "")),
		"canonical_construction_owned": authority == "authority/a" and not _construction6.is_empty(),
		"authority_owner": SeamFactory.SERVER_A,
		"authority_entry": SeamFactory.SERVER_B,
		"authority_process_id": OS.get_process_id(),
		"single_item_graph_identity": bool(_construction6.get("single_item_graph_identity", false)),
		"route_receipts": _route_receipts6.duplicate(true),
		"replays": _replays6.duplicate(true),
	}
	for key in extra:
		value[key] = extra[key]
	return value


func _ensure_construction6() -> Dictionary:
	if authority != "authority/a":
		return Protocol.failure("MVP6_CONSTRUCTION_CANONICAL_OWNER_REQUIRED")
	if not _construction6.is_empty():
		return Protocol.success(_public6({"replay": true}))
	var ore_ready := _ensure_ore6(SeamFactory.FINAL_PART_COUNT)
	if not bool(ore_ready.get("success", false)):
		return ore_ready
	var decision_a: Dictionary = decisions["a"].snapshot()
	if String(decision_a.get("active_authority_id", "")) != "authority/a":
		return Protocol.failure("MVP6_CONSTRUCTION_PLAYER_A_NOT_RETURNED")
	var root := "user://mvp6-live-construction/%s-%d" % [String(cfg["run_id"]), OS.get_process_id()]
	var created: Dictionary = SeamFactory.create(_graph6(), "authority/a", 1, root)
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


func _route_attestation6(attestation: Dictionary, intent: String) -> Dictionary:
	if not Protocol.verify(cfg, attestation, "authority/b", "gateway", String(cfg.get("internal_keys", {}).get("authority/b", ""))):
		return Protocol.failure("MVP6_AUTHORITY_B_ROUTE_ATTESTATION_INVALID")
	var body: Dictionary = attestation.get("body", {})
	var envelope: Dictionary = body.get("details", {})
	var result: Dictionary = envelope.get("result", {})
	var details: Dictionary = result.get("details", {})
	if body.get("success") != true or result.get("success") != true or String(details.get("intent", "")) != intent or details.get("route_validated") != true or details.get("canonical_construction_owned") != false:
		return Protocol.failure("MVP6_AUTHORITY_B_ROUTE_ATTESTATION_MISMATCH")
	return Protocol.success({"authority_b_process_id": details.get("authority_process_id", 0), "route_sequence": attestation.get("sequence", 0)})


func _apply_add6() -> Dictionary:
	if _phase6 != "BASE":
		return Protocol.failure("MVP6_ADD_PHASE_INVALID")
	var inner := _build_command6(1, 1, "add-east-leaf")
	var route := DistributedCommand.create("authority-route/mvp6/live/add-east", SeamFactory.SERVER_B, SeamFactory.SERVER_A, 1, inner, {"entry":"east", "operation":"ADD"})
	var applied: Dictionary = _construction6["cluster"].submit(SeamFactory.SERVER_B, route)
	if not bool(applied.get("success", false)):
		return applied
	_routes6["ADD"] = route.duplicate(true)
	_phase6 = "ADDED"
	_route_receipts6.append({"intent":"ADD", "entry_process":"authority/b", "writer_process":"authority/a", "forwarded":applied.get("forwarded", false), "owner_server_id":applied.get("owner_server_id", "")})
	return Protocol.success(_public6({"gateway_result": applied.get("gateway_result", {})}))


func _publish_damage6() -> Dictionary:
	var permissions = _construction6["gateway"].get_permission_store()
	var grant := SeamGrant.create(
		"permission/mvp6/live/damage", String(_sessions6["a"].get("client_id", "")), SeamFactory.CONSTRUCT_ID,
		[SeamGrant.ACTION_DAMAGE, SeamGrant.ACTION_READ], int(permissions.get_epoch())
	)
	var published: Dictionary = permissions.publish(grant)
	return published if not bool(published.get("success", false)) else Protocol.success({"permission_epoch": permissions.get_epoch()})


func _apply_remove6() -> Dictionary:
	if _phase6 != "ADDED":
		return Protocol.failure("MVP6_REMOVE_PHASE_INVALID")
	var permission_ready := _publish_damage6()
	if not bool(permission_ready.get("success", false)):
		return permission_ready
	var added := _snapshot6()
	var permissions = _construction6["gateway"].get_permission_store()
	var salvage_transform := Transform3D(Basis.IDENTITY, Vector3(float(SeamFactory.ADD_PART_INDEX) - 49.5, 0.5, 0.0))
	var request := DamageRequest.create(
		"damage/mvp6/live/remove-east-leaf", SeamFactory.CONSTRUCT_ID, String(added.get("checksum", "")),
		SeamFactory.part_id(0), [SeamFactory.bond_id(SeamFactory.ADD_PART_INDEX - 1)], [], {}, [],
		SalvagePolicy.create(2, ItemRelations.world(salvage_transform), false)
	)
	var checked: Dictionary = DamageRequest.validate(request)
	if not bool(checked.get("success", false)):
		return checked
	var bundle: Dictionary = _bridge6.get_snapshot_packet().get("state_bundle", {})
	var inner := SeamCommand.create(
		"multiplayer-command/mvp6/live/remove-east-leaf",
		String(_sessions6["a"].get("client_id", "")), String(_sessions6["a"].get("session_id", "")), int(_sessions6["a"].get("session_epoch", 0)), 2,
		SeamGrant.ACTION_DAMAGE, SeamFactory.CONSTRUCT_ID, String(added.get("checksum", "")), int(bundle.get("server_generation", 0)), int(permissions.get_epoch()),
		{"plan_id":"plan/mvp6/live/remove-east-leaf", "operation_id":"operation/mvp6/live/remove-east-leaf", "request":request, "failure_mode":""}
	)
	var valid: Dictionary = SeamCommand.validate(inner)
	if not bool(valid.get("success", false)):
		return valid
	var route := DistributedCommand.create("authority-route/mvp6/live/remove-east", SeamFactory.SERVER_B, SeamFactory.SERVER_A, 1, inner, {"entry":"east", "operation":"REMOVE"})
	var applied: Dictionary = _construction6["cluster"].submit(SeamFactory.SERVER_B, route)
	if not bool(applied.get("success", false)):
		return applied
	_routes6["REMOVE"] = route.duplicate(true)
	_phase6 = "REMOVED"
	_route_receipts6.append({"intent":"REMOVE", "entry_process":"authority/b", "writer_process":"authority/a", "forwarded":applied.get("forwarded", false), "owner_server_id":applied.get("owner_server_id", "")})
	return Protocol.success(_public6({"gateway_result": applied.get("gateway_result", {})}))


func _replay6(intent: String) -> Dictionary:
	if not _routes6.has(intent):
		return Protocol.failure("MVP6_REPLAY_ROUTE_MISSING")
	var before := _snapshot6()
	var replayed: Dictionary = _construction6["cluster"].submit(SeamFactory.SERVER_B, _routes6[intent])
	if not bool(replayed.get("success", false)):
		return replayed
	if not bool(replayed.get("gateway_result", {}).get("replay", false)) or _snapshot6() != before:
		return Protocol.failure("MVP6_EXACT_REPLAY_MUTATED_CONSTRUCTION")
	_replays6[intent] = true
	return Protocol.success(_public6({"replay": true, "gateway_result": replayed.get("gateway_result", {})}))


func _sync_replica6(body: Dictionary) -> Dictionary:
	if authority != "authority/b":
		return Protocol.failure("MVP6_REPLICA_NONOWNER_REQUIRED")
	var attestation: Dictionary = body.get("source_attestation", {})
	if not Protocol.verify(cfg, attestation, "authority/a", "gateway", String(cfg.get("internal_keys", {}).get("authority/a", ""))):
		return Protocol.failure("MVP6_REPLICA_SOURCE_ATTESTATION_INVALID")
	var source_body: Dictionary = attestation.get("body", {})
	var envelope: Dictionary = source_body.get("details", {})
	var result: Dictionary = envelope.get("result", {})
	var details: Dictionary = result.get("details", {})
	var snapshot: Dictionary = details.get("construction", {})
	if source_body.get("success") != true or result.get("success") != true or snapshot.is_empty() or String(snapshot.get("checksum", "")) != String(body.get("checksum", "")):
		return Protocol.failure("MVP6_REPLICA_SOURCE_PAYLOAD_INVALID")
	_replica6 = snapshot.duplicate(true)
	return Protocol.success({
		"construction": _replica6.duplicate(true),
		"checksum": String(_replica6.get("checksum", "")),
		"part_count": Array(_replica6.get("parts", [])).size(),
		"canonical_construction_owned": false,
		"replica_read_only": true,
		"authority_process_id": OS.get_process_id(),
	})


func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP6_"):
		return super.handle_rpc(body)
	if closing_ms > 0:
		return Protocol.failure("MVP6_AUTHORITY_STOPPING")
	var ingested: Dictionary = ingest_decisions(body)
	if not bool(ingested.get("success", false)):
		return ingested
	if service == null:
		return Protocol.failure("MVP6_NATIVE_OWNER_NOT_INITIALIZED")
	var actor := String(body.get("actor", ""))
	if actor not in ["a", "b"] or String(body.get("session", "")) != Protocol.session(cfg, actor):
		return Protocol.failure("MVP6_NATIVE_PEER_BINDING_INVALID")
	var result: Dictionary
	match kind:
		"MVP6_CONSTRUCTION_INIT":
			result = _ensure_construction6()
		"MVP6_CONSTRUCTION_ROUTE":
			if authority != "authority/b":
				result = Protocol.failure("MVP6_ROUTE_NONOWNER_AUTHORITY_REQUIRED")
			else:
				var intent := String(body.get("intent", ""))
				result = Protocol.success({"intent": intent, "route_validated": intent in ["ADD", "REMOVE", "REPLAY_ADD", "REPLAY_REMOVE"], "canonical_construction_owned": false, "authority_process_id": OS.get_process_id(), "replica_checksum": String(_replica6.get("checksum", ""))})
		"MVP6_CONSTRUCTION_APPLY":
			if authority != "authority/a":
				result = Protocol.failure("MVP6_CANONICAL_WRITER_A_REQUIRED")
			else:
				var intent := String(body.get("intent", ""))
				var attested := _route_attestation6(body.get("route_attestation", {}), intent)
				if not bool(attested.get("success", false)):
					result = attested
				elif intent == "ADD":
					result = _apply_add6()
				elif intent == "REMOVE":
					result = _apply_remove6()
				elif intent == "REPLAY_ADD":
					result = _replay6("ADD")
				elif intent == "REPLAY_REMOVE":
					result = _replay6("REMOVE")
				else:
					result = Protocol.failure("MVP6_CONSTRUCTION_INTENT_INVALID")
				if bool(result.get("success", false)):
					var details: Dictionary = result.get("details", {})
					details["authority_b_process_id"] = attested.get("details", {}).get("authority_b_process_id", 0)
					result["details"] = details
		"MVP6_REPLICA_SYNC":
			result = _sync_replica6(body)
		"MVP6_CONSTRUCTION_READ":
			if authority == "authority/a":
				result = Protocol.success(_public6())
			else:
				result = Protocol.success({"construction":_replica6.duplicate(true), "checksum":String(_replica6.get("checksum", "")), "part_count":Array(_replica6.get("parts", [])).size(), "canonical_construction_owned":false, "replica_read_only":true, "authority_process_id":OS.get_process_id()})
		_:
			result = Protocol.failure("MVP6_UNKNOWN_NATIVE_COMMAND")
	return native_envelope(kind, actor, result)


func report(passed: bool, phase: String) -> Dictionary:
	var value: Dictionary = super.report(passed, phase)
	var graph = _graph6()
	var graph_snapshot: Dictionary = graph.create_snapshot() if graph != null else {}
	value["mvp6"] = {
		"authority_id": authority,
		"canonical_construction_owned": authority == "authority/a" and not _construction6.is_empty(),
		"replica_read_only": authority == "authority/b",
		"construction_phase": _phase6,
		"construction": _snapshot6() if authority == "authority/a" else _replica6.duplicate(true),
		"canonical_item_graph_revision": graph_snapshot.get("revision", -1),
		"canonical_item_graph_checksum": graph_snapshot.get("checksum", ""),
		"actor_a_ore": _ore6(graph_snapshot, "a"),
		"route_receipts": _route_receipts6.duplicate(true),
		"replays": _replays6.duplicate(true),
		"predicate_verified": false,
	}
	return value
