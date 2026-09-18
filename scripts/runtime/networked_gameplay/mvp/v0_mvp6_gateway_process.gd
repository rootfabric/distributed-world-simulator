extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_gateway_process.gd"

# Transport/orchestration only. The gateway owns neither Construction nor an
# Item Graph. Mutations enter the real authority/b process first, are attested,
# then commit on the single canonical writer authority/a. The A-signed result
# is immediately installed as a read-only B replica before clients may observe.
var _construction6: Dictionary = {}
var _replica6: Dictionary = {}
var _phase6 := "EMPTY"
var _observed6 := {"BASE": {}, "ADDED": {}, "REMOVED": {}}
var _replays6 := {"ADD": false, "REMOVE": false}
var _route_processes6: Array = []
var _mutation_count6 := 0

var _item_phase6 := "APPROACH"
var _item_ready6 := {"a": false, "b": false}
var _item_id6 := ""
var _item_quantity6 := 0
var _item_winner6 := ""
var _item_loser_error6 := ""
var _item_container_open6 := {"a": false, "b": false}
var _item_target_position6: Dictionary = {}
var _item_container_position6: Dictionary = {}
var _item_events6: Array = []
var _item_pickup_operation6 := ""
var _item_pickup_replay6 := false
var _item_before_carry6: Dictionary = {}
var _item_on_b6: Dictionary = {}
var _item_after_carry6: Dictionary = {}
var _item_carry_out_verified6 := false
var _item_carry_back_verified6 := false
const SHARED_CONTAINER6 := "container/shared/crate/1"


func _authority6(authority_id: String, actor: String, request: Dictionary) -> Dictionary:
	var body := request.duplicate(true)
	body["actor"] = actor
	body["session"] = Protocol.session(cfg, actor)
	return call_authority(authority_id, body)


func _native6(rpc: Dictionary) -> Dictionary:
	return native_result(rpc)


func _sync_b6(actor: String, owner_rpc: Dictionary) -> Dictionary:
	var owner_result := _native6(owner_rpc)
	if not bool(owner_result.get("success", false)):
		return owner_result
	var snapshot: Dictionary = owner_result.get("details", {}).get("construction", {})
	if snapshot.is_empty():
		return Protocol.failure("MVP6_CANONICAL_CONSTRUCTION_SNAPSHOT_REQUIRED")
	var owner_attestation: Dictionary = links["authority/a"].last_signed_reply.duplicate(true)
	var replica_rpc := _authority6("authority/b", actor, {
		"kind": "MVP6_REPLICA_SYNC",
		"checksum": String(snapshot.get("checksum", "")),
		"source_attestation": owner_attestation,
	})
	var replica := _native6(replica_rpc)
	if not bool(replica.get("success", false)):
		return replica
	var replica_details: Dictionary = replica.get("details", {})
	if String(replica_details.get("checksum", "")) != String(snapshot.get("checksum", "")) or replica_details.get("canonical_construction_owned") != false or replica_details.get("replica_read_only") != true:
		return Protocol.failure("MVP6_AUTHORITY_B_REPLICA_DIVERGED")
	_construction6 = snapshot.duplicate(true)
	_replica6 = Dictionary(replica_details.get("construction", {})).duplicate(true)
	return Protocol.success({
		"construction": _construction6.duplicate(true),
		"replica": _replica6.duplicate(true),
		"owner_process_id": owner_result.get("details", {}).get("authority_process_id", 0),
		"replica_process_id": replica_details.get("authority_process_id", 0),
	})


func _item_position6(item: Dictionary) -> Dictionary:
	var raw = item.get("transform", {}).get("position_m", [])
	if not raw is Array or raw.size() != 3:
		return {}
	return {"x": float(raw[0]), "y": float(raw[1]), "z": float(raw[2])}


func _find_item6(snapshot: Dictionary, item_id: String) -> Dictionary:
	for raw in snapshot.get("items", []):
		if raw is Dictionary and String(raw.get("item_id", "")) == item_id:
			return Dictionary(raw).duplicate(true)
	return {}


