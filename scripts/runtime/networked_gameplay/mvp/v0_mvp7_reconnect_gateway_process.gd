extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_guarded_gateway_process.gd"

const Protocol7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")

var _mvp7_waiting_reconnect := false
var _mvp7_reconnects := 0
var _mvp7_original_peer := ""
var _mvp7_reconnect_peer := ""
var _mvp7_hello_digest := ""
var _mvp7_after_digest := ""
var _mvp7_position_before: Dictionary = {}
var _mvp7_position_after: Dictionary = {}
var _mvp7_continue_ok := false
var _mvp7_proved := false
var _mvp7_finish_ack_disconnect := false
var _mvp7_last_current: Dictionary = {}
const MVP7_BACKEND_LIVENESS_INTERVAL_MS := 4000
var _mvp7_backend_liveness_last_ms := 0
var _mvp7_backend_liveness_cycles := 0
var _mvp7_backend_liveness_failures := 0
var _mvp7_backend_liveness_last: Dictionary = {}


func _current7(actor: String) -> Dictionary:
	# Read current Matter directly from the authenticated owner without mutating
	# inherited _source4: that cache is the historical MVP4/MVP5 observer cut.
	var report_result: Dictionary = _owner4(actor, {"kind": "MVP4_REPORT"})
	if not bool(report_result.get("success", false)):
		return report_result
	var matter_source: Dictionary = Dictionary(report_result.get("details", {})).duplicate(true)
	var material_result: Dictionary = _owner4(actor, {"kind": "MVP5_MATERIAL"})
	if not bool(material_result.get("success", false)):
		return material_result
	var decision: Dictionary = coordinators[actor].snapshot()
	var player: Dictionary = lookup(String(decision.get("active_authority_id", "")), actor)
	if player.is_empty() or _construction6.is_empty():
		return Protocol7.failure("MVP7_CURRENT_WORLD_INCOMPLETE")
	var material: Dictionary = material_result.get("details", {})
	var snapshot: Dictionary = world_snapshot()
	var digest := Utils.payload_hash({
		"mvp4_store_hash": matter_source.get("store_hash", ""),
		"mvp4_state_hash": matter_source.get("state_hash", ""),
		"mvp4_stream_sequence": matter_source.get("stream_sequence", 0),
		"material_digest": material.get("material_digest", ""),
		"item_graph_checksum": material.get("item_graph_checksum", ""),
		"construction_checksum": _construction6.get("checksum", ""),
		"construction_replica_checksum": _replica6.get("checksum", ""),
	})
	var current := {
		"snapshot": snapshot,
		"matter_source": matter_source,
		"material": material.duplicate(true),
		"construction": _construction6.duplicate(true),
		"construction_replica": _replica6.duplicate(true),
		"player": player.duplicate(true),
	}
	return Protocol7.success({"current": current, "world_digest": digest})


