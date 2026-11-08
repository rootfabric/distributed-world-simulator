extends SceneTree

# R31 #815 true RED: the original send-validated JOIN packet can fail
# Frame.decode(packet) with PAYLOAD_CHECKSUM_MISMATCH without any byte changes.
# This test PROVES the Godot 4.7.1 double serializer problem exists; it is
# NOT a product fix and must NEVER treat a real JOIN failure as PASS.
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const F = preload("res://scripts/network/smoothness/r31_815_wire_checksum_forensics.gd")

var checks: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures.append(detail)


func _join_frame(index: int, x: float) -> Dictionary:
	var payload: Dictionary = {
		"type": "JOIN_ACK", "reason": "JOIN_COMPLETE",
		"player": {"logical_player_id": "a", "position": {
			"x": x, "y": x * 0.134, "z": x / 11.0},
			"velocity": [x * 0.35, x]},
		"snapshot": {"player": [x, x * 0.4, x * 0.25]},
	}
	return Frame.create(
		"frame/815/float/%d" % index, "transport-session/815/float/a",
		index, "RESYNC", "RELIABLE_ORDERED",
		"planet_simulator.m3.graphical_multiplayer_message.v1", payload)


func _run() -> void:
	check(not F.enabled(),
		"wire metadata inspection is disabled by default (production behavior unchanged)")
	# Fixed numeric samples from pinned Linux Godot 4.7.1 double RED vectors.
	var samples: Array[float] = [
		2.9065513610839842e-08,
		-5.366959869861603e-12,
		8.280936479568481e-10,
		4.466712474822998e-12,
		-9.543574489653109e-11,
		2.0544457435607908e-10,
		0.1,
		1.0e-8,
	]
	var float_checksum_rejects: int = 0
	for i in range(samples.size()):
		var frame: Dictionary = _join_frame(i + 1, samples[i])
		check(bool(Frame.validate(frame).get("success", false)),
			"original complete sender validator PASS before encoding %d" % i)
		var encoded: Dictionary = Frame.encode(frame)
		check(bool(encoded.get("success", false)),
			"original sender frame encode PASS %d" % i)
		if not bool(encoded.get("success", false)):
			continue
		var packet: PackedByteArray = encoded.get("details", {}).get(
			"packet", PackedByteArray())
		var recv: Dictionary = Frame.decode(packet)
		var tx_meta: Dictionary = F.inspect_packet(
			"tx_enet", "peer/815/a", packet, frame)
		check(bool(tx_meta.get("sender_checksum_matches", false)),
			"source frame checksum authentic BEFORE sending %d" % i)
		check(int(tx_meta.get("packet_bytes", 0)) == packet.size(),
			"exact packet bytes correctly fingerprinted %d" % i)
		check(String(tx_meta.get("message_type", "")) == "JOIN_ACK",
			"JOIN envelope type pinned %d" % i)
		if not bool(recv.get("success", false)):
			var rx_meta: Dictionary = F.inspect_packet(
				"rx_reject", "", packet, {}, String(recv.get("error_code", "")))
			check(String(recv.get("error_code", "")) == "PAYLOAD_CHECKSUM_MISMATCH",
				"rejected original unmodified canonical packet for numeric checksum %d" % i)
			check(String(tx_meta["packet_sha256"]) == String(rx_meta["packet_sha256"]),
				"sender and receiver inspected EXACT SAME bytes %d" % i)
			check(not bool(tx_meta["postparse_checksum_matches"]),
				"JSON reparse changes canonical payload hash %d" % i)
			check(bool(rx_meta.get("raw_payload_redacted", false)),
				"diagnostics never log personal/raw payload %d" % i)
			float_checksum_rejects += 1
	check(float_checksum_rejects >= 1,
		"native exact float64 sender-PASS/receiver-checksum-FAIL defect reproduced")

	var intact: Dictionary = Frame.create(
		"frame/815/float/intact", "transport-session/815/float/a", 50,
		"RESYNC", "RELIABLE_ORDERED", "planet_simulator.m3.graphical_multiplayer_message.v1",
		{"type": "JOIN_ACK", "reason": "JOIN_MARKER_815", "tick": 17})
	var ok_packet: Dictionary = Frame.encode(intact)
	check(bool(ok_packet.get("success", false)), "clean integer-only JOIN encoded")
	if bool(ok_packet.get("success", false)):
		var bytes: PackedByteArray = ok_packet.get("details", {}).get(
			"packet", PackedByteArray())
		check(bool(Frame.decode(bytes).get("success", false)),
			"unmodified integer-only frame still accepted")
		var damaged: PackedByteArray = bytes.duplicate()
		var marker_at: int = bytes.get_string_from_utf8().find("JOIN_MARKER_815")
		check(marker_at > 0, "wire checksum probe target found")
		if marker_at > 0:
			damaged[marker_at] = damaged[marker_at] ^ 0x01
			var refused: Dictionary = Frame.decode(damaged)
			check(not bool(refused.get("success", false)) and
				String(refused.get("error_code", "")) == "PAYLOAD_CHECKSUM_MISMATCH",
				"genuine byte tampering still triggers original exact checksum error")

	for error in failures:
		push_error("R31_815_FLOAT_WIRE_REPRO_FAIL:" + error)
	print("R31_815_FLOAT_WIRE_REPRO %s assertions=%d failures=%d reproduced=%d" % [
		"PASS" if failures.is_empty() else "FAIL",
		checks, failures.size(), float_checksum_rejects])
	quit(0 if failures.is_empty() else 1)