func _actor_item_closure6(snapshot: Dictionary, actor: String) -> Dictionary:
	var inventory: Dictionary = Dictionary(snapshot.get("inventories", {}).get(actor, {})).duplicate(true)
	var ids: Dictionary = {}
	for raw_id in Array(inventory.get("inventory", [])) + Array(inventory.get("hotbar", [])):
		var item_id := String(raw_id)
		if not item_id.is_empty():
			ids[item_id] = true
	var items: Array = []
	for raw in snapshot.get("items", []):
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		var item_id := String(row.get("item_id", ""))
		var location: Dictionary = Dictionary(row.get("location", {}))
		var equipment: Dictionary = Dictionary(row.get("equipment", {}))
		if ids.has(item_id) or String(location.get("player_id", "")) == actor or String(equipment.get("player_id", "")) == actor:
			ids[item_id] = true
			items.append(row.duplicate(true))
	items.sort_custom(func(left, right): return String(left.get("item_id", "")) < String(right.get("item_id", "")))
	return Utils.canonicalize({"actor": actor, "inventory": inventory, "items": items})


func _item_read6(authority_id: String, actor: String) -> Dictionary:
	var rpc := _authority6(authority_id, actor, {"kind": "MVP6_ITEM_READ"})
	return _native6(rpc)


func _active_authority6(actor: String) -> String:
	return String(coordinators.get(actor).snapshot().get("active_authority_id", "")) if coordinators.has(actor) else ""


func _item_command6(actor: String, suffix: String, item_kind: String, payload: Dictionary, operation_override: String = "") -> Dictionary:
	var authority_id := _active_authority6(actor)
	if authority_id not in ["authority/a", "authority/b"]:
		return Protocol.failure("MVP6_LIVE_ITEM_ACTIVE_AUTHORITY_INVALID")
	var operation_id := operation_override
	if operation_id.is_empty():
		operation_id = "operation/mvp6/live-item/%s/%s" % [String(cfg.get("run_id", "run")), suffix]
	var rpc := _authority6(authority_id, actor, {
		"kind": "MVP6_ITEM_COMMAND",
		"operation_id": operation_id,
		"item_kind": item_kind,
		"payload": payload.duplicate(true),
	})
	return _native6(rpc)


func _mvp5_item_id6() -> String:
	var material: Dictionary = Dictionary(_source4.get("material_projection", {}).get("details", {}))
	for raw in material.get("items", []):
		if raw is Dictionary and String(raw.get("definition_id", "")) == "item/ore" and int(raw.get("quantity", 0)) > 101:
			return String(raw.get("item_id", ""))
	return ""


func _initialize_item6() -> Dictionary:
	if not _item_id6.is_empty():
		return Protocol.success({"replay": true})
	if not _complete5():
		return Protocol.failure("MVP6_LIVE_MVP5_PREREQUISITE_REQUIRED")
	var read := _item_read6("authority/a", "a")
	if not bool(read.get("success", false)):
		return read
	var graph: Dictionary = read.get("details", {}).get("item_graph", {})
	var material_id := _mvp5_item_id6()
	var ore := _find_item6(graph, material_id)
	var container := _find_item6(graph, "item/shared/crate/1")
	if material_id.is_empty() or String(ore.get("definition_id", "")) != "item/ore" or int(ore.get("quantity", 0)) <= 101:
		return Protocol.failure("MVP6_LIVE_REAL_MVP5_ORE_REQUIRED")
	if String(ore.get("location", {}).get("player_id", "")) != "a":
		return Protocol.failure("MVP6_LIVE_MVP5_ORE_OWNER_INVALID")
	var tool_ok := false
	for raw in graph.get("items", []):
		if raw is Dictionary and String(raw.get("equipment", {}).get("player_id", "")) == "a" and String(raw.get("equipment", {}).get("slot_id", "")) == "tool/main":
			tool_ok = true
	if not tool_ok:
		return Protocol.failure("MVP6_LIVE_CANONICAL_TOOL_REQUIRED")
	_item_id6 = material_id
	_item_quantity6 = int(ore.get("quantity", 0))
	_item_container_position6 = _item_position6(container)
	if _item_container_position6.is_empty():
		return Protocol.failure("MVP6_LIVE_SHARED_CONTAINER_POSITION_REQUIRED")
	return Protocol.success({"item_id": _item_id6, "quantity": _item_quantity6})


