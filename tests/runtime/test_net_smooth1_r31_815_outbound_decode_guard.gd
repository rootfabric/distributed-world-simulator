extends SceneTree

# R31 #815 R1: fail-closed sender preflight on the EXACT packet bytes.
# The default transport is byte-identical; opt-in guard never permits
# a payload with an invalid original receiver checksum/canonical frame.
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Enet = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Forensics = preload("res://scripts/network/smoothness/r31_815_wire_checksum_forensics.gd")

const PEER: String = "peer/815/guard"
const SESSION: String = "transport-session/815/guard/a"
const GUARD_ENV: String = "DWS_NET_R31_815_OUTBOUND_DECODE_GUARD"

var checks: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func make_frame(sequence: int, value: float) -> Dictionary:
	return Frame.create(
		"frame/815/guard/%d" % sequence,
		SESSION, sequence, "SNAPSHOT", "UNRELIABLE_SEQUENCED",
		"planet_simulator.m3.graphical_multiplayer_message.v1", {
			"type": "COMPACT_GAMEPLAY_SNAPSHOT",
			"reason": "MOVEMENT_NETWORK_TICK",
			"snapshot": {
				"schema": "planet_simulator.guard_test.v1",
				"revision": sequence,
				"players": [{
					"p": [value, value * 0.3, value * 0.132],
					"v": [value * 0.375, -value / 11.0, value * 0.024],
					"y": value * 0.25
				}],
			}
		}
	)


func make_port(source) -> Object:
	var port = Enet.new()
	check(bool(port.configure_r31p23r21_single_pass_compact(true).get(
		"success", false)), "original R2.1 validator configured")
	check(bool(port.configure_r31p23r22_attested_compact(
		true, source, "authority/815/guard", 1).get("success", false)),
		"original R2.2 immutable/one-use proof configured")
	port.set("_peer", ENetMultiplayerPeer.new())
	port.set("_mode", "SERVER")
	port.set("_logical_to_numeric", {PEER: 2})
	port.set("_session_by_peer", {PEER: SESSION})
	port.set("_route_generation_by_peer", {PEER: 3})
	return port


