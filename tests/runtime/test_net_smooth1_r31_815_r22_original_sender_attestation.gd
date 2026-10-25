extends SceneTree

# R31 #815 R2: original validated frame hash is visible to forensics in
# R2.2 attested native sender. The old diagnostic had sender_frame={} and
# therefore sender_checksum_matches=null despite genuine source validation.
# This test leaves the original protocol checksum, replay/epoch/session
# fences and outgoing ENet bytes UNCHANGED.
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Port = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
const Forensics = preload("res://scripts/network/smoothness/r31_815_wire_checksum_forensics.gd")

const PEER: String = "peer/815/r22"
const SESSION: String = "transport-session/815/r22/a"

var checks: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _frame(sequence: int) -> Dictionary:
	return Frame.create(
		"frame/815/r22/%d" % sequence, SESSION, sequence,
		"SNAPSHOT", "UNRELIABLE_SEQUENCED",
		"planet_simulator.m3.graphical_multiplayer_message.v1", {
			"type": "COMPACT_GAMEPLAY_SNAPSHOT",
			"reason": "R31_815_SENTINEL",
			"snapshot": {
				"server_tick": 300 + sequence,
				"players": [{"id": "player/a", "x": 0.125}],
			},
		}
	)


func _run() -> void:
	var original_env: String = OS.get_environment(Forensics.OPT_IN_ENV)
	var source = RefCounted.new()
	var enet = Port.new()
	check(bool(enet.configure_r31p23r21_single_pass_compact(true).get("success", false)),
		"full native R2.1 parent enabled")
	check(bool(enet.configure_r31p23r22_attested_compact(
		true, source, "authority/815/r22", 7).get("success", false)),
		"native R2.2 sender uses frozen single-use packet attestation")
	enet.set("_peer", ENetMultiplayerPeer.new())
	enet.set("_mode", "SERVER")
	enet.set("_logical_to_numeric", {PEER: 11})
	enet.set("_session_by_peer", {PEER: SESSION})
	enet.set("_route_generation_by_peer", {PEER: 3})

	OS.set_environment(Forensics.OPT_IN_ENV, "1")
	var frame: Dictionary = _frame(1)
	check(bool(Frame.validate(frame).get("success", false)),
		"original Frame.validate source checksum is valid")
	var prepared: Dictionary = enet.r22_prepare_validated_compact(source, PEER, frame)
	check(bool(prepared.get("success", false)), "same-frame R2.2 proof prepared")
	if bool(prepared.get("success", false)):
		var native_proof: Dictionary = Dictionary(enet.get("_r22_pending"))
		var original_hash: String = String(
			native_proof.get("r31_815_original_payload_sha256", ""))
		check(original_hash.length() == 64,
			"R2 original validated payload hash captured BEFORE proof consumed")
		check(original_hash == String(frame["payload_checksum"]),
			"original source payload hash matches original checked frame")
		var taken: Dictionary = enet.call(
			"_r22_take_attestation", source, PEER,
			int(prepared.get("details", {}).get("ticket", 0)))
		check(bool(taken.get("success", false)), "single-use original proof consumed")
		if bool(taken.get("success", false)):
			var proof: Dictionary = Dictionary(taken.get("details", {}))
			var pkt: PackedByteArray = proof.get("packet", PackedByteArray())
			check(String(proof.get("r31_815_original_payload_sha256", "")) ==
				original_hash,
				"source checksum attestation retained WITHOUT mutating native packet")
			var legacy: Dictionary = Frame.encode(frame)
			check(bool(legacy.get("success", false)),
				"original unchanged protocol-frame encoding succeeds")
			if bool(legacy.get("success", false)):
				check(pkt == legacy.get("details", {}).get("packet", PackedByteArray()),
					"R2 forensic proof has byte-for-byte identical original ENet bytes")
			var meta: Dictionary = Forensics.inspect_packet(
				"tx_enet", PEER, pkt, {}, "", original_hash)
			check(meta.get("sender_checksum_matches") == true,
				"source-validated R2.2 tx receipt is attested TRUE, never null")
			check(String(meta.get("sender_hash_provenance", "")) ==
				"R22_ORIGINAL_VALIDATED_FRAME",
				"the proof provenance is ORIGINAL frozen source frame")
			check(meta.get("postparse_checksum_matches") == true,
				"stable control COMPACT roundtrip remains checksum-correct")
			check(bool(Frame.decode(pkt).get("success", false)),
				"receiver unmodified strict checksum still validates control packet")
			var bad: PackedByteArray = pkt.duplicate()
			var marker_offset: int = pkt.get_string_from_utf8().find(
				"R31_815_SENTINEL")
			check(marker_offset > 0, "corrupting the checksum-protected payload")
			if marker_offset > 0:
				bad[marker_offset] = bad[marker_offset] ^ 0x01
				var refused: Dictionary = Frame.decode(bad)
				check(not bool(refused.get("success", false))
					and String(refused.get("error_code", "")) ==
						"PAYLOAD_CHECKSUM_MISMATCH",
					"unchanged receiver FAIL-CLOSED on real one-byte payload tampering")
		check(not bool(enet.call(
			"_r22_take_attestation", source, PEER,
			int(prepared.get("details", {}).get("ticket", 0))
		).get("success", true)), "one-use R2 proof cannot be replayed")

	OS.set_environment(Forensics.OPT_IN_ENV, "0")
	var second: Dictionary = _frame(2)
	check(bool(Frame.validate(second).get("success", false)),
		"original source checksum remains validated with forensics OFF")
	var off_prepared: Dictionary = enet.r22_prepare_validated_compact(
		source, PEER, second)
	check(bool(off_prepared.get("success", false)),
		"R2.2 normal non-forensic frame still prepares")
	if bool(off_prepared.get("success", false)):
		var off_proof: Dictionary = Dictionary(enet.get("_r22_pending"))
		check(not off_proof.has("r31_815_original_payload_sha256"),
			"the default mode does NOT alter frozen native proof shape")
		var off_taken: Dictionary = enet.call(
			"_r22_take_attestation", source, PEER,
			int(off_prepared.get("details", {}).get("ticket", 0)))
		check(bool(off_taken.get("success", false)),
			"default original R2.2 proof consumption still succeeds")
		if bool(off_taken.get("success", false)):
			check(not Dictionary(off_taken.get("details", {})).has(
				"r31_815_original_payload_sha256"),
				"default native attestation receipt unchanged")
	check(checks >= 18, "native #815 R22 attestation negative/positive matrix complete")
	OS.set_environment(Forensics.OPT_IN_ENV, original_env)
	for item in failures:
		push_error("R31_815_R22_SENDER_ATTESTATION_FAIL:" + item)
	print("R31_815_R22_SENDER_ATTESTATION %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