func _player_stationary6(row: Dictionary) -> bool:
	var velocity: Dictionary = Dictionary(row.get("velocity", {}))
	return absf(float(velocity.get("x", 1.0))) <= 0.000001 and absf(float(velocity.get("z", 1.0))) <= 0.000001


func _ready_item6(actor: String) -> Dictionary:
	var initialized := _initialize_item6()
	if not bool(initialized.get("success", false)):
		return initialized
	if _item_phase6 != "APPROACH":
		return Protocol.failure("MVP6_LIVE_ITEM_READY_PHASE_INVALID")
	var players: Dictionary = world_snapshot().get("players", {})
	var row: Dictionary = players.get(actor, {})
	if row.is_empty() or not _player_stationary6(row):
		return Protocol.failure("MVP6_LIVE_ITEM_PLAYER_NOT_STATIONARY")
	if actor == "a":
		var x := float(row.get("position", {}).get("x", -99.0))
		if x < -1.6 or x >= -0.25:
			return Protocol.failure("MVP6_LIVE_ITEM_A_APPROACH_REQUIRED")
	_item_ready6[actor] = true
	if bool(_item_ready6["a"]) and bool(_item_ready6["b"]):
		_item_phase6 = "DROP_READY"
	return Protocol.success({"ready": _item_ready6.duplicate(true)})


func _drop_item6(actor: String) -> Dictionary:
	if actor != "a" or _item_phase6 != "DROP_READY":
		return Protocol.failure("MVP6_LIVE_ITEM_DROP_PHASE_INVALID")
	var result := _item_command6("a", "drop-mvp5-ore", "item.drop", {"item_id": _item_id6, "quantity": -1})
	if not bool(result.get("success", false)):
		return result
	var graph: Dictionary = result.get("details", {}).get("item_graph", {})
	var item := _find_item6(graph, _item_id6)
	if String(item.get("location", {}).get("kind", "")) != "WORLD" or int(item.get("quantity", 0)) != _item_quantity6:
		return Protocol.failure("MVP6_LIVE_ITEM_DROP_STATE_INVALID")
	_item_target_position6 = _item_position6(item)
	if _item_target_position6.is_empty():
		return Protocol.failure("MVP6_LIVE_ITEM_DROP_POSITION_MISSING")
	_item_phase6 = "DROPPED"
	_item_events6.append({"event": "DROP", "actor": "a", "item_id": _item_id6, "quantity": _item_quantity6})
	return Protocol.success({"item_id": _item_id6, "target_position": _item_target_position6.duplicate(true)})


func _pickup_item6(actor: String, replay: bool = false) -> Dictionary:
	if actor != "b" or (not replay and _item_phase6 != "DROPPED") or (replay and _item_phase6 != "PICKED"):
		return Protocol.failure("MVP6_LIVE_ITEM_PICKUP_PHASE_INVALID")
	if not replay:
		_item_pickup_operation6 = "operation/mvp6/live-item/%s/pickup-b" % String(cfg.get("run_id", "run"))
	var result := _item_command6("b", "pickup-b", "item.pickup", {"item_id": _item_id6}, _item_pickup_operation6)
	if not bool(result.get("success", false)):
		return result
	var graph: Dictionary = result.get("details", {}).get("item_graph", {})
	var item := _find_item6(graph, _item_id6)
	if String(item.get("location", {}).get("player_id", "")) != "b" or int(item.get("quantity", 0)) != _item_quantity6:
		return Protocol.failure("MVP6_LIVE_ITEM_PICKUP_STATE_INVALID")
	if replay:
		if result.get("replay") != true:
			return Protocol.failure("MVP6_LIVE_ITEM_PICKUP_REPLAY_REQUIRED")
		_item_pickup_replay6 = true
		_item_phase6 = "PICKUP_REPLAYED"
		_item_events6.append({"event": "PICKUP_REPLAY", "actor": "b", "replay": true})
	else:
		_item_winner6 = "b"
		_item_phase6 = "PICKED"
		_item_events6.append({"event": "PICKUP", "actor": "b", "winner": "b"})
	return Protocol.success({"winner": "b", "replay": replay})


