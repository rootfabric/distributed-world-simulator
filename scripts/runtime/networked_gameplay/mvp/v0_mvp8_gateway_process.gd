extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_guarded_gateway_process.gd"

const Protocol8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const BackendLink8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_backend_link.gd")
const RemoteRoute8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_remote_player_command_route.gd")
const Identity8 = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const Ledger8 = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const Admission8 = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const Closure8 = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const Coordinator8 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Carry8 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_player_carrying_domain.gd")
const Pivot8 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_gateway_route_pivot.gd")
const Support8 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")
const Utils8 = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SyncRequest8 = preload("res://scripts/simulation/matter/network/matter_replication_sync_request.gd")

const TOTAL_ROUNDS8 := 12
const RECONNECT_AFTER_ROUND8 := 4
const RESTART_AFTER_ROUND8 := 8
const LEDGER_CAP8 := 512
const OP_FINGERPRINT_CAP8 := 256
const RPC_CAP8 := 512
const REPLAY_PENDING_CAP8 := 32
const TERMINAL_COMMAND_CAP8 := 16
const MATTER_STREAM_CAP8 := 64
const LIVENESS_INTERVAL_MS8 := 4000
const DIG_HIT_MIN_SEPARATION_M8 := 1.0
const DIG_EXECUTION_ATTEMPT_CAP8 := 2

var _round8 := 0
var _round_moves8 := {"a": false, "b": false}
var _action_counts8 := {"DIG": 0, "ITEM": 0, "BUILD_ADD": 0, "BUILD_REMOVE": 0}
var _fixed_receipts8 := 0
var _active8 := false
var _recovery_boot8 := false
var _waiting_reconnect8 := false
var _reconnect_complete8 := false
var _original_peer8 := ""
var _reconnect_peer8 := ""
var _reconnect_count8 := 0
var _checkpointed8 := false
var _checkpoint_receipt8: Dictionary = {}
var _restart_file8 := ""
var _bounds8: Dictionary = {}
var _last_dig8: Dictionary = {}
var _dig_hits8: Array = []
var _round_history8: Array = []
var _backend_liveness_cycles8 := 0
var _backend_liveness_failures8 := 0
var _backend_liveness_last_ms8 := 0
var _backend_liveness_last8: Dictionary = {}
var _backend_liveness_seen_sequence8 := {"authority/a": -1, "authority/b": -1}
var _backend_liveness_active_skips8 := 0
var _backend_liveness_syncs8 := 0
var _seam_crossings8 := 0
var _handoff_stage8 := "IDLE"
var _matter_resynced8 := {"a": false, "b": false}
var _handoff_tick_barriers8 := 0
var _handoff_tick_barrier_last8: Dictionary = {}
var _current_cache8 := {"a": {}, "b": {}}
var _current_cache_hits8 := 0
var _current_cache_misses8 := 0
var _terminal_snapshot8: Dictionary = {}


func _phase8() -> String:
	if _round8 < RECONNECT_AFTER_ROUND8:
		return "PRE_RECONNECT"
	if _round8 < RESTART_AFTER_ROUND8:
		return "POST_RECONNECT"
	if _round8 < TOTAL_ROUNDS8:
		return "POST_RESTART"
	return "COMPLETE"


func _action_for_round8(round_index: int) -> String:
	var actions := [
		"DIG", "ITEM", "BUILD_ADD", "BUILD_REMOVE",
		"DIG", "ITEM", "DIG", "ITEM",
		"DIG", "ITEM", "BUILD_ADD", "BUILD_REMOVE",
	]
	return String(actions[round_index]) if round_index >= 0 and round_index < actions.size() else ""


func setup_control() -> bool:
	identity = Identity8.new()
	ledger = Ledger8.new()
	admission = Admission8.new()
	closure = Closure8.new()
	if not success(ledger.configure(LEDGER_CAP8), "MVP8 bounded P6 ledger"):
		return false
	for actor in ["a", "b"]:
		if not success(identity.bind("client-session/mvp3/" + actor, "player/mvp3/" + actor, "entity/mvp3/" + actor), "P6 identity " + actor):
			return false
	if not success(admission.configure(identity, ledger), "P6 admission") or not success(closure.configure(identity, ledger), "P6 closure"):
		return false
	var epochs: Dictionary = Dictionary(cfg.get("mvp8_authority_epochs", {"a": 1, "b": 1})).duplicate(true)
	var initial_sequences: Dictionary = Dictionary(cfg.get("mvp8_initial_sequences", {"a": 0, "b": 0})).duplicate(true)
	sequences["a"] = int(initial_sequences.get("a", 0))
	sequences["b"] = int(initial_sequences.get("b", 0))
	for actor in ["a", "b"]:
		var coordinator = Coordinator8.new()
		var initial := {
			"logical_player_id": "player/mvp3/" + actor,
			"player_entity_id": "entity/mvp3/" + actor,
			"last_input_sequence": int(initial_sequences.get(actor, 0)),
			"last_operation_id": "",
		}
		if not success(coordinator.configure("authority/a", int(epochs.get(actor, 1)), initial), "MVP8 SM1 coordinator " + actor):
			return false
		coordinators[actor] = coordinator
		var carry = Carry8.new()
		if not success(carry.configure(identity, ledger, closure, coordinator), "SM1 carrying " + actor):
			return false
		carrying[actor] = carry
		var by_authority: Dictionary = {}
		for authority_id in ["authority/a", "authority/b"]:
			var route = RemoteRoute8.new()
			if not success(route.configure(self, authority_id, actor, Protocol8.session(cfg, actor), identity, ledger, admission, closure), "MVP8 remote owner route"):
				return false
			routes.append(route)
			by_authority[authority_id] = route
		var pivot = Pivot8.new()
		if not success(pivot.configure(by_authority, coordinator, "gateway/mvp8/" + String(cfg["run_id"]), "client-session/mvp3/" + actor), "MVP8 stable gateway pivot"):
			return false
		pivots[actor] = pivot
	_round8 = int(cfg.get("mvp8_start_round", 0))
	_recovery_boot8 = bool(cfg.get("mvp8_recovery", false))
	_action_counts8 = Dictionary(cfg.get("mvp8_initial_action_counts", _action_counts8)).duplicate(true)
	_fixed_receipts8 = int(cfg.get("mvp8_initial_fixed_receipts", 0))
	_round_history8 = Array(cfg.get("mvp8_initial_round_history", [])).duplicate(true)
	_dig_hits8 = Array(cfg.get("mvp8_initial_dig_hits", [])).duplicate(true)
	_seam_crossings8 = int(cfg.get("mvp8_initial_seam_crossings", 0))
	_active8 = _recovery_boot8
	_reconnect_complete8 = _recovery_boot8 or _round8 >= RECONNECT_AFTER_ROUND8
	_restart_file8 = String(cfg.get("mvp8_restart_file", ""))
	return true