func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if kind == "FINISH" and not _mvp7_proved:
		var finished: Dictionary = super.handle_client(actor, body)
		if bool(finished.get("success", false)) and bool(client_finished["a"]) and bool(client_finished["b"]) and _complete6():
			closing_at_ms = 0
			_mvp7_waiting_reconnect = true
			_mvp7_original_peer = String(client_peers.get("a", ""))
			client_hello["a"] = false
		return finished
	if kind == "MVP7_RECONNECT_HELLO":
		if actor != "a" or not _mvp7_waiting_reconnect or _mvp7_reconnects != 1 or String(client_peers.get("a", "")) != _mvp7_reconnect_peer:
			return Protocol7.failure("MVP7_RECONNECT_ADMISSION_INVALID")
		client_hello["a"] = true
		client_finished["a"] = false
		var current := _current7(actor)
		if not bool(current.get("success", false)):
			return current
		_mvp7_hello_digest = String(current.get("details", {}).get("world_digest", ""))
		_mvp7_last_current = Dictionary(current.get("details", {}).get("current", {})).duplicate(true)
		return Protocol7.success({
			"kind": kind,
			"actor": actor,
			"current": _mvp7_last_current.duplicate(true),
			"world_digest": _mvp7_hello_digest,
			"reconnect_count": _mvp7_reconnects,
		})
	if kind == "MVP7_RECONNECT_CONTINUE":
		if actor != "a" or not _mvp7_waiting_reconnect or _mvp7_reconnects != 1 or not body.get("wire") is Dictionary:
			return Protocol7.failure("MVP7_RECONNECT_CONTINUE_INVALID")
		var before := _current7(actor)
		if not bool(before.get("success", false)):
			return before
		var routed: Dictionary = route_client_input(actor, Dictionary(body["wire"]))
		if not bool(routed.get("success", false)):
			return routed
		var after := _current7(actor)
		if not bool(after.get("success", false)):
			return after
		var before_current: Dictionary = before["details"]["current"]
		var after_current: Dictionary = after["details"]["current"]
		_mvp7_position_before = Dictionary(before_current.get("player", {}).get("position", {})).duplicate(true)
		_mvp7_position_after = Dictionary(after_current.get("player", {}).get("position", {})).duplicate(true)
		_mvp7_after_digest = String(after["details"]["world_digest"])
		_mvp7_continue_ok = (
			_mvp7_position_before != _mvp7_position_after
			and String(before["details"]["world_digest"]) == _mvp7_hello_digest
			and _mvp7_after_digest == _mvp7_hello_digest
		)
		if not _mvp7_continue_ok:
			return Protocol7.failure("MVP7_RECONNECT_CONTINUITY_DIVERGED")
		_mvp7_last_current = after_current.duplicate(true)
		return Protocol7.success({
			"kind": kind,
			"actor": actor,
			"outcome": routed,
			"current": after_current,
			"world_digest_before": before["details"]["world_digest"],
			"world_digest_after": _mvp7_after_digest,
			"position_before": _mvp7_position_before,
			"position_after": _mvp7_position_after,
			"position_changed": true,
		})
	if kind == "MVP7_RECONNECT_FINISH":
		if actor != "a" or not _mvp7_continue_ok or _mvp7_reconnects != 1:
			return Protocol7.failure("MVP7_RECONNECT_PROOF_INCOMPLETE")
		_mvp7_proved = true
		_mvp7_waiting_reconnect = false
		client_finished["a"] = true
		# Do not close on a timer here. The client stops its ENet peer only after
		# it receives this FINISH ACK, so that disconnect is the delivery witness.
		closing_at_ms = 0
		return Protocol7.success({
			"kind": kind,
			"actor": actor,
			"current": _mvp7_last_current.duplicate(true),
			"world_digest": _mvp7_after_digest,
			"reconnect_proved": true,
		})
	return super.handle_client(actor, body)


func _mvp7_mvp6_read_only_witness7() -> Dictionary:
	# Preserve the inherited MVP6 evidence contract on the longer MVP7 story.
	# This performs the same real read-only canonical Construction check against
	# both authorities; it does not synthesize report fields without RPCs.
	if _backend_keepalive_cycles6 > 0:
		return Protocol7.success({"skipped": true, "reason": "MVP6_WITNESS_ALREADY_RECORDED"})
	if _construction6.is_empty():
		return Protocol7.failure("MVP7_MVP6_READ_ONLY_WITNESS_CONSTRUCTION_REQUIRED")
	var expected_checksum := String(_construction6.get("checksum", ""))
	if expected_checksum.is_empty():
		return Protocol7.failure("MVP7_MVP6_READ_ONLY_WITNESS_CHECKSUM_REQUIRED")
	var observed: Dictionary = {}
	for authority_id in ["authority/a", "authority/b"]:
		var rpc: Dictionary = _authority6(authority_id, "a", {"kind": "MVP6_CONSTRUCTION_READ"})
		var native: Dictionary = _native6(rpc)
		if not bool(native.get("success", false)):
			_backend_keepalive_failures6 += 1
			return Protocol7.failure("MVP7_MVP6_READ_ONLY_WITNESS_RPC_FAILED:" + authority_id + ":" + String(native.get("error_code", "")))
		var details: Dictionary = native.get("details", {})
		var construction: Dictionary = details.get("construction", {})
		var checksum := String(details.get("checksum", construction.get("checksum", "")))
		if checksum != expected_checksum:
			_backend_keepalive_failures6 += 1
			return Protocol7.failure("MVP7_MVP6_READ_ONLY_WITNESS_DIVERGED:" + authority_id)
		observed[authority_id] = checksum
	_backend_keepalive_cycles6 += 1
	_backend_keepalive_last_ms6 = Time.get_ticks_msec()
	_backend_keepalive_last6 = {
		"expected_checksum": expected_checksum,
		"observed": observed,
		"canonical_state_owned": false,
		"mutation_performed": false,
	}
	return Protocol7.success(_backend_keepalive_last6.duplicate(true))