func _loser_pickup6(actor: String) -> Dictionary:
	if actor != "a" or _item_phase6 != "PICKUP_REPLAYED":
		return Protocol.failure("MVP6_LIVE_ITEM_CONTENTION_PHASE_INVALID")
	var result := _item_command6("a", "pickup-a-loser", "item.pickup", {"item_id": _item_id6})
	if bool(result.get("success", false)) or String(result.get("error_code", "")) != "ITEM_ALREADY_CLAIMED":
		return Protocol.failure("MVP6_LIVE_ITEM_SINGLE_WINNER_REQUIRED")
	_item_loser_error6 = "ITEM_ALREADY_CLAIMED"
	_item_phase6 = "CONTENDED"
	_item_events6.append({"event": "PICKUP_LOSER", "actor": "a", "error_code": _item_loser_error6})
	return Protocol.success({"semantic_success": false, "expected_error_code": _item_loser_error6})


func _open_container6(actor: String) -> Dictionary:
	var expected := ("a" if _item_phase6 == "CONTENDED" else "b" if _item_phase6 == "A_OPEN" else "")
	if actor != expected:
		return Protocol.failure("MVP6_LIVE_CONTAINER_OPEN_PHASE_INVALID")
	var result := _item_command6(actor, "open-container-" + actor, "container.open", {"container_id": SHARED_CONTAINER6})
	if not bool(result.get("success", false)):
		return result
	_item_container_open6[actor] = true
	_item_phase6 = "A_OPEN" if actor == "a" else "BOTH_OPEN"
	_item_events6.append({"event": "CONTAINER_OPEN", "actor": actor, "container_id": SHARED_CONTAINER6})
	return Protocol.success({"opened": _item_container_open6.duplicate(true)})


func _deposit_item6(actor: String) -> Dictionary:
	if actor != "b" or _item_phase6 != "BOTH_OPEN":
		return Protocol.failure("MVP6_LIVE_CONTAINER_DEPOSIT_PHASE_INVALID")
	var result := _item_command6("b", "deposit-b", "item.transfer", {
		"item_id": _item_id6, "quantity": -1, "target_container_id": SHARED_CONTAINER6, "target_slot_index": 0,
	})
	if not bool(result.get("success", false)):
		return result
	var item := _find_item6(result.get("details", {}).get("item_graph", {}), _item_id6)
	if String(item.get("location", {}).get("kind", "")) != "CONTAINER":
		return Protocol.failure("MVP6_LIVE_CONTAINER_DEPOSIT_STATE_INVALID")
	_item_phase6 = "DEPOSITED"
	_item_events6.append({"event": "DEPOSIT", "actor": "b", "item_id": _item_id6})
	return Protocol.success({"deposited": true})


func _withdraw_item6(actor: String) -> Dictionary:
	if actor != "a" or _item_phase6 != "DEPOSITED":
		return Protocol.failure("MVP6_LIVE_CONTAINER_WITHDRAW_PHASE_INVALID")
	var result := _item_command6("a", "withdraw-a", "item.transfer", {
		"item_id": _item_id6, "quantity": -1, "target_container_id": "inventory/a", "target_slot_index": -1,
	})
	if not bool(result.get("success", false)):
		return result
	var graph: Dictionary = result.get("details", {}).get("item_graph", {})
	var item := _find_item6(graph, _item_id6)
	if String(item.get("location", {}).get("player_id", "")) != "a" or int(item.get("quantity", 0)) != _item_quantity6:
		return Protocol.failure("MVP6_LIVE_CONTAINER_WITHDRAW_STATE_INVALID")
	_item_before_carry6 = _actor_item_closure6(graph, "a")
	if _item_before_carry6.get("items", []).size() < 2:
		return Protocol.failure("MVP6_LIVE_NONEMPTY_TOOL_AND_ORE_REQUIRED")
	_item_phase6 = "WITHDRAWN"
	_item_events6.append({"event": "WITHDRAW", "actor": "a", "item_id": _item_id6})
	return Protocol.success({"withdrawn": true})