func initialize_native() -> bool:
	var okay: bool = setup_control()
	for authority_id in ["authority/a", "authority/b"]:
		if not okay:
			break
		var link = BackendLink8.new()
		links[authority_id] = link
		okay = success(link.start(cfg, authority_id, int(cfg["ports"][authority_id]), String(cfg["internal_keys"][authority_id])), "authenticated backend " + authority_id)
	if okay and _recovery_boot8:
		if not success(call_authority("authority/a", {"kind": "MVP8_RECOVERY_SETUP"}), "MVP8 recovery setup authority/a"):
			okay = false
		elif not success(call_authority("authority/b", {"kind": "INIT"}), "native owner init authority/b"):
			okay = false
		elif not success(call_authority("authority/a", {"kind": "MVP8_RECOVERY_GAMEPLAY"}), "MVP8 recovery gameplay authority/a"):
			okay = false
		elif not success(call_authority("authority/a", {"kind": "MVP8_RECOVERY_CONSTRUCTION"}), "MVP8 recovery Construction authority/a"):
			okay = false
	elif okay:
		for authority_id in ["authority/a", "authority/b"]:
			if not success(call_authority(authority_id, {"kind": "INIT"}), "native owner init " + authority_id):
				okay = false
				break
	if okay and _recovery_boot8:
		var owner_rpc := _authority6("authority/a", "a", {"kind": "MVP6_CONSTRUCTION_READ"})
		var synced := _sync_b6("a", owner_rpc)
		if not bool(synced.get("success", false)):
			failures.append("MVP8_RECOVERED_CONSTRUCTION_SYNC_FAILED:" + String(synced.get("error_code", "")))
			okay = false
		else:
			_phase6 = "REMOVED"
			var current := _current8("a")
			if not bool(current.get("success", false)):
				failures.append("MVP8_RECOVERED_CURRENT_STATE_FAILED:" + String(current.get("error_code", "")))
				okay = false
	return okay


func _authority_tick8(authority_id: String, actor: String) -> Dictionary:
	var rpc := call_authority(authority_id, {
		"kind": "LOOKUP",
		"actor": actor,
		"operation_id": "",
	})
	if not bool(rpc.get("success", false)):
		return rpc
	var snapshot_value = rpc.get("details", {}).get("snapshot", {})
	if not snapshot_value is Dictionary:
		return Protocol8.failure("MVP8_HANDOFF_TICK_SNAPSHOT_REQUIRED")
	var tick := int(Dictionary(snapshot_value).get("server_tick", -1))
	if tick < 0:
		return Protocol8.failure("MVP8_HANDOFF_SERVER_TICK_REQUIRED")
	return Protocol8.success({"server_tick": tick})


func _await_post_handoff_tick8(authority_id: String, actor: String) -> Dictionary:
	var baseline := _authority_tick8(authority_id, actor)
	if not bool(baseline.get("success", false)):
		return baseline
	var baseline_tick := int(baseline.get("details", {}).get("server_tick", -1))
	var observed_tick := baseline_tick
	var samples := 1
	# A freshly activated target may still remember that this actor consumed the
	# current fixed tick during an earlier tenure. Wait for an objectively newer
	# canonical server tick before allowing the next client intent. Read-only
	# LOOKUPs never re-execute input or mutate player state.
	for _attempt in range(6):
		OS.delay_msec(4)
		var observed := _authority_tick8(authority_id, actor)
		if not bool(observed.get("success", false)):
			return observed
		samples += 1
		observed_tick = int(observed.get("details", {}).get("server_tick", -1))
		if observed_tick > baseline_tick:
			_handoff_tick_barriers8 += 1
			_handoff_tick_barrier_last8 = {
				"actor": actor,
				"authority_id": authority_id,
				"baseline_tick": baseline_tick,
				"observed_tick": observed_tick,
				"samples": samples,
				"mutation_performed": false,
			}
			return Protocol8.success(_handoff_tick_barrier_last8.duplicate(true))
	return Protocol8.failure("MVP8_HANDOFF_NEXT_TICK_NOT_OBSERVED")


func maybe_cross_a() -> bool:
	var decision: Dictionary = coordinators["a"].snapshot()
	var source := String(decision.get("active_authority_id", ""))
	var player := lookup(source, "a")
	if player.is_empty():
		return false
	var target := ""
	if source == "authority/a" and float(player.get("position", {}).get("x", -999.0)) >= 0.0:
		target = "authority/b"
	elif source == "authority/b" and float(player.get("position", {}).get("x", 999.0)) < 0.0:
		target = "authority/a"
	if target.is_empty():
		return true
	var transfer_id := "transfer/mvp8/a/%03d" % (_seam_crossings8 + 1)
	_handoff_stage8 = "BEGIN:%s->%s:%s" % [source, target, transfer_id]
	_publish_progress8()
	if not cross("a", target, transfer_id, false, false):
		_handoff_stage8 = "FAILED:" + transfer_id
		_publish_progress8()
		return false
	_seam_crossings8 += 1
	var tick_barrier := _await_post_handoff_tick8(target, "a")
	if not bool(tick_barrier.get("success", false)):
		_handoff_stage8 = "TICK_BARRIER_FAILED:" + transfer_id
		_publish_progress8()
		return false
	_invalidate_current8("a")
	_handoff_stage8 = "COMPLETE:" + transfer_id
	_publish_progress8()
	return true


func route_client_input(actor: String, wire: Dictionary) -> Dictionary:
	var routed := super.route_client_input(actor, wire)
	if bool(routed.get("success", false)):
		_invalidate_current8(actor)
		if _active8 and _round8 < TOTAL_ROUNDS8:
			_round_moves8[actor] = true
			_fixed_receipts8 += 1
	return routed


func _matter_observer8() -> String:
	# Matter remains canonically owned on authority/a while player A is free to
	# cross the SM1 seam. Use whichever authenticated logical player is currently
	# local to the Matter owner for read/dig authorization; never pretend A still
	# belongs to authority/a after its ownership transfer.
	# B is the stable authority/a observer and did not perform the inherited
	# MVP4 bootstrap dig, so prefer its real player/tool state for repeated
	# workload Matter actions. Fall back to A only when B is not local.
	for actor in ["b", "a"]:
		if String(coordinators[actor].snapshot().get("active_authority_id", "")) == "authority/a":
			return actor
	return ""