func _mvp7_backend_liveness7() -> Dictionary:
	# MVP7 keeps the already-authenticated authority links alive for the entire
	# graphical story, including the long client-side evidence/capture interval
	# before reconnect. This is traffic, not a timeout-policy relaxation: real
	# PEER_DISCONNECTED / RPC failures remain terminal and no retry/reconnect is
	# introduced on the backend links.
	if links.size() != 2 or closing_at_ms > 0:
		return Protocol7.success({"skipped": true})
	var now := Time.get_ticks_msec()
	if _mvp7_backend_liveness_last_ms > 0 and now - _mvp7_backend_liveness_last_ms < MVP7_BACKEND_LIVENESS_INTERVAL_MS:
		return Protocol7.success({"skipped": true})
	var observed: Dictionary = {}
	for authority_id in ["authority/a", "authority/b"]:
		var rpc: Dictionary = call_authority(authority_id, {"kind": "SYNC"})
		if not bool(rpc.get("success", false)):
			_mvp7_backend_liveness_failures += 1
			return Protocol7.failure("MVP7_BACKEND_LIVENESS_RPC_FAILED:" + authority_id + ":" + String(rpc.get("error_code", "")))
		var native: Dictionary = rpc.get("details", {}).get("result", {})
		if not bool(native.get("success", false)):
			_mvp7_backend_liveness_failures += 1
			return Protocol7.failure("MVP7_BACKEND_LIVENESS_NATIVE_FAILED:" + authority_id + ":" + String(native.get("error_code", "")))
		observed[authority_id] = {
			"sequence": int(links[authority_id].sequence),
			"ready": Dictionary(native.get("details", {}).get("ready", {})).duplicate(true),
		}
	_mvp7_backend_liveness_cycles += 1
	_mvp7_backend_liveness_last_ms = now
	_mvp7_backend_liveness_last = {
		"observed": observed,
		"mutation_performed": false,
		"backend_reconnect_performed": false,
		"timeout_policy_changed": false,
	}
	return Protocol7.success(_mvp7_backend_liveness_last.duplicate(true))