func _carry_item6(actor: String, target: String) -> Dictionary:
	if actor != "a":
		return Protocol.failure("MVP6_LIVE_ITEM_CARRY_ACTOR_INVALID")
	var outward := target == "authority/b"
	if (outward and _item_phase6 != "WITHDRAWN") or (not outward and _item_phase6 != "CARRIED_OUT"):
		return Protocol.failure("MVP6_LIVE_ITEM_CARRY_PHASE_INVALID")
	var player: Dictionary = world_snapshot().get("players", {}).get("a", {})
	var x := float(player.get("position", {}).get("x", 0.0))
	if outward and (x < 0.0 or _active_authority6("a") != "authority/a"):
		return Protocol.failure("MVP6_LIVE_ITEM_OUTBOUND_SEAM_POSITION_REQUIRED")
	if not outward and (x > 0.0 or _active_authority6("a") != "authority/b"):
		return Protocol.failure("MVP6_LIVE_ITEM_RETURN_SEAM_POSITION_REQUIRED")
	var transfer_id := "transfer/mvp6/live-item/a-out" if outward else "transfer/mvp6/live-item/a-back"
	if not cross("a", target, transfer_id, false, false):
		return Protocol.failure("MVP6_LIVE_ITEM_HANDOFF_FAILED")
	_item_phase6 = "CARRY_OUT_PENDING" if outward else "CARRY_BACK_PENDING"
	_item_events6.append({"event": "CARRY_OUT" if outward else "CARRY_BACK", "actor": "a", "transfer_id": transfer_id})
	return Protocol.success({"transfer_id": transfer_id, "target": target})


func _advance_item_handoff6() -> Dictionary:
	if _item_phase6 not in ["CARRY_OUT_PENDING", "CARRY_BACK_PENDING"] or not String(pending_continuity.get("a", "")).is_empty():
		return Protocol.success({"advanced": false})
	var outward := _item_phase6 == "CARRY_OUT_PENDING"
	var authority_id := "authority/b" if outward else "authority/a"
	if _active_authority6("a") != authority_id:
		return Protocol.failure("MVP6_LIVE_ITEM_HANDOFF_AUTHORITY_MISMATCH")
	var read := _item_read6(authority_id, "a")
	if not bool(read.get("success", false)):
		return read
	var closure := _actor_item_closure6(read.get("details", {}).get("item_graph", {}), "a")
	if Utils.canonical_json(closure) != Utils.canonical_json(_item_before_carry6):
		return Protocol.failure("MVP6_LIVE_ITEM_CLOSURE_DIVERGED")
	if outward:
		_item_on_b6 = closure.duplicate(true)
		_item_carry_out_verified6 = true
		_item_phase6 = "CARRIED_OUT"
	else:
		_item_after_carry6 = closure.duplicate(true)
		_item_carry_back_verified6 = true
		_item_phase6 = "RETURNED"
	return Protocol.success({"advanced": true, "phase": _item_phase6})


func _finish_item6(actor: String) -> Dictionary:
	if actor != "a" or _item_phase6 != "RETURNED":
		return Protocol.failure("MVP6_LIVE_ITEM_FINISH_PHASE_INVALID")
	var player: Dictionary = world_snapshot().get("players", {}).get("a", {})
	if player.is_empty() or not _player_stationary6(player) or _active_authority6("a") != "authority/a":
		return Protocol.failure("MVP6_LIVE_ITEM_RETURN_NEUTRAL_REQUIRED")
	var read := _item_read6("authority/a", "a")
	if not bool(read.get("success", false)):
		return read
	var closure := _actor_item_closure6(read.get("details", {}).get("item_graph", {}), "a")
	if Utils.canonical_json(closure) != Utils.canonical_json(_item_before_carry6):
		return Protocol.failure("MVP6_LIVE_ITEM_FINAL_CLOSURE_DIVERGED")
	_item_after_carry6 = closure.duplicate(true)
	_item_phase6 = "COMPLETE"
	_item_events6.append({"event": "ITEM_COMPLETE", "actor": "a", "neutral": true})
	return Protocol.success({"complete": true})


func _item_complete6() -> bool:
	return (
		_item_phase6 == "COMPLETE"
		and _item_winner6 == "b"
		and _item_loser_error6 == "ITEM_ALREADY_CLAIMED"
		and _item_pickup_replay6
		and bool(_item_container_open6["a"])
		and bool(_item_container_open6["b"])
		and _item_carry_out_verified6
		and _item_carry_back_verified6
		and not _item_before_carry6.is_empty()
		and Utils.canonical_json(_item_before_carry6) == Utils.canonical_json(_item_on_b6)
		and Utils.canonical_json(_item_before_carry6) == Utils.canonical_json(_item_after_carry6)
	)


