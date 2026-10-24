extends SceneTree

# R2.2 one-shot proof and exact native wire/error falsifiers.
# No external ENet sockets or mutable packets are needed to prove the seal.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Enet = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Wire = preload("res://scripts/network/contracts/network_contract_utils.gd")

var checks := 0
var failures: Array[String] = []
const PEER_ID := "peer/r22"
const SESSION := "transport-session/r22/a"


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _port() -> int:
	var socket := PacketPeerUDP.new()
	if socket.bind(0, "127.0.0.1") != OK:
		return 0
	var port: int = socket.get_local_port()
	socket.close()
	return port


func _config(label: String, enabled: bool = false) -> Dictionary:
	var result: Dictionary = {
		"host": "127.0.0.1", "port": _port(),
		"playable_sandbox": true, "product_seam_enabled": true,
		"persistence_root": ProjectSettings.globalize_path(
			"res://artifacts/net-smooth1/r31p23r22-%s-%d" % [
				label, Time.get_ticks_usec()]),
	}
	if enabled:
		result.merge({
			"r3c4_periodic_frame_pacing_canary": true,
			"r3c4r2_worker_envelope_canary": true,
			"r3c4r31_replay_projection_canary": true,
			"r3c4r31b_durable_attribution_canary": true,
			"r31bp1_durable_chunks_canary": true,
			"r31p22_loop_attribution_canary": true,
			"r31p23r2_flush_attribution_canary": true,
			"r31p23r21_single_pass_compact_canary": true,
			"r31p23r22_attested_compact_canary": true,
		})
	return result


func _frame(sequence: int) -> Dictionary:
	return Frame.create(
		"frame/r22/%d" % sequence, SESSION, sequence,
		"SNAPSHOT", "UNRELIABLE_SEQUENCED",
		"planet_simulator.m3_network_message.v1", {
			"type": "COMPACT_GAMEPLAY_SNAPSHOT",
			"snapshot": {
				"schema": "planet_simulator.compact_gameplay_snapshot.v1",
				"revision": sequence,
				"server_tick": sequence * 3,
				"players": [{"id": "player/r22", "x": float(sequence) / 4.0}],
			},
		}
	)


func _make_port(source) -> Object:
	var enet = Enet.new()
	check(bool(enet.configure_r31p23r21_single_pass_compact(true).get(
		"success", false)), "R2.1 native parent")
	check(bool(enet.configure_r31p23r22_attested_compact(
		true, source, "authority/r22", 7).get("success", false)),
		"R2.2 private source and authority configured")
	# Only the proof preparation/consumption is exercised. No network send.
	enet.set("_peer", ENetMultiplayerPeer.new())
	enet.set("_mode", "SERVER")
	enet.set("_logical_to_numeric", {PEER_ID: 11})
	enet.set("_session_by_peer", {PEER_ID: SESSION})
	enet.set("_route_generation_by_peer", {PEER_ID: 3})
	return enet


func _issue(enet, source, sequence: int) -> Dictionary:
	var frame := _frame(sequence)
	var checked := Frame.validate(frame)
	check(bool(checked.get("success", false)),
		"original complete validator before attestation %d" % sequence)
	return enet.r22_prepare_validated_compact(source, PEER_ID, frame)