func _process(_delta: float) -> bool:
	if not interactive or client_boundary == null:
		return false
	var polled: Dictionary = client_boundary.poll_events(128)
	if not bool(polled.get("success", false)):
		finish_interactive(false, "MVP7_CLIENT_GATEWAY_POLL_FAILED")
		return false
	for raw in polled.get("details", {}).get("events", []):
		var event: Dictionary = raw
		var peer := String(event.get("peer_id", ""))
		if event.get("event_type") == "PEER_CONNECTED":
			Support.mark_ready(client_boundary, peer)
		elif event.get("event_type") == "PEER_DISCONNECTED":
			if peer == _mvp7_reconnect_peer and _mvp7_proved:
				_mvp7_finish_ack_disconnect = true
				closing_at_ms = Time.get_ticks_msec() + 25
				continue
			if peer == _mvp7_original_peer and (_mvp7_waiting_reconnect or _mvp7_reconnects > 0):
				if String(client_peers.get("a", "")) == peer:
					client_peers.erase("a")
				continue
			for actor_value in client_peers.keys():
				var actor := String(actor_value)
				if client_peers[actor] == peer and not bool(client_finished[actor]):
					finish_interactive(false, "MVP7_CLIENT_DISCONNECTED_DURING_ACTIVE_WORKLOAD")
					return false
		elif event.get("event_type") == "MESSAGE_RECEIVED":
			var packet := Protocol7.payload(event)
			var actor := identify_client(packet)
			if actor.is_empty():
				continue
			var kind := String(packet.get("body", {}).get("kind", ""))
			var packet_sequence := int(packet.get("sequence", 0))
			var reconnect_hello := actor == "a" and kind == "MVP7_RECONNECT_HELLO" and _mvp7_waiting_reconnect and _mvp7_reconnects == 0
			if reconnect_hello:
				var existing := String(client_peers.get(actor, ""))
				if packet_sequence != 1 or peer == _mvp7_original_peer or (not existing.is_empty() and existing != _mvp7_original_peer and existing != peer):
					continue
				client_peers[actor] = peer
				client_sequences[actor] = packet_sequence
				_mvp7_reconnect_peer = peer
				_mvp7_reconnects = 1
				client_finished[actor] = false
			else:
				if (client_peers.has(actor) and client_peers[actor] != peer) or packet_sequence != int(client_sequences.get(actor, 0)) + 1:
					continue
				client_peers[actor] = peer
				client_sequences[actor] = packet_sequence
			var response := handle_client(actor, packet["body"])
			var signed := Protocol7.seal(cfg, "gateway", "client/" + actor, packet_sequence, response, String(cfg["client_keys"][actor]))
			var sent := Protocol7.send(client_boundary, peer, signed)
			if not bool(sent.get("success", false)):
				finish_interactive(false, "MVP7_CLIENT_GATEWAY_REPLY_FAILED")
				return false
	client_boundary.flush_outbound(128)
	if closing_at_ms > 0 and Time.get_ticks_msec() >= closing_at_ms:
		finish_interactive(_complete6() and _mvp7_proved and _mvp7_finish_ack_disconnect)
	elif Time.get_ticks_msec() - started_at_ms > int(cfg.get("timeout_ms", 240000)):
		finish_interactive(false, "MVP7_GRAPHICAL_GATEWAY_TIMEOUT")
	elif failures.is_empty():
		var kept: Dictionary = _mvp7_backend_liveness7()
		if not bool(kept.get("success", false)):
			finish_interactive(false, String(kept.get("error_code", "MVP7_BACKEND_LIVENESS_FAILED")))
			return false
		if _complete6() and _backend_keepalive_cycles6 == 0:
			var inherited_witness: Dictionary = _mvp7_mvp6_read_only_witness7()
			if not bool(inherited_witness.get("success", false)):
				finish_interactive(false, String(inherited_witness.get("error_code", "MVP7_MVP6_READ_ONLY_WITNESS_FAILED")))
	return false


func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	value["mvp7_backend_liveness"] = {
		"interval_ms": MVP7_BACKEND_LIVENESS_INTERVAL_MS,
		"cycles": _mvp7_backend_liveness_cycles,
		"failures": _mvp7_backend_liveness_failures,
		"last": _mvp7_backend_liveness_last.duplicate(true),
		"mutation_performed": false,
		"backend_reconnect_performed": false,
		"timeout_policy_changed": false,
	}
	value["mvp7_reconnect"] = {
		"waiting": _mvp7_waiting_reconnect,
		"reconnect_count": _mvp7_reconnects,
		"original_peer": _mvp7_original_peer,
		"reconnect_peer": _mvp7_reconnect_peer,
		"hello_world_digest": _mvp7_hello_digest,
		"after_world_digest": _mvp7_after_digest,
		"position_before": _mvp7_position_before.duplicate(true),
		"position_after": _mvp7_position_after.duplicate(true),
		"position_changed": _mvp7_position_before != _mvp7_position_after and not _mvp7_position_before.is_empty(),
		"continue_ok": _mvp7_continue_ok,
		"proved": _mvp7_proved,
		"finish_ack_disconnect": _mvp7_finish_ack_disconnect,
		"current": _mvp7_last_current.duplicate(true),
		"canonical_state_owned": false,
		"mvp7_predicate_verified": false,
	}
	return value


func finish_interactive(seam_criterion: bool, error_code: String = "") -> void:
	if error_code.is_empty() and not _mvp7_proved:
		error_code = "MVP7_RECONNECT_PROOF_REQUIRED"
	super.finish_interactive(seam_criterion and _mvp7_proved, error_code)