func _initialize6(actor: String) -> Dictionary:
	if not _construction6.is_empty():
		return Protocol.success({"construction":_construction6.duplicate(true), "replica":_replica6.duplicate(true), "replay":true})
	if actor != "a" or not _complete5() or not _item_complete6():
		return Protocol.failure("MVP6_LIVE_ITEM_COMPOSITION_REQUIRED")
	var rpc := _authority6("authority/a", actor, {"kind":"MVP6_CONSTRUCTION_INIT"})
	var synced := _sync_b6(actor, rpc)
	if not bool(synced.get("success", false)):
		return synced
	if Array(_construction6.get("parts", [])).size() != 100:
		return Protocol.failure("MVP6_LIVE_BASE100_REQUIRED")
	_phase6 = "BASE"
	return Protocol.success(synced.get("details", {}))


func _route6(actor: String, intent: String) -> Dictionary:
	if actor != "a" or intent not in ["ADD", "REMOVE", "REPLAY_ADD", "REPLAY_REMOVE"]:
		return Protocol.failure("MVP6_LIVE_MUTATION_ACTOR_OR_INTENT_INVALID")
	var route_rpc := _authority6("authority/b", actor, {"kind":"MVP6_CONSTRUCTION_ROUTE", "intent":intent})
	var routed := _native6(route_rpc)
	if not bool(routed.get("success", false)):
		return routed
	var route_details: Dictionary = routed.get("details", {})
	if route_details.get("route_validated") != true or route_details.get("canonical_construction_owned") != false:
		return Protocol.failure("MVP6_LIVE_NONOWNER_ROUTE_INVALID")
	var route_attestation: Dictionary = links["authority/b"].last_signed_reply.duplicate(true)
	var owner_rpc := _authority6("authority/a", actor, {
		"kind":"MVP6_CONSTRUCTION_APPLY",
		"intent":intent,
		"route_attestation":route_attestation,
	})
	var owner := _native6(owner_rpc)
	if not bool(owner.get("success", false)):
		return owner
	var synced := _sync_b6(actor, owner_rpc)
	if not bool(synced.get("success", false)):
		return synced
	var details: Dictionary = owner.get("details", {})
	var owner_pid := int(details.get("authority_process_id", 0))
	var b_pid := int(details.get("authority_b_process_id", 0))
	if owner_pid <= 0 or b_pid <= 0 or owner_pid == b_pid:
		return Protocol.failure("MVP6_LIVE_DISTINCT_AUTHORITY_PROCESSES_REQUIRED")
	_route_processes6.append({"intent":intent, "authority_b_process_id":b_pid, "authority_a_process_id":owner_pid})
	if intent == "ADD":
		_phase6 = "ADDED"
		_mutation_count6 += 1
	elif intent == "REMOVE":
		_phase6 = "REMOVED"
		_mutation_count6 += 1
	elif intent == "REPLAY_ADD":
		_replays6["ADD"] = bool(details.get("replay", false)) or bool(details.get("gateway_result", {}).get("replay", false))
	elif intent == "REPLAY_REMOVE":
		_replays6["REMOVE"] = bool(details.get("replay", false)) or bool(details.get("gateway_result", {}).get("replay", false))
	return Protocol.success({
		"construction": _construction6.duplicate(true),
		"replica": _replica6.duplicate(true),
		"intent": intent,
		"owner_result": details.duplicate(true),
	})


func _phase_count6(phase: String) -> int:
	return Dictionary(_observed6.get(phase, {})).size()


func _expected_parts6(phase: String) -> int:
	if phase == "ADDED": return 101
	if phase in ["BASE", "REMOVED"]: return 100
	return -1