func _run() -> void:
	var initial_guard: String = OS.get_environment(GUARD_ENV)
	var initial_forensics: String = OS.get_environment(Forensics.OPT_IN_ENV)
	OS.set_environment(GUARD_ENV, "0")
	OS.set_environment(Forensics.OPT_IN_ENV, "0")
	var source = RefCounted.new()
	var port = make_port(source)
	var rng = RandomNumberGenerator.new()
	rng.seed = 128791
	var known_unstable: Dictionary = {}
	var unstable_bytes: PackedByteArray = PackedByteArray()
	var decoded_error_code: String = ""
	for index in range(1, 301):
		var scale: float = pow(10.0, rng.randi_range(-12, 12))
		var value: float = rng.randf_range(-100.0, 100.0) * scale
		var candidate: Dictionary = make_frame(index, value)
		if not bool(Frame.validate(candidate).get("success", false)):
			continue
		var encoded: Dictionary = Frame.encode(candidate)
		if not bool(encoded.get("success", false)):
			continue
		var packet: PackedByteArray = encoded.get("details", {}).get(
			"packet", PackedByteArray())
		var original_decoder: Dictionary = Frame.decode(packet)
		if not bool(original_decoder.get("success", false)):
			known_unstable = candidate
			unstable_bytes = packet
			decoded_error_code = String(
				original_decoder.get("error_code", "INVALID_FRAME"))
			break
	check(not known_unstable.is_empty(),
		"RED witness exists: sender validates/encodes but unmodified receiver rejects")
	if not known_unstable.is_empty():
		check(decoded_error_code in [
			"PAYLOAD_CHECKSUM_MISMATCH", "NON_CANONICAL_FRAME"
		], "strict decoder rejects exact bytes for known numeric instability")
		var old_behavior: Dictionary = port.call(
			"_r31_815_preflight", unstable_bytes, known_unstable)
		check(bool(old_behavior.get("success", false)),
			"default OFF does not change original transport preflight")
		var old_proof: Dictionary = port.r22_prepare_validated_compact(
			source, PEER, known_unstable)
		check(bool(old_proof.get("success", false)),
			"default OFF preserves old immutable R2.2 proof construction")
		if bool(old_proof.get("success", false)):
			var native_proof: Dictionary = Dictionary(port.get("_r22_pending"))
			check(native_proof.get("packet", PackedByteArray()) == unstable_bytes,
				"legacy default preserves byte-for-byte original packet")

		OS.set_environment(GUARD_ENV, "1")
		var stopped: Dictionary = port.call(
			"_r31_815_preflight", unstable_bytes, known_unstable)
		check(not bool(stopped.get("success", false)) and
			String(stopped.get("error_code", "")) == "R31_815_OUTBOUND_RECEIVER_REJECTED",
			"GREEN opt-in stops decoder-invalid source bytes BEFORE ENet")
		check(String(stopped.get("details", {}).get("decoder_error_code", "")) ==
			decoded_error_code,
			"original receiver exact error code preserved in fail-closed receipt")
		var refused: Dictionary = port.r22_prepare_validated_compact(
			source, PEER, known_unstable)
		check(not bool(refused.get("success", false)) and
			String(refused.get("error_code", "")) == "R31_815_OUTBOUND_RECEIVER_REJECTED",
			"R2.2 frozen one-use proof DENIED before sending unstable packet")
		check(Dictionary(port.get("_r22_pending")).is_empty(),
			"no stale R2.2 capability left after rejected outgoing bytes")
		check(bool(Frame.validate(known_unstable).get("success", false)),
			"guard never mutates the original source Dictionary")
		# Exercise the unprepared native R2.1 fallback send path as well.
		var denied_legacy: Dictionary = port.send_to_peer(PEER, known_unstable)
		check(not bool(denied_legacy.get("success", false)) and
			String(denied_legacy.get("error_code", "")) ==
				"R31_815_OUTBOUND_RECEIVER_REJECTED",
			"legacy send path refuses same invalid on-wire bytes")

	# A stable ordinary outgoing packet cannot be changed by this guard.
	var stable: Dictionary = make_frame(10000, 0.125)
	check(bool(Frame.validate(stable).get("success", false)),
		"stable original sender remains checksum valid")
	var original_encoded: Dictionary = Frame.encode(stable)
	check(bool(original_encoded.get("success", false)),
		"stable packet encodes exactly using original legacy bytes")
	if bool(original_encoded.get("success", false)):
		var packet: PackedByteArray = original_encoded.get(
			"details", {}).get("packet", PackedByteArray())
		check(bool(Frame.decode(packet).get("success", false)),
			"stable original receiver accepts exact canonical packet")
		OS.set_environment(GUARD_ENV, "1")
		check(bool(port.call("_r31_815_preflight", packet, stable).get(
			"success", false)), "opt-in guard accepts unchanged valid packet")
		var accepted: Dictionary = port.r22_prepare_validated_compact(
			source, PEER, stable)
		check(bool(accepted.get("success", false)),
			"R2.2 still mints one-use capability for receiver-valid exact bytes")
		if bool(accepted.get("success", false)):
			var retained: Dictionary = Dictionary(port.get("_r22_pending"))
			check(retained.get("packet", PackedByteArray()) == packet,
				"R2.2 opt-in guard does NOT change packet bytes")
			var took: Dictionary = port.call(
				"_r22_take_attestation", source, PEER,
				int(accepted.get("details", {}).get("ticket", -1)))
			check(bool(took.get("success", false)),
				"original one-use authority proof remains valid")
			check(not bool(port.call(
				"_r22_take_attestation", source, PEER,
				int(accepted.get("details", {}).get("ticket", -1))
			).get("success", true)), "one-use proof cannot be replayed")
		var tampered: PackedByteArray = packet.duplicate()
		var marker_at: int = packet.get_string_from_utf8().find(
			"MOVEMENT_NETWORK_TICK")
		check(marker_at > 0, "exact payload text located for true tamper")
		if marker_at > 0:
			tampered[marker_at] = tampered[marker_at] ^ 0x01
			var decoded: Dictionary = Frame.decode(tampered)
			check(not bool(decoded.get("success", false)) and
				String(decoded.get("error_code", "")) ==
					"PAYLOAD_CHECKSUM_MISMATCH",
				"original strict checksum still rejects a real one-byte corruption")
			check(not bool(port.call(
				"_r31_815_preflight", tampered, stable
			).get("success", false)), "opt-in guard never admits actual tamper")
		# Even inherited guard env cannot change a client-role send path.
		port.set("_mode", "CLIENT")
		check(bool(port.call(
			"_r31_815_preflight", unstable_bytes, known_unstable
		).get("success", false)),
			"client role is not subject to server-only outbound guard")
	OS.set_environment(GUARD_ENV, initial_guard)
	OS.set_environment(Forensics.OPT_IN_ENV, initial_forensics)
	check(checks >= 22, "all native R31 #815 outbound safety checks ran")
	for failure in failures:
		push_error("R31_815_OUTBOUND_GUARD_FAIL:" + failure)
	print("NET_SMOOTH_R31_815_OUTBOUND_GUARD %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