func _proof_falsifiers() -> void:
	var source = RefCounted.new()
	var wrong_source = RefCounted.new()
	var enet = _make_port(source)
	for i in range(1, 33):
		var frame: Dictionary = _frame(i)
		check(bool(Frame.validate(frame).get("success", false)),
			"original full validator on source %d" % i)
		var before: String = Wire.canonical_json(frame)
		var prepared: Dictionary = enet.r22_prepare_validated_compact(
			source, PEER_ID, frame)
		check(bool(prepared.get("success", false)), "mint native proof %d" % i)
		if not bool(prepared.get("success", false)):
			continue
		var ticket: int = int(prepared.get("details", {}).get("ticket", -1))
		var taken: Dictionary = enet.call("_r22_take_attestation",
			source, PEER_ID, ticket)
		check(bool(taken.get("success", false)),
			"consume exactly one native proof %d" % i)
		if bool(taken.get("success", false)):
			var actual: PackedByteArray = taken.get("details", {}).get(
				"packet", PackedByteArray())
			var legacy: Dictionary = Frame.encode(frame)
			check(bool(legacy.get("success", false)) and
				actual == legacy.get("details", {}).get("packet", PackedByteArray()),
				"frozen exact legacy canonical wire bytes %d" % i)
			check(bool(Frame.decode(actual).get("success", false)),
				"receiver native checksum remains checked %d" % i)
			check(int(taken.get("details", {}).get("sequence", -1)) == i and
				String(taken.get("details", {}).get("session_id", "")) == SESSION and
				String(taken.get("details", {}).get("payload_checksum", "")) ==
					String(frame["payload_checksum"]),
				"ticket binds sequence session checksum %d" % i)
		check(not bool(enet.call("_r22_take_attestation",
			source, PEER_ID, ticket).get("success", true)),
			"same ticket cannot be replayed %d" % i)
		check(Wire.canonical_json(frame) == before,
			"source frame never mutated %d" % i)

	var wrong := _issue(enet, source, 40)
	if bool(wrong.get("success", false)):
		var denied: Dictionary = enet.call("_r22_take_attestation",
			wrong_source, PEER_ID, int(wrong["details"]["ticket"]))
		check(String(denied.get("error_code", "")) ==
			"R31P23R22_SOURCE_MISMATCH", "wrong native source rejected")

	var peer_mismatch := _issue(enet, source, 41)
	if bool(peer_mismatch.get("success", false)):
		var denied: Dictionary = enet.call("_r22_take_attestation",
			source, "peer/other", int(peer_mismatch["details"]["ticket"]))
		check(String(denied.get("error_code", "")) ==
			"R31P23R22_PROOF_OWNER_MISMATCH", "different peer cannot reuse proof")

	var session := _issue(enet, source, 42)
	if bool(session.get("success", false)):
		enet.set("_session_by_peer", {PEER_ID: "transport-session/r22/new"})
		var denied: Dictionary = enet.call("_r22_take_attestation",
			source, PEER_ID, int(session["details"]["ticket"]))
		check(String(denied.get("error_code", "")) == "SESSION_MISMATCH",
			"new session invalidates one-use proof")
		enet.set("_session_by_peer", {PEER_ID: SESSION})

	var route := _issue(enet, source, 43)
	if bool(route.get("success", false)):
		enet.set("_route_generation_by_peer", {PEER_ID: 4})
		var denied: Dictionary = enet.call("_r22_take_attestation",
			source, PEER_ID, int(route["details"]["ticket"]))
		check(String(denied.get("error_code", "")) ==
			"R31P23R22_ROUTE_CHANGED", "route generation ABA invalidates proof")
		enet.set("_route_generation_by_peer", {PEER_ID: 3})

	var authority := _issue(enet, source, 44)
	if bool(authority.get("success", false)):
		enet.set("_r22_authority_epoch", 8)
		var denied: Dictionary = enet.call("_r22_take_attestation",
			source, PEER_ID, int(authority["details"]["ticket"]))
		check(String(denied.get("error_code", "")) ==
			"R31P23R22_AUTHORITY_CHANGED", "authority epoch invalidates proof")
		enet.set("_r22_authority_epoch", 7)

	var damaged := _issue(enet, source, 45)
	if bool(damaged.get("success", false)):
		var proof: Dictionary = Dictionary(enet.get("_r22_pending")).duplicate(true)
		var packet: PackedByteArray = proof.get("packet", PackedByteArray())
		if not packet.is_empty():
			packet[0] = 0
			proof["packet"] = packet
			enet.set("_r22_pending", proof)
		var denied: Dictionary = enet.call("_r22_take_attestation",
			source, PEER_ID, int(damaged["details"]["ticket"]))
		check(String(denied.get("error_code", "")) ==
			"PAYLOAD_CHECKSUM_MISMATCH",
			"internal native packet mutation retains checksum error")

	var frame: Dictionary = _frame(46)
	var original: Dictionary = Frame.encode(frame)
	frame["payload"]["snapshot"]["server_tick"] = -100
	var validator: Dictionary = Frame.validate(frame)
	var legacy: Dictionary = Frame.encode(frame)
	check(not bool(validator.get("success", true)) and
		String(validator.get("error_code", "")) == "PAYLOAD_CHECKSUM_MISMATCH" and
		String(legacy.get("error_code", "")) == "PAYLOAD_CHECKSUM_MISMATCH",
		"tampered nested payload rejected with EXACT original checksum error")
	check(bool(original.get("success", false)),
		"original native packet before tamper was valid")

	var denied_parent = Enet.new()
	var early: Dictionary = denied_parent.configure_r31p23r22_attested_compact(
		true, source, "authority/r22", 7)
	check(String(early.get("error_code", "")) ==
		"R31P23R22_REQUIRES_R21", "without R2.1 prerequisite fail closed")

	var disabled: Dictionary = enet.configure_r31p23r22_attested_compact(
		false, source, "", 0)
	check(bool(disabled.get("success", false)), "explicit native OFF")
	var after_off: Dictionary = enet.r22_prepare_validated_compact(
		source, PEER_ID, _frame(47))
	check(String(after_off.get("error_code", "")) ==
		"R31P23R22_NOT_ENABLED", "no proof issuance when off")
	enet = null


func _run() -> void:
	OS.set_environment("DWS_NET_R31P23R22_ATTESTED_COMPACT", "bad")
	var invalid = Runtime.new()
	var invalid_result: Dictionary = invalid.setup(_config("bad-mode"))
	check(String(invalid_result.get("error_code", "")) ==
		"R31P23R22_INVALID_MODE", "invalid opt-in mode fail-closed")
	invalid.free()
	OS.set_environment("DWS_NET_R31P23R22_ATTESTED_COMPACT", "")

	var denied = Runtime.new()
	var denied_config: Dictionary = _config("without-parent")
	denied_config["r31p23r22_attested_compact_canary"] = true
	var denied_result: Dictionary = denied.setup(denied_config)
	check(String(denied_result.get("error_code", "")) ==
		"R31P23R22_REQUIRES_R21", "R2.2 cannot start without R2.1")
	denied.free()

	var on = Runtime.new()
	var configured: Dictionary = on.setup(_config("on", true))
	check(bool(configured.get("success", false)),
		"R2.2 real native server + persistence configured")
	if bool(configured.get("success", false)):
		on.set_process(false)
		var boundary = on.get("_boundary")
		check(bool(on.get("_r31p23r22_attested_compact_enabled")),
			"server R2.2 opt-in ON")
		check(boundary != null and bool(boundary.get(
			"_r31p23r22_attested_compact_enabled")), "boundary R2.2 ON")
		if boundary != null:
			var sim = boundary.get("_port")
			check(sim != null and bool(sim.get(
				"_r31p23r22_attested_compact_enabled")), "simulator R2.2 ON")
			if sim != null:
				var enet = sim.get("_delegate")
				check(enet != null and bool(enet.get(
					"_r31p23r22_attested_compact_enabled")), "real ENet R2.2 ON")
		check(bool(on.stop().get("success", false)), "native M6 stop unchanged")
	on.free()
	_proof_falsifiers()
	for failure in failures:
		push_error("NET_SMOOTH_R31P23R22_FAIL:" + failure)
	print("NET_SMOOTH_R31P23R22 %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