func _observe6(actor: String, body: Dictionary) -> Dictionary:
	var phase := String(body.get("phase", ""))
	if phase not in _observed6 or phase != _phase6:
		return Protocol.failure("MVP6_CLIENT_OBSERVATION_PHASE_INVALID")
	var expected := _expected_parts6(phase)
	var checksum := String(_construction6.get("checksum", ""))
	if String(body.get("checksum", "")) != checksum or int(body.get("part_count", -1)) != expected:
		return Protocol.failure("MVP6_CLIENT_OBSERVATION_DIVERGED")
	if int(body.get("collision_part_count", -1)) != expected or body.get("canonical_truth_owner") != false or int(body.get("construct_count", -1)) != 1:
		return Protocol.failure("MVP6_CLIENT_DERIVED_RUNTIME_VIEW_INVALID")
	_observed6[phase][actor] = {
		"checksum": checksum,
		"part_count": expected,
		"collision_part_count": int(body.get("collision_part_count", -1)),
		"descriptor_checksum": String(body.get("descriptor_checksum", "")),
		"process_id": int(body.get("process_id", 0)),
	}
	return Protocol.success({"accepted":true, "phase":phase, "actor":actor})


func _complete6() -> bool:
	if _mutation_count6 != 2 or not bool(_replays6["ADD"]) or not bool(_replays6["REMOVE"]):
		return false
	if _phase6 != "REMOVED" or Array(_construction6.get("parts", [])).size() != 100:
		return false
	for phase in ["BASE", "ADDED", "REMOVED"]:
		if _phase_count6(phase) != 2:
			return false
		var rows: Dictionary = _observed6[phase]
		if int(rows["a"].get("process_id", 0)) <= 0 or int(rows["b"].get("process_id", 0)) <= 0 or rows["a"].get("process_id") == rows["b"].get("process_id"):
			return false
	return not _route_processes6.is_empty()


func world_snapshot() -> Dictionary:
	var value: Dictionary = super.world_snapshot()
	value["mvp6"] = {
		"item": {
			"phase": _item_phase6,
			"complete": _item_complete6(),
			"ready": _item_ready6.duplicate(true),
			"item_id": _item_id6,
			"quantity": _item_quantity6,
			"winner": _item_winner6,
			"loser_error": _item_loser_error6,
			"pickup_replay": _item_pickup_replay6,
			"container_open": _item_container_open6.duplicate(true),
			"target_position": _item_target_position6.duplicate(true),
			"container_position": _item_container_position6.duplicate(true),
			"carry_out_verified": _item_carry_out_verified6,
			"carry_back_verified": _item_carry_back_verified6,
		},
		"initialized": not _construction6.is_empty(),
		"phase": _phase6,
		"checksum": String(_construction6.get("checksum", "")),
		"part_count": Array(_construction6.get("parts", [])).size(),
		"base_observers": _phase_count6("BASE"),
		"added_observers": _phase_count6("ADDED"),
		"removed_observers": _phase_count6("REMOVED"),
		"replay_add": _replays6["ADD"],
		"replay_remove": _replays6["REMOVE"],
		"complete": _complete6(),
	}
	return value