func _invalidate_current8(actor: String = "") -> void:
	if actor in ["a", "b"]:
		_current_cache8[actor] = {}
	else:
		_current_cache8 = {"a": {}, "b": {}}


func _remember_terminal_snapshot8(snapshot: Dictionary) -> void:
	var players = snapshot.get("players", {})
	if not players is Dictionary:
		return
	var a = Dictionary(players).get("a", {})
	var b = Dictionary(players).get("b", {})
	if not a is Dictionary or not b is Dictionary or Dictionary(a).is_empty() or Dictionary(b).is_empty():
		return
	if String(Dictionary(a).get("logical_player_id", "")) != "a" or String(Dictionary(b).get("logical_player_id", "")) != "b":
		return
	_terminal_snapshot8 = snapshot.duplicate(true)


func _overlay_snapshot8(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty() or not snapshot.get("players", {}) is Dictionary:
		return world_snapshot()
	var value := snapshot.duplicate(true)
	var decisions := {}
	for actor in ["a", "b"]:
		decisions[actor] = coordinators[actor].snapshot()
	value["decisions"] = decisions
	value["transfer_count"] = transfers.size()
	value["a_roundtrip_complete"] = transfers.filter(func(row): return row.get("actor") == "a").size() >= 2 and String(pending_continuity["a"]).is_empty()
	value["both_clients_ready"] = bool(client_hello["a"]) and bool(client_hello["b"])
	value["input_sequences"] = sequences.duplicate()
	value["gateway_sessions"] = {
		"a": pivots["a"].get_client_route_identity(),
		"b": pivots["b"].get_client_route_identity(),
	}
	var mvp8 := Dictionary(value.get("mvp8", {})).duplicate(true)
	mvp8["active"] = _active8
	mvp8["round"] = _round8
	mvp8["phase"] = _phase8()
	mvp8["round_moves"] = _round_moves8.duplicate(true)
	mvp8["action_counts"] = _action_counts8.duplicate(true)
	mvp8["fixed_receipts"] = _fixed_receipts8
	mvp8["seam_crossings"] = _seam_crossings8
	mvp8["reconnect_due"] = _round8 == RECONNECT_AFTER_ROUND8 and not _reconnect_complete8
	mvp8["reconnect_complete"] = _reconnect_complete8
	mvp8["checkpoint_due"] = _round8 == RESTART_AFTER_ROUND8 and not _recovery_boot8 and not _checkpointed8
	mvp8["checkpointed"] = _checkpointed8
	mvp8["recovery_boot"] = _recovery_boot8
	mvp8["matter_resynced"] = _matter_resynced8.duplicate(true)
	mvp8["current_cache"] = {"hits": _current_cache_hits8, "misses": _current_cache_misses8}
	mvp8["complete"] = _round8 >= TOTAL_ROUNDS8
	mvp8["bounds"] = _bounds8.duplicate(true)
	mvp8["last_dig"] = _last_dig8.duplicate(true)
	mvp8["dig_hits"] = _dig_hits8.duplicate(true)
	value["mvp8"] = mvp8
	return value


func _status_current8(actor: String) -> Dictionary:
	var cached_value = _current_cache8.get(actor, {})
	var details: Dictionary = {}
	if cached_value is Dictionary and not Dictionary(cached_value).is_empty():
		_current_cache_hits8 += 1
		details = Dictionary(cached_value).duplicate(true)
	else:
		var sampled := _current8(actor)
		if not bool(sampled.get("success", false)):
			return sampled
		_current_cache_misses8 += 1
		details = Dictionary(sampled.get("details", {})).duplicate(true)
		_current_cache8[actor] = details.duplicate(true)
	# Gateway-only coordination can change while canonical owners remain stable.
	# Reuse the already owner-validated snapshot on cache hits and update only
	# local orchestration fields. A real MOVE/action invalidates the cache, so
	# the first STATUS after canonical mutation still performs fresh owner reads.
	var base_snapshot = details.get("snapshot", {})
	details["snapshot"] = _overlay_snapshot8(Dictionary(base_snapshot) if base_snapshot is Dictionary else {})
	_remember_terminal_snapshot8(Dictionary(details["snapshot"]))
	return Protocol8.success(details)


func _current8(actor: String) -> Dictionary:
	var observer := _matter_observer8()
	if observer.is_empty():
		return Protocol8.failure("MVP8_MATTER_OWNER_OBSERVER_REQUIRED")
	var matter_result := _owner4(observer, {"kind": "MVP4_REPORT"})
	if not bool(matter_result.get("success", false)):
		return matter_result
	var material_result := _owner4(observer, {"kind": "MVP5_MATERIAL"})
	if not bool(material_result.get("success", false)):
		return material_result
	var decision: Dictionary = coordinators[actor].snapshot()
	var player: Dictionary = lookup(String(decision.get("active_authority_id", "")), actor)
	if player.is_empty() or _construction6.is_empty():
		return Protocol8.failure("MVP8_CURRENT_STATE_INCOMPLETE")
	var matter: Dictionary = matter_result.get("details", {})
	var material: Dictionary = material_result.get("details", {})
	var digest := Utils8.payload_hash({
		"store_hash": matter.get("store_hash", ""),
		"state_hash": matter.get("state_hash", ""),
		"stream_sequence": matter.get("stream_sequence", 0),
		"material_digest": material.get("material_digest", ""),
		"item_graph_checksum": material.get("item_graph_checksum", ""),
		"construction_checksum": _construction6.get("checksum", ""),
	})
	return Protocol8.success({
		"world_digest": digest,
		"matter": matter.duplicate(true),
		"material": material.duplicate(true),
		"construction": _construction6.duplicate(true),
		"replica": _replica6.duplicate(true),
		"player": player.duplicate(true),
		"snapshot": world_snapshot(),
	})


func _dig_hit_far_enough8(hit: Array) -> bool:
	if hit.size() != 3:
		return false
	for raw in _dig_hits8:
		if not raw is Array or Array(raw).size() != 3:
			continue
		var prior: Array = raw
		var dx := float(hit[0]) - float(prior[0])
		var dy := float(hit[1]) - float(prior[1])
		var dz := float(hit[2]) - float(prior[2])
		if sqrt(dx * dx + dy * dy + dz * dz) < DIG_HIT_MIN_SEPARATION_M8:
			return false
	return true


func _dig8(round_index: int) -> Dictionary:
	# PREPARE stays a read-only canonical MVP4 query. Repeated digs must not
	# accidentally select the surface of an already excavated hole, otherwise
	# EXECUTE can validly return a no-effect REJECTED result. Keep accepted hit
	# positions as orchestration evidence only and require spatial separation.
	var candidates: Array[String] = []
	# Match the canonical current-state observer preference: B is intentionally
	# kept near the Matter bubble and should be tried first. A is only a fallback
	# when it is local to authority/a and B cannot produce a valid canonical hit.
	for actor in ["b", "a"]:
		if String(coordinators[actor].snapshot().get("active_authority_id", "")) == "authority/a":
			candidates.append(actor)
	if candidates.is_empty():
		return Protocol8.failure("MVP8_DIG_OWNER_OBSERVER_REQUIRED")
	# Prioritize a compact set of directions that are known to intersect the
	# bounded bootstrap surface. A player far on +X/-X first probes back toward
	# the Matter bubble centre; this avoids dozens of authenticated PREPARE RPCs.
	var directions: Array = [
		[0.0, -1.0, 0.0],
		[0.714142842854285, -0.7, 0.0], [-0.714142842854285, -0.7, 0.0],
		[0.4358898943540673, -0.9, 0.0], [-0.4358898943540673, -0.9, 0.0],
		[0.0, -0.9, 0.4358898943540673], [0.0, -0.9, -0.4358898943540673],
		[0.6, -0.8, 0.0], [-0.6, -0.8, 0.0],
		[0.0, -0.8, 0.6], [0.0, -0.8, -0.6],
		[0.30822070014844877, -0.9, 0.30822070014844877],
		[0.30822070014844877, -0.9, -0.30822070014844877],
		[-0.30822070014844877, -0.9, 0.30822070014844877],
		[-0.30822070014844877, -0.9, -0.30822070014844877],
	]
	_last_dig8 = {
		"round": round_index,
		"candidates": candidates.duplicate(),
		"existing_hits": _dig_hits8.duplicate(true),
		"attempts": [],
		"execute_attempts": 0,
	}
	var last_failure: Dictionary = {}
	var attempt_index := 0
	var execute_attempts := 0
	for candidate in candidates:
		var player_owner := String(coordinators[candidate].snapshot().get("active_authority_id", ""))
		var player: Dictionary = lookup(player_owner, candidate)
		var candidate_directions: Array = directions.duplicate(true)
		var px := float(player.get("position", {}).get("x", 0.0))
		if absf(px) > 1.0:
			candidate_directions.push_front([-0.714142842854285 if px > 0.0 else 0.714142842854285, -0.7, 0.0])
		for direction in candidate_directions:
			var operation := "operation/mvp4/%s/mvp8-dig/%d/attempt-%02d" % [candidate, round_index, attempt_index]
			attempt_index += 1
			var prepared := _owner4(candidate, {"kind": "MVP4_PREPARE", "operation_id": operation, "direction": direction})
			var prepare_error := String(prepared.get("error_code", ""))
			var hit: Array = Array(Dictionary(prepared.get("details", {})).get("hit_position_m", [])).duplicate()
			var separated := bool(prepared.get("success", false)) and _dig_hit_far_enough8(hit)
			_last_dig8["attempts"].append({
				"actor": candidate,
				"operation_id": operation,
				"player_owner": player_owner,
				"player_position": Dictionary(player.get("position", {})).duplicate(true),
				"direction": Array(direction).duplicate(),
				"prepare_success": bool(prepared.get("success", false)),
				"error_code": prepare_error,
				"hit_position_m": hit.duplicate(),
				"separated_from_prior_hits": separated,
			})
			if not bool(prepared.get("success", false)):
				last_failure = prepared
				if prepare_error == "SM1_AUTHORITY_TRANSFER_WRITE_FENCED":
					break
				continue
			if not separated:
				continue
			if execute_attempts >= DIG_EXECUTION_ATTEMPT_CAP8:
				return Protocol8.failure("MVP8_DIG_EXECUTION_ATTEMPT_CAP")
			execute_attempts += 1
			_last_dig8["execute_attempts"] = execute_attempts
			var executed := _owner4(candidate, {"kind": "MVP4_EXECUTE", "plan": Dictionary(prepared.get("details", {})).duplicate(true)})
			if bool(executed.get("success", false)):
				var current := _current8("a")
				if not bool(current.get("success", false)):
					return current
				_dig_hits8.append(hit.duplicate())
				_last_dig8["selected_actor"] = candidate
				_last_dig8["selected_operation_id"] = operation
				_last_dig8["selected_hit_position_m"] = hit.duplicate()
				_last_dig8["executed"] = true
				_action_counts8["DIG"] = int(_action_counts8["DIG"]) + 1
				return Protocol8.success({"current": Dictionary(current.get("details", {})).duplicate(true)})
			_last_dig8["attempts"][-1]["execute_error"] = String(executed.get("error_code", ""))
			last_failure = executed
			if String(executed.get("error_code", "")) != "MVP4_MATTER_NOT_COMMITTED":
				return executed
	return last_failure if not last_failure.is_empty() else Protocol8.failure("MVP8_CANONICAL_DIG_COMMIT_FAILED")

func _item8(round_index: int) -> Dictionary:
	var owner_id := String(coordinators["a"].snapshot().get("active_authority_id", ""))
	if owner_id not in ["authority/a", "authority/b"]:
		return Protocol8.failure("MVP8_ITEM_ACTIVE_OWNER_REQUIRED")
	var rpc := _authority6(owner_id, "a", {
		"kind": "MVP8_ITEM",
		"operation_id": "operation/mvp8/item/select/%d" % round_index,
		"command_kind": "inventory.select_hotbar",
		"payload": {"selected_hotbar_index": round_index % 4},
	})
	var native := _native6(rpc)
	if bool(native.get("success", false)):
		_action_counts8["ITEM"] = int(_action_counts8["ITEM"]) + 1
	return native


func _build8(intent: String, round_index: int) -> Dictionary:
	var cycle := 1 if round_index < RESTART_AFTER_ROUND8 else 2
	var route_rpc := _authority6("authority/b", "a", {"kind": "MVP6_CONSTRUCTION_ROUTE", "intent": intent})
	var routed := _native6(route_rpc)
	if not bool(routed.get("success", false)):
		return routed
	var attestation: Dictionary = links["authority/b"].last_signed_reply.duplicate(true)
	var owner_rpc := _authority6("authority/a", "a", {
		"kind": "MVP8_BUILD_APPLY",
		"intent": intent,
		"cycle": cycle,
		"route_attestation": attestation,
	})
	var owner := _native6(owner_rpc)
	if not bool(owner.get("success", false)):
		return owner
	var synced := _sync_b6("a", owner_rpc)
	if not bool(synced.get("success", false)):
		return synced
	if intent == "ADD":
		_phase6 = "ADDED"
		_action_counts8["BUILD_ADD"] = int(_action_counts8["BUILD_ADD"]) + 1
	else:
		_phase6 = "REMOVED"
		_action_counts8["BUILD_REMOVE"] = int(_action_counts8["BUILD_REMOVE"]) + 1
	return Protocol8.success({"construction": _construction6.duplicate(true), "replica": _replica6.duplicate(true)})


func _refresh_bounds8() -> Dictionary:
	var native := _native6(_authority6("authority/a", "a", {"kind": "MVP8_BOUNDS"}))
	if not bool(native.get("success", false)):
		return native
	var authority_bounds: Dictionary = native.get("details", {})
	var ledger_report: Dictionary = ledger.get_report()
	var backend_sequences := {}
	for authority_id in links:
		backend_sequences[authority_id] = int(links[authority_id].sequence)
	_bounds8 = {
		"operation_fingerprints": operation_fingerprints.size(),
		"ledger": ledger_report,
		"backend_sequences": backend_sequences,
		"client_sequences": client_sequences.duplicate(true),
		"input_observations": {"a": input_observations["a"].size(), "b": input_observations["b"].size()},
		"authority": authority_bounds.duplicate(true),
		"current_cache": {"hits": _current_cache_hits8, "misses": _current_cache_misses8},
	}
	var okay: bool = (
		operation_fingerprints.size() <= OP_FINGERPRINT_CAP8
		and int(ledger_report.get("tracked_count", 0)) <= LEDGER_CAP8
		and int(backend_sequences.get("authority/a", 0)) <= RPC_CAP8
		and int(backend_sequences.get("authority/b", 0)) <= RPC_CAP8
		and int(client_sequences.get("a", 0)) <= RPC_CAP8
		and int(client_sequences.get("b", 0)) <= RPC_CAP8
		and input_observations["a"].size() <= 128
		and input_observations["b"].size() <= 128
		and int(authority_bounds.get("durable_replay_pending", 0)) <= REPLAY_PENDING_CAP8
		and int(authority_bounds.get("construction_terminal_commands", 0)) <= TERMINAL_COMMAND_CAP8
		and int(authority_bounds.get("matter_stream_sequence", 0)) <= MATTER_STREAM_CAP8
		and authority_bounds.get("duplicate_item_identity") == false
	)
	return Protocol8.success({"bounded": okay, "bounds": _bounds8.duplicate(true)}) if okay else Protocol8.failure("MVP8_BOUNDED_STATE_EXCEEDED")


func _commit_round8(round_index: int) -> Dictionary:
	if round_index != _round8 or round_index < 0 or round_index >= TOTAL_ROUNDS8:
		return Protocol8.failure("MVP8_ROUND_SEQUENCE_INVALID")
	if not bool(_round_moves8["a"]) or not bool(_round_moves8["b"]):
		return Protocol8.failure("MVP8_BOTH_CLIENT_MOVES_REQUIRED")
	if round_index >= RECONNECT_AFTER_ROUND8 and not _reconnect_complete8:
		return Protocol8.failure("MVP8_RECONNECT_REQUIRED_BEFORE_ROUND")
	if round_index >= RESTART_AFTER_ROUND8 and not _recovery_boot8:
		return Protocol8.failure("MVP8_SERVER_RESTART_REQUIRED_BEFORE_ROUND")
	var action := _action_for_round8(round_index)
	var outcome: Dictionary
	if action == "DIG":
		outcome = _dig8(round_index)
	elif action == "ITEM":
		outcome = _item8(round_index)
	elif action == "BUILD_ADD":
		outcome = _build8("ADD", round_index)
	elif action == "BUILD_REMOVE":
		outcome = _build8("REMOVE", round_index)
	else:
		return Protocol8.failure("MVP8_ROUND_ACTION_INVALID")
	if not bool(outcome.get("success", false)):
		return outcome
	var outcome_current = outcome.get("details", {}).get("current", {})
	_invalidate_current8()
	var current: Dictionary
	if outcome_current is Dictionary and not Dictionary(outcome_current).is_empty():
		current = Protocol8.success(Dictionary(outcome_current).duplicate(true))
	else:
		current = _current8("a")
	if not bool(current.get("success", false)):
		return current
	_round_history8.append({
		"round": round_index,
		"phase": _phase8(),
		"action": action,
		"world_digest": current.get("details", {}).get("world_digest", ""),
		"transfer_count": transfers.size(),
		"input_sequences": sequences.duplicate(true),
	})
	_round8 += 1
	_round_moves8 = {"a": false, "b": false}
	var bounded := _refresh_bounds8()
	if not bool(bounded.get("success", false)):
		return bounded
	var current_details: Dictionary = Dictionary(current.get("details", {})).duplicate(true)
	# The canonical world sample above is still valid after advancing only the
	# MVP8 orchestration cursor, but its embedded snapshot carries the pre-commit
	# round number. Publish one post-commit orchestration snapshot so clients never
	# replay the round they just completed.
	var base_snapshot = current_details.get("snapshot", {})
	var post_snapshot := _overlay_snapshot8(Dictionary(base_snapshot) if base_snapshot is Dictionary else {})
	_remember_terminal_snapshot8(post_snapshot)
	current_details["snapshot"] = post_snapshot.duplicate(true)
	_current_cache8["a"] = current_details.duplicate(true)
	return Protocol8.success({
		"round_completed": round_index,
		"action": action,
		"current": current_details,
		"snapshot": post_snapshot.duplicate(true),
	})


func _normalize_checkpoint_owner8() -> Dictionary:
	var decision: Dictionary = coordinators["a"].snapshot()
	if decision.get("state") != "ACTIVE":
		return Protocol8.failure("MVP8_CHECKPOINT_PLAYER_A_DECISION_NOT_ACTIVE")
	var owner := String(decision.get("active_authority_id", ""))
	if owner == "authority/a":
		return Protocol8.success({"replay": true, "authority_epoch": int(decision.get("authority_epoch", 0))})
	if owner != "authority/b":
		return Protocol8.failure("MVP8_CHECKPOINT_PLAYER_A_OWNER_INVALID")
	var transfer_id := "transfer/mvp8/a/checkpoint-return-%03d" % (_seam_crossings8 + 1)
	_handoff_stage8 = "CHECKPOINT_RETURN:%s" % transfer_id
	_publish_progress8()
	# Both clients have already acknowledged their neutral fixed-tick input for
	# round 7. The transfer replays that neutral command and performs no new
	# post-activation movement, leaving the native owners quiescent for the cut.
	if not cross("a", "authority/a", transfer_id, false, false):
		_handoff_stage8 = "CHECKPOINT_RETURN_FAILED:%s" % transfer_id
		_publish_progress8()
		return Protocol8.failure("MVP8_CHECKPOINT_PLAYER_A_RETURN_FAILED")
	_seam_crossings8 += 1
	_invalidate_current8()
	decision = coordinators["a"].snapshot()
	if decision.get("state") != "ACTIVE" or String(decision.get("active_authority_id", "")) != "authority/a":
		return Protocol8.failure("MVP8_CHECKPOINT_PLAYER_A_RETURN_NOT_CURRENT")
	_handoff_stage8 = "CHECKPOINT_RETURN_COMPLETE:%s" % transfer_id
	_publish_progress8()
	return Protocol8.success({"replay": false, "authority_epoch": int(decision.get("authority_epoch", 0))})


func _checkpoint8() -> Dictionary:
	if _round8 != RESTART_AFTER_ROUND8 or not _reconnect_complete8 or _checkpointed8:
		return Protocol8.failure("MVP8_CHECKPOINT_PHASE_INVALID")
	var normalized := _normalize_checkpoint_owner8()
	if not bool(normalized.get("success", false)):
		return normalized
	var rpc := _authority6("authority/a", "a", {"kind": "MVP8_CHECKPOINT"})
	var native := _native6(rpc)
	if not bool(native.get("success", false)):
		return native
	var checkpoint: Dictionary = native.get("details", {}).get("checkpoint", {})
	if checkpoint.is_empty():
		return Protocol8.failure("MVP8_CHECKPOINT_RECEIPT_REQUIRED")
	var next_decision_epochs := {}
	var next_player_epochs := {}
	for actor in ["a", "b"]:
		var player_value = checkpoint.get("players", {}).get(actor, {})
		if not player_value is Dictionary:
			return Protocol8.failure("MVP8_CHECKPOINT_PLAYER_REQUIRED:" + actor)
		var player: Dictionary = player_value
		var position_value = player.get("position", {})
		if int(player.get("ownership_epoch", 0)) < 1 or not position_value is Dictionary or not Dictionary(position_value).has_all(["x", "y", "z"]):
			return Protocol8.failure("MVP8_CHECKPOINT_PLAYER_DURABLE_STATE_REQUIRED:" + actor)
		next_player_epochs[actor] = int(player.get("ownership_epoch", 0)) + 1
		next_decision_epochs[actor] = int(coordinators[actor].snapshot().get("authority_epoch", 0)) + 1
	_checkpoint_receipt8 = {
		"schema": "distributed_world_simulator.mvp8_restart_receipt.v1",
		"subject_head": cfg.get("subject_head", ""),
		"subject_tree": cfg.get("subject_tree", ""),
		"generation": int(checkpoint.get("generation", 0)),
		"checkpoint": checkpoint.duplicate(true),
		"next_round": _round8,
		"initial_sequences": sequences.duplicate(true),
		"authority_epochs": next_decision_epochs,
		"player_ownership_epochs": next_player_epochs,
		"checkpoint_player_a_normalized": true,
		"action_counts": _action_counts8.duplicate(true),
		"fixed_receipts": _fixed_receipts8,
		"round_history": _round_history8.duplicate(true),
		"dig_hits": _dig_hits8.duplicate(true),
		"seam_crossings": _seam_crossings8,
		"bounds": _bounds8.duplicate(true),
	}
	if _restart_file8.is_empty() or not Support8.write_json(_restart_file8, _checkpoint_receipt8):
		return Protocol8.failure("MVP8_RESTART_RECEIPT_WRITE_FAILED")
	_checkpointed8 = true
	var checkpoint_snapshot := world_snapshot()
	_remember_terminal_snapshot8(checkpoint_snapshot)
	return Protocol8.success({"checkpointed": true, "restart": _checkpoint_receipt8.duplicate(true), "snapshot": checkpoint_snapshot.duplicate(true)})


func _publish_progress8() -> void:
	var path := String(cfg.get("mvp8_progress_file", ""))
	if path.is_empty():
		return
	Support8.write_json(path, {
		"schema": "distributed_world_simulator.mvp8_gateway_progress.v1",
		"process_id": OS.get_process_id(),
		"round": _round8,
		"phase": _phase8(),
		"active": _active8,
		"round_moves": _round_moves8.duplicate(true),
		"action_counts": _action_counts8.duplicate(true),
		"fixed_receipts": _fixed_receipts8,
		"seam_crossings": _seam_crossings8,
		"handoff_stage": _handoff_stage8,
		"handoff_tick_barriers": _handoff_tick_barriers8,
		"handoff_tick_barrier_last": _handoff_tick_barrier_last8.duplicate(true),
		"last_dig": _last_dig8.duplicate(true),
		"dig_hits": _dig_hits8.duplicate(true),
		"reconnect_complete": _reconnect_complete8,
		"checkpointed": _checkpointed8,
		"matter_resynced": _matter_resynced8.duplicate(true),
		"current_cache": {"hits": _current_cache_hits8, "misses": _current_cache_misses8},
		"bounds": _bounds8.duplicate(true),
		"backend_liveness": {
			"cycles": _backend_liveness_cycles8,
			"active_skips": _backend_liveness_active_skips8,
			"syncs": _backend_liveness_syncs8,
			"failures": _backend_liveness_failures8,
		},
		"mvp6": {
			"phase": _phase6,
			"complete": _complete6(),
			"removed_observers": _phase_count6("REMOVED"),
			"replay_remove": _replays6["REMOVE"],
		},
	})


func world_snapshot() -> Dictionary:
	var value: Dictionary = super.world_snapshot()
	value["mvp8"] = {
		"active": _active8,
		"round": _round8,
		"phase": _phase8(),
		"round_moves": _round_moves8.duplicate(true),
		"action_counts": _action_counts8.duplicate(true),
		"fixed_receipts": _fixed_receipts8,
		"seam_crossings": _seam_crossings8,
		"reconnect_due": _round8 == RECONNECT_AFTER_ROUND8 and not _reconnect_complete8,
		"reconnect_complete": _reconnect_complete8,
		"checkpoint_due": _round8 == RESTART_AFTER_ROUND8 and not _recovery_boot8 and not _checkpointed8,
		"checkpointed": _checkpointed8,
		"recovery_boot": _recovery_boot8,
		"matter_resynced": _matter_resynced8.duplicate(true),
		"current_cache": {"hits": _current_cache_hits8, "misses": _current_cache_misses8},
		"complete": _round8 >= TOTAL_ROUNDS8,
		"bounds": _bounds8.duplicate(true),
		"last_dig": _last_dig8.duplicate(true),
		"dig_hits": _dig_hits8.duplicate(true),
	}
	return value


func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP8_"):
		return super.handle_client(actor, body)
	if not bool(client_hello.get(actor, false)):
		return Protocol8.failure("MVP8_HELLO_REQUIRED")
	_active8 = true
	if kind == "MVP8_MATTER_CONNECT":
		if not _recovery_boot8:
			return Protocol8.failure("MVP8_MATTER_RESYNC_ONLY_AFTER_RESTART")
		if bool(_matter_resynced8.get(actor, false)):
			return Protocol8.success({"replay": true, "actor": actor, "snapshot": world_snapshot()})
		var report_rpc := _owner4(actor, {"kind": "MVP4_REPORT"})
		if not bool(report_rpc.get("success", false)):
			return report_rpc
		var matter: Dictionary = Dictionary(report_rpc.get("details", {})).duplicate(true)
		var sync := SyncRequest8.create(
			"client/mvp4/" + actor,
			Protocol8.session(cfg, actor),
			1,
			int(matter.get("stream_sequence", 0)),
			String(matter.get("state_hash", ""))
		)
		var connected := _owner4(actor, {"kind": "MVP4_CONNECT", "sync_request": sync})
		if not bool(connected.get("success", false)):
			return connected
		if int(connected.get("details", {}).get("queued_frames", 0)) != 0:
			return Protocol8.failure("MVP8_MATTER_CURRENT_RESYNC_QUEUED_UNEXPECTED_FRAMES")
		_matter_resynced8[actor] = true
		return Protocol8.success({
			"actor": actor,
			"matter": matter,
			"mode": connected.get("details", {}).get("mode", ""),
			"snapshot": world_snapshot(),
		})
	if kind == "MVP8_STATUS":
		var current := _status_current8(actor)
		if not bool(current.get("success", false)):
			return current
		var details: Dictionary = Dictionary(current.get("details", {})).duplicate(true)
		return Protocol8.success({"current": details, "snapshot": Dictionary(details.get("snapshot", {})).duplicate(true)})
	if kind == "MVP8_ROUND":
		if actor != "a":
			return Protocol8.failure("MVP8_ROUND_DRIVER_A_REQUIRED")
		return _commit_round8(int(body.get("round", -1)))
	if kind == "MVP8_RECONNECT_PREPARE":
		if actor != "a" or _round8 != RECONNECT_AFTER_ROUND8 or _waiting_reconnect8 or _reconnect_complete8:
			return Protocol8.failure("MVP8_RECONNECT_PREPARE_INVALID")
		_waiting_reconnect8 = true
		_invalidate_current8("a")
		_original_peer8 = String(client_peers.get("a", ""))
		client_hello["a"] = false
		client_finished["a"] = true
		return Protocol8.success({"prepared": true, "original_peer": _original_peer8, "snapshot": world_snapshot()})
	if kind == "MVP8_CHECKPOINT":
		if actor != "a":
			return Protocol8.failure("MVP8_CHECKPOINT_DRIVER_A_REQUIRED")
		return _checkpoint8()
	if kind == "MVP8_PHASE_FINISH":
		client_finished[actor] = true
		if bool(client_finished["a"]) and bool(client_finished["b"]):
			closing_at_ms = Time.get_ticks_msec() + 50
		# The inherited graphical client validates every successful reply before
		# exiting, including the terminal ACK. Reuse the last already-validated
		# two-player snapshot instead of returning an empty snapshot or issuing
		# fresh backend LOOKUPs after the quiescent checkpoint.
		if _terminal_snapshot8.is_empty():
			return Protocol8.failure("MVP8_TERMINAL_SNAPSHOT_REQUIRED")
		return Protocol8.success({
			"finished": true,
			"actor": actor,
			"round": _round8,
			"snapshot": _terminal_snapshot8.duplicate(true),
		})
	return Protocol8.failure("MVP8_UNKNOWN_CLIENT_COMMAND")


func _backend_liveness8() -> Dictionary:
	var now := Time.get_ticks_msec()
	if _backend_liveness_last_ms8 > 0 and now - _backend_liveness_last_ms8 < LIVENESS_INTERVAL_MS8:
		return Protocol8.success({"skipped": true})
	var observed := {}
	var idle_syncs := {}
	for authority_id in ["authority/a", "authority/b"]:
		var before := int(links[authority_id].sequence)
		var previous := int(_backend_liveness_seen_sequence8.get(authority_id, -1))
		# A real workload RPC already proves this authenticated backend link is
		# alive. Do not add a redundant SYNC on top of useful traffic. If the
		# sequence did not move during the interval, issue the same fail-closed
		# read-only SYNC used previously.
		if previous < 0 or before != previous:
			_backend_liveness_seen_sequence8[authority_id] = before
			_backend_liveness_active_skips8 += 1
			observed[authority_id] = before
			idle_syncs[authority_id] = false
			continue
		var rpc: Dictionary = call_authority(authority_id, {"kind": "SYNC"})
		if not bool(rpc.get("success", false)):
			_backend_liveness_failures8 += 1
			return Protocol8.failure("MVP8_BACKEND_LIVENESS_FAILED:" + authority_id)
		var after := int(links[authority_id].sequence)
		_backend_liveness_seen_sequence8[authority_id] = after
		_backend_liveness_syncs8 += 1
		observed[authority_id] = after
		idle_syncs[authority_id] = true
	_backend_liveness_cycles8 += 1
	_backend_liveness_last_ms8 = now
	_backend_liveness_last8 = {
		"observed_sequences": observed,
		"idle_syncs": idle_syncs,
		"active_skips": _backend_liveness_active_skips8,
		"syncs": _backend_liveness_syncs8,
		"mutation_performed": false,
		"backend_reconnect_performed": false,
	}
	return Protocol8.success(_backend_liveness_last8.duplicate(true))


func _phase_success8() -> bool:
	if _recovery_boot8:
		return (
			_round8 >= TOTAL_ROUNDS8
			and int(_action_counts8["DIG"]) >= 4
			and int(_action_counts8["ITEM"]) >= 4
			and int(_action_counts8["BUILD_ADD"]) >= 2
			and int(_action_counts8["BUILD_REMOVE"]) >= 2
			and _fixed_receipts8 >= 24
			and _seam_crossings8 >= 4
		)
	return _checkpointed8 and _round8 == RESTART_AFTER_ROUND8 and _reconnect_complete8 and _reconnect_count8 == 1


func _process(_delta: float) -> bool:
	if not interactive or client_boundary == null:
		return false
	var polled: Dictionary = client_boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		finish_interactive(false, "MVP8_CLIENT_GATEWAY_POLL_FAILED")
		return false
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = raw
		var peer := String(event.get("peer_id", ""))
		if event.get("event_type") == "PEER_CONNECTED":
			Support8.mark_ready(client_boundary, peer)
		elif event.get("event_type") == "PEER_DISCONNECTED":
			if peer == _original_peer8 and _waiting_reconnect8 and not _reconnect_complete8:
				if String(client_peers.get("a", "")) == peer:
					client_peers.erase("a")
				continue
			for actor_value in client_peers.keys():
				var actor := String(actor_value)
				if String(client_peers[actor]) == peer and not bool(client_finished[actor]):
					finish_interactive(false, "MVP8_CLIENT_DISCONNECTED_DURING_WORKLOAD")
					return false
		elif event.get("event_type") == "MESSAGE_RECEIVED":
			var packet := Protocol8.payload(event)
			var actor := identify_client(packet)
			if actor.is_empty():
				continue
			var kind := String(packet.get("body", {}).get("kind", ""))
			var packet_sequence := int(packet.get("sequence", 0))
			var replacement := actor == "a" and kind == "HELLO" and _waiting_reconnect8 and not _reconnect_complete8
			if replacement:
				var existing := String(client_peers.get("a", ""))
				if packet_sequence != 1 or peer == _original_peer8 or (not existing.is_empty() and existing != _original_peer8 and existing != peer):
					continue
				client_peers["a"] = peer
				client_sequences["a"] = 1
				_reconnect_peer8 = peer
				_reconnect_count8 = 1
				_reconnect_complete8 = true
				_waiting_reconnect8 = false
				client_finished["a"] = false
			else:
				if (client_peers.has(actor) and String(client_peers[actor]) != peer) or packet_sequence != int(client_sequences.get(actor, 0)) + 1:
					continue
				client_peers[actor] = peer
				client_sequences[actor] = packet_sequence
			var response := handle_client(actor, packet["body"])
			_publish_progress8()
			var signed := Protocol8.seal(cfg, "gateway", "client/" + actor, packet_sequence, response, String(cfg["client_keys"][actor]))
			if not bool(Protocol8.send(client_boundary, peer, signed).get("success", false)):
				finish_interactive(false, "MVP8_CLIENT_GATEWAY_REPLY_FAILED")
				return false
	client_boundary.flush_outbound(128)
	if closing_at_ms > 0 and Time.get_ticks_msec() >= closing_at_ms:
		finish_interactive(_phase_success8())
	elif Time.get_ticks_msec() - started_at_ms > int(cfg.get("timeout_ms", 360000)):
		finish_interactive(false, "MVP8_GATEWAY_TIMEOUT")
	elif failures.is_empty():
		var kept := _backend_liveness8()
		if not bool(kept.get("success", false)):
			finish_interactive(false, String(kept.get("error_code", "MVP8_BACKEND_LIVENESS_FAILED")))
	return false


func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	value["mvp8"] = {
		"round": _round8,
		"phase": _phase8(),
		"round_history": _round_history8.duplicate(true),
		"action_counts": _action_counts8.duplicate(true),
		"fixed_receipts": _fixed_receipts8,
		"seam_crossings": _seam_crossings8,
		"handoff_tick_barriers": _handoff_tick_barriers8,
		"handoff_tick_barrier_last": _handoff_tick_barrier_last8.duplicate(true),
		"reconnect_count": _reconnect_count8,
		"original_peer": _original_peer8,
		"reconnect_peer": _reconnect_peer8,
		"reconnect_complete": _reconnect_complete8,
		"checkpointed": _checkpointed8,
		"checkpoint_receipt": _checkpoint_receipt8.duplicate(true),
		"recovery_boot": _recovery_boot8,
		"matter_resynced": _matter_resynced8.duplicate(true),
		"current_cache": {"hits": _current_cache_hits8, "misses": _current_cache_misses8},
		"bounds": _bounds8.duplicate(true),
		"backend_liveness_cycles": _backend_liveness_cycles8,
		"backend_liveness_failures": _backend_liveness_failures8,
		"backend_liveness_active_skips": _backend_liveness_active_skips8,
		"backend_liveness_syncs": _backend_liveness_syncs8,
		"backend_liveness_last": _backend_liveness_last8.duplicate(true),
		"last_dig": _last_dig8.duplicate(true),
		"dig_hits": _dig_hits8.duplicate(true),
		"canonical_state_owned": false,
		"mvp8_predicate_verified": false,
	}
	return value


func finish_interactive(_criterion: bool, error_code: String = "") -> void:
	var bounded := _refresh_bounds8() if error_code.is_empty() else Protocol8.failure(error_code)
	var okay: bool = error_code.is_empty() and failures.is_empty() and _phase_success8() and bool(bounded.get("success", false))
	var report := base_report("distributed_world_simulator.mvp8_gateway_process.v1", okay, true)
	report["passed"] = okay
	report["error"] = error_code if not error_code.is_empty() else ("" if okay else "MVP8_PHASE_COMPLETION_FAILED")
	var saved := Support8.write_json(String(cfg.get("result_file", "")), report)
	if client_boundary != null:
		client_boundary.stop()
	stop_native()
	print("MVP8_GATEWAY round=%d phase=%s passed=%s" % [_round8, _phase8(), okay])
	quit(0 if okay and saved else 1)