func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP6_"):
		var inherited: Dictionary = super.handle_client(actor, body)
		if bool(inherited.get("success", false)) and kind == "MOVE":
			var advanced := _advance_item_handoff6()
			if not bool(advanced.get("success", false)):
				return advanced
			if bool(advanced.get("details", {}).get("advanced", false)):
				var details: Dictionary = inherited.get("details", {}).duplicate(true)
				details["snapshot"] = world_snapshot()
				inherited = Protocol.success(details)
		return inherited
	if not bool(client_hello.get(actor, false)):
		return Protocol.failure("MVP6_HELLO_REQUIRED")
	var result: Dictionary
	match kind:
		"MVP6_ITEM_READY":
			result = _ready_item6(actor)
		"MVP6_ITEM_DROP":
			result = _drop_item6(actor)
		"MVP6_ITEM_PICKUP":
			result = _pickup_item6(actor, false)
		"MVP6_ITEM_PICKUP_REPLAY":
			result = _pickup_item6(actor, true)
		"MVP6_ITEM_PICKUP_LOSER":
			result = _loser_pickup6(actor)
		"MVP6_ITEM_OPEN":
			result = _open_container6(actor)
		"MVP6_ITEM_DEPOSIT":
			result = _deposit_item6(actor)
		"MVP6_ITEM_WITHDRAW":
			result = _withdraw_item6(actor)
		"MVP6_ITEM_CARRY_OUT":
			result = _carry_item6(actor, "authority/b")
		"MVP6_ITEM_CARRY_BACK":
			result = _carry_item6(actor, "authority/a")
		"MVP6_ITEM_FINISH":
			result = _finish_item6(actor)
		"MVP6_INIT":
			result = _initialize6(actor)
		"MVP6_OBSERVE":
			result = Protocol.success({"construction":_construction6.duplicate(true), "replica":_replica6.duplicate(true)})
		"MVP6_ADD":
			if _phase_count6("BASE") != 2:
				result = Protocol.failure("MVP6_BOTH_BASE_OBSERVERS_REQUIRED")
			else:
				result = _route6(actor, "ADD")
		"MVP6_REPLAY_ADD":
			if _phase_count6("ADDED") != 2:
				result = Protocol.failure("MVP6_BOTH_ADDED_OBSERVERS_REQUIRED")
			else:
				result = _route6(actor, "REPLAY_ADD")
		"MVP6_REMOVE":
			if not bool(_replays6["ADD"]):
				result = Protocol.failure("MVP6_ADD_REPLAY_REQUIRED")
			else:
				result = _route6(actor, "REMOVE")
		"MVP6_REPLAY_REMOVE":
			if _phase_count6("REMOVED") != 2:
				result = Protocol.failure("MVP6_BOTH_REMOVED_OBSERVERS_REQUIRED")
			else:
				result = _route6(actor, "REPLAY_REMOVE")
		"MVP6_OBSERVED":
			result = _observe6(actor, body)
		_:
			result = Protocol.failure("MVP6_UNKNOWN_CLIENT_COMMAND")
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = result.get("details", {}).duplicate(true)
	if not _construction6.is_empty():
		details["construction"] = _construction6.duplicate(true)
		details["replica"] = _replica6.duplicate(true)
	details["snapshot"] = world_snapshot()
	return Protocol.success(details)


func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	value["mvp6"] = {
		"live_item": {
			"phase": _item_phase6,
			"complete": _item_complete6(),
			"ready": _item_ready6.duplicate(true),
			"item_id": _item_id6,
			"quantity": _item_quantity6,
			"winner": _item_winner6,
			"loser_error": _item_loser_error6,
			"pickup_replay": _item_pickup_replay6,
			"container_open": _item_container_open6.duplicate(true),
			"events": _item_events6.duplicate(true),
			"before_carry": _item_before_carry6.duplicate(true),
			"on_authority_b": _item_on_b6.duplicate(true),
			"after_carry": _item_after_carry6.duplicate(true),
			"carry_out_verified": _item_carry_out_verified6,
			"carry_back_verified": _item_carry_back_verified6,
			"canonical_state_owned": false,
		},
		"phase": _phase6,
		"construction": _construction6.duplicate(true),
		"authority_b_replica": _replica6.duplicate(true),
		"observed": _observed6.duplicate(true),
		"replays": _replays6.duplicate(true),
		"route_processes": _route_processes6.duplicate(true),
		"mutation_count": _mutation_count6,
		"complete": _complete6(),
		"canonical_state_owned": false,
		"predicate_verified": false,
	}
	return value


func finish_interactive(_seam_criterion: bool, error_code: String = "") -> void:
	var a_transfers: Array = transfers.filter(func(row): return row.get("actor") == "a")
	var expected_ids := [
		"transfer/mvp3/graphical/a-out",
		"transfer/mvp3/graphical/a-back",
		"transfer/mvp6/live-item/a-out",
		"transfer/mvp6/live-item/a-back",
	]
	var actual_ids: Array = a_transfers.map(func(row): return String(row.get("transfer_id", "")))
	var inherited_and_item_seam := (
		actual_ids == expected_ids
		and String(pending_continuity.get("a", "")).is_empty()
		and int(sequences.get("b", 0)) >= 2
		and a_transfers.all(func(row): return bool(row.get("post_activation_movement_proven", false)))
	)
	if error_code.is_empty() and not _item_complete6():
		error_code = "MVP6_LIVE_ITEM_COMPOSITION_FAILED"
	if error_code.is_empty() and not _complete6():
		error_code = "MVP6_LIVE_CONSTRUCTION_CONVERGENCE_FAILED"
	super.finish_interactive(inherited_and_item_seam and _item_complete6() and _complete6(), error_code)
